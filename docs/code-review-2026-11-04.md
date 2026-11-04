# Code review of `main` (2026-11-04)

A full read of every file on `main` at commit `8b2175c`. Findings are ordered most serious first. Line numbers refer to that commit.

## Correctness

### 1. A new day or a new folder never re-locks once `isLockedIn` is set

`GoodMorning/Session.swift:260` (`openToday`), `GoodMorning/Session.swift:591` (`lockIn`)

`openToday()` relies on `lockIn(fillingScreen: true)` to lock the fresh page, but `lockIn` returns early on `!isLockedIn`. `isLockedIn` stays true after the goal is met, because `checkGoal` only clears `isLocked`. So a page opened overnight, or through Change Folder, starts with the timer running but no lock.

How it shows: reach 750 words, Cmd-Tab away (allowed once the goal is met), come back the next morning. `startNewDayIfNeeded` calls `openToday`, `lockIn` bails, `updateClock` starts the timer, and the Dock, menu bar and Cmd-Tab stay available. The status bar hides the "Lock in" button while `isLockedIn` is true, so the only way to the lock is Esc then ⌘L. The README promises the app "locks again".

The mirror case: Change Folder from a locked page to a folder whose today is already completed leaves the hard lock on with `isComplete` true, since `checkGoal` never runs again.

Fix at the root: have `openToday` reset the lock state (call `unlock()`, or clear `isLockedIn`) before deciding whether to `lockIn`, instead of depending on the previous page's state.

### 2. A missing folder at load reads as "no log yet", and the real log is later overwritten

`GoodMorning/JournalStore.swift:148` (`loadLog`)

`loadLog()` treats any `fileReadNoSuchFile` as a folder that has not been used yet and leaves `log = [:]` writable. `readExisting()` is more careful and distinguishes a missing folder (`FolderMissing`). If the folder is absent when the log is loaded but comes back later, `saveLog()` writes the near-empty in-memory log over the real one.

Scenario: the bookmark resolves at launch but the folder is not there yet (a network or cloud volume still mounting, or a vault restored a moment later). `loadLog` hits NoSuchFile, so `log = [:]` and `logUnreadable = false`. The first tick's `save()` calls `setRecord`, which marks the log dirty. Every save fails until the folder appears, then the atomic write replaces `.good-morning.json` with only today's entry. Every past day that counted by time is gone, which contradicts the file's own promise that nothing it couldn't read is replaced.

Fix: check `folderIsThere` (as `readExisting` does) and mark the log unreadable, so the existing `retryUnreadableLog` path merges instead of replacing.

### 3. ⌘= fires in every window of the app

`GoodMorning/Session.swift:729` (`installEscapeKey`)

The local key monitor handles ⌘= before checking which window the event belongs to. The Esc path checks `windowNumber`; the ⌘= path does not. Pressing ⌘= while Settings is key, or while typing in the palette's search field, steps up the editor's text size and swallows the key. Low impact; the same `event.windowNumber == window.windowNumber` guard fixes it.

## Simplification

### 4. `isLocked` and `isFullScreen` are tracked in both `Lockdown` and `Session`

`GoodMorning/Lockdown.swift:27`, `GoodMorning/Session.swift:24`

`Lockdown` keeps `private(set) var isLocked` and `isFullScreen`, and `Session` keeps its own copies that it sets by hand after every lockdown call. `Session` never reads Lockdown's, so there are two sources of truth kept in step manually. `Lockdown.enterFullScreen` can return early on `!isFullScreen` while `Session` still flips its flag. Either drop Lockdown's flags and pass the state in, or make Lockdown the owner and expose the flags through `Session` as observable computed properties.

## Reuse

### 5. Card overlay and card chrome are copy-pasted three times

`GoodMorning/ContentView.swift:69-98`, `GoodMorning/ContentView.swift:820-825`, `GoodMorning/CalendarView.swift:54-59`, `GoodMorning/CommandPalette.swift:61-64`

`ContentView` repeats the same dismiss backdrop plus `.padding(.top, 80).frame(maxHeight: .infinity, alignment: .top)` block for help, calendar and commands. `HelpCard`, `CalendarCard` and `CommandPalette` each repeat the same material background, separator border and shadow. A tweak to the card look or overlay placement has to be made in six places. A small `CardOverlay(isShown:dismiss:)` wrapper and a `.cardChrome(width:)` modifier would hold it once.

### 6. The page-part and appearance command lists are duplicated between the menu and the palette

`GoodMorning/GoodMorningApp.swift:74`, `GoodMorning/CommandPalette.swift:116`

The four hideable page parts (titles, keys, ⌥⌘1-4 numbering) and the appearance entries are defined once for the menu and again inline in the palette, with the shortcut strings typed by hand. Reordering or adding a part in one list but not the other makes the palette show ⌥⌘3 for a command the menu binds to ⌥⌘4, and nothing fails at build time. Move the list to a shared `PagePart` enum that both iterate, deriving the shortcut from the index in one place.

## Efficiency

### 7. `Day.formatted` builds a `DateFormatter` on every call

`GoodMorning/Prefs.swift:170`

`Day.formatted(_:)` allocates a new `DateFormatter` and calls `setLocalizedDateFormatFromTemplate` each time. `CalendarCard` evaluates it for all ~31 `DayCell.detail` help strings plus the header on every body pass, and the calendar re-renders every tick while the timer runs and on every hover. Cache one formatter per template in a static dictionary; the calendar and time zone never change for `Day`.

### 8. The sand canvas redraws at 30 fps for the whole session, mostly idle

`GoodMorning/ContentView.swift:415`

While the timer runs, the sand timer uses `TimelineView(.animation(minimumInterval: 1/30))`, and each frame calls `Sandglass.places`, which replays every completed trip and allocates fresh `Leg` closures. With a 30-minute goal a grain is in motion for only about 3 seconds of each 60-second stretch, so almost every frame is identical. Pass `paused:` to the schedule (true when no leg of the current trip is in flight), or fall back to the periodic schedule between drops.

### 9. The time log is rewritten to the vault every 5 seconds while running

`GoodMorning/Session.swift:471` (`tick`), `GoodMorning/JournalStore.swift:184` (`saveLog`)

`tick()` calls `save()` every 5 seconds, and because `record.seconds` changes on each tick, `setRecord` marks the log dirty and `saveLog()` re-encodes and atomically rewrites `.good-morning.json` each time, even with nothing typed. In an Obsidian, iCloud or Dropbox-synced vault this is a file replace every 5 seconds for the whole session, so the sync client uploads continuously and may raise conflict copies. Bank the seconds in memory and write the log on a slower cadence (say every 60 seconds), on pause, on completion and on quit, keeping the page's 5-second autosave as it is.

## Altitude

### 10. `currentDay` exposes an `@ObservationIgnored` field to views

`GoodMorning/Session.swift:57`, `GoodMorning/Session.swift:82`

`day` is `@ObservationIgnored` but exposed as `currentDay`, which `CalendarCard` uses for `today`, `isThisMonth` and its `.task` id. The calendar only notices a new day because other observed properties happen to change in `openToday` at the same time. The earlier fix "keep the open calendar's today live" patched the symptom. The root fix is to drop `@ObservationIgnored` from `day` (a tiny value type) so views depending on it are tracked like everything else.

## Not flagged

Things checked and found sound: the UTC-noon `Day` representation and its ISO file names; the outside-change detection and other-version copies; the rescue path on quit; the damaged-log salvage and backup; the sandglass heap arithmetic (columns never go negative); the Esc monitor's handling of sheets, panels and marked text; the CI build and smoke script.
