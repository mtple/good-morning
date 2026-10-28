// Points the app at a pages folder with a long page in it, as if you'd chosen the folder on first launch.
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
do {
    let bookmark = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    defaults.set(bookmark, forKey: "journalFolderBookmark")
    print("seeded a security-scoped bookmark")
} catch {
    print("security-scoped bookmark failed (\(error)), using a plain one")
    defaults.set(try folder.bookmarkData(), forKey: "journalFolderBookmark")
}
defaults.set(2000, forKey: "wordGoal")  // so the goal isn't met by the seeded page
defaults.synchronize()
print("page words:", page.split(whereSeparator: \.isWhitespace).count)
