import AppKit
import Observation

/// Today's writing session: the page, the timer, the goal, the lock and the streak.
///
/// Rules:
/// - Opening the app locks it until you write `wordGoal` words or spend `minuteGoal` minutes on the page.
/// - Either one counts the day toward the streak. Time only accrues on the full-screen page while the app is frontmost.
/// - One tap of Esc leaves the lock and pauses the timer. Locking in again resumes it.
/// - Once the goal is met the lock relaxes on its own. You can keep writing as long as you like.
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
    private(set) var streak = 0
    private(set) var folderURL: URL?
    private(set) var errorMessage: String?

    var wordGoal: Int { Prefs.wordGoal }
    var secondsGoal: Int { Prefs.minuteGoal * 60 }
    var secondsLeft: Int { max(0, secondsGoal - elapsedNow) }
    var isTimerRunning: Bool { runningSince != nil }

    /// Today's seconds on the page, including the stretch running right now.
    var elapsedNow: Int {
        elapsed + Int(runningSince.map { Date().timeIntervalSince($0) } ?? 0)
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
    private var runningSince: Date?        // the timer is running: page full screen, app frontmost
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var hasOpened = false

    init() {
        folderURL = store.folder
    }

    // MARK: Lifecycle

    /// Called once the main window exists.
    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.tabbingMode = .disallowed
        // The lock does its own full screen. Native full screen (green button) would fight it.
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.insert(.fullScreenNone)
        installEscapeKey()
        startTicker()
        if folderURL != nil { openToday() }
    }

    func appDidBecomeActive() {
        updateClock()
        guard hasOpened, folderURL != nil, Day.today != day else { return }
        save()
        openToday()
    }

    /// Switching to another app stops the timer and saves.
    func appWillResignActive() {
        updateClock(isActive: false)
        save()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose where your daily pages are saved. A folder inside your Obsidian vault works well."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        save()
        do {
            try store.choose(url)
            folderURL = url
            errorMessage = nil
            openToday()
        } catch {
            errorMessage = "Couldn't use that folder: \(error.localizedDescription)"
        }
    }

    private func openToday() {
        hasOpened = true
        day = .today
        text = store.read(day)
        wordCount = countWords(text)
        textDirty = false
        let record = store.record(for: day)
        runningSince = nil
        elapsed = record.seconds
        isComplete = record.completed || wordCount >= wordGoal || elapsed >= secondsGoal
        if isComplete && !record.completed { markComplete() }
        streak = store.streak(endingOn: day, wordGoal: wordGoal)

        if isComplete {
            leaveLockdown()
        } else {
            lockIn()
        }
    }

    // MARK: Writing

    func edit(_ newText: String) {
        guard newText != text else { return }
        text = newText
        wordCount = countWords(newText)
        textDirty = true
        checkGoal()
    }

    /// Autosave runs every few seconds, on switching away, and on quit.
    func save() {
        guard folderURL != nil, hasOpened else { return }
        bankTime()
        var record = store.record(for: day)
        record.seconds = elapsed
        store.setRecord(record, for: day)
        do {
            if textDirty {
                try store.write(text, for: day)
                textDirty = false
            }
            try store.saveLog()
            if errorMessage != nil { errorMessage = nil }
        } catch {
            errorMessage = "Not saved: \(error.localizedDescription)"
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
        let left = Double(secondsGoal - elapsed) - Date().timeIntervalSince(since)
        return .seconds(min(5, max(0.1, left)))
    }

    private func tick() {
        guard hasOpened else { return }
        bankTime()
        checkGoal()
        save()
    }

    // MARK: Timer

    /// Moves the running stretch into `elapsed`, keeping the part-second still running.
    /// Time is measured by the clock, not by counting checks, so it stays exact however rarely they run.
    private func bankTime() {
        guard let since = runningSince else { return }
        let seconds = Int(Date().timeIntervalSince(since))
        guard seconds > 0 else { return }
        elapsed += seconds
        runningSince = since + TimeInterval(seconds)
    }

    /// The timer runs only while the page is full screen and the app is frontmost. Esc pauses it.
    private func updateClock(isActive: Bool? = nil) {
        bankTime()
        if isFullScreen, isActive ?? NSApp.isActive {
            if runningSince == nil { runningSince = Date() }
        } else {
            runningSince = nil
        }
    }

    // MARK: Goal and streak

    private func checkGoal() {
        guard !isComplete, wordCount >= wordGoal || elapsed >= secondsGoal else { return }
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

    /// Lock (again). Does nothing once today's goal is met.
    func lockIn() {
        guard !isComplete, folderURL != nil else { return }
        // A short delay lets SwiftUI finish placing the window at launch before we resize it.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, let window = self.window, !self.isComplete else { return }
            self.lockdown.engage(window)
            self.isLocked = true
            self.isFullScreen = true
            self.updateClock()
        }
    }

    func leaveLockdown() {
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
        if isShowingCommands { window?.makeKeyAndOrderFront(nil) }
    }

    func hideCommands() {
        isShowingCommands = false
    }

    /// One tap of Esc closes the command palette if it's up, or else leaves the full-screen page,
    /// locked or not. Elsewhere Esc is swallowed, so the text view doesn't pop up its word-completion list.
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
        } else if isFullScreen {
            leaveLockdown()
        }
        return true
    }
}
