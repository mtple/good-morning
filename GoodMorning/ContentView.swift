import AppKit
import SwiftUI

struct ContentView: View {
    let session: Session

    @AppStorage(Prefs.fontSizeKey) private var fontSize = Prefs.defaultFontSize
    @AppStorage(Prefs.lineWidthKey) private var lineWidth = Prefs.defaultLineWidth

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            if session.folderURL != nil {
                VStack(spacing: 0) {
                    ProgressLine(progress: session.progress, celebration: session.celebrations)
                    if let loadError = session.loadError {
                        // No editor until the page can be read, so nothing typed here can replace it.
                        UnreadablePage(error: loadError, reveal: session.canRevealPage ? { session.revealPage() } : nil,
                                       chooseFolder: { session.chooseFolder() })
                    } else {
                        EditorView(text: session.text, fontSize: fontSize.clamped(to: Prefs.fontSizes),
                                   isFocused: !session.isShowingCommands && !session.isShowingHelp,
                                   onChange: { session.edit($0) })
                            // Over the bottom of the page rather than in the column, so the text doesn't move.
                            .overlay(alignment: .bottom) {
                                if session.isShowingLockReminder {
                                    LockReminder(lockIn: { session.lockIn() }, dismiss: { session.hideLockReminder() })
                                        .padding(.bottom, 10)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                            .animation(.easeOut(duration: 0.25), value: session.isShowingLockReminder)
                            .frame(maxWidth: column)
                            .frame(maxWidth: .infinity)
                    }
                    // Under the text, where the eye is, not out in the corners of a full-screen page.
                    StatusBar(session: session)
                        .frame(maxWidth: column)
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

    private var column: CGFloat { lineWidth.clamped(to: Prefs.lineWidths) }
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
            }
            if session.isTimerRunning {
                // Checks run every 5 seconds; the clock on screen still ticks each second.
                TimelineView(.periodic(from: .now, by: 1)) { _ in Text(clockText) }
            } else {
                Text(clockText)
            }
            if !session.isComplete, !session.isFullScreen, session.loadError == nil {  // no locking in to a page that isn't there
                Button("Lock in") { session.lockIn() }
                    .buttonStyle(.link)
                    .help("Command-L")
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
                // A small lift when a goal is reached.
                .phaseAnimator([false, true], trigger: session.celebrations) { content, lifted in
                    content
                        .scaleEffect(lifted ? 1.12 : 1)
                        .foregroundStyle(lifted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                } animation: { lifted in
                    lifted ? .spring(duration: 0.4, bounce: 0.5) : .easeOut(duration: 1.2)
                }
        }
    }

    private var right: some View {
        HStack(spacing: 10) {
            SaveIndicator(saves: session.pageSaves)
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

    /// Counts down to the time goal, then keeps going, counting up the whole time on the page.
    private var clockText: String {
        let seconds = session.secondsLeft > 0 ? session.secondsLeft : session.elapsedNow
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// "Saved" fades in for a moment each time the page is written to disk, then fades away.
private struct SaveIndicator: View {
    let saves: Int
    @State private var isVisible = false

    var body: some View {
        Text("Saved")
            .foregroundStyle(.tertiary)
            .opacity(isVisible ? 1 : 0)
            .task(id: saves) {
                guard saves > 0 else { return }
                withAnimation(.easeIn(duration: 0.2)) { isVisible = true }
                // A save that comes in sooner restarts this, and the word stays up.
                guard (try? await Task.sleep(for: .seconds(1.5))) != nil else { return }
                withAnimation(.easeOut(duration: 0.8)) { isVisible = false }
            }
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

/// A hairline across the top that fills with whichever goal is further along, and glows for a moment when one is reached.
private struct ProgressLine: View {
    let progress: Double
    let celebration: Int  // goes up each time a goal is reached

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.accentColor.opacity(0.6))
                .frame(width: geo.size.width * progress)
                .animation(.easeOut(duration: 0.4), value: progress)
                .phaseAnimator([false, true], trigger: celebration) { line, glowing in
                    line
                        .brightness(glowing ? 0.15 : 0)
                        .shadow(color: .accentColor.opacity(glowing ? 0.9 : 0), radius: glowing ? 6 : 0)
                } animation: { glowing in
                    glowing ? .easeIn(duration: 0.3) : .easeOut(duration: 1.6)
                }
        }
        .frame(height: 2)
    }
}

/// Shown the first time you type outside the lock: the timer isn't running. A banner, not an alert,
/// so it never takes the keyboard and nothing you type is lost.
private struct LockReminder: View {
    let lockIn: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("You're not locked in, so the timer is paused.")
            Button("Lock in", action: lockIn)
                .buttonStyle(.link)
                .help("Command-L")
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss (esc)")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
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
                point("While you write, the page fills the screen and the Dock, menu bar and Cmd-Tab are switched off.")
                point("Esc steps out and pauses the timer. ⌘L locks you back in, or steps out. The timer only runs while the page is full screen and Good Morning is in front.")
                point("Reaching a goal plays a chime, counts the day toward your streak, and gives back the Dock and Cmd-Tab.")
                point("Your page saves itself every few seconds as a plain markdown file, one per day, in \(folder).")
                point("⌘+ and ⌘− change the text size. ⌘P shows every command, like dark mode or a wider page. ⌘, opens Settings.")
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
