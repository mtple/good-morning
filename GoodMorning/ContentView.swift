import AppKit
import SwiftUI

struct ContentView: View {
    let session: Session

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            if session.folderURL != nil {
                VStack(spacing: 0) {
                    ProgressLine(progress: session.progress)
                    EditorView(text: session.text, isFocused: !session.isShowingCommands && !session.isShowingHelp,
                               onChange: { session.edit($0) })
                        .frame(maxWidth: 680)
                        .frame(maxWidth: .infinity)
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
        HStack(spacing: 0) {
            left
            Spacer(minLength: 16)
            right
        }
        // The word count stays centered, whatever the two sides hold.
        .overlay { center.frame(maxWidth: 240) }
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
                if !session.isFullScreen {
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
            Text(error).foregroundStyle(.red).lineLimit(1)
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
