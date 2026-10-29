import Foundation

/// Reads and writes the daily pages: one plain markdown file per day in a folder the user picks.
///
/// Alongside the pages sits a small hidden log, `.good-morning.json`, that remembers how long
/// you spent on the page each day. Words come from the files themselves; time can't, so it goes here.
/// Obsidian ignores dotfiles, so the log never shows up in the vault.
///
/// Nothing here replaces a file it couldn't read: a page that fails to load throws rather than reading
/// as blank, an unreadable log is left alone, and a damaged log is copied aside before it's rewritten.
@MainActor
final class JournalStore {
    struct DayRecord: Codable, Equatable {
        var seconds = 0
        var completed = false
    }

    private(set) var folder: URL?
    /// The time log can't be read right now, so it's being left as it is. Nil when all is well.
    private(set) var logNotice: String?
    private var logRepair: String?           // a damaged log was repaired: say so once (see takeLogRepair)
    private var log: [String: DayRecord] = [:]
    private var logDirty = false
    private var logUnreadable = false    // couldn't be read at all: never write over it
    private var logNeedsBackup = false   // read but damaged: copy the original aside before the first rewrite

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

    func pageURL(for day: Day) -> URL? {
        folder?.appending(path: "\(day.key).md")
    }

    /// The day's page, or "" if it hasn't been written yet. Fails as readExisting does.
    func read(_ day: Day) throws -> String {
        try readExisting(day) ?? ""
    }

    /// The day's page, or nil if it hasn't been written yet. Any other failure (no permission, not UTF-8,
    /// the drive gone) throws, so a page that couldn't be read is never mistaken for a missing one.
    func readExisting(_ day: Day) throws -> String? {
        guard let url = pageURL(for: day) else { return nil }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // Not written yet, unless the folder itself is gone (moved, or on a drive that's unplugged).
            guard folderIsThere else { throw FolderMissing() }
            return nil
        }
    }

    /// When the page was changed elsewhere (Obsidian, sync) while Good Morning had changes too, the other version
    /// is kept beside it, as "2026-10-24 other version 10.32.15.md", before Good Morning's is written. Returns where.
    func saveOtherVersion(_ text: String, for day: Day) throws -> URL {
        guard let folder else { throw FolderMissing() }
        let url = Self.unusedURL(in: folder, name: "\(day.key) other version \(Self.stamp("HH.mm.ss"))", extension: "md")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private var folderIsThere: Bool {
        guard let folder else { return false }
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isFolder)
            && isFolder.boolValue
    }

    func write(_ text: String, for day: Day) throws {
        guard let url = pageURL(for: day) else { return }
        // Don't litter the folder with empty files for days nothing was written.
        if text.isEmpty && !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { return }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// When a page can't be saved to the folder, a copy goes here instead: the app's own Application Support
    /// folder (inside its sandbox container), which stays writable when the journal folder isn't.
    func rescue(_ text: String, for day: Day) throws -> URL {
        let unsaved = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Good Morning/Unsaved Pages", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: unsaved, withIntermediateDirectories: true)
        let url = Self.unusedURL(in: unsaved, name: "\(day.key) unsaved \(Self.stamp())", extension: "md")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
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

    private var logURL: URL? { folder?.appending(path: logName) }

    private func loadLog() {
        log = [:]
        logDirty = false
        logUnreadable = false
        logNeedsBackup = false
        logNotice = nil
        guard let url = logURL else { return }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return  // a folder that hasn't been used yet
        } catch {
            logUnreadable = true
            logNotice = "Couldn't read the time log, so it's being left as it is: \(error.localizedDescription)"
            return
        }
        if let decoded = try? JSONDecoder().decode([String: DayRecord].self, from: data) {
            log = decoded
            return
        }
        // Damaged: keep every day that still reads, and copy the original aside before the first rewrite.
        let salvaged = try? JSONDecoder().decode([String: Salvaged].self, from: data)
        log = salvaged?.compactMapValues(\.record) ?? [:]
        logNeedsBackup = true
    }

    /// Tries an unreadable log again (an iCloud file that has finished downloading, say), adding what this
    /// session recorded to it. The session started each day from zero, not knowing what the log held, so its
    /// time is on top of the log's; a day is completed if either says so.
    private func retryUnreadableLog() {
        let recorded = log
        loadLog()
        if logUnreadable {
            log = recorded
        } else {
            for (key, mine) in recorded {
                var merged = log[key] ?? DayRecord()
                merged.seconds += mine.seconds
                merged.completed = merged.completed || mine.completed
                log[key] = merged
            }
        }
        logDirty = true
    }

    func saveLog() throws {
        guard logDirty, let url = logURL else { return }
        if logUnreadable { retryUnreadableLog() }
        guard !logUnreadable else { throw LogUnreadable() }
        if logNeedsBackup {
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                let backup = Self.unusedURL(in: url.deletingLastPathComponent(),
                                            name: ".good-morning damaged \(Self.stamp())", extension: "json")
                try FileManager.default.copyItem(at: url, to: backup)
                logRepair = "Days that could still be read were kept, and the original is saved beside your pages as “\(backup.lastPathComponent)”."
            }
            logNeedsBackup = false
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(log).write(to: url, options: .atomic)
        logDirty = false
    }

    /// What was done about a damaged log, once, for the user to be told.
    func takeLogRepair() -> String? {
        defer { logRepair = nil }
        return logRepair
    }

    // MARK: Streak

    /// A day counts if you hit the word goal or spent the full time on the page.
    func counts(_ day: Day, wordGoal: Int) -> Bool {
        if log[day.key]?.completed == true { return true }
        return countWords((try? read(day)) ?? "") >= wordGoal
    }

    /// What one day came to, for the calendar.
    struct DaySummary: Equatable {
        var words = 0
        var seconds = 0
        var counts = false
    }

    /// A page that can't be read shows as nothing written; it's left as it is.
    func summary(of day: Day, wordGoal: Int) -> DaySummary {
        let words = countWords((try? read(day)) ?? "")
        let logged = record(for: day)
        return DaySummary(words: words, seconds: logged.seconds, counts: logged.completed || words >= wordGoal)
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

    // MARK: Helpers

    /// "2026-10-24 103215" (or another format), for names of copies that mustn't collide.
    private static func stamp(_ format: String = "yyyy-MM-dd HHmmss") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: Date())
    }

    /// `name.extension` in the folder, or "name 2.extension" and so on if that's taken, so a copy never replaces another.
    private static func unusedURL(in folder: URL, name: String, extension ext: String) -> URL {
        var url = folder.appending(path: "\(name).\(ext)")
        var number = 2
        while FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            url = folder.appending(path: "\(name) \(number).\(ext)")
            number += 1
        }
        return url
    }

    /// One day's record, or nil if that record is damaged, so one bad entry doesn't cost the rest.
    private struct Salvaged: Decodable {
        let record: DayRecord?
        init(from decoder: Decoder) throws { record = try? DayRecord(from: decoder) }
    }

    private struct FolderMissing: LocalizedError {
        var errorDescription: String? { "the folder isn't there. It may have been moved, or be on a drive that isn't connected." }
    }

    private struct LogUnreadable: LocalizedError {
        var errorDescription: String? { "the time log couldn't be read, so it was left as it is" }
    }
}
