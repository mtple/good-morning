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

/// A calendar day in the user's time zone. Its key doubles as the file name: 2026-10-23.md
struct Day: Hashable {
    let date: Date

    static var today: Day { Day(date: Calendar.current.startOfDay(for: Date())) }

    var key: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func adding(days: Int) -> Day {
        Day(date: Calendar.current.date(byAdding: .day, value: days, to: date) ?? date)
    }
}

func countWords(_ text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace }).count
}
