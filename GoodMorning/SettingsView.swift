import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let session: Session

    @AppStorage(Prefs.wordGoalKey) private var wordGoal = Prefs.defaultWordGoal
    @AppStorage(Prefs.minuteGoalKey) private var minuteGoal = Prefs.defaultMinuteGoal
    @AppStorage(Prefs.appearanceKey) private var appearance = Appearance.system
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

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
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            openAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
