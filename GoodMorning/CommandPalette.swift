import SwiftUI

/// Cmd-P: every action in one place. The menu bar is hidden while you write,
/// so this is how you reach the rest of the app without leaving the page.
struct CommandPalette: View {
    let session: Session

    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        let matches = recentFirst(commands).filter { $0.matches(query) }
        VStack(alignment: .leading, spacing: 0) {
            TextField("Type a command, like “dark”", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .padding(14)
                .focused($isFocused)
                .onSubmit { if matches.indices.contains(selection) { run(matches[selection]) } }
                // Up and down wrap around, so the last command is one key away.
                .onKeyPress(.downArrow) {
                    if !matches.isEmpty { selection = (selection + 1) % matches.count }
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    if !matches.isEmpty { selection = (selection - 1 + matches.count) % matches.count }
                    return .handled
                }
            Divider()
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: 2) {
                        if matches.isEmpty {
                            Text("No matching commands")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        ForEach(Array(matches.enumerated()), id: \.element.title) { index, command in
                            Row(command: command, isSelected: index == selection)
                                .id(index)
                                .onTapGesture { run(command) }
                                .onHover { if $0 { selection = index } }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 380)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: selection) { scroller.scrollTo(selection) }
            }
            Divider()
            Text("↑↓ to choose, return to run, esc to close")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(width: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.2), radius: 24, y: 8)
        .onAppear { isFocused = true }
        .onChange(of: query) { selection = 0 }
    }

    private var commands: [Command] {
        var commands: [Command] = []
        if session.isFullScreen {
            commands.append(Command(id: "lock", title: "Leave Full Screen", keywords: "exit escape unlock lock out pause", shortcut: "⌘L") {
                session.leaveLockdown()
            })
        } else if session.folderURL != nil {
            commands.append(Command(id: "lock", title: session.isComplete ? "Full Screen" : "Lock In",
                                    keywords: "full screen lock in focus resume start timer", shortcut: "⌘L") {
                session.lockIn()
            })
        }
        if session.folderURL != nil {
            commands.append(Command(title: "Calendar", keywords: "history streak past days month stats", shortcut: "⌘Y") {
                session.toggleCalendar()
            })
        }
        commands.append(Command(title: "Save Now", keywords: "write disk", shortcut: "⌘S") {
            session.saveNow()
        })
        commands.append(Command(title: "Bigger Text", keywords: "font size larger zoom in increase", shortcut: "⌘+") {
            Prefs.changeFontSize(by: Prefs.fontSizeStep)
        })
        commands.append(Command(title: "Smaller Text", keywords: "font size zoom out decrease", shortcut: "⌘−") {
            Prefs.changeFontSize(by: -Prefs.fontSizeStep)
        })
        commands.append(Command(title: "Default Text Size", keywords: "font size reset actual zoom", shortcut: "⌘0") {
            Prefs.resetFontSize()
        })
        commands.append(Command(title: "Wider Lines", keywords: "line width column page measure", shortcut: "⌘]") {
            Prefs.changeLineWidth(by: Prefs.lineWidthStep)
        })
        commands.append(Command(title: "Narrower Lines", keywords: "line width column page measure", shortcut: "⌘[") {
            Prefs.changeLineWidth(by: -Prefs.lineWidthStep)
        })
        commands.append(Command(title: "Typewriter Sound", keywords: "typing keys click clack audio noise",
                                shortcut: "⇧⌘T", isChecked: Prefs.typingSound) {
            Prefs.setTypingSound(!Prefs.typingSound)
        })
        let current = Prefs.appearance
        for (index, appearance) in Appearance.allCases.enumerated() {
            commands.append(Command(title: "Appearance: \(appearance.title)", keywords: "mode theme color night day",
                                    shortcut: "⌥⌘\(index + 1)", isChecked: appearance == current) {
                appearance.choose()
            })
        }
        commands.append(Command(id: "folder", title: session.folderURL == nil ? "Choose Folder…" : "Change Folder…",
                                keywords: "pages save location obsidian vault open", shortcut: "⌘O") {
            session.chooseFolder()
        })
        commands.append(Command(title: "Settings…", keywords: "preferences goal words minutes login font size line width", shortcut: "⌘,") {
            openSettings()
        })
        commands.append(Command(title: "Help: How Good Morning Works", keywords: "info about guide lost what why ?", shortcut: "⌘?") {
            session.toggleHelp()
        })
        return commands
    }

    /// The last few commands run from here come first, most recent at the top, then the rest in their usual order.
    private func recentFirst(_ commands: [Command]) -> [Command] {
        let recent = Prefs.recentCommands
        let used = recent.compactMap { id in commands.first { $0.id == id } }
        return used + commands.filter { !recent.contains($0.id) }
    }

    private func run(_ command: Command) {
        Prefs.noteRecentCommand(command.id)
        session.hideCommands()
        // On the next turn of the run loop, so a folder picker or Settings opens over the page, not the palette.
        Task { command.action() }
    }

    private struct Command {
        var id: String  // stays the same when the title changes with the state, like Lock In and Leave Full Screen
        let title: String
        var keywords = ""
        var shortcut = ""
        var isChecked = false
        let action: () -> Void

        init(id: String? = nil, title: String, keywords: String = "", shortcut: String = "", isChecked: Bool = false,
             action: @escaping () -> Void) {
            self.id = id ?? title
            self.title = title
            self.keywords = keywords
            self.shortcut = shortcut
            self.isChecked = isChecked
            self.action = action
        }

        /// Every word typed has to appear somewhere in the title or keywords.
        func matches(_ query: String) -> Bool {
            let haystack = "\(title) \(keywords)".lowercased()
            return query.lowercased().split(separator: " ").allSatisfy { haystack.contains($0) }
        }
    }

    private struct Row: View {
        let command: Command
        let isSelected: Bool

        var body: some View {
            HStack {
                Text(command.title)
                Spacer()
                Text(command.shortcut).foregroundStyle(.secondary)
                Image(systemName: "checkmark")
                    .opacity(command.isChecked ? 1 : 0)
                    .accessibilityHidden(!command.isChecked)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
    }
}
