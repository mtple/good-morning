import Foundation

/// Reads and writes the daily pages: one plain markdown file per day in a folder the user picks.
///
/// Alongside the pages sits a small hidden log, `.good-morning.json`, that remembers how long
/// you spent on the page each day. Words come from the files themselves; time can't, so it goes here.
/// Obsidian ignores dotfiles, so the log never shows up in the vault.
@MainActor
final class JournalStore {
    struct DayRecord: Codable, Equatable {
        var seconds = 0
        var completed = false
    }

    private(set) var folder: URL?
    private var log: [String: DayRecord] = [:]
    private var logDirty = false

    private let bookmarkKey = "journalFolderBookmark"
    private let logName = ".good-morning.json"

    init() {
        folder = resolveBookmark()
        loadLog()
    }

    // MARK: Folder

    /// Remember the folder across launches. The sandbox only lets us back in with a security-scoped bookmark.
    func choose(_ url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope,
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        folder?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        folder = url
        loadLog()
    }

    private func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    // MARK: Pages

    private func pageURL(for day: Day) -> URL? {
        folder?.appending(path: "\(day.key).md")
    }

    func read(_ day: Day) -> String {
        guard let url = pageURL(for: day) else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func write(_ text: String, for day: Day) throws {
        guard let url = pageURL(for: day) else { return }
        // Don't litter the folder with empty files for days nothing was written.
        if text.isEmpty && !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { return }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Time log

    func record(for day: Day) -> DayRecord {
        log[day.key] ?? DayRecord()
    }

    func setRecord(_ record: DayRecord, for day: Day) {
        guard log[day.key] != record else { return }
        log[day.key] = record
        logDirty = true
    }

    private func loadLog() {
        log = [:]
        logDirty = false
        guard let url = folder?.appending(path: logName),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: DayRecord].self, from: data) else { return }
        log = decoded
    }

    func saveLog() throws {
        guard logDirty, let url = folder?.appending(path: logName) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(log).write(to: url, options: .atomic)
        logDirty = false
    }

    // MARK: Streak

    /// A day counts if you hit the word goal or spent the full time on the page.
    func counts(_ day: Day, wordGoal: Int) -> Bool {
        if log[day.key]?.completed == true { return true }
        return countWords(read(day)) >= wordGoal
    }

    /// Consecutive counted days ending today. If today isn't done yet, the streak
    /// still stands from yesterday until the day is over.
    func streak(endingOn today: Day, wordGoal: Int) -> Int {
        var day = counts(today, wordGoal: wordGoal) ? today : today.adding(days: -1)
        var streak = 0
        while streak < 100_000, counts(day, wordGoal: wordGoal) {
            streak += 1
            day = day.adding(days: -1)
        }
        return streak
    }
}
