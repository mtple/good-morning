import AppKit
import Observation

/// Today's writing session: the page, the timer, the goal, the lock and the streak.
///
/// Rules:
/// - Opening the app locks it until you write `wordGoal` words or spend `minuteGoal` minutes on the page.
/// - Either one counts the day toward the streak. Time only accrues on the full-screen page while the app is frontmost
///   and the screen is awake, unlocked and yours.
/// - One tap of Esc leaves the lock and pauses the timer. Locking in again resumes it.
/// - Once the goal is met the lock relaxes on its own. You can keep writing as long as you like.
/// - Writing is never dropped: a page that won't save stays in memory, and is copied aside before anything replaces it.
///   A page that won't open is left as it is, and isn't shown or locked until it opens.
/// - Today's page can be edited elsewhere too (Obsidian, or sync). With nothing unsaved here, the change is taken in.
///   If both changed, the other version is saved beside the page before this one is written, so both are kept.
@MainActor
@Observable
final class Session {
    private(set) var text = ""
    private(set) var wordCount = 0
    private(set) var elapsed = 0           // seconds today, up to the last check (see elapsedNow)
    private(set) var isLocked = false      // Dock, menu bar and Cmd-Tab are off
    private(set) var isFullScreen = false  // window covers the screen (locked, or done but not yet left)
    private(set) var isComplete = false    // today counts toward the streak
    private(set) var isShowingCommands = false  // the Cmd-P palette is up
    private(set) var isShowingHelp = false      // the "How Good Morning works" card is up
    private(set) var streak = 0
    private(set) var folderURL: URL?
    private(set) var loadError: String?    // today's page couldn't be read: it's left untouched and not shown
    private(set) var saveError: String?    // the last save failed (the page, or else the time log); cleared by one that works
    private(set) var logNotice: String?    // the time log is damaged or unreadable, copied from the store

    /// The problem to show, most serious first.
    var errorMessage: String? { loadError ?? saveError ?? logNotice }

    var wordGoal: Int { Prefs.wordGoal }
    var secondsGoal: Int { Prefs.minuteGoal * 60 }
    var secondsLeft: Int { max(0, secondsGoal - elapsedNow) }
    var isTimerRunning: Bool { runningSince != nil }

    /// Today's seconds on the page, including the stretch running right now.
    var elapsedNow: Int {
        max(0, elapsed + runningSeconds)
    }

    /// The same, to the fraction of a second, for drawing things that move smoothly with the clock.
    var elapsedExact: Double {
        guard let since = runningSince else { return Double(elapsed) }
        let running = since.duration(to: .now).components
        return Double(elapsed) + max(0, Double(running.seconds) + Double(running.attoseconds) / 1e18)
    }

    /// The further along of the two goals, 0...1.
    var progress: Double {
        if isComplete { return 1 }
        let words = Double(wordCount) / Double(max(1, wordGoal))
        let time = Double(elapsed) / Double(max(1, secondsGoal))
        return min(1, max(words, time))
    }

    private let store = JournalStore()
    private let lockdown = Lockdown()
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var day = Day.today
    @ObservationIgnored private var textDirty = false
    @ObservationIgnored private var onDisk: String?  // today's file as last read or written here (nil: no file)
    @ObservationIgnored private var saveFailure = ""  // why the page last failed to save, for the alerts
    @ObservationIgnored private var pageProblem: String?  // the last page write's failure, kept until one works
    private var runningSince: SuspendingClock.Instant?  // the timer is running: page full screen, app frontmost, nobody away
    @ObservationIgnored private var awayReasons: Set<Notification.Name> = []  // screen asleep or locked, or another user's session up
    @ObservationIgnored private var awayObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var pendingLock: Task<Void, Never>?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var hasOpened = false
    @ObservationIgnored private var isTurningPage = false  // a new folder or new day is under way
    @ObservationIgnored private var notices: [Notice] = []
    @ObservationIgnored private var lastEdit: SuspendingClock.Instant?  // when you last typed

    /// Something to tell you that can wait for a calm moment (see showNotice). Kept across a quit if it wasn't shown.
    private struct Notice: Codable {
        let title: String
        let text: String
        var file: URL?
    }

    private static let noticesKey = "pendingNotices"

    init() {
        folderURL = store.folder
        logNotice = store.logNotice
        // Anything not yet said when the app last quit (a page copied aside while quitting, say).
        if let saved = UserDefaults.standard.data(forKey: Self.noticesKey) {
            UserDefaults.standard.removeObject(forKey: Self.noticesKey)
            notices = (try? JSONDecoder().decode([Notice].self, from: saved)) ?? []
        }
        // Left by an earlier build, which kept only this one.
        if let path = UserDefaults.standard.string(forKey: "rescuedOnQuit") {
            UserDefaults.standard.removeObject(forKey: "rescuedOnQuit")
            let file = URL(fileURLWithPath: path)
            notices.append(Notice(title: "Your page couldn't be saved to your folder",
                                  text: "So nothing was lost, a copy was saved as “\(file.lastPathComponent)” in Good Morning's Unsaved Pages folder.",
                                  file: file))
        }
    }

    /// On quit: notices not yet shown wait for the next launch, rather than holding up a logout or restart.
    func keepNoticesForNextLaunch() {
        guard !notices.isEmpty, let data = try? JSONEncoder().encode(notices) else { return }
        UserDefaults.standard.set(data, forKey: Self.noticesKey)
    }

    // MARK: Lifecycle

    /// Called when the main window appears. Today's page opens only the first time, so a window
    /// reopened after a cancelled quit keeps what's in it.
    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.tabbingMode = .disallowed
        // The lock does its own full screen. Native full screen (green button) would fight it.
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.insert(.fullScreenNone)
        installEscapeKey()
        watchForAway()
        startTicker()
        if folderURL != nil, !hasOpened { openToday() }
    }

    func appDidBecomeActive() {
        updateClock()
        startNewDayIfNeeded()
        takeInOutsideChange()  // back from Obsidian, say
    }

    /// Switching to another app stops the timer and saves.
    func appWillResignActive() {
        updateClock(isActive: false)
        save()
    }

    /// On quit. True once the page is saved or copied aside. If neither works, you choose: save a copy
    /// somewhere, stay, or quit and lose what's unsaved. False keeps the app open.
    func prepareToQuit() -> Bool {
        if keepPageSafe() { return true }
        let alert = NSAlert()
        alert.messageText = "Today's page couldn't be saved"
        alert.informativeText = "\(saveFailure)\n\nIf you quit now, what you've written since the last save is lost."
        alert.addButton(withTitle: "Save a Copy…")
        alert.addButton(withTitle: "Don't Quit")
        alert.addButton(withTitle: "Quit Without Saving")
        alert.buttons[1].keyEquivalent = "\u{1b}"  // Esc doesn't quit
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveCopy()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    func chooseFolder() {
        guard !isTurningPage else { return }
        isTurningPage = true
        defer { isTurningPage = false }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose where your daily pages are saved. A folder inside your Obsidian vault works well."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard keepPageSafe() else {
            saveError = "Couldn't save today's page, so the folder wasn't changed."
            return
        }
        do {
            try store.choose(url)
            folderURL = url
            openToday()
        } catch {
            textDirty = true  // the page stays here, so it still has to reach this folder (a copy may be aside)
            saveError = "Couldn't use that folder: \(error.localizedDescription)"
        }
    }

    /// If the app sat open overnight, a new day gets a new page, once yesterday's is safe.
    private func startNewDayIfNeeded() {
        guard !isTurningPage, hasOpened, folderURL != nil, Day.today != day else { return }
        isTurningPage = true
        defer { isTurningPage = false }
        guard keepPageSafe() else { return }
        openToday()
    }

    /// Shows today's page in Finder, or its folder if the page isn't there.
    func revealPage() {
        guard let target = revealTarget else { return }
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    /// False when neither the page nor its folder is there (a drive that's unplugged, say): nothing to show.
    var canRevealPage: Bool { revealTarget != nil }

    private var revealTarget: URL? {
        [store.pageURL(for: day), folderURL].compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    private func openToday() {
        hasOpened = true
        day = .today
        do {
            onDisk = try store.readExisting(day)
            text = onDisk ?? ""
            loadError = nil
        } catch {
            onDisk = nil
            text = ""
            loadError = "Couldn't open \(day.key).md: \(error.localizedDescription)"
        }
        wordCount = countWords(text)
        textDirty = false
        pageProblem = nil  // only reached once the last page was saved or copied aside
        let record = store.record(for: day)
        runningSince = nil
        elapsed = record.seconds
        isComplete = record.completed || wordCount >= wordGoal || elapsed >= secondsGoal
        if isComplete && !record.completed { markComplete() }
        streak = store.streak(endingOn: day, wordGoal: wordGoal)
        logNotice = store.logNotice

        if isComplete || loadError != nil {
            leaveLockdown()
        } else {
            lockIn()
        }
        // Already locked (a new folder chosen from the palette, say): the timer starts again on the new page.
        updateClock()
    }

    // MARK: Writing

    /// Ignored while the page couldn't be read, so nothing typed can end up over it.
    func edit(_ newText: String) {
        guard loadError == nil, newText != text else { return }
        // Typing means you're here, whatever a missed wake or unlock notification said.
        if !awayReasons.isEmpty {
            awayReasons.removeAll()
            updateClock()
        }
        text = newText
        wordCount = countWords(newText)
        textDirty = true
        lastEdit = .now
        checkGoal()
    }

    /// Autosave runs every few seconds, on switching away, and on quit. True when the page is safely on disk
    /// or there was nothing to write. False when writing it failed: the text stays here, still unsaved.
    /// A time log that won't save is shown as an error but doesn't make this false.
    @discardableResult
    func save() -> Bool {
        guard folderURL != nil, hasOpened else { return true }
        bankTime()
        var record = store.record(for: day)
        record.seconds = elapsed
        store.setRecord(record, for: day)
        var pageIsSafe = true
        if textDirty, loadError == nil {
            do {
                try keepOtherVersion()
                try store.write(text, for: day)
                if !(text.isEmpty && onDisk == nil) { onDisk = text }  // an empty page with no file stays without one
                textDirty = false
                pageProblem = nil
            } catch {
                pageIsSafe = false
                saveFailure = error.localizedDescription
                pageProblem = "Not saved: \(saveFailure)"
            }
        }
        // A page error stays up until a page write works, even through saves with nothing new to write.
        var problem = pageProblem
        do {
            try store.saveLog()
        } catch {
            problem = problem ?? "Time not saved: \(error.localizedDescription)"
        }
        if saveError != problem { saveError = problem }
        if logNotice != store.logNotice { logNotice = store.logNotice }
        if let repair = store.takeLogRepair() {
            notices.append(Notice(title: "The time log was damaged", text: repair))
        }
        // A time log that couldn't be read before may have come back with more time for today.
        let logged = store.record(for: day).seconds
        if logged > elapsed { elapsed = logged }
        return pageIsSafe
    }

    /// Before writing over today's file: if it was changed elsewhere since it was last read or written here, that
    /// version is saved beside it first, so both are kept. A file that has gone is simply written again. Throws if
    /// the file can't be checked or the other version can't be kept, and then nothing is written over.
    private func keepOtherVersion() throws {
        guard let current = try store.readExisting(day), current != onDisk else { return }
        if current != text {  // unless it already says what's here (a sync echo, say)
            let copy = try store.saveOtherVersion(current, for: day)
            notices.append(Notice(title: "Today's page was also changed outside Good Morning",
                                  text: "Your writing here is still today's page. The other version was saved beside it as “\(copy.lastPathComponent)”.",
                                  file: copy))
        }
        onDisk = current  // kept once it's safe, so a failed write below doesn't copy it again on every retry
    }

    /// A change made elsewhere (Obsidian, sync) while nothing here is waiting to be saved: show it, so what you type
    /// next adds to it rather than to an older page. Only once you've paused, so it can't land under a keystroke or
    /// an input method's composition. If it would lose writing (an older synced version, say), the version here is
    /// kept beside it first, just in case; if that can't be done, the change waits.
    private func takeInOutsideChange() {
        guard hasOpened, loadError == nil, !textDirty, !isTurningPage, isPaused,
              let current = try? store.readExisting(day), current != onDisk else { return }
        if let mine = onDisk, losesWriting(from: mine, to: current) {
            guard let copy = try? store.saveOtherVersion(mine, for: day) else { return }
            notices.append(Notice(title: "Today's page changed outside Good Morning",
                                  text: "Some of what Good Morning had isn't in the new version, so that version was saved beside it as “\(copy.lastPathComponent)”, just in case.",
                                  file: copy))
        }
        onDisk = current
        text = current
        wordCount = countWords(current)
        checkGoal()
    }

    /// Whether taking in `new` would lose writing from `old`: it has fewer words, or more than about a sentence of
    /// `old` is missing between where they start and end alike (an older version with additions, say).
    /// Additions and small fixes don't count, so ordinary edits in Obsidian don't leave copies behind.
    private func losesWriting(from old: String, to new: String) -> Bool {
        if countWords(new) < countWords(old) { return true }
        let start = zip(old, new).prefix { $0 == $1 }.count
        let end = zip(old.reversed(), new.reversed()).prefix { $0 == $1 }.count
        let missing = old.count - start - min(end, old.count - start, new.count - start)
        return missing > 40
    }

    /// No typing in the last two seconds, and nothing half-composed in an input method.
    private var isPaused: Bool {
        if let lastEdit, lastEdit.duration(to: .now) < .seconds(2) { return false }
        if let textView = window?.firstResponder as? NSTextView, textView.hasMarkedText() { return false }
        return true
    }

    /// Before anything replaces the page or its folder, or the app quits. Saves it, or if that fails, puts a copy
    /// in the app's Unsaved Pages folder, with a notice saying where for a calm moment (the next launch, if
    /// quitting), so nothing is held up by an alert. False only if neither worked, and then the page must stay.
    private func keepPageSafe() -> Bool {
        if save() { return true }
        guard let url = try? store.rescue(text, for: day) else { return false }
        textDirty = false
        notices.append(Notice(title: "Your page couldn't be saved to your folder",
                              text: "\(saveFailure)\n\nSo nothing was lost, a copy was saved as “\(url.lastPathComponent)” in Good Morning's Unsaved Pages folder.",
                              file: url))
        return true
    }

    /// One waiting notice, from the regular check. Never over the full-screen page while you write (it waits for the
    /// goal or Esc), never while a lock is on its way (that would take the screen straight back from Finder), and
    /// never in the middle of changing pages or quitting. A sheet rather than a modal alert, so autosave and the
    /// timer carry on underneath, with OK as the default so Return just closes it.
    private func showNotice() {
        guard !notices.isEmpty, NSApp.isActive, !isFullScreen, pendingLock == nil, !isTurningPage,
              let window, window.attachedSheet == nil else { return }
        let notice = notices.removeFirst()
        let alert = NSAlert()
        alert.messageText = notice.title
        alert.informativeText = notice.text
        alert.addButton(withTitle: "OK")
        if notice.file != nil { alert.addButton(withTitle: "Show in Finder") }
        alert.beginSheetModal(for: window) { response in
            guard response == .alertSecondButtonReturn, let file = notice.file else { return }
            NSWorkspace.shared.activateFileViewerSelecting([file])
        }
    }

    /// Lets you put the page wherever you like. True if it was written there.
    private func saveCopy() -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(day.key).md"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    /// Every 5 seconds: bank the time, check the goal, autosave. When the time goal falls
    /// sooner than that, the wait is cut short so the chime lands on it.
    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.timeToNextCheck ?? .seconds(5))
                self?.tick()
            }
        }
    }

    private var timeToNextCheck: Duration {
        guard let since = runningSince, !isComplete else { return .seconds(5) }
        let left = Duration.seconds(secondsGoal - elapsed) - since.duration(to: .now)
        return min(.seconds(5), max(.milliseconds(100), left))
    }

    private func tick() {
        guard hasOpened else { return }
        // A page that couldn't be read is tried again, so a drive that comes back recovers. Only while the app is
        // frontmost, so the lock that follows can't take the screen from another app.
        if loadError != nil, NSApp.isActive, !isTurningPage, (try? store.read(day)) != nil { openToday() }
        takeInOutsideChange()
        bankTime()
        checkGoal()
        save()
        showNotice()
    }

    // MARK: Timer

    /// Whole seconds in the stretch running right now. The clock is monotonic and stops while the Mac sleeps,
    /// so changing the time can't add or take away any.
    private var runningSeconds: Int {
        guard let since = runningSince else { return 0 }
        return max(0, Int(since.duration(to: .now).components.seconds))
    }

    /// Moves the running stretch into `elapsed`, keeping the part-second still running.
    /// Time is measured by the clock, not by counting checks, so it stays exact however rarely they run.
    private func bankTime() {
        guard let since = runningSince else { return }
        let seconds = runningSeconds
        guard seconds > 0 else { return }
        elapsed += seconds
        runningSince = since + .seconds(seconds)
    }

    /// The timer runs only while the page is full screen, the app is frontmost, and the screen is awake,
    /// unlocked and yours. Esc pauses it.
    private func updateClock(isActive: Bool? = nil) {
        bankTime()
        if isFullScreen, isActive ?? NSApp.isActive, awayReasons.isEmpty {
            if runningSince == nil { runningSince = .now }
        } else {
            runningSince = nil
        }
    }

    /// Time stops while the screen is asleep, locked or showing the screensaver, or another user's session is up.
    /// Each "away" notification adds its name to `awayReasons`, and the matching "back" notification takes it out.
    private func watchForAway() {
        guard awayObservers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let pairs: [(center: NotificationCenter, away: Notification.Name, back: Notification.Name)] = [
            (workspace, NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification),
            (DistributedNotificationCenter.default(),
             Notification.Name("com.apple.screenIsLocked"), Notification.Name("com.apple.screenIsUnlocked")),
            (DistributedNotificationCenter.default(),
             Notification.Name("com.apple.screensaver.didstart"), Notification.Name("com.apple.screensaver.didstop")),
        ]
        for (center, away, back) in pairs {
            awayObservers.append(center.addObserver(forName: away, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setAway(away, true) }
            })
            awayObservers.append(center.addObserver(forName: back, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setAway(away, false) }
            })
        }
    }

    private func setAway(_ reason: Notification.Name, _ isAway: Bool) {
        if isAway {
            awayReasons.insert(reason)
        } else {
            awayReasons.remove(reason)
        }
        updateClock()
    }

    // MARK: Goal and streak

    private func checkGoal() {
        // The log can also say so: a time log that couldn't be read at launch may have come back.
        guard !isComplete, wordCount >= wordGoal || elapsed >= secondsGoal || store.record(for: day).completed else { return }
        isComplete = true
        markComplete()
        streak = store.streak(endingOn: day, wordGoal: wordGoal)
        save()
        NSSound(named: "Glass")?.play()
        if isLocked {
            lockdown.relax()
            isLocked = false
        }
    }

    private func markComplete() {
        var record = store.record(for: day)
        record.completed = true
        record.seconds = elapsed
        store.setRecord(record, for: day)
    }

    // MARK: Lockdown

    /// Lock (again). Does nothing once today's goal is met, while the page couldn't be read,
    /// or if the lock is already on or on its way.
    func lockIn() {
        guard !isComplete, folderURL != nil, loadError == nil, !isLocked, pendingLock == nil else { return }
        // A short delay lets SwiftUI finish placing the window at launch before we resize it.
        pendingLock = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            // Before touching pendingLock, so a cancelled lock can't clear a newer one.
            guard !Task.isCancelled, let self else { return }
            self.pendingLock = nil
            guard let window = self.window, !self.isComplete else { return }
            self.lockdown.engage(window)
            self.isLocked = true
            self.isFullScreen = true
            self.updateClock()
        }
    }

    /// Also calls off a lock that's on its way.
    func leaveLockdown() {
        pendingLock?.cancel()
        pendingLock = nil
        guard let window else { return }
        lockdown.release(window)
        isLocked = false
        isFullScreen = false
        updateClock()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Commands

    /// Cmd-P. The menu bar is hidden while you write, so the palette is the way to everything else.
    func toggleCommands() {
        isShowingCommands.toggle()
        if isShowingCommands {
            isShowingHelp = false
            window?.makeKeyAndOrderFront(nil)
        }
    }

    func hideCommands() {
        isShowingCommands = false
    }

    /// ⌘?, the ? in the bottom bar, or Help in the palette. While it's up, typing doesn't go into the page.
    func toggleHelp() {
        isShowingHelp.toggle()
        if isShowingHelp {
            isShowingCommands = false
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(nil)
        }
    }

    func hideHelp() {
        isShowingHelp = false
    }

    /// One tap of Esc closes the command palette or help if either is up, or else leaves the full-screen page,
    /// locked or not, or calls off a lock that's on its way. Elsewhere Esc is swallowed, so the text view doesn't
    /// pop up its word-completion list.
    private func installEscapeKey() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // 53 = Esc
            let windowNumber = event.windowNumber
            let handled = MainActor.assumeIsolated {
                self?.handleEscape(windowNumber: windowNumber) ?? false
            }
            return handled ? nil : event
        }
    }

    private func handleEscape(windowNumber: Int) -> Bool {
        guard let window, window.windowNumber == windowNumber else { return false }
        // Let input methods (e.g. Japanese) use Esc to cancel what's being composed.
        if let textView = window.firstResponder as? NSTextView, textView.hasMarkedText() { return false }
        if isShowingCommands {
            hideCommands()
        } else if isShowingHelp {
            hideHelp()
        } else if isFullScreen || pendingLock != nil {
            leaveLockdown()
        }
        return true
    }
}
