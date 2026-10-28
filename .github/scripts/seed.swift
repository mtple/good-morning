// Makes a pages folder with a long page in it for today, and raises the word goal so that page doesn't meet it.
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
defaults.set(2000, forKey: "wordGoal")  // so the goal isn't met by the seeded page
defaults.synchronize()
print("page words:", page.split(whereSeparator: \.isWhitespace).count)
