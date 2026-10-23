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
                Button("Lock In") { appDelegate.session.lockIn() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Commands…") { appDelegate.session.toggleCommands() }
                    .keyboardShortcut("p")
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

    func applicationWillTerminate(_ notification: Notification) {
        session.save()
    }
}
