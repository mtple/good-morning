import AppKit

/// Goals and the page's look live in UserDefaults so the Settings window and the page can share them with @AppStorage.
enum Prefs {
    static let wordGoalKey = "wordGoal"
    static let minuteGoalKey = "minuteGoal"
    static let appearanceKey = "appearance"
    static let fontSizeKey = "fontSize"
    static let lineWidthKey = "lineWidth"
    static let typingSoundKey = "typingSound"

    static let defaultWordGoal = 750
    static let defaultMinuteGoal = 30
    static let defaultFontSize = 18.0
    static let fontSizes = 12.0...40.0
    static let fontSizeStep = 2.0
    static let defaultLineWidth = 680.0  // the text column, margins included
    static let lineWidths = 440.0...1240.0
    static let lineWidthStep = 80.0

    static var wordGoal: Int { positive(wordGoalKey, or: defaultWordGoal) }
    static var minuteGoal: Int { positive(minuteGoalKey, or: defaultMinuteGoal) }
    static var fontSize: Double { clamped(fontSizeKey, to: fontSizes, or: defaultFontSize) }
    static var lineWidth: Double { clamped(lineWidthKey, to: lineWidths, or: defaultLineWidth) }
    static var typingSound: Bool { UserDefaults.standard.bool(forKey: typingSoundKey) }  // off unless turned on

    /// ⌘+ and ⌘−.
    static func changeFontSize(by step: Double) {
        UserDefaults.standard.set((fontSize + step).clamped(to: fontSizes), forKey: fontSizeKey)
    }

    /// ⌘0.
    static func resetFontSize() {
        UserDefaults.standard.removeObject(forKey: fontSizeKey)
    }

    static func changeLineWidth(by step: Double) {
        UserDefaults.standard.set((lineWidth + step).clamped(to: lineWidths), forKey: lineWidthKey)
    }

    /// Turning it on plays a key, so you hear what you chose.
    @MainActor static func setTypingSound(_ isOn: Bool) {
        UserDefaults.standard.set(isOn, forKey: typingSoundKey)
        if isOn { Typewriter.shared.play(.key) }
    }

    static var appearance: Appearance {
        UserDefaults.standard.string(forKey: appearanceKey).flatMap(Appearance.init) ?? .system
    }

    private static func positive(_ key: String, or fallback: Int) -> Int {
        let value = UserDefaults.standard.integer(forKey: key)
        return value > 0 ? value : fallback
    }

    private static func clamped(_ key: String, to range: ClosedRange<Double>, or fallback: Double) -> Double {
        let value = UserDefaults.standard.double(forKey: key)
        return value > 0 ? value.clamped(to: range) : fallback
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
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

    /// Remembered, then applied.
    @MainActor func choose() {
        UserDefaults.standard.set(rawValue, forKey: Prefs.appearanceKey)
        apply()
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

/// The parts of a day, for the calendar. Gregorian, like the file names.
extension Day {
    /// Nil for a date that doesn't exist, like February 30.
    init?(year: Int, month: Int, day: Int) {
        guard let date = Self.utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              Self.utc.component(.day, from: date) == day else { return nil }
        self.init(date: date)
    }

    var year: Int { Self.utc.component(.year, from: date) }
    var month: Int { Self.utc.component(.month, from: date) }
    var dayOfMonth: Int { Self.utc.component(.day, from: date) }
    var weekday: Int { Self.utc.component(.weekday, from: date) }  // 1 is Sunday
    var daysInMonth: Int { Self.utc.range(of: .day, in: .month, for: date)?.count ?? 30 }

    /// "October 2026", "Friday, October 23" and so on, in the Mac's language, for this calendar date wherever you are.
    func formatted(_ template: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Self.utc
        formatter.timeZone = Self.utc.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

func countWords(_ text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace }).count
}
