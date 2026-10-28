# Good Morning

A small Mac app for morning pages. You open it and it locks the Mac until you write 750 words or 30 minutes pass, whichever comes first. Your pages are saved as plain markdown, one file per day, in a folder you choose, so they can live inside your Obsidian vault.

No accounts and no network. Just a page, a timer and a streak.

## How it behaves

- **Opening the app locks it.** The window fills the screen, the Dock and menu bar disappear, and Cmd-Tab and Cmd-H stop working.
- **Esc gets you out.** One tap returns you to a normal window and pauses the timer. Shift-Cmd-L (or the "Lock in" link) locks you back in and starts it again.
- **Cmd-P shows every command:** dark or light mode, lock in, change folder, Settings. The menu bar is hidden while you write, so this is how you reach everything else. The bottom bar shows the hint, and an empty page tells you to just start typing.
- **Lost?** The ? at the bottom right (or Cmd-?, or Help in the menu bar) opens a short card that explains all of this.
- **A day counts** if you reach the word goal *or* spend the full time on the page. Time only counts while the page is full screen and Good Morning is the frontmost app, and not while the Mac sleeps, the screen is locked, or the display is asleep.
- **When you reach the goal,** a chime plays and the lock relaxes. The Dock, menu bar and Cmd-Tab come back, and the page stays full screen until you press Esc. You can keep writing as long as you like.
- **The margins track your progress.** Lines build up in the left margin as you write, one for every 30th of the word goal, and dots fill in on the right as the time passes. They are drawn faint and change a hair at a time, so they stay out of the way until you look. Hover over either for the numbers. They step aside when the window is too narrow to fit them.
- **Your streak** counts consecutive days. Until today counts, the streak shown is the one through yesterday.
- **Pages** are saved as `2026-10-23.md` in the folder you pick on first launch. File names are always ISO dates, and an open page keeps its file if the time zone changes. Autosave runs every 5 seconds, whenever you switch away, and on quit. A day with no writing gets no file.
- **Editing today's page elsewhere** (in Obsidian, or through sync) is fine. If Good Morning has nothing unsaved, your change shows up in it within a few seconds. If both changed, Good Morning keeps its writing as today's page and saves the other version beside it, as `2026-10-23 other version 10.32.15.md`, and tells you. Nothing is written over.
- **If a save fails** (say the folder's drive is gone), the page stays on screen with the error and autosave keeps trying. Before leaving a page it couldn't save (changing folders, a new day, quitting), Good Morning copies it to its own Unsaved Pages folder and tells you where. That's `Application Support/Good Morning/Unsaved Pages` inside the app's container in `~/Library/Containers`. If even that fails, quitting asks first. A page that can't be read is left untouched and not shown.
- **Time is logged** in a hidden `.good-morning.json` in the same folder. Word counts come from the files themselves, but time can't, so it's stored there. Obsidian ignores dotfiles. If you delete the log, you lose only the days that counted by time; days that reached the word goal still count. A damaged log is repaired, keeping every day that still reads, and the original is saved beside it as a hidden file.
- **If the app stays open overnight,** switching back to it the next morning starts a new page and locks again.
- **Settings** (Cmd-,) holds the goals, the folder, the appearance (light, dark, or matching the Mac), and "Open at login", which makes it the first thing on screen in the morning.

The lock is meant to be easy to get out of. Force Quit, Mission Control and Spotlight still work. The lock only applies while this app is frontmost, and AppKit lifts it as soon as the app quits or crashes.

## Building

Requires macOS 14 or later and Xcode 16 or later.

### With XcodeGen (quickest)

```sh
brew install xcodegen
xcodegen
open GoodMorning.xcodeproj
```

Then press Cmd-R. `project.yml` already sets the deployment target, the sandbox entitlements and local signing.

### By hand

1. **File → New → Project → macOS → App.** Name it `GoodMorning`, choose SwiftUI and Swift, and set Storage to None.
2. Replace the generated Swift files with the ones in `GoodMorning/`.
3. Select the target, open **General**, and set **Minimum Deployments** to macOS 14.0.
4. Open **Signing & Capabilities → App Sandbox → File Access** and set **User Selected File** to **Read/Write**. Without this, the app can't save into the folder you pick. `GoodMorning/GoodMorning.entitlements` shows the complete set.
5. Press Cmd-R.

**Debugging tip:** if you hit a breakpoint while the app is locked, the full-screen window covers Xcode and Cmd-Tab won't work. Press Cmd-Option-Esc, or swipe up for Mission Control, to get back to Xcode.

## Code

| File | What it does |
| --- | --- |
| `GoodMorningApp.swift` | App entry, the single window, Settings, quit and activation hooks |
| `Session.swift` | Today's page, timer, goals, streak, autosave, and the Esc key |
| `Lockdown.swift` | Hiding the Dock and menu bar, disabling Cmd-Tab, filling the screen and restoring the window |
| `JournalStore.swift` | The folder bookmark, reading and writing daily files, the time log, and the streak calculation |
| `EditorView.swift` | The plain-text editor (spellcheck and smart punctuation off), its empty-page hint, and its typography |
| `ContentView.swift` | Layout, the status bar, the progress line, the margin trackers, the first-launch screen, the unreadable-page message, and the help card |
| `CommandPalette.swift` | The Cmd-P palette: every command in one place, searchable |
| `SettingsView.swift` | Goals, folder, and open at login |
| `Prefs.swift` | Defaults, dates and the word counter |

## Known limits

- Only the screen the window is on is covered. Other displays stay usable.
- The word count splits on whitespace, so markdown symbols like `#` count as words.

## License

[MIT](LICENSE)
