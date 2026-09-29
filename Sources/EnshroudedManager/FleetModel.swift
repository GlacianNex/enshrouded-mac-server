import SwiftUI
import Combine
import ServiceManagement
import EnshroudedCore

@MainActor final class FleetModel: ObservableObject {
    @Published var models: [Model]
    @Published var selectedID: String
    @Published var showNewServer = false
    @Published var error: String?
    @Published var managerRelease: ManagerRelease?
    @Published var checkingManagerRelease = false
    @Published var managerCheckDate: Date?
    @Published var managerCheckFailed = false
    var managerUpdateStatus: String {
        if managerUpdateAvailable { return "Update Available" }
        if checkingManagerRelease || managerCheckDate == nil { return "Checking…" }
        return managerCheckFailed ? "Check Unavailable" : "Up to Date"
    }
    private var managerTimer: Timer?
    var managerUpdateAvailable: Bool { !selected.build.experimental && managerRelease?.isNewer(than: selected.build.version) == true }
    var statusMenu: StatusMenu?
    private var subscriptions: Set<AnyCancellable> = []
    let store: ProfileStore
    let sharedDownloads: URL
    var selected: Model { models.first { $0.engine.home.path == selectedID } ?? models[0] }
    init() {
        let env = ProcessInfo.processInfo.environment
        let defaultHome = (env["ESM_HOME"] ?? UserDefaults.standard.string(forKey: "serverHome")).map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/EnshroudedServer")
        let isolated = env["ESM_HOME"] != nil
        let managementRoot = isolated ? defaultHome.deletingLastPathComponent().appendingPathComponent(defaultHome.lastPathComponent + "-manager")
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Enshrouded Manager")
        sharedDownloads = managementRoot.appendingPathComponent("downloads")
        store = ProfileStore(registry: managementRoot.appendingPathComponent("profiles.json"))
        var registered: [ServerProfile] = []
        var loadError: String?
        do {
            // Migrate isolated registries out of the server folder before using recovery.
            let legacy = defaultHome.appendingPathComponent("profiles.json")
            if isolated && !FileManager.default.fileExists(atPath: store.registry.path) && FileManager.default.fileExists(atPath: legacy.path) {
                try store.save(ProfileStore(registry: legacy).load())
            }
            registered = try store.load()
        } catch { loadError = "Could not load server profiles: \(error.localizedDescription)" }
        if registered.isEmpty && loadError == nil && !FileManager.default.fileExists(atPath: store.registry.path) {
            let engine = Engine(home: defaultHome, resources: Bundle.main.resourceURL!)
            registered = [.init(id: "primary", name: (try? engine.readSettings().name) ?? "Enshrouded Server", home: defaultHome.path, port: Int(engine.hostPort))]
            do { try store.save(registered) } catch { loadError = error.localizedDescription }
        }
        // A malformed registry must not autostart an unrelated default server.
        let initialModels = registered.isEmpty ? [Model(homeOverride: managementRoot.appendingPathComponent("unconfigured"), automaticStartup: false, sharedDownloads: managementRoot.appendingPathComponent("downloads"))]
            : registered.map { Model(homeOverride: URL(fileURLWithPath: $0.home), sharedDownloads: managementRoot.appendingPathComponent("downloads")) }
        models = initialModels
        selectedID = initialModels[0].engine.home.path
        error = loadError
        observe()
        ApplicationLifetime.isBusy = { [weak self] in self?.models.contains { $0.busy } ?? false }
        if !selected.build.experimental && !isolated {
            checkManagerUpdates()
            managerTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkManagerUpdates() }
            }
        }
    }
    private func observe() {
        subscriptions.removeAll()
        for model in models {
            model.fleetEngines = models.map(\.engine)
            model.managerUpdateHandler = { [weak self] in self?.chooseManagerUpdate() }
            model.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions) }
    }
    var configuredModels: [Model] {
        let homes = Set(((try? store.load()) ?? []).map(\.home))
        return models.filter { homes.contains($0.engine.home.path) }
    }
    var menuValue: String {
        if let busy = models.first(where: \.busy) { return busy.operationTitle }
        let running = models.filter { $0.state == "RUNNING" }
        if running.isEmpty { return models.allSatisfy { $0.stopped || $0.state == "NOT_INSTALLED" } ? "0" : "…" }
        guard running.allSatisfy({ $0.playerCount != nil }) else { return "…" }
        return String(running.compactMap(\.playerCount).reduce(0, +))
    }
    var canChangeProfiles: Bool { !models.contains { $0.busy && $0.activeAction != "stop" } }
    func create(settings: ServerSettings, port: Int) throws {
        guard canChangeProfiles else { throw EngineError("Wait for server maintenance to finish before creating a server") }
        _ = try settings.applying(to: [:])
        var profiles = try store.load()
        guard (1024...65535).contains(port), !profiles.contains(where: { $0.port == port }) else { throw EngineError("Choose an unused UDP port from 1024–65535") }
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        let retained = try store.retainedInstallations().first { $0.port == port && FileManager.default.fileExists(atPath: $0.home) }
        let root = retained.map { URL(fileURLWithPath: $0.home) } ?? (ProcessInfo.processInfo.environment["ESM_HOME"] != nil
            ? store.registry.deletingLastPathComponent().appendingPathComponent("servers/\(id)")
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/ESM/\(id)"))
        let profile = ServerProfile(id: id, name: settings.name, home: root.path, port: port)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(profile).write(to: root.appendingPathComponent("profile.json"), options: .atomic)
        let initial = try settings.applying(to: [:])
        try JSONSerialization.data(withJSONObject: initial).write(to: root.appendingPathComponent("initial-settings.json"), options: .atomic)
        if retained != nil { try Data().write(to: root.appendingPathComponent("needs-setup")) }
        profiles.append(profile); try store.save(profiles)
        for placeholder in models where !profiles.contains(where: { $0.home == placeholder.engine.home.path }) { placeholder.retire() }
        models.removeAll { model in !profiles.contains { $0.home == model.engine.home.path } }
        let model = Model(homeOverride: root, sharedDownloads: sharedDownloads); models.append(model); selectedID = root.path; observe()
    }
}
struct FleetView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var fleet: FleetModel
    var body: some View {
        VStack(spacing: 0) {
            if let error = fleet.error { Text(error).foregroundStyle(.orange) }
            if fleet.configuredModels.isEmpty {
                VStack(spacing: 16) {
                    Text("No Servers").font(.title2.bold())
                    Text("Create a server to get started. Existing installation files are reused.")
                    Button("New Server…") { fleet.showNewServer = true }.disabled(!fleet.canChangeProfiles)
                }.frame(width: 640, height: 860)
            } else {
                ManagementView(model: fleet.selected, removeServer: { fleet.removeSelectedServer() }).id(fleet.selectedID)
            }
        }.onAppear {
            if fleet.statusMenu == nil { fleet.statusMenu = StatusMenu(fleet: fleet, showManagement: { openWindow(id: "management") }) }
        }.sheet(isPresented: $fleet.showNewServer) { NewServerView(fleet: fleet) }
    }
}
struct NewServerView: View {
    let fleet: FleetModel
    @State private var draft = ServerSettings()
    @State private var port = "15637"
    @State private var error: String?
    @FocusState private var focused: Field?
    private enum Field: Hashable { case name, player, admin, port }
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Enshrouded Server").font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                Text("Server Name").font(.headline)
                TextField("Server name", text: $draft.name).focused($focused, equals: .name)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Player Password").font(.headline)
                SecureField("At least 8 characters", text: $draft.password).focused($focused, equals: .player)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Admin Password").font(.headline)
                SecureField("At least 8 characters; different from player password", text: $draft.adminPassword).focused($focused, equals: .admin)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("UDP Port").font(.headline)
                TextField("UDP port", text: $port).focused($focused, equals: .port)
            }
            Text("Each server needs 8 GB of RAM, 30 GB of free disk space, and its own forwarded UDP port.").font(.callout).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Server") {
                    do {
                        guard let number = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw EngineError("Enter a UDP port from 1024–65535.") }
                        try fleet.create(settings: draft, port: number)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.textFieldStyle(.roundedBorder).controlSize(.large)
        .padding(24).frame(width: 500)
        .onAppear {
            port = String((15637...65535).first { candidate in !fleet.configuredModels.contains { Int($0.engine.hostPort) == candidate } } ?? 15637)
            focused = .name
        }
    }
}

extension FleetModel {
    func chooseManagerUpdate() {
        guard !models.contains(where: { $0.busy || $0.polling }) else { return }
        let panel = NSOpenPanel(); panel.title = "Choose the downloaded Enshrouded Manager app"
        panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            _ = try ManagerInstallation.validate(source, replacing: Bundle.main.bundleURL)
            let alert = NSAlert(); alert.messageText = "Update Enshrouded Server Manager?"
            alert.informativeText = "Updating the manager will stop all running servers. They will start back up once the update finishes."
            alert.addButton(withTitle: "Stop, Update & Relaunch"); alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { installManager(source) }
        } catch { self.error = error.localizedDescription }
    }
    private func installManager(_ source: URL, destination: URL = Bundle.main.bundleURL, progressWindow: ManagerInstallProgressWindow? = nil) {
        let progress = progressWindow ?? ManagerInstallProgressWindow(logURL: selected.engine.home.appendingPathComponent("manager-activity.log"))
        let engines = models.map(\.engine)
        for model in models { model.busy = true; model.operationTitle = "Updating manager…" }
        Task {
            while models.contains(where: { $0.polling || $0.checkingRelease }) { try? await Task.sleep(for: .milliseconds(100)) }
            do {
                let backup = try await Task.detached {
                    try ManagerInstallation.replaceManagingServers(source, destination: destination, engines: engines, output: { chunk in
                        Task { @MainActor in self.selected.recordActivity(chunk) }
                    }, progress: { stage in Task { @MainActor in progress.advance(stage); self.selected.recordActivity(stage.title + "\n") } })
                }.value
                selected.recordActivity("Previous manager retained at \(backup.path)\n")
                progress.advance(.opening)
                let config = NSWorkspace.OpenConfiguration(); config.createsNewApplicationInstance = true
                config.allowsRunningApplicationSubstitution = false
                config.environment = ["ESM_RELAUNCH_FROM_PID": String(ProcessInfo.processInfo.processIdentifier)]
                if let home = ProcessInfo.processInfo.environment["ESM_HOME"] { config.environment["ESM_HOME"] = home }
                NSWorkspace.shared.openApplication(at: destination, configuration: config) { _, error in
                    Task { @MainActor in
                        progress.close()
                        if let error { self.error = "Installed, but relaunch failed: \(error.localizedDescription). Open the manager in Finder to resume servers."; for model in self.models { model.busy = false; model.refresh() } }
                        else { ApplicationLifetime.allowTermination = true; NSApp.terminate(nil) }
                    }
                }
            } catch {
                progress.close()
                selected.recordActivity("Manager update failed: " + error.localizedDescription + "\n")
                self.error = error.localizedDescription
                for model in models { model.busy = false; model.refresh() }
            }
        }
    }
}


extension FleetModel {
    func installInApplications() {
        guard !models.contains(where: { $0.busy || $0.polling }) else { return }
        let destination = URL(fileURLWithPath: "/Applications/Enshrouded Server Manager.app")
        let alert = NSAlert(); alert.messageText = "Install Enshrouded Manager in Applications?"
        alert.informativeText = "The app will be copied and reopened from Applications. Running servers will stop and start back up once installation finishes."
        alert.addButton(withTitle: "Install & Reopen"); alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn { installManager(Bundle.main.bundleURL, destination: destination) }
    }
}

extension FleetModel {
    func updateAllServers() {
        guard !models.contains(where: { $0.busy || $0.polling }) else { return }
        let alert = NSAlert(); alert.messageText = "Update all installed Enshrouded servers?"
        alert.informativeText = "All running servers must be empty. Each installation is backed up and updated separately. Previously running servers restart; stopped servers stay stopped."
        alert.addButton(withTitle: "Update All Servers"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let targets = models.filter { $0.state != "NOT_INSTALLED" }
        for model in models { model.busy = true; model.operationTitle = "Updating servers…" }
        Task {
            do {
                let engines = targets.map(\.engine)
                try await Task.detached {
                    for engine in engines where try engine.status() == "RUNNING" {
                        guard try engine.queryServer().players == 0 else { throw EngineError("Players are connected; updates were not started") }
                    }
                }.value
                for model in targets {
                    let engine = model.engine
                    try await Task.detached {
                        try engine.perform("update") { chunk in Task { @MainActor in model.recordActivity(chunk) } }
                    }.value
                }
            } catch { self.error = error.localizedDescription }
            for model in models { model.busy = false; model.loadSettings(); model.refresh() }
        }
    }
    func removeSelectedServer() { deleteServer(selected) }
    func deleteServer(_ model: Model) {
        guard canChangeProfiles, !model.busy else { return }
        let alert = NSAlert(); alert.messageText = "Delete \(model.name)?"
        alert.informativeText = "Stops this server and removes its settings and entry. Worlds, logs and backups are archived. Downloaded files and the environment stay available for reuse."
        alert.addButton(withTitle: "Delete Server"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.busy = true; model.operationTitle = "Deleting server…"
        let engine = model.engine, store = store
        Task {
            do {
                while model.polling || model.checkingRelease { try? await Task.sleep(for: .milliseconds(100)) }
                await model.flushActivity()
                let remaining = try await Task.detached { try engine.deleteServer(store: store) }.value
                model.retire(); models.removeAll { $0 === model }
                if models.isEmpty {
                    models = [Model(homeOverride: store.registry.deletingLastPathComponent().appendingPathComponent("unconfigured"), automaticStartup: false, sharedDownloads: sharedDownloads)]
                }
                selectedID = models[0].engine.home.path; observe()
                if ProcessInfo.processInfo.environment["ESM_HOME"] == nil {
                    if let first = remaining.first { UserDefaults.standard.set(first.home, forKey: "serverHome") }
                    else { UserDefaults.standard.removeObject(forKey: "serverHome") }
                    if !models.contains(where: { $0.automation.startAtLogin }) && SMAppService.mainApp.status == .enabled {
                        do { try await SMAppService.mainApp.unregister() }
                        catch { self.error = "Server deleted, but login startup could not be disabled: " + error.localizedDescription }
                    }
                }
            } catch { model.error = error.localizedDescription; model.busy = false; model.refresh() }
        }
    }
    func uninstallServerFiles() {
        guard !models.contains(where: \.busy) else { return }
        let alert = NSAlert(); alert.messageText = "Uninstall All Server Files?"
        alert.informativeText = "Stops all servers and removes downloaded server files, environments, compatibility tools and shared downloads. Keeps server settings, archived worlds, backups and the manager app."
        alert.addButton(withTitle: "Stop All & Uninstall"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for model in models { model.busy = true; model.operationTitle = "Uninstalling server files…" }
        let targets = models, store = store, shared = sharedDownloads
        Task {
            do {
                while targets.contains(where: { $0.polling || $0.checkingRelease }) { try? await Task.sleep(for: .milliseconds(100)) }
                for model in targets { await model.flushActivity() }
                let active = targets.map(\.engine)
                try await Task.detached {
                    let retained = try store.retainedInstallations().map { Engine(home: URL(fileURLWithPath: $0.home), resources: active[0].resources) }
                    try active[0].withSharedDownloads {
                        for engine in active + retained { try engine.uninstallServerFiles { _ in } }
                        if FileManager.default.fileExists(atPath: shared.path) { try FileManager.default.removeItem(at: shared) }
                    }
                }.value
            } catch { self.error = error.localizedDescription }
            for model in targets { model.busy = false; model.refresh() }
        }
    }
    func recoverServer() {
        let panel = NSOpenPanel(); panel.title = "Choose a removed server's recovery folder"; panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.directoryURL = store.registry.deletingLastPathComponent().appendingPathComponent("deleted-servers")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            let profile = try JSONDecoder().decode(ServerProfile.self, from: Data(contentsOf: folder.appendingPathComponent("profile.json")))
            let home = URL(fileURLWithPath: profile.home)
            guard profile.home.hasPrefix("/"), !FileManager.default.fileExists(atPath: home.path) else { throw EngineError("Original server location is in use. Recovery files are unchanged.") }
            var profiles = try store.load()
            // A blank setup placeholder is replaced by the recovered server.
            profiles.removeAll { $0.home == profile.home }
            try store.save(profiles + [profile])
            do { try FileManager.default.moveItem(at: folder.appendingPathComponent("data"), to: home) }
            catch { try store.save(profiles); throw error }
            let recovered = Engine(home: home, resources: Bundle.main.resourceURL!)
            var automation = recovered.loadAutomation(); automation.startAtLogin = false; automation.nextRestart = nil; automation.waitingRestart = nil
            try recovered.saveAutomation(automation)
            try? FileManager.default.removeItem(at: home.appendingPathComponent("resume-after-manager-update"))
            models.removeAll { $0.engine.home.path == profile.home }
            models.append(Model(homeOverride: home, sharedDownloads: sharedDownloads)); selectedID = home.path; observe()
        } catch { self.error = error.localizedDescription }
    }
}

extension FleetModel {
    func checkManagerUpdates() {
        guard !selected.build.experimental, !checkingManagerRelease else { return }
        checkingManagerRelease = true
        managerCheckDate = Date()
        Task {
            defer { checkingManagerRelease = false }
            do { managerRelease = try await ManagerUpdater.latest(); managerCheckFailed = false }
            catch { managerCheckFailed = true }
        }
    }
    func updateManager() {
        guard managerUpdateAvailable, let release = managerRelease, !models.contains(where: \.busy) else { return }
        let prompt = NSAlert()
        prompt.messageText = "Update Enshrouded Server Manager?"
        prompt.informativeText = "Updating the manager will stop all running servers. They will start back up once the update finishes."
        prompt.addButton(withTitle: "Stop, Update & Relaunch"); prompt.addButton(withTitle: "Cancel")
        guard prompt.runModal() == .alertFirstButtonReturn else { return }
        for model in models { model.busy = true; model.operationTitle = "Downloading manager…" }
        let progress = ManagerInstallProgressWindow(logURL: selected.engine.home.appendingPathComponent("manager-activity.log"))
        progress.advance(.downloading)
        selected.recordActivity("Downloading the manager update…\n")
        Task {
            do {
                let app = try await ManagerUpdater.download(release) { stage in Task { @MainActor in progress.advance(stage); self.selected.recordActivity(stage.title + "\n") } }
                installManager(app, destination: URL(fileURLWithPath: "/Applications/Enshrouded Server Manager.app"), progressWindow: progress)
            } catch {
                progress.close()
                selected.recordActivity("Manager download failed: " + error.localizedDescription + "\n")
                self.error = error.localizedDescription
                for model in models { model.busy = false; model.refresh() }
            }
        }
    }
}
