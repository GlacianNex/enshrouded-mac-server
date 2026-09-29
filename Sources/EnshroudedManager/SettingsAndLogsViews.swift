import SwiftUI
import EnshroudedCore

struct SettingsView: View {
    @ObservedObject var model: Model
    @State var draft: ServerSettings
    @State private var reveal = false
    @State private var rules: [GameplayRule] = []
    @State private var ruleValues: [String: String] = [:]
    @State private var originalRules: [String: String] = [:]
    @State private var rulesLoaded = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(model.stopped ? "Server Settings" : "Server Settings · Read Only").font(.title2.bold())
                Spacer()
            }
            if !model.stopped { Text("Save and stop the server to edit settings.").foregroundStyle(.secondary) }
            Form {
                Section("Server") {
                    TextField("Server name", text: $draft.name)
                    Stepper("Player slots: \(draft.slots)", value: $draft.slots, in: 1...16)
                    Text("Maximum number of players who can join (1–16).").font(.caption).foregroundStyle(.secondary)
                    Button("Import World…") { model.chooseWorldImport() }
                }.disabled(!model.canEdit)
                Section("World Rules") {
                    Picker("Difficulty preset", selection: $draft.preset) {
                        ForEach(ServerSettings.presets, id: \.self) { Text($0).tag($0) }
                    }.disabled(!model.canEdit).help("Choose a preset managed by the game. Editing an individual rule automatically selects Custom.")
                    Text(presetHelp).font(.caption).foregroundStyle(.secondary)
                    if draft.preset == "Custom" {
                        Text("Edit the saved rules below. Multipliers use 1× for normal; durations are in minutes.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Changing a rule below automatically selects Custom. These are your saved custom values; presets apply their own values when the server starts.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    GameplayRulesView(rules: rules, values: Binding(
                        get: { ruleValues },
                        set: { ruleValues = $0; draft.preset = "Custom" }
                    ), original: originalRules, canEdit: model.canEdit)
                }
                Section("Role Passwords") {
                    if reveal { TextField("Player (Friend)", text: $draft.password); TextField("Admin", text: $draft.adminPassword) }
                    else { SecureField("Player (Friend)", text: $draft.password); SecureField("Admin", text: $draft.adminPassword) }
                    Toggle("Show passwords", isOn: $reveal)
                    Text("Use different player and admin passwords, each at least 8 characters.").font(.caption).foregroundStyle(.secondary)
                }.disabled(!model.canEdit)
                Section("Chat") {
                    Toggle("Enable text chat", isOn: $draft.textChat)
                    Toggle("Enable voice chat", isOn: $draft.voice)
                    Picker("Voice range", selection: $draft.voiceMode) { Text("Proximity").tag("Proximity"); Text("Server-wide").tag("Global") }.disabled(!draft.voice)
                }.disabled(!model.canEdit)
            }.formStyle(.grouped)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Text("Changes take effect on the next server start.").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("Cancel") { dismiss() }
                Button("Save Settings", action: save).disabled(!model.canEdit || !rulesLoaded).keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 640, height: 680)
        .onAppear {
            do {
                rules = try model.engine.gameplayRules()
                let saved = try model.engine.gameplayValues()
                originalRules = Dictionary(uniqueKeysWithValues: rules.map { ($0.key, $0.display(saved[$0.key])) })
                ruleValues = originalRules
                rulesLoaded = true
            } catch { self.error = error.localizedDescription }
        }
    }
    private func save() {
        do {
            _ = try draft.applying(to: [:])
            let changed = draft.preset == "Custom" ? ruleValues.filter { originalRules[$0.key] != $0.value } : [:]
            for rule in rules { if let value = changed[rule.key] { _ = try rule.parse(value) } }
            let settings = draft
            model.operation("Save settings") { try $0.saveSettings(settings, worldRules: changed) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
    var presetHelp: String {
        switch draft.preset {
        case "Relaxed": return "Fewer enemies and more resources, for building and lighter adventuring."
        case "Hard": return "More enemies and more aggressive combat."
        case "Survival": return "Additional survival mechanics and more aggressive enemies."
        case "Custom": return "Set individual rules for everyone playing on this server. Starts from your saved custom values."
        default: return "The standard Enshrouded experience, recommended for a first playthrough."
        }
    }
}
struct LogsView: View {
    @ObservedObject var model: Model
    @State private var selected = "Server"
    @State private var filter = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Server Logs").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            Picker("Log", selection: $selected) { Text("Server").tag("Server"); Text("Manager Activity").tag("Manager") }.pickerStyle(.segmented)
            TextField("Filter log lines", text: $filter)
            ScrollView([.horizontal, .vertical]) {
                Text(filtered.isEmpty ? "No matching log lines." : filtered).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }.background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Text("Latest 256 KB · refreshes every 5 seconds while idle").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("Open Log Folder") { NSWorkspace.shared.open(model.engine.data.appendingPathComponent("logs")) }
            }
        }.padding(20).frame(width: 820, height: 580)
    }
    var filtered: String {
        let text = selected == "Server" ? model.serverLog : model.activity
        return filter.isEmpty ? text : text.components(separatedBy: .newlines).filter { $0.localizedCaseInsensitiveContains(filter) }.joined(separator: "\n")
    }
}
