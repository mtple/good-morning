import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let session: Session

    @AppStorage(Prefs.wordGoalKey) private var wordGoal = Prefs.defaultWordGoal
    @AppStorage(Prefs.minuteGoalKey) private var minuteGoal = Prefs.defaultMinuteGoal
    @AppStorage(Prefs.appearanceKey) private var appearance = Appearance.system
    @AppStorage(Prefs.fontSizeKey) private var fontSize = Prefs.defaultFontSize
    @AppStorage(Prefs.lineWidthKey) private var lineWidth = Prefs.defaultLineWidth
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?  // why the last change to "Open at login" didn't take

    var body: some View {
        Form {
            Section("Daily goal: whichever comes first") {
                Stepper(value: $wordGoal, in: 100...10_000, step: 50) {
                    Text("\(wordGoal.formatted()) words")
                }
                Stepper(value: $minuteGoal, in: 5...180, step: 5) {
                    Text("\(minuteGoal) minutes")
                }
            }

            Section("Writing") {
                Stepper(value: $fontSize, in: Prefs.fontSizes, step: 1) {
                    Text("Text size: \(Int(fontSize)) pt")
                }
                Slider(value: $lineWidth, in: Prefs.lineWidths, step: Prefs.lineWidthStep) {
                    Text("Line width")
                } minimumValueLabel: {
                    Text("Narrow")
                } maximumValueLabel: {
                    Text("Wide")
                }
            }

            Section("Pages") {
                LabeledContent("Folder") {
                    HStack {
                        Text(session.folderURL?.path(percentEncoded: false) ?? "Not chosen")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Change…") { session.chooseFolder() }
                    }
                }
            }

            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases, id: \.self) { Text($0.title) }
                }
                .onChange(of: appearance) { _, appearance in appearance.apply() }

                Toggle("Open Good Morning at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, enabled in
                        // Also runs when refreshLogin() sets the toggle to match. Nothing to change then.
                        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            loginError = nil
                        } catch {
                            loginError = "Couldn't turn this \(enabled ? "on" : "off"): \(error.localizedDescription)"
                        }
                        refreshLogin()
                    }
                if loginStatus == .requiresApproval {
                    HStack {
                        Text("Approve Good Morning in System Settings › General › Login Items.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    .font(.callout)
                } else if let loginError {
                    Text(loginError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            loginError = nil
            refreshLogin()
        }
        // Back from approving it in System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLogin()
        }
    }

    /// The toggle shows what macOS has, which can change in System Settings while this window is closed.
    private func refreshLogin() {
        loginStatus = SMAppService.mainApp.status
        openAtLogin = loginStatus == .enabled
    }
}
