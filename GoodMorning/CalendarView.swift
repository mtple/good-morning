import SwiftUI

/// ⌘Y: a month of days at a glance. A filled day counted toward the streak, a ringed one has some writing,
/// and today has a line under it. Hover a day for its words and time. ← and → step through the months.
///
/// Only how much you wrote, never what: morning pages aren't for rereading.
struct CalendarCard: View {
    let session: Session

    @State private var month: Month
    @State private var pastSummaries: [Day: JournalStore.DaySummary] = [:]
    @FocusState private var isFocused: Bool

    init(session: Session) {
        self.session = session
        _month = State(initialValue: Month(containing: session.currentDay))
    }

    private var today: Day { session.currentDay }
    private var isThisMonth: Bool { month == Month(containing: today) }

    /// The month's past days as read from the folder, plus today straight from the session, so today's ring,
    /// time and the totals keep up while the card is open.
    private var summaries: [Day: JournalStore.DaySummary] {
        var summaries = pastSummaries
        if isThisMonth { summaries[today] = session.todaySummary }
        return summaries
    }

    /// What the past days were read for. A new folder, a new day or a new word goal reads them again.
    private struct Source: Hashable {
        let month: Month
        let folder: URL?
        let today: Day
        let wordGoal: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            grid
            Text(totals)
                .foregroundStyle(.secondary)
            HStack {
                Text("← → to change month, esc to close")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Done") { session.hideCalendar() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 13))
        .padding(24)
        .frame(width: 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.2), radius: 24, y: 8)
        // Holds the keyboard while it's up, so typing can't reach the page underneath.
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.leftArrow) {
            month = month.adding(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if !isThisMonth { month = month.adding(1) }
            return .handled
        }
        .onAppear { isFocused = true }
        // Reads each of the month's pages to count its words: a month is only a few dozen small files.
        .task(id: Source(month: month, folder: session.folderURL, today: today, wordGoal: session.wordGoal)) {
            pastSummaries = session.pastSummaries(for: month.days)
        }
    }

    private var header: some View {
        HStack {
            Text(month.first.formatted("MMMMy"))
                .font(.system(size: 20, design: .serif))
            Spacer()
            Button { month = month.adding(-1) } label: { Image(systemName: "chevron.left") }
                .help("Previous month")
            Button { month = month.adding(1) } label: { Image(systemName: "chevron.right") }
                .help("Next month")
                .disabled(isThisMonth)  // nothing written there yet
        }
        .buttonStyle(.borderless)
    }

    private var grid: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 6) {
            GridRow {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(month.weeks.enumerated()), id: \.offset) { _, week in
                GridRow {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            DayCell(day: day, summary: summaries[day], isToday: day == today,
                                    isFuture: day.date > today.date)
                        } else {
                            Color.clear.frame(height: 36)
                        }
                    }
                }
            }
        }
    }

    /// "S M T W T F S", starting on the first day of the week where you are.
    private var weekdaySymbols: [String] {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let first = Calendar.current.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// "18 of 28 days counted · 14,203 words", up to today.
    private var totals: String {
        let written = summaries.values
        let counted = written.filter(\.counts).count
        let words = written.reduce(0) { $0 + $1.words }
        let days = month.days.filter { $0.date <= today.date }.count
        guard days > 0 else { return "" }
        let daysText = "\(counted) of \(days) \(days == 1 ? "day" : "days") counted"
        return words > 0 ? "\(daysText) · \(words.formatted()) words" : daysText
    }

    private struct DayCell: View {
        let day: Day
        let summary: JournalStore.DaySummary?
        let isToday: Bool
        let isFuture: Bool

        var body: some View {
            Text("\(day.dayOfMonth)")
                .monospacedDigit()
                .foregroundStyle(counts ? AnyShapeStyle(Color.white) : isFuture ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .frame(width: 32, height: 32)
                .background {
                    if counts {
                        Circle().fill(Color.accentColor.opacity(0.85))
                    } else if isWritten {
                        Circle().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                    }
                }
                .overlay(alignment: .bottom) {
                    if isToday {
                        Capsule()
                            .fill(.primary)
                            .frame(width: 12, height: 2)
                            .offset(y: 5)
                    }
                }
                .frame(height: 36)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .help(detail)
        }

        private var counts: Bool { summary?.counts == true }
        private var isWritten: Bool { (summary?.words ?? 0) > 0 || (summary?.seconds ?? 0) > 0 }

        /// "Friday, October 23: 812 words, 31 min"
        private var detail: String {
            let date = day.formatted("EEEEMMMMd")
            guard let summary, isWritten else { return isFuture ? date : "\(date): nothing written" }
            var parts = ["\(summary.words.formatted()) \(summary.words == 1 ? "word" : "words")"]
            if summary.seconds >= 60 { parts.append("\(summary.seconds / 60) min") }
            return "\(date): \(parts.joined(separator: ", "))"
        }
    }
}

/// A calendar month, Gregorian like the file names.
struct Month: Hashable {
    let year: Int
    let month: Int

    init(containing day: Day) {
        year = day.year
        month = day.month
    }

    private init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    var first: Day { Day(year: year, month: month, day: 1) ?? .today }

    var days: [Day] {
        (1...first.daysInMonth).compactMap { Day(year: year, month: month, day: $0) }
    }

    /// Rows of seven, with empty cells (nil) before the 1st so it falls under its weekday, and after the last day.
    var weeks: [[Day?]] {
        let blanks = (first.weekday - Calendar.current.firstWeekday + 7) % 7
        var cells: [Day?] = Array(repeating: nil, count: blanks)
        cells += days.map(Optional.some)
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    func adding(_ months: Int) -> Month {
        let index = year * 12 + (month - 1) + months
        return Month(year: index / 12, month: index % 12 + 1)
    }
}
