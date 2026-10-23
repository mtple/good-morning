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
        let matches = commands.filter { $0.matches(query) }
        VStack(alignment: .leading, spacing: 0) {
            TextField("Type a command, like “dark”", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .padding(14)
                .focused($isFocused)
                .onSubmit { if matches.indices.contains(selection) { run(matches[selection]) } }
                .onKeyPress(.downArrow) {
                    selection = max(0, min(selection + 1, matches.count - 1))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    selection = max(0, selection - 1)
                    return .handled
                }
            Divider()
            VStack(spacing: 2) {
                if matches.isEmpty {
                    Text("No matching commands")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                ForEach(Array(matches.enumerated()), id: \.element.title) { index, command in
                    Row(command: command, isSelected: index == selection)
                        .onTapGesture { run(command) }
                        .onHover { if $0 { selection = index } }
                }
            }
            .padding(6)
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
            commands.append(Command(title: "Leave Full Screen", keywords: "exit escape unlock pause", shortcut: "esc") {
                session.leaveLockdown()
            })
        } else if session.folderURL != nil, !session.isComplete {
            commands.append(Command(title: "Lock In", keywords: "full screen focus resume start", shortcut: "⇧⌘L") {
                session.lockIn()
            })
        }
        let current = Prefs.appearance
        for appearance in Appearance.allCases {
            commands.append(Command(title: "Appearance: \(appearance.title)", keywords: "mode theme color night day",
                                    isChecked: appearance == current) {
                UserDefaults.standard.set(appearance.rawValue, forKey: Prefs.appearanceKey)
                appearance.apply()
            })
        }
        commands.append(Command(title: session.folderURL == nil ? "Choose Folder…" : "Change Folder…",
                                keywords: "pages save location obsidian vault") {
            session.chooseFolder()
        })
        commands.append(Command(title: "Settings…", keywords: "preferences goal words minutes login", shortcut: "⌘,") {
            openSettings()
        })
        return commands
    }

    private func run(_ command: Command) {
        session.hideCommands()
        // On the next turn of the run loop, so a folder picker or Settings opens over the page, not the palette.
        Task { command.action() }
    }

    private struct Command {
        let title: String
        var keywords = ""
        var shortcut = ""
        var isChecked = false
        let action: () -> Void

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
                if command.isChecked {
                    Image(systemName: "checkmark")
                } else {
                    Text(command.shortcut).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
    }
}
