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
    private var managerTimer: Timer?
    var managerUpdateAvailable: Bool { !selected.build.experimental && managerRelease?.isNewer(than: selected.build.version) == true }
    var statusMenu: StatusMenu?
    private var subscriptions: Set<AnyCancellable> = []
    let store: ProfileStore
    var selected: Model { models.first { $0.engine.home.path == selectedID } ?? models[0] }
    init() {
        let env = ProcessInfo.processInfo.environment
        let defaultHome = (env["ESM_HOME"] ?? UserDefaults.standard.string(forKey: "serverHome")).map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/EnshroudedServer")
        let isolated = env["ESM_HOME"] != nil
        let managementRoot = isolated ? defaultHome.deletingLastPathComponent().appendingPathComponent(defaultHome.lastPathComponent + "-manager")
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Enshrouded Manager")
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
        if registered.isEmpty && loadError == nil {
            let engine = Engine(home: defaultHome, resources: Bundle.main.resourceURL!)
            registered = [.init(id: "primary", name: (try? engine.readSettings().name) ?? "Enshrouded Server", home: defaultHome.path, port: Int(engine.hostPort))]
            do { try store.save(registered) } catch { loadError = error.localizedDescription }
        }
        // A malformed registry must not autostart an unrelated default server.
        let initialModels = registered.isEmpty ? [Model(homeOverride: managementRoot.appendingPathComponent("unconfigured"), automaticStartup: false)]
            : registered.map { Model(homeOverride: URL(fileURLWithPath: $0.home)) }
        models = initialModels
        selectedID = initialModels[0].engine.home.path
        error = loadError
        observe()
        ApplicationLifetime.isBusy = { [weak self] in self?.models.contains { $0.busy } ?? false }
        if !selected.build.experimental && !isolated {
            checkManagerUpdates()
            managerTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
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
    var menuValue: String {
        if let busy = models.first(where: \.busy) { return busy.operationTitle }
        let running = models.filter { $0.state == "RUNNING" }
        if running.isEmpty { return models.allSatisfy { $0.stopped || $0.state == "NOT_INSTALLED" } ? "0" : "…" }
        guard running.allSatisfy({ $0.playerCount != nil }) else { return "…" }
        return String(running.compactMap(\.playerCount).reduce(0, +))
    }
    func create(settings: ServerSettings, port: Int) throws {
        _ = try settings.applying(to: [:])
        var profiles = try store.load()
        guard (1024...65535).contains(port), !profiles.contains(where: { $0.port == port }) else { throw EngineError("Choose an unused UDP port from 1024–65535") }
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        let root = ProcessInfo.processInfo.environment["ESM_HOME"] != nil
            ? store.registry.deletingLastPathComponent().appendingPathComponent("servers/\(id)")
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/ESM/\(id)")
        let profile = ServerProfile(id: id, name: settings.name, home: root.path, port: port)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(profile).write(to: root.appendingPathComponent("profile.json"), options: .atomic)
        let initial = try settings.applying(to: [:])
        try JSONSerialization.data(withJSONObject: initial).write(to: root.appendingPathComponent("initial-settings.json"), options: .atomic)
        profiles.append(profile); try store.save(profiles)
        let model = Model(homeOverride: root); models.append(model); selectedID = root.path; observe()
    }
}
struct FleetView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var fleet: FleetModel
    var body: some View {
        VStack(spacing: 0) {
            if let error = fleet.error { Text(error).foregroundStyle(.orange) }
            ManagementView(model: fleet.selected, removeServer: { fleet.removeSelectedServer() }).id(fleet.selectedID)
        }.onAppear {
            if fleet.statusMenu == nil { fleet.statusMenu = StatusMenu(fleet: fleet, showManagement: { openWindow(id: "management") }) }
        }.sheet(isPresented: $fleet.showNewServer) { NewServerView(fleet: fleet) }
    }
}
struct NewServerView: View {
    @ObservedObject var fleet: FleetModel
    @State private var draft = ServerSettings()
    @State private var port = 15638
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Enshrouded Server").font(.title2.bold())
            TextField("Server name", text: $draft.name)
            SecureField("Player password (8+ characters)", text: $draft.password)
            SecureField("Different admin password", text: $draft.adminPassword)
            TextField("UDP port", value: $port, format: .number.grouping(.never))
            Text("Each server needs 8 GB of RAM, 30 GB of free disk space, and its own forwarded UDP port.").font(.callout).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Create Server") { do { try fleet.create(settings: draft, port: port); dismiss() } catch { self.error = error.localizedDescription } } }
        }.padding(24).frame(width: 500)
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
    private func installManager(_ source: URL, destination: URL = Bundle.main.bundleURL) {
        let engines = models.map(\.engine)
        for model in models { model.busy = true; model.operationTitle = "Updating manager…" }
        Task {
            while models.contains(where: { $0.polling || $0.checkingRelease }) { try? await Task.sleep(for: .milliseconds(100)) }
            do {
                let backup = try await Task.detached {
                    try ManagerInstallation.replaceManagingServers(source, destination: destination, engines: engines)
                }.value
                selected.recordActivity("Previous manager retained at \(backup.path)\n")
                let config = NSWorkspace.OpenConfiguration(); config.createsNewApplicationInstance = true
                config.allowsRunningApplicationSubstitution = false
                config.environment = ["ESM_RELAUNCH_FROM_PID": String(ProcessInfo.processInfo.processIdentifier)]
                if let home = ProcessInfo.processInfo.environment["ESM_HOME"] { config.environment["ESM_HOME"] = home }
                NSWorkspace.shared.openApplication(at: destination, configuration: config) { _, error in
                    Task { @MainActor in
                        if let error { self.error = "Installed, but relaunch failed: \(error.localizedDescription). Open the manager in Finder to resume servers."; for model in self.models { model.busy = false; model.refresh() } }
                        else { ApplicationLifetime.allowTermination = true; NSApp.terminate(nil) }
                    }
                }
            } catch {
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
    func removeSelectedServer() {
        let model = selected
        guard model.canEdit else { return }
        let alert = NSAlert(); alert.messageText = "Remove \(model.name)?"
        alert.informativeText = "The environment will shut down. Its world, settings and complete runtime are moved to a recovery folder, not erased."
        alert.addButton(withTitle: "Move to Recovery"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.busy = true; model.operationTitle = "Moving to recovery…"
        let engine = model.engine, store = store
        Task {
            do {
                while model.polling { try? await Task.sleep(for: .milliseconds(100)) }
                await model.flushActivity()
                let remaining = try await Task.detached { try engine.moveToRecovery(store: store) }.value
                model.retire()
                models.removeAll { $0 === model }
                if models.isEmpty {
                    let fresh = Model(homeOverride: engine.home)
                    models = [fresh]
                    try store.save([ServerProfile(id: "primary", name: fresh.name, home: fresh.engine.home.path, port: Int(fresh.engine.hostPort))])
                }
                if ProcessInfo.processInfo.environment["ESM_HOME"] == nil {
                    if let first = remaining.first { UserDefaults.standard.set(first.home, forKey: "serverHome") }
                    if !models.contains(where: { $0.automation.startAtLogin }) && SMAppService.mainApp.status == .enabled {
                        do { try await SMAppService.mainApp.unregister() }
                        catch { self.error = "Server removed, but login startup could not be disabled: \(error.localizedDescription)" }
                    }
                }
                selectedID = models[0].engine.home.path; observe()
            } catch { model.error = error.localizedDescription; model.busy = false; model.refresh() }
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
            models.append(Model(homeOverride: home)); selectedID = home.path; observe()
        } catch { self.error = error.localizedDescription }
    }
}

extension FleetModel {
    func checkManagerUpdates() {
        guard !selected.build.experimental, !checkingManagerRelease else { return }
        checkingManagerRelease = true
        Task {
            defer { checkingManagerRelease = false }
            do { managerRelease = try await ManagerUpdater.latest() }
            catch { /* Background discovery retries on the next scheduled check. */ }
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
        Task {
            do {
                let app = try await ManagerUpdater.download(release)
                installManager(app, destination: URL(fileURLWithPath: "/Applications/Enshrouded Server Manager.app"))
            } catch {
                self.error = error.localizedDescription
                for model in models { model.busy = false; model.refresh() }
            }
        }
    }
}
