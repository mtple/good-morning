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
/// you write, and on the right grains of sand fall down the margin as the minutes pass. Soft and slow
/// enough to stay out of the way at the edge of your eye.
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
                        // Smooth enough for a grain in flight. Twenty dots cost next to nothing to redraw.
                        TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in grains }
                    } else if session.isTimerRunning {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in grains }
                    } else {
                        grains
                    }
                }
                .frame(width: 32, height: height)
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
        FallingGrains(elapsed: session.elapsedExact, goal: Double(max(1, session.secondsGoal)),
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

/// A fixed number in 0..<1 for each grain and `salt`, so every grain has its own manner, the same every day.
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

/// The time as ten grains of sand, each a tenth of the goal, in a column of twenty places. They start
/// stacked in the top half. In each stretch the lowest grain lets go, the ones above slide down after it,
/// and it falls to the pile at the bottom, at its own uneven pace, swaying a little, and lands with a small
/// bounce. With Reduce Motion on, nothing moves: the top empties from its surface and the pile fills from
/// the floor, each grain fading across.
private struct FallingGrains: View {
    let elapsed: Double  // seconds on the page today
    let goal: Double     // seconds in the time goal
    var reduceMotion = false

    private static let grains = 10
    private static let diameter: CGFloat = 17

    var body: some View {
        Canvas { context, size in
            let rows = Self.grains * 2
            let pitch = size.height / CGFloat(rows)
            let middle = size.width / 2
            let stretch = goal / Double(Self.grains)
            let progress = max(0, elapsed / stretch)
            let current = Int(progress.rounded(.down))  // the grain on the move
            let into = (progress - Double(current)) * stretch  // seconds into its stretch
            let mover = current < Self.grains && !reduceMotion
                ? Fall(grain: current, stretch: stretch, distance: CGFloat(Self.grains - current)) : nil

            for row in 0..<rows {
                context.stroke(Self.dot(at: CGPoint(x: middle, y: (CGFloat(row) + 0.5) * pitch)),
                               with: .color(.primary.opacity(0.1)), lineWidth: 1)
            }
            for grain in 0..<Self.grains {
                for place in places(of: grain, current: current, into: into, stretch: stretch,
                                    mover: mover, pitch: pitch) where place.amount > 0 {
                    let center = CGPoint(x: middle + place.x, y: (place.row + 0.5) * pitch)
                    let color = dawn(at: min(1, max(0, 1 - Double(center.y / size.height))))
                    context.fill(Self.dot(at: center), with: .color(color.opacity(0.5 * place.amount)))
                }
            }
        }
    }

    /// Where a grain is drawn: a sideways offset in points, a row (0 at the top, with fractions in between),
    /// and how strongly. A grain fading across under Reduce Motion is drawn in two places at once.
    private func places(of grain: Int, current: Int, into: Double, stretch: Double, mover: Fall?,
                        pitch: CGFloat) -> [(x: CGFloat, row: CGFloat, amount: Double)] {
        let neck = CGFloat(Self.grains - 1)  // the lowest place in the top half, where grains let go
        let pile = CGFloat(Self.grains * 2 - 1 - grain)  // where this grain comes to rest
        if grain < current { return [(x: 0, row: pile, amount: 1)] }
        guard let mover else {
            let moved = grain == current ? into / stretch : 0
            return [(x: 0, row: CGFloat(grain), amount: 1 - moved), (x: 0, row: pile, amount: moved)]
        }
        if grain == current {
            let at = mover.position(at: into)
            return [(x: at.x, row: neck + at.fallen - at.lift / pitch, amount: 1)]
        }
        // Still in the top half, stacked down to the neck. They slide down a place each time the one below lets go.
        return [(x: 0, row: neck - CGFloat(grain - current) + mover.settled(at: into), amount: 1)]
    }

    private static func dot(at center: CGPoint) -> Path {
        Path(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                               width: diameter, height: diameter))
    }
}

/// One grain's trip down the margin. Each grain has its own: when it lets go, how long it takes,
/// how its speed comes and goes, how it sways, and how high it bounces when it lands.
private struct Fall {
    let distance: CGFloat  // rows from the neck to its place on the pile
    let start: Double      // seconds into the stretch when it lets go
    let end: Double        // seconds into the stretch when it lands
    let bounceTime: Double
    let settleStart: Double  // when it has cleared the neck, so the grains above can follow
    let settleTime: Double
    let sway: CGFloat, swayTurns: Double, swayPhase: Double
    let wobble: Double, wobblePhase: Double
    let bounce: CGFloat  // points

    init(grain: Int, stretch: Double, distance: CGFloat) {
        self.distance = distance
        bounceTime = min(1.4, stretch * 0.1)
        settleTime = min(2.5, stretch * 0.1)
        // Longer drops take longer, give or take, and each one waits a different while before letting go.
        let room = stretch - bounceTime
        let length = min(room, room * (0.35 + 0.05 * Double(distance)) * (0.85 + 0.3 * noise(grain, 1)))
        start = (room - length) * noise(grain, 2)
        end = start + length
        sway = 1.5 + 2 * CGFloat(noise(grain, 3))
        swayTurns = 1 + 1.5 * noise(grain, 4)
        swayPhase = noise(grain, 5)
        wobble = 0.07 * noise(grain, 6)
        wobblePhase = noise(grain, 7) * 2 * .pi
        bounce = 4 + 4 * CGFloat(noise(grain, 8))
        var q = 0.0
        while q < 1, Self.drop(q, wobble: wobble, phase: wobblePhase) * Double(distance) < 1 { q += 0.01 }
        // Finished before the next grain lets go, so nothing jumps between stretches.
        settleStart = min(start + q * length, stretch - settleTime)
    }

    /// How far down the drop it is, 0...1, a share `q` of the way through. Slow to start and quicker at the
    /// end, like something falling, with a little give and take in the speed. Always moving downward.
    private static func drop(_ q: Double, wobble: Double, phase: Double) -> Double {
        0.6 * q * q + 0.4 * q + wobble * sin(4 * .pi * q + phase) * q * (1 - q)
    }

    /// Sideways offset and bounce height in points, and rows fallen, `t` seconds into the stretch.
    func position(at t: Double) -> (x: CGFloat, fallen: CGFloat, lift: CGFloat) {
        if t <= start { return (x: 0, fallen: 0, lift: 0) }
        if t < end {
            let q = (t - start) / (end - start)
            let x = sway * CGFloat(sin(2 * .pi * (q * swayTurns + swayPhase)) * sin(.pi * q))
            return (x: x, fallen: distance * CGFloat(Self.drop(q, wobble: wobble, phase: wobblePhase)), lift: 0)
        }
        // Two and a half small hops, each lower than the last.
        let τ = min(1, (t - end) / bounceTime)
        return (x: 0, fallen: distance, lift: bounce * CGFloat(abs(sin(2.5 * .pi * τ)) * (1 - τ) * (1 - τ)))
    }

    /// How far the grains above have slid down after it, 0...1.
    func settled(at t: Double) -> CGFloat {
        let s = min(1, max(0, (t - settleStart) / settleTime))
        return CGFloat(s * s * (3 - 2 * s))
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
