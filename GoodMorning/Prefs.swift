import Foundation

/// Goals live in UserDefaults so the Settings window can edit them with @AppStorage.
enum Prefs {
    static let wordGoalKey = "wordGoal"
    static let minuteGoalKey = "minuteGoal"

    static let defaultWordGoal = 1000
    static let defaultMinuteGoal = 30

    static var wordGoal: Int { positive(wordGoalKey, or: defaultWordGoal) }
    static var minuteGoal: Int { positive(minuteGoalKey, or: defaultMinuteGoal) }

    private static func positive(_ key: String, or fallback: Int) -> Int {
        let value = UserDefaults.standard.integer(forKey: key)
        return value > 0 ? value : fallback
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
