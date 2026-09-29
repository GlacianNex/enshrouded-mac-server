import SwiftUI
import EnshroudedCore

struct SetupView: View {
    @ObservedObject var model: Model
    @State var draft: ServerSettings
    @State private var importedWorld: URL?
    @State private var startWhenReady = true
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set Up Enshrouded").font(.title2.bold())
            Text("Setup downloads everything you need. Connect to the internet and allow at least 30 GB of free space.").foregroundStyle(.secondary)
            TextField("Server name", text: $draft.name)
            SecureField("Player password (8+ characters)", text: $draft.password)
            SecureField("Different admin password", text: $draft.adminPassword)
            HStack {
                Text(importedWorld == nil ? "Create a new Embervale world" : "Import: \(importedWorld!.lastPathComponent)")
                Spacer(); Button("Choose Existing World…") {
                    let panel = NSOpenPanel(); panel.title = "Select the main world file (eight hexadecimal characters, no suffix)"; panel.canChooseDirectories = false
                    if panel.runModal() == .OK { importedWorld = panel.url }
                }
                if importedWorld != nil { Button("Clear") { importedWorld = nil } }
            }
            Text("Stop the source game or server before importing. World saves are copied; characters stay with their players.").font(.caption).foregroundStyle(.secondary)
            Toggle("Start the server when setup finishes", isOn: $startWhenReady)
            Text("Internet hosting uses UDP \(model.engine.hostPort). Your router must forward that port to this Mac.").font(.caption)
            if model.busy { HStack { ProgressView().controlSize(.small); Text(model.operationTitle) } }
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Button("Cancel") { dismiss() }.disabled(model.busy); Spacer(); Button("Install & Set Up") {
                do {
                    _ = try draft.applying(to: [:]); error = nil
                    model.setup(draft, world: importedWorld, start: startWhenReady) { success in
                        if success { dismiss() } else { error = model.error ?? "Setup could not finish. Try again." }
                    }
                }
                catch { self.error = error.localizedDescription }
            }.disabled(model.busy) }
        }.padding(24).frame(width: 610)
    }
}
extension Model {
    func setup(_ settings: ServerSettings, world: URL?, start: Bool, completion: ((Bool) -> Void)? = nil) {
        operation("Setting up server…", work: { engine in
            try engine.perform("install") { chunk in Task { @MainActor in self.recordActivity(chunk) } }
            try engine.saveSettings(settings)
            if let world { try engine.importWorld(primaryFile: world) }
            if start { try engine.perform("start") { chunk in Task { @MainActor in self.recordActivity(chunk) } } }
        }, completion: completion)
    }
    func chooseWorldImport() {
        guard canEdit else { return }
        let panel = NSOpenPanel(); panel.title = "Choose the main Enshrouded world file"; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let file = panel.url else { return }
        let alert = NSAlert(); alert.messageText = "Import this world?"
        alert.informativeText = "Back up the current world, then import the selected world. Settings and passwords stay the same. Stop the source game or server first."
        alert.addButton(withTitle: "Back Up & Import"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { operation("Import world") { try $0.importWorld(primaryFile: file) } }
    }
}
