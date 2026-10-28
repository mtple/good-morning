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

/// The empty space either side of the text, put to work: lines of writing pile up on the left as you
/// write, and dots for the minutes fill in on the right. Faint, and still enough that nothing moves at
/// the edge of your eye. Each mark changes by a hair at a time, never with a jump.
private struct Margins: View {
    let session: Session

    var body: some View {
        GeometryReader { geo in
            let side = (geo.size.width - 680) / 2  // the text column is 680 wide, centered
            if side >= 64 {
                // Halfway out into the margin, but not so far that it leaves the page behind.
                let inset = min(side / 2, 150)
                let height = min(geo.size.height * 0.5, 420)
                let y = geo.size.height / 2

                WordMarks(progress: Double(session.wordCount) / Double(max(1, session.wordGoal)),
                          isComplete: session.isComplete)
                    .frame(width: 28, height: height)
                    .help("\(session.wordCount.formatted()) of \(session.wordGoal.formatted()) words")
                    .accessibilityElement()
                    .accessibilityLabel("Words")
                    .accessibilityValue("\(session.wordCount) of \(session.wordGoal)")
                    .position(x: side - inset, y: y)

                Group {
                    if session.isTimerRunning {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in timeMarks }
                    } else {
                        timeMarks
                    }
                }
                .frame(width: 28, height: height)
                .help(minutesText)
                .accessibilityElement()
                .accessibilityLabel("Time")
                .accessibilityValue(minutesText)
                .position(x: geo.size.width - side + inset, y: y)
            }
        }
        .ignoresSafeArea()
    }

    private var timeMarks: some View {
        TimeMarks(progress: Double(session.elapsedNow) / Double(max(1, session.secondsGoal)),
                  isComplete: session.isComplete)
            // Paused: the dots stay where they are, just quieter.
            .opacity(session.isTimerRunning || session.isComplete ? 1 : 0.5)
    }

    private var minutesText: String {
        "\(session.elapsedNow / 60) of \(Prefs.minuteGoal) minutes"
    }
}

/// How many marks make up a goal, whatever the goal is.
private let marksPerGoal = 30

/// How full mark `index` is, 0...1, when the marks fill from the first one up.
private func fill(of index: Int, progress: Double) -> Double {
    min(1, max(0, progress * Double(marksPerGoal) - Double(index)))
}

/// Short strokes stacked from the bottom, ragged on the right like lines of text.
/// Each one draws itself left to right as you write the words it stands for.
private struct WordMarks: View {
    let progress: Double
    let isComplete: Bool

    var body: some View {
        Canvas { context, size in
            let step = size.height / CGFloat(marksPerGoal)
            let ink: Color = isComplete ? .accentColor.opacity(0.5) : .primary.opacity(0.26)
            let style = StrokeStyle(lineWidth: 1.5, lineCap: .round)
            for i in 0..<marksPerGoal {
                let y = size.height - (CGFloat(i) + 0.5) * step
                let length = size.width * Self.length(of: i)
                context.stroke(line(at: y, length: length), with: .color(.primary.opacity(0.07)), style: style)
                let done = fill(of: i, progress: progress)
                if done > 0 {
                    context.stroke(line(at: y, length: length * done), with: .color(ink), style: style)
                }
            }
        }
    }

    private func line(at y: CGFloat, length: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: length, y: y))
        }
    }

    /// The same ragged edge every day, with a short line now and then where a paragraph ends.
    private static func length(of index: Int) -> CGFloat {
        if index % 7 == 6 { return 0.35 }
        let noise = sin(Double(index) * 12.9898) * 43758.5453
        return 0.6 + 0.4 * CGFloat(noise - noise.rounded(.down))
    }
}

/// A column of dots, one for each stretch of the time, filling from the bottom.
/// The current dot grows from a speck to full size over its stretch.
private struct TimeMarks: View {
    let progress: Double
    let isComplete: Bool

    var body: some View {
        Canvas { context, size in
            let step = size.height / CGFloat(marksPerGoal)
            let ink: Color = isComplete ? .accentColor.opacity(0.5) : .primary.opacity(0.26)
            for i in 0..<marksPerGoal {
                let center = CGPoint(x: size.width / 2, y: size.height - (CGFloat(i) + 0.5) * step)
                context.fill(dot(at: center, diameter: 3), with: .color(.primary.opacity(0.08)))
                let done = fill(of: i, progress: progress)
                if done > 0 {
                    context.fill(dot(at: center, diameter: 1 + 3.5 * done), with: .color(ink))
                }
            }
        }
    }

    private func dot(at center: CGPoint, diameter: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                               width: diameter, height: diameter))
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
                point("Lines build up in the left margin as you write, and dots fill in on the right as the minutes pass. Each column is full at its goal.")
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
