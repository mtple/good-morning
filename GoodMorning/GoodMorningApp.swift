import SwiftUI

@main
struct GoodMorningApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Good Morning", id: "pages") {
            ContentView(session: appDelegate.session)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 820, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Lock In or Out") { appDelegate.session.toggleLock() }
                    .keyboardShortcut("l")
                Button("Commands…") { appDelegate.session.toggleCommands() }
                    .keyboardShortcut("p")
                Button("Calendar") { appDelegate.session.toggleCalendar() }
                    .keyboardShortcut("y")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { appDelegate.session.saveNow() }
                    .keyboardShortcut("s")
            }
            // ⌘P is the command palette, not Print.
            CommandGroup(replacing: .printItem) {}
            CommandGroup(after: .toolbar) {
                // ⌘= works too (see Session.installEscapeKey).
                Button("Bigger Text") { Prefs.changeFontSize(by: Prefs.fontSizeStep) }
                    .keyboardShortcut("+")
                Button("Smaller Text") { Prefs.changeFontSize(by: -Prefs.fontSizeStep) }
                    .keyboardShortcut("-")
                Button("Default Text Size") { Prefs.resetFontSize() }
                    .keyboardShortcut("0")
                Divider()
                Button("Wider Lines") { Prefs.changeLineWidth(by: Prefs.lineWidthStep) }
                Button("Narrower Lines") { Prefs.changeLineWidth(by: -Prefs.lineWidthStep) }
            }
            CommandGroup(replacing: .help) {
                Button("How Good Morning Works") { appDelegate.session.toggleHelp() }
                    .keyboardShortcut("?")
            }
        }

        Settings {
            SettingsView(session: appDelegate.session)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = Session()

    // Before the window appears, so it doesn't open in the wrong colors.
    func applicationWillFinishLaunching(_ notification: Notification) {
        Prefs.appearance.apply()
    }

    // One window, one job: closing it quits the app (and saves).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // Restarts the timer. If the app sat open overnight, coming back to it starts a new day's page.
    func applicationDidBecomeActive(_ notification: Notification) {
        session.appDidBecomeActive()
    }

    func applicationWillResignActive(_ notification: Notification) {
        session.appWillResignActive()
    }

    // If today's page can't be saved or copied aside, you choose whether to quit and lose it.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        session.prepareToQuit() ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.save()
        session.keepNoticesForNextLaunch()
    }
}
