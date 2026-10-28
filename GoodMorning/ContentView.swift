import AppKit
import SwiftUI

struct ContentView: View {
    let session: Session

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            if session.folderURL != nil, session.loadError == nil {
                Margins(session: session)
            }

            if session.folderURL != nil {
                VStack(spacing: 0) {
                    ProgressLine(progress: session.progress)
                    if let loadError = session.loadError {
                        // No editor until the page can be read, so nothing typed here can replace it.
                        UnreadablePage(error: loadError, reveal: session.canRevealPage ? { session.revealPage() } : nil,
                                       chooseFolder: { session.chooseFolder() })
                    } else {
                        EditorView(text: session.text, isFocused: !session.isShowingCommands && !session.isShowingHelp,
                                   onChange: { session.edit($0) })
                            .frame(maxWidth: 680)
                            .frame(maxWidth: .infinity)
                    }
                    // Under the text, where the eye is, not out in the corners of a full-screen page.
                    StatusBar(session: session)
                        .frame(maxWidth: 680)
                }
                .ignoresSafeArea(edges: .top)
            } else {
                Welcome(choose: { session.chooseFolder() })
                    // Otherwise its Return shortcut beats the palette (or help) to the key.
                    .disabled(session.isShowingCommands || session.isShowingHelp)
            }

            if session.isShowingHelp {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { session.hideHelp() }
                HelpCard(session: session)
                    .padding(.top, 80)
                    .frame(maxHeight: .infinity, alignment: .top)
            }

            if session.isShowingCommands {
                // A click anywhere else closes the palette.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { session.hideCommands() }
                CommandPalette(session: session)
                    .padding(.top, 80)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(WindowReader { session.attach($0) })
    }
}

// MARK: - Status bar

private struct StatusBar: View {
    let session: Session

    var body: some View {
        // The word count stays centered, whatever the two sides hold, and never runs into them.
        StatusBarLayout(gap: 16) {
            left
            center.frame(maxWidth: 260)
            right
        }
        .lineLimit(1)
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 37)  // lines up with the text: the editor's 32 pt inset plus 5 pt line padding
        .padding(.vertical, 14)
    }

    @ViewBuilder private var left: some View {
        HStack(spacing: 10) {
            if session.isComplete {
                Text("Done for today")
            } else {
                if session.isTimerRunning {
                    // Checks run every 5 seconds; the clock on screen still ticks each second.
                    TimelineView(.periodic(from: .now, by: 1)) { _ in Text(clock(session.secondsLeft)) }
                } else {
                    Text(clock(session.secondsLeft))
                }
                if !session.isFullScreen, session.loadError == nil {  // no locking in to a page that isn't there
                    Button("Lock in") { session.lockIn() }
                        .buttonStyle(.link)
                        .help("Shift-Command-L")
                }
            }
            if session.isFullScreen {
                Text("esc to leave").foregroundStyle(.tertiary)
            }
            Button("⌘P commands") { session.toggleCommands() }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private var center: some View {
        if let error = session.errorMessage {
            Text(error)
                .foregroundStyle(.red)
                .help(error)  // the bar may cut it short
        } else {
            Text("\(session.wordCount.formatted()) / \(session.wordGoal.formatted()) words")
        }
    }

    private var right: some View {
        HStack(spacing: 10) {
            Text(streakText)
            Button { session.toggleHelp() } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.plain)
            .help("How Good Morning works (⌘?)")
        }
    }

    private var streakText: String {
        switch session.streak {
        case 0: "No streak yet"
        default: "\(session.streak)-day streak"
        }
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Left, middle and right on one line. The two ends get their full width. The middle sits centered
/// if it fits between them, moves over just enough if it doesn't, and only then truncates. Nothing overlaps.
private struct StatusBarLayout: Layout {
    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = sizes.reduce(0) { $0 + $1.width } + gap * CGFloat(max(0, sizes.count - 1))
        return CGSize(width: proposal.width ?? width, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let (left, middle, right) = (subviews[0], subviews[1], subviews[2])
        let rightWidth = min(right.sizeThatFits(.unspecified).width, bounds.width)
        let leftWidth = min(left.sizeThatFits(.unspecified).width, max(0, bounds.width - rightWidth - gap))
        let start = bounds.minX + leftWidth + gap
        let end = bounds.maxX - rightWidth - gap
        let width = min(middle.sizeThatFits(.unspecified).width, max(0, end - start))
        let x = max(start, min(bounds.midX - width / 2, end - width))

        left.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                   proposal: ProposedViewSize(width: leftWidth, height: nil))
        middle.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                     proposal: ProposedViewSize(width: width, height: nil))
        right.place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing,
                    proposal: ProposedViewSize(width: rightWidth, height: nil))
    }
}

/// A hairline across the top that fills with whichever goal is further along.
private struct ProgressLine: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.accentColor.opacity(0.6))
                .frame(width: geo.size.width * progress)
                .animation(.easeOut(duration: 0.4), value: progress)
        }
        .frame(height: 2)
    }
}

// MARK: - Margins

/// The empty space either side of the text, put to work: bands of morning colour stack up on the left as
/// you write, and on the right grains of sand drop through the margin as the minutes pass, one at a time.
private struct Margins: View {
    let session: Session

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let side = (geo.size.width - 680) / 2  // the text column is 680 wide, centered
            if side >= 96 {
                // Halfway out into the margin, but not so far that it leaves the page behind.
                let inset = min(side / 2, 150)
                let height = min(geo.size.height * 0.5, 420)
                let y = geo.size.height / 2

                WordBands(progress: Double(session.wordCount) / Double(max(1, session.wordGoal)))
                    .frame(width: 56, height: height)
                    .help("\(session.wordCount.formatted()) of \(session.wordGoal.formatted()) words")
                    .accessibilityElement()
                    .accessibilityLabel("Words")
                    .accessibilityValue("\(session.wordCount) of \(session.wordGoal)")
                    .position(x: side - inset, y: y)

                Group {
                    if session.isTimerRunning, !reduceMotion {
                        // Smooth enough for a falling grain. A few dozen dots cost next to nothing to redraw.
                        TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in grains }
                    } else if session.isTimerRunning {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in grains }
                    } else {
                        grains
                    }
                }
                .frame(width: SandColumn.width, height: height)
                .help(minutesText)
                .accessibilityElement()
                .accessibilityLabel("Time")
                .accessibilityValue(minutesText)
                .position(x: geo.size.width - side + inset, y: y)
            }
        }
        .ignoresSafeArea()
    }

    private var grains: some View {
        SandColumn(elapsed: session.elapsedExact, goal: Double(max(1, session.secondsGoal)),
                   reduceMotion: reduceMotion)
            // Paused: everything stays where it is, just quieter.
            .opacity(session.isTimerRunning || session.isComplete ? 1 : 0.5)
    }

    private var minutesText: String {
        "\(session.elapsedNow / 60) of \(Prefs.minuteGoal) minutes"
    }
}

/// How full mark `index` of `count` is, 0...1, when the marks fill one after another.
private func fill(of index: Int, in count: Int, progress: Double) -> Double {
    min(1, max(0, progress * Double(count) - Double(index)))
}

/// Deep orange at the bottom of a margin to pale gold at the top (`height` 0...1), like the sky at dawn.
private func dawn(at height: Double) -> Color {
    let low = (0.78, 0.45, 0.30), high = (0.92, 0.82, 0.72)
    return Color(red: low.0 + (high.0 - low.0) * height,
                 green: low.1 + (high.1 - low.1) * height,
                 blue: low.2 + (high.2 - low.2) * height)
}

/// A fixed number in 0..<1 for each grain and `salt`, so every grain has its own timing, the same every day.
private func noise(_ grain: Int, _ salt: Int) -> Double {
    let value = sin(Double(grain * 31 + salt * 17 + 1) * 12.9898) * 43758.5453
    return value - value.rounded(.down)
}

/// Ten bands stacked from the bottom, each a tenth of the word goal.
/// A band warms in slowly as you write the words it stands for.
private struct WordBands: View {
    let progress: Double

    private let bands = 10

    var body: some View {
        Canvas { context, size in
            let step = size.height / CGFloat(bands)
            for i in 0..<bands {
                let band = Path(CGRect(x: 0, y: size.height - CGFloat(i + 1) * step + 2.5,
                                       width: size.width, height: step - 5))
                context.fill(band, with: .color(.primary.opacity(0.04)))
                let done = fill(of: i, in: bands, progress: progress)
                if done > 0 {
                    context.fill(band, with: .color(dawn(at: Double(i) / Double(bands - 1)).opacity(0.45 * done)))
                }
            }
        }
    }
}

/// The time as sand: thirty solid grains in a column three wide, one for each thirtieth of the goal,
/// starting in the top half. Drawn from `Sandglass`, which works out where every grain is.
private struct SandColumn: View {
    let elapsed: Double  // seconds on the page today
    let goal: Double     // seconds in the time goal
    var reduceMotion = false

    static let diameter: CGFloat = 14
    static let across: CGFloat = 19  // centre to centre, side to side
    static let width = across * 2 + diameter

    var body: some View {
        Canvas { context, size in
            let pitch = size.height / CGFloat(Sandglass.depth * 2)
            func dot(_ column: CGFloat, _ row: CGFloat) -> Path {
                let x = size.width / 2 + (column - 1) * Self.across, y = (row + 0.5) * pitch
                return Path(ellipseIn: CGRect(x: x - Self.diameter / 2, y: y - Self.diameter / 2,
                                              width: Self.diameter, height: Self.diameter))
            }
            for row in 0..<Sandglass.depth * 2 {
                for column in 0..<3 {
                    context.stroke(dot(CGFloat(column), CGFloat(row)), with: .color(.primary.opacity(0.1)), lineWidth: 1)
                }
            }
            for place in Sandglass.places(elapsed: elapsed, goal: goal, pitch: pitch, calm: reduceMotion)
            where place.amount > 0 {
                let height = 1 - Double((place.row + 0.5) * pitch / size.height)
                context.fill(dot(place.column, place.row),
                             with: .color(dawn(at: min(1, max(0, height))).opacity(place.amount)))
            }
        }
    }
}

/// Where the sand is at any moment. Columns are 0 (left), 1 (middle) and 2 (right). Rows run from 0 at
/// the top; the top half is rows 0 to 9, with the neck at 9, and the bottom half rows 10 to 19.
///
/// In each stretch the lowest middle grain drops through the neck under gravity, bounces off the pile with
/// most of its speed lost, and rolls off to a lower side if there is one, so the pile builds into a mound.
/// The middle column above it drops a place, and a side two grains higher slides its top grain into the
/// dip, so the top drains from the middle as real sand does. Each grain lets go at its own moment.
/// With Reduce Motion on, nothing moves: grains fade from the top half to the bottom instead.
private enum Sandglass {
    static let grains = 30
    static let depth = 10  // rows in each half
    static let gravity = 2400.0  // points per second squared
    static let restitution = 0.3  // how much of its speed a grain keeps on each bounce
    static let rollTime = 0.3
    static let slideTime = 0.35

    struct Place {
        var column: CGFloat
        var row: CGFloat
        var amount = 1.0  // under 1 only while fading across with Reduce Motion
    }

    /// One leg of a grain's trip, from `start` to `end` seconds into the stretch.
    struct Leg {
        let start: Double
        let end: Double
        let from: Place
        let to: Place
        let at: (Double) -> Place
    }

    private struct Slot: Hashable {
        let column: Int
        let row: Int
    }

    static func places(elapsed: Double, goal: Double, pitch: CGFloat, calm: Bool) -> [Place] {
        let stretch = goal / Double(grains)
        let progress = max(0, elapsed / stretch)
        let current = min(grains, Int(progress.rounded(.down)))  // the grain on the move
        let into = (progress - Double(current)) * stretch  // seconds into its stretch
        if calm { return calmPlaces(current: current, moved: current < grains ? into / stretch : 0) }

        // Replay every trip so far to see how the heaps stand, then work out the one under way.
        var top = [depth, depth, depth], bottom = [0, 0, 0]
        for k in 0..<current { _ = trip(of: k, top: &top, bottom: &bottom, stretch: stretch, pitch: pitch) }
        let before = (top: top, bottom: bottom)
        let moves = current < grains ? trip(of: current, top: &top, bottom: &bottom, stretch: stretch, pitch: pitch) : []

        let moving = Set(moves.map { Slot(column: Int($0[0].from.column), row: Int($0[0].from.row)) })
        var out: [Place] = []
        for column in 0..<3 {
            for i in 0..<before.top[column] where !moving.contains(Slot(column: column, row: depth - 1 - i)) {
                out.append(Place(column: CGFloat(column), row: CGFloat(depth - 1 - i)))
            }
            for i in 0..<before.bottom[column] {
                out.append(Place(column: CGFloat(column), row: CGFloat(depth * 2 - 1 - i)))
            }
        }
        for legs in moves { out.append(position(of: legs, at: into)) }
        return out
    }

    /// Grain `k`'s trip, worked out from the heaps as they stand, which it moves on to how they'll be after it.
    /// Each inner list is one grain's legs.
    private static func trip(of k: Int, top: inout [Int], bottom: inout [Int], stretch: Double,
                             pitch: CGFloat) -> [[Leg]] {
        let neck = CGFloat(depth - 1), floor = CGFloat(depth * 2 - 1)
        func topRow(_ column: Int) -> CGFloat { neck - CGFloat(top[column]) + 1 }  // its highest grain
        var moves: [[Leg]] = []
        let busy = 2.2  // the longest a trip takes, give or take
        var t = stretch > busy ? (stretch - busy) * (0.05 + 0.9 * noise(k, 2)) : 0

        // The middle has run dry: a grain from a side rolls in over the neck first, then drops through it.
        var legs: [Leg] = []
        if top[1] == 0 {
            let side = taller(top[0], top[2], k, 3)
            legs.append(roll(from: Place(column: CGFloat(side), row: topRow(side)), to: Place(column: 1, row: neck),
                             at: t, for: slideTime))
            top[side] -= 1
            top[1] = 1
            t += slideTime
        }
        // The lowest middle grain drops through the neck, and rolls off the pile's peak if a side is lower.
        top[1] -= 1
        let land = floor - CGFloat(bottom[1])
        let drop = fall(column: 1, from: neck, to: land, at: t, pitch: pitch)
        legs.append(drop)
        if bottom[1] > min(bottom[0], bottom[2]) {
            let side = lower(bottom[0], bottom[2], k, 4)
            legs.append(roll(from: Place(column: 1, row: land), to: Place(column: CGFloat(side), row: floor - CGFloat(bottom[side])),
                             at: drop.end, for: rollTime))
            bottom[side] += 1
        } else {
            bottom[1] += 1
        }
        moves.append(legs)

        // The middle column above drops a place after it.
        var settled = t
        for i in 0..<top[1] {
            let leg = fall(column: 1, from: neck - CGFloat(i) - 1, to: neck - CGFloat(i), at: t, pitch: pitch)
            moves.append([leg])
            settled = max(settled, leg.end)
        }
        // A side two higher than the middle lets its top grain slide down into the dip.
        if max(top[0], top[2]) - top[1] >= 2 {
            let side = taller(top[0], top[2], k, 5)
            moves.append([roll(from: Place(column: CGFloat(side), row: topRow(side)),
                               to: Place(column: 1, row: neck - CGFloat(top[1])), at: settled + 0.05, for: slideTime)])
            top[side] -= 1
            top[1] += 1
        }
        return moves
    }

    /// A drop from row `r0` to `r1` under gravity, then bounces, each keeping `restitution` of the speed,
    /// until a bounce would rise less than half a point.
    private static func fall(column: CGFloat, from r0: CGFloat, to r1: CGFloat, at start: Double, pitch: CGFloat) -> Leg {
        let g = gravity, points = Double(pitch)
        let drop = (2 * max(0, Double(r1 - r0)) * points / g).squareRoot()
        var hops: [Double] = []
        var speed = g * drop * restitution, end = start + drop
        while speed * speed / (2 * g) > 0.5 {
            hops.append(speed)
            end += 2 * speed / g
            speed *= restitution
        }
        let bounces = hops
        return Leg(start: start, end: end, from: Place(column: column, row: r0), to: Place(column: column, row: r1)) { t in
            var s = t - start
            if s < drop { return Place(column: column, row: r0 + CGFloat(0.5 * g * s * s / points)) }
            s -= drop
            for hop in bounces {
                let flight = 2 * hop / g
                if s < flight { return Place(column: column, row: r1 - CGFloat((hop * s - 0.5 * g * s * s) / points)) }
                s -= flight
            }
            return Place(column: column, row: r1)
        }
    }

    /// A roll from one place to another: sideways quickly at first, and downward faster as it goes.
    private static func roll(from a: Place, to b: Place, at start: Double, for duration: Double) -> Leg {
        Leg(start: start, end: start + duration, from: a, to: b) { t in
            let u = min(1, max(0, (t - start) / duration))
            return Place(column: a.column + (b.column - a.column) * CGFloat(sin(.pi / 2 * u)),
                         row: a.row + (b.row - a.row) * CGFloat(u * u))
        }
    }

    private static func position(of legs: [Leg], at t: Double) -> Place {
        if t <= legs[0].start { return legs[0].from }
        for leg in legs where t < leg.end { return t < leg.start ? leg.from : leg.at(t) }
        return legs[legs.count - 1].to
    }

    /// The taller side (0 or 2), or either one at even, the same way every day.
    private static func taller(_ left: Int, _ right: Int, _ k: Int, _ salt: Int) -> Int {
        left > right ? 0 : right > left ? 2 : noise(k, salt) < 0.5 ? 0 : 2
    }

    private static func lower(_ left: Int, _ right: Int, _ k: Int, _ salt: Int) -> Int {
        left < right ? 0 : right < left ? 2 : noise(k, salt) < 0.5 ? 0 : 2
    }

    /// Reduce Motion: the top empties from its surface and the pile fills from the floor, middle first,
    /// each grain fading across over its stretch.
    private static func calmPlaces(current: Int, moved: Double) -> [Place] {
        let order = [1, 0, 2]
        return (0..<grains).flatMap { (k: Int) -> [Place] in
            let column = CGFloat(order[k % 3]), row = CGFloat(k / 3)
            let gone: Double = k < current ? 1 : k == current ? moved : 0
            return [Place(column: column, row: row, amount: 1 - gone),
                    Place(column: column, row: CGFloat(depth * 2 - 1) - row, amount: gone)]
        }
    }
}

// MARK: - First launch

private struct Welcome: View {
    let choose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("Good Morning")
                .font(.system(size: 34, design: .serif))
            Text("Write until you reach \(Prefs.wordGoal.formatted()) words or \(Prefs.minuteGoal) minutes pass. Once you choose a folder, the page fills the screen and the Dock, menu bar and Cmd-Tab go away until you're done.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
            Text("Esc steps out and pauses the timer. ⌘P shows everything else.")
                .foregroundStyle(.secondary)
            Text("Pages are saved as plain markdown, one file per day.")
                .foregroundStyle(.secondary)
            Button("Choose a Folder…", action: choose)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 6)
        }
        .padding(40)
    }
}

// MARK: - Unreadable page

/// In place of the editor when today's page couldn't be read. The file is left as it is while the session tries again.
private struct UnreadablePage: View {
    let error: String
    let reveal: (() -> Void)?  // nil when there's nothing in Finder to show
    let chooseFolder: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Today's page couldn't be opened")
                .font(.system(size: 24, design: .serif))
            Text(error)
                .foregroundStyle(.secondary)
            Text("Nothing has been changed. Fix or move the file, or choose another folder. Good Morning keeps trying in the meantime.")
                .foregroundStyle(.secondary)
            HStack {
                if let reveal {
                    Button("Show in Finder", action: reveal)
                }
                Button("Choose Another Folder…", action: chooseFolder)
            }
            .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 460)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Help

/// What's going on, for anyone who feels lost. Opened by the ? in the bottom bar, ⌘?, Help in the menu bar, or ⌘P.
private struct HelpCard: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How Good Morning works")
                .font(.system(size: 20, design: .serif))
            VStack(alignment: .leading, spacing: 8) {
                point("Write until you reach \(session.wordGoal.formatted()) words or spend \(Prefs.minuteGoal) minutes on the page, whichever comes first.")
                point("Bands of warm colour build up in the left margin as you write. On the right, grains of sand fall down the margin as the minutes pass. Each side is full at its goal.")
                point("While you write, the page fills the screen and the Dock, menu bar and Cmd-Tab are switched off.")
                point("Esc steps out and pauses the timer. ⇧⌘L locks you back in. The timer only runs while the page is full screen and Good Morning is in front.")
                point("Reaching a goal plays a chime, counts the day toward your streak, and gives back the Dock and Cmd-Tab.")
                point("Your page saves itself every few seconds as a plain markdown file, one per day, in \(folder).")
                point("⌘P shows every command, like dark mode. ⌘, opens Settings.")
            }
            .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Got it") { session.hideHelp() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 13))
        .padding(24)
        .frame(width: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.2), radius: 24, y: 8)
    }

    private var folder: String {
        session.folderURL.map { "your “\($0.lastPathComponent)” folder" } ?? "the folder you choose"
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Helpers

/// Hands the hosting NSWindow to the session once SwiftUI has created it.
private struct WindowReader: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { ReaderView(onWindow: onWindow) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ReaderView: NSView {
        let onWindow: @MainActor (NSWindow) -> Void

        init(onWindow: @escaping @MainActor (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow(window) }
        }
    }
}

extension Color {
    /// Warm off-white by day, warm near-black by night.
    static let paper = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.11, green: 0.105, blue: 0.10, alpha: 1)
            : NSColor(red: 0.98, green: 0.972, blue: 0.955, alpha: 1)
    })
}
