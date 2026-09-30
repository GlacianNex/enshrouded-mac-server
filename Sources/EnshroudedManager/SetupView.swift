import SwiftUI
import EnshroudedCore

struct SetupView: View {
    @ObservedObject var model: Model
    @State var draft: ServerSettings
    @State private var importedWorld: URL?
    @State private var startWhenReady = true
    @State private var error: String?
    @State private var downloadsExpanded = true
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            Text("Set Up Enshrouded").font(.title2.bold())
            Text("Keep 30 GB free for the environment, extracted server files, and update space. This is a disk-space allowance—not the download size.").foregroundStyle(.secondary)
            if model.setupProgress == nil || (!model.busy && model.setupProgress?.failed == true) {
                DisclosureGroup("What Will Be Downloaded", isExpanded: $downloadsExpanded) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(SetupStep.allCases.filter { $0 != .configure && $0 != .start }, id: \.self) { step in
                            Text("\(step.title): \(step.downloadDescription)").font(.caption)
                        }
                        Text("Lima VM launcher tools are already included with the app. Verified cached components are reused. Total download size varies with Valve’s current release and missing system packages.").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 6)
                }
            TextField("Server name", text: $draft.name)
            SecureField("Player password (8+ characters)", text: $draft.password)
            SecureField("Different admin password", text: $draft.adminPassword)
            HStack {
                Text(importedWorld == nil ? "Create a new Embervale world" : "Import: \(importedWorld!.lastPathComponent)")
                Spacer(); Button("Choose Existing World…") {
                    let panel = NSOpenPanel(); panel.title = "Choose an Enshrouded World"; panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false; panel.message = "Choose a one-world folder, ZIP archive, or main save file (eight hexadecimal characters, no suffix)."
                    if panel.runModal() == .OK { importedWorld = panel.url }
                }
                if importedWorld != nil { Button("Clear") { importedWorld = nil } }
            }
            Text("Import a one-world folder, ZIP archive, or main save file. Stop the source game or server first. Originals are copied; characters stay with their players.").font(.caption).foregroundStyle(.secondary)
            Toggle("Start the server when setup finishes", isOn: $startWhenReady)
            Text("Internet hosting uses UDP \(model.engine.hostPort). Your router must forward that port to this Mac.").font(.caption)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Server Data Folder").font(.caption.bold())
                    Text(model.engine.home.path).font(.caption).textSelection(.enabled)
                    Text("Downloads and saved data stay outside the manager app.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Folder") {
                    let folder = FileManager.default.fileExists(atPath: model.engine.home.path) ? model.engine.home : model.engine.home.deletingLastPathComponent()
                    NSWorkspace.shared.open(folder)
                }
            }
            if let progress = model.setupProgress { SetupProgressView(progress: progress, startsServer: startWhenReady) }
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Button(model.setupProgress?.finished == true ? "Done" : "Cancel") { dismiss() }.disabled(model.busy); Spacer(); Button("Install & Set Up") {
                do {
                    _ = try draft.applying(to: [:]); error = nil
                    model.setup(draft, world: importedWorld, start: startWhenReady) { success in
                        if !success { error = model.error ?? "Setup could not finish. Try again." }
                    }
                }
                catch { self.error = error.localizedDescription }
            }.disabled(model.busy || model.setupProgress?.finished == true) }
        }.padding(24) }.frame(width: 650, height: 760)
        .onAppear { if !model.busy { model.setupProgress = nil } }
    }
}
extension Model {
    func setup(_ settings: ServerSettings, world: URL?, start: Bool, completion: ((Bool) -> Void)? = nil) {
        guard !busy else { return }
        setupProgress = SetupProgress()
        operation("Setting up server…", work: { engine in
            try engine.perform("install") { chunk in Task { @MainActor in self.recordSetupActivity(chunk) } }
            Task { @MainActor in self.recordSetupActivity(SetupEvent(.configure, "Saving settings and preparing the world…").line) }
            try engine.saveSettings(settings)
            if let world { try WorldImportSource.withPreparedWorld(at: world) { try engine.importWorld(primaryFile: $0) } }
            if start {
                Task { @MainActor in self.recordSetupActivity(SetupEvent(.start, "Starting the server and checking readiness…").line) }
                try engine.perform("start") { chunk in Task { @MainActor in self.recordSetupActivity(chunk) } } }
        }, completion: { success in
            self.setupProgress?.finish(success: success)
            completion?(success)
        })
    }
    func recordSetupActivity(_ text: String) {
        recordActivity(text)
        setupProgress?.consume(text)
    }
    func chooseWorldImport() {
        guard canEdit else { return }
        let panel = NSOpenPanel(); panel.title = "Choose an Enshrouded World"; panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false; panel.message = "Choose a one-world folder, ZIP archive, or main save file (eight hexadecimal characters, no suffix)."
        guard panel.runModal() == .OK, let file = panel.url else { return }
        let alert = NSAlert(); alert.messageText = "Import this world?"
        alert.informativeText = "Back up the current world, then import the selected world. Settings and passwords stay the same. Stop the source game or server first."
        alert.addButton(withTitle: "Back Up & Import"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            operation("Import world") { engine in
                try WorldImportSource.withPreparedWorld(at: file) { try engine.importWorld(primaryFile: $0) }
            }
        }
    }
}

struct SetupProgressView: View {
    let progress: SetupProgress
    let startsServer: Bool
    private var steps: [SetupStep] { SetupStep.allCases.filter { startsServer || $0 != .start } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(progress.failed ? "Setup Needs Attention" : progress.finished ? "Setup Complete" : "Installing Server").font(.headline)
                Spacer()
                if !progress.failed && !progress.finished { Text(progress.started, style: .timer).monospacedDigit().font(.caption) }
            }
            ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                let current = steps.firstIndex(of: progress.step) ?? 0
                HStack(spacing: 10) {
                    Image(systemName: progress.finished || index < current ? "checkmark.circle.fill" : index == current ? (progress.failed ? "exclamationmark.circle.fill" : "arrow.down.circle") : "circle")
                        .foregroundStyle(progress.failed && index == current ? Color.orange : index <= current ? Color.accentColor : Color.secondary)
                    Text(step.title)
                    Spacer()
                    if let bytes = progress.downloaded[step] {
                        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    if index < current && !progress.finished { Text("Ready").font(.caption).foregroundStyle(.secondary) }
                    if index == current && !progress.finished { Text(progress.failed ? "Failed" : "In Progress").font(.caption) }
                }.font(.callout)
            }
            if !progress.finished {
                Text(progress.message).font(.callout)
                if !progress.failed {
                    if let percent = progress.percent {
                        ProgressView(value: percent, total: 100)
                        Text("Current step: \(Int(percent))%").font(.caption).monospacedDigit()
                    } else { ProgressView().progressViewStyle(.linear) }
                }
                if ![SetupStep.configure, .start].contains(progress.step) {
                    Text(progress.downloadDetail).font(.caption).foregroundStyle(.secondary)
                }
                Text("Keep the manager open. Building and extracting files can take time without downloading more data.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14).background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
}
