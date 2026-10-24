import AppKit

/// Goals live in UserDefaults so the Settings window can edit them with @AppStorage.
enum Prefs {
    static let wordGoalKey = "wordGoal"
    static let minuteGoalKey = "minuteGoal"
    static let appearanceKey = "appearance"

    static let defaultWordGoal = 750
    static let defaultMinuteGoal = 30

    static var wordGoal: Int { positive(wordGoalKey, or: defaultWordGoal) }
    static var minuteGoal: Int { positive(minuteGoalKey, or: defaultMinuteGoal) }

    static var appearance: Appearance {
        UserDefaults.standard.string(forKey: appearanceKey).flatMap(Appearance.init) ?? .system
    }

    private static func positive(_ key: String, or fallback: Int) -> Int {
        let value = UserDefaults.standard.integer(forKey: key)
        return value > 0 ? value : fallback
    }
}

/// Light or dark page, or follow the Mac.
enum Appearance: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Set app-wide, so Settings and the folder picker match the page.
    @MainActor func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// A calendar date where the user is. Its key doubles as the file name: 2026-10-23.md
///
/// The date is held as noon UTC on that day: a plain calendar date with no time zone in it. So the key of
/// a page that's open can't change under it when the Mac's time zone or calendar setting changes, and adding
/// days never drifts. File names are always Gregorian ISO dates, whatever calendar the Mac is set to.
struct Day: Hashable {
    let date: Date

    static var today: Day {
        var here = Calendar(identifier: .gregorian)
        here.timeZone = .current
        let c = here.dateComponents([.year, .month, .day], from: Date())
        return Day(date: utc.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 12)) ?? Date())
    }

    var key: String {
        let c = Self.utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func adding(days: Int) -> Day {
        Day(date: Self.utc.date(byAdding: .day, value: days, to: date) ?? date)
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}

func countWords(_ text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace }).count
}
