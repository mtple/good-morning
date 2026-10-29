// Makes a pages folder with a long page in it for today, and sets the word goal 50 words past it and the time goal to
// two minutes. Also a 600-word page from earlier this month, with no time logged, for the calendar steps.
// The folder itself is chosen through the app's own picker (smoke.sh), since a folder bookmark only works for the app that made it.
// Run on the CI Mac before the smoke run (see smoke.sh).
import Foundation

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

let formatter = DateFormatter()
formatter.dateFormat = "yyyy-MM-dd"
let today = formatter.string(from: Date())
let sentence = "This is a line of yesterday's thinking that goes on for a while so the page gets long. "
let page = (1...40).map { "Paragraph \($0). " + String(repeating: sentence, count: 3) }.joined(separator: "\n\n")
try page.write(to: folder.appending(path: "\(today).md"), atomically: true, encoding: .utf8)

let defaults = UserDefaults(suiteName: "com.mtple.GoodMorning")!
// 50 words to go, so the page locks on launch and smoke.sh's last burst of typing reaches the goal.
let words = page.split(whereSeparator: \.isWhitespace).count
defaults.set(words + 50, forKey: "wordGoal")
// Short enough that the time goal is reached while the calendar is open (smoke.sh).
defaults.set(2, forKey: "minuteGoal")
defaults.synchronize()
print("page words:", words, "goal:", words + 50)

// Under the word goal, so it shows as a ring until smoke.sh lowers the goal to 550. Skipped on the 1st,
// when there's no earlier day in the month for the calendar to show.
let calendar = Calendar.current
let earlier = calendar.date(byAdding: .day, value: -1, to: Date())!
if calendar.isDate(earlier, equalTo: Date(), toGranularity: .month) {
    let past = Array(repeating: "word", count: 600).joined(separator: " ")
    try past.write(to: folder.appending(path: "\(formatter.string(from: earlier)).md"), atomically: true, encoding: .utf8)
    print("600-word page on", formatter.string(from: earlier))
} else {
    print("first of the month: no earlier page")
}
