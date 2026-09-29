import SwiftUI
import EnshroudedCore

struct AutomationView: View {
    @ObservedObject var model: Model
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Startup & Scheduled Restarts") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Open the manager and start this server at login", isOn: binding(\.startAtLogin))
                        Text("Starts after you sign in. Allow Login Items access if macOS asks. Keep the manager open for scheduled tasks.").font(.caption).foregroundStyle(.secondary)
                        Toggle("Schedule restarts", isOn: binding(\.restartEnabled))
                        HStack {
                            Picker("Hour", selection: binding(\.hour)) { ForEach(0..<24) { Text(String(format: "%02d", $0)).tag($0) } }.frame(width: 130)
                            Picker("Minute", selection: binding(\.minute)) { ForEach(0..<60) { Text(String(format: "%02d", $0)).tag($0) } }.frame(width: 145)
                            Text("Local time").foregroundStyle(.secondary)
                        }.disabled(!model.automation.restartEnabled)
                        Stepper("Repeat every \(model.automation.everyDays ?? 1) day(s)", value: Binding(get: { model.automation.everyDays ?? 1 }, set: { var value = model.automation; value.everyDays = $0; value.anchorDate = Date(); model.saveAutomation(value) }), in: 1...30).disabled(!model.automation.restartEnabled)
                        if (model.automation.everyDays ?? 1) == 1 {
                            HStack { ForEach(1...7, id: \.self) { day in
                                Toggle(Calendar.current.shortWeekdaySymbols[day - 1], isOn: Binding(get: { model.automation.weekdays.contains(day) }, set: { enabled in var value = model.automation; if enabled { value.weekdays.append(day) } else { value.weekdays.removeAll { $0 == day } }; model.saveAutomation(value) })).toggleStyle(.button)
                            } }.disabled(!model.automation.restartEnabled)
                        }
                        if let next = model.automation.nextRestart { Text("Next restart: \(next.formatted())").font(.caption) }
                        Text("Restarts wait until the server is confirmed empty. Stopped servers stay stopped.").font(.caption).foregroundStyle(.secondary)
                    }.padding(10)
                }
                GroupBox("Scheduled Backups") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Back up this server daily", isOn: backupBinding(\.enabled))
                        HStack {
                            Picker("Hour", selection: backupBinding(\.hour)) { ForEach(0..<24) { Text(String(format: "%02d", $0)).tag($0) } }.frame(width: 130)
                            Picker("Minute", selection: backupBinding(\.minute)) { ForEach(0..<60) { Text(String(format: "%02d", $0)).tag($0) } }.frame(width: 145)
                            Text("Local time").foregroundStyle(.secondary)
                        }.disabled(model.automation.scheduledBackups?.enabled != true)
                        if let next = model.automation.scheduledBackups?.nextRun {
                            Text("Next backup: \(next.formatted())").font(.caption)
                        }
                        Text("Keep the manager open. Backups wait until the server is empty, then save, stop, back up, and restart it. Stopped servers stay stopped. Missed backups run when available.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Find saved worlds and settings in Backups. Backups are kept until removed. Failures appear in Manager Activity; retry is at the next daily run.")
                            .font(.caption).foregroundStyle(.secondary)
                        if model.automationMessage.hasPrefix("Scheduled backup") {
                            Text(model.automationMessage).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(10)
                }
                Text("Automatic Enshrouded software updates apply to all servers. Change that setting beside Enshrouded Server Build in the menu bar.").font(.caption).foregroundStyle(.secondary)
                Text("Changes save automatically.").font(.caption).foregroundStyle(.secondary)
            }.disabled(model.busy)
        }.padding(18)

    }
    private func backupBinding<Value>(_ keyPath: WritableKeyPath<BackupSchedule, Value>) -> Binding<Value> {
        Binding(get: { (model.automation.scheduledBackups ?? BackupSchedule())[keyPath: keyPath] }, set: { newValue in
            var settings = model.automation
            var schedule = settings.scheduledBackups ?? BackupSchedule()
            schedule[keyPath: keyPath] = newValue; settings.scheduledBackups = schedule
            model.saveAutomation(settings)
        })
    }
    private func binding<Value>(_ keyPath: WritableKeyPath<HostingAutomation, Value>) -> Binding<Value> {
        Binding(get: { model.automation[keyPath: keyPath] }, set: { newValue in
            var value = model.automation
            value[keyPath: keyPath] = newValue
            model.saveAutomation(value)
        })
    }
}
