import SwiftUI
import AppKit
import IOKit.pwr_mgt
import ServiceManagement
import EnshroudedCore

@MainActor final class Model: ObservableObject {
    @Published var state = "Checking…"
    @Published var busy = false
    @Published var polling = false
    @Published var activity = ""
    @Published var serverLog = ""
    @Published var settings = ServerSettings()
    @Published var error: String?
    @Published var localAddresses: [String] = []
    @Published var publicAddress: String?
    @Published var snapshot = LogSnapshot()
    @Published var metrics: RuntimeMetrics?
    @Published var backups: [WorldBackup] = []
    @Published var memoryHistory: [PerformancePoint] = []
    @Published var cpuHistory: [PerformancePoint] = []
    @Published var updateHistory: [PerformancePoint] = []
    @Published var pingHistory: [String: [PerformancePoint]] = [:]
    @Published var lastCheck: Date?
    @Published var lastStats: Date?
    @Published var lastPeers: Date?
    @Published var showMaintenance = false
    @Published var showRestart = false
    @Published var operationTitle = ""
    @Published var release: ServerRelease?
    @Published var checkingRelease = false
    @Published var releaseCheckedAt: Date?
    @Published var releaseError: String?
    @Published var automation = HostingAutomation()
    @Published var automationMessage = ""
    @Published var playerCount: Int?
    let build = BuildInfo()
    private var startupHandled = false
    private var automationAttempt: Date?
    private var nextReleaseCheck = Date.distantPast
    @Published var keepAwake: Bool { didSet { preferences.set(keepAwake, forKey: "keepAwake"); updateSleepAssertion() } }
    var managerUpdateHandler: (() -> Void)?
    var fleetEngines: [Engine] = []
    let engine: Engine
    private var timer: Timer?
    private var lastCounter: (Date, RuntimeMetrics)?
    private var memorySeries = PerformanceHistory()
    private var segment = 0
    private var lastPeerPosition: UInt64 = 0
    private var assertion: IOPMAssertionID = 0
    private let preferences: UserDefaults
    init(homeOverride: URL? = nil) {
        let env = ProcessInfo.processInfo.environment
        let home = homeOverride ?? (env["ESM_HOME"] ?? UserDefaults.standard.string(forKey: "serverHome")).map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/EnshroudedServer")
        let resources = env["ESM_RESOURCES"].map { URL(fileURLWithPath: $0) } ?? Bundle.main.resourceURL!
        engine = Engine(home: home, resources: resources)
        preferences = UserDefaults(suiteName: "com.glaciannex.enshrouded-manager.\(home.path.data(using: .utf8)!.base64EncodedString())")!
        keepAwake = preferences.object(forKey: "keepAwake") as? Bool ?? true
        automation = engine.loadAutomation()
        loadSettings()
        refresh()
        let sampleTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        RunLoop.main.add(sampleTimer, forMode: .common); timer = sampleTimer
    }
    var name: String { settings.name }
    var stopped: Bool { ["INSTALLED", "VM_STOPPED"].contains(state) }
    var canEdit: Bool { stopped && !busy && !checkingRelease }
    var endpoint: String? { publicAddress.map { "\($0):\(engine.hostPort)" } }
    var label: String {
        if busy { return operationTitle }
        switch state {
        case "NOT_INSTALLED": return "Ready to set up"
        case "INSTALLED", "VM_STOPPED": return "Stopped"
        case "RUNNING": return "Running"
        default: return state
        }
    }
    var peerSummary: String {
        if stopped { return "0 players" }
        if state == "RUNNING", let playerCount { return "\(playerCount) player\(playerCount == 1 ? "" : "s")" }
        guard state == "RUNNING", let lastPeers, Date().timeIntervalSince(lastPeers) < 90 else { return "Players: checking…" }
        return "\(snapshot.peers.count) reported connection\(snapshot.peers.count == 1 ? "" : "s")"
    }
    func loadSettings() {
        if let value = try? engine.readSettings() { settings = value }
        else if let data = try? Data(contentsOf: engine.home.appendingPathComponent("initial-settings.json")), let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { settings = ServerSettings(config: config) }
    }
    func refresh() {
        guard !busy, !polling else { return }
        polling = true
        let engine = engine
        Task {
            do {
                let result = try await Task.detached { () -> (String, String, RuntimeMetrics?, [WorldBackup], Int?) in
                    let state = try engine.status()
                    let metrics = state == "RUNNING" ? try? engine.metrics() : nil
                    return (state, engine.logTail(), metrics, engine.backups(), state == "RUNNING" ? metrics?.playerCount : 0)
                }.value
                let now = Date()
                playerCount = result.4
                state = result.0; serverLog = result.1; metrics = result.2; backups = result.3
                localAddresses = ConnectionInfo.localAddresses()
                let parsed = LogSnapshot.parse(serverLog)
                if let ip = parsed.publicIP { publicAddress = ip }
                if state == "RUNNING", let m = metrics, m.active {
                    if let old = lastCounter, old.1.invocation == m.invocation, now.timeIntervalSince(old.0) < 20, m.cpuSeconds >= old.1.cpuSeconds {
                        // 100% is all four configured vCPUs, rather than one core.
                        let cpu = max(0, min(100, (m.cpuSeconds - old.1.cpuSeconds) / now.timeIntervalSince(old.0) / 4 * 100))
                        cpuHistory.append(.init(date: now, value: cpu, segment: segment))
                    } else { segment += 1 }
                    memorySeries.record(m.memoryBytes / 1_073_741_824, at: now, segment: segment)
                    memoryHistory = memorySeries.points
                    lastCounter = (now, m)
                    if parsed.statsLine != snapshot.statsLine, let value = parsed.updateRate {
                        lastStats = now; updateHistory.append(.init(date: now, value: value, segment: segment))
                    }
                    let size = (try? FileManager.default.attributesOfItem(atPath: engine.data.appendingPathComponent("logs/server.log").path)[.size] as? NSNumber)?.uint64Value ?? 0
                    let base = size > UInt64(serverLog.utf8.count) ? size - UInt64(serverLog.utf8.count) : 0
                    let position = base + UInt64(parsed.peerReportEnd)
                    if parsed.peerReportEnd > 0 && position != lastPeerPosition {
                        lastPeerPosition = position; lastPeers = now
                        for peer in parsed.peers { pingHistory[peer.id, default: []].append(.init(date: now, value: peer.ping, segment: segment)) }
                    }
                } else { lastCounter = nil; lastStats = nil; lastPeers = nil }
                snapshot = parsed
                let cutoff = now.addingTimeInterval(-PerformanceHistory.duration)
                memoryHistory.removeAll { $0.date < cutoff }; cpuHistory.removeAll { $0.date < cutoff }; updateHistory.removeAll { $0.date < cutoff }
                for key in Array(pingHistory.keys) { pingHistory[key]?.removeAll { $0.date < cutoff } }
                lastCheck = now
                updateSleepAssertion()
            } catch {
                metrics = nil; playerCount = nil; lastCounter = nil; self.error = "Status check failed: " + error.localizedDescription
                // Preserve an existing sleep assertion during a transient monitoring failure.
            }
            polling = false
            afterRefresh()
        }
    }
    func operation(_ title: String, work: @escaping (Engine) throws -> Void) {
        guard !busy else { return }
        busy = true; operationTitle = (polling || checkingRelease) ? "Waiting for status check…" : title; error = nil; activity += "\n\(title)…\n"
        let engine = engine
        Task {
            while polling || checkingRelease { try? await Task.sleep(for: .milliseconds(100)) }
            operationTitle = title
            do { try await Task.detached { try work(engine) }.value; activity += "\(title) completed.\n" }
            catch { self.error = error.localizedDescription; activity += "\(title) failed: \(error.localizedDescription)\n" }
            activity = String(activity.suffix(40_000))
            busy = false; loadSettings(); refresh()
        }
    }
    func run(_ action: String) {
        let titles = ["start": "Starting…", "stop": "Saving & stopping…", "restart": "Restarting…", "update": "Updating server…", "install": "Setting up server…", "shutdown": "Shutting down…"]
        operation(titles[action] ?? action.capitalized) { engine in
            try engine.perform(action) { chunk in Task { @MainActor in
                self.activity = String((self.activity + chunk).suffix(40_000))
                if chunk.hasPrefix("Saving and stopping") { self.operationTitle = "Saving & stopping…" }
                if chunk.hasPrefix("Backing up and updating") { self.operationTitle = "Updating server…" }
                if chunk.hasPrefix("Starting server") { self.operationTitle = "Starting…" }
            } }
        }
    }
    func save(_ value: ServerSettings) { operation("Save settings") { try $0.saveSettings(value) } }
    func backup(_ name: String) { operation("Create backup") { try $0.createBackup(name: name) } }
    func restore(_ id: String) { operation("Restore backup") { try $0.restoreBackup(id: id) } }
    func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
    func updateSleepAssertion() {
        if keepAwake && state == "RUNNING" && assertion == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Hosting Enshrouded" as CFString, &assertion)
        } else if (!keepAwake || stopped || state == "NOT_INSTALLED") && assertion != 0 {
            IOPMAssertionRelease(assertion); assertion = 0
        }
    }
}

extension Model {
    var menuValue: String { busy ? operationTitle : state == "RUNNING" ? playerCount.map(String.init) ?? "—" : "—" }
    func checkUpdates(allowBoot: Bool = true) {
        guard !busy, !checkingRelease, ["INSTALLED", "RUNNING", "VM_STOPPED"].contains(state), allowBoot || state != "VM_STOPPED" else { return }
        checkingRelease = true; releaseError = nil; nextReleaseCheck = Date().addingTimeInterval(600)
        let engine = engine
        Task {
            do { release = try await Task.detached { try engine.checkServerRelease() }.value; releaseCheckedAt = Date() }
            catch { releaseError = error.localizedDescription }
            checkingRelease = false
        }
    }
    func afterRefresh() {
        guard !busy, !polling else { return }
        if !startupHandled && ["INSTALLED", "VM_STOPPED", "RUNNING", "NOT_INSTALLED"].contains(state) {
            startupHandled = true
            let resume = engine.home.appendingPathComponent("resume-after-manager-update")
            let shouldResume = FileManager.default.fileExists(atPath: resume.path)
            if shouldResume { try? FileManager.default.removeItem(at: resume) }
            if stopped && (shouldResume || automation.startAtLogin) { run("start"); return }
        }
        if Date() >= nextReleaseCheck { checkUpdates(allowBoot: false) }
        if stopped, let due = automation.nextRestart, Date() >= due {
            automation.nextRestart = automation.next(after: Date()); try? engine.saveAutomation(automation)
        }
        guard !checkingRelease, !busy else { return }
        if var schedule = automation.scheduledBackups, schedule.enabled,
           ["RUNNING", "INSTALLED", "VM_STOPPED"].contains(state) {
            if schedule.nextRun == nil {
                schedule.nextRun = schedule.next(after: Date())
                var updated = automation; updated.scheduledBackups = schedule
                do { try engine.saveAutomation(updated); automation = updated }
                catch { self.error = error.localizedDescription; return }
            }
            if let due = schedule.nextRun, Date() >= due {
                if state == "RUNNING" && playerCount != 0 {
                    automationMessage = "Scheduled backup waiting for a confirmed empty server."
                } else {
                    schedule.nextRun = schedule.next(after: Date())
                    var updated = automation; updated.scheduledBackups = schedule
                    do { try engine.saveAutomation(updated); automation = updated }
                    catch { self.error = error.localizedDescription; return }
                    automationMessage = "Scheduled backup started."
                    operation("Scheduled backup") { engine in
                        do {
                            try engine.scheduledBackup()
                            Task { @MainActor in self.automationMessage = "Scheduled backup completed." }
                        } catch {
                            Task { @MainActor in self.automationMessage = "Scheduled backup failed. See Manager Activity for details." }
                            throw error
                        }
                    }
                    return
                }
            }
        }
        guard state == "RUNNING" else { return }
        if let attempt = automationAttempt, Date().timeIntervalSince(attempt) < 60 { return }
        if automation.automaticUpdates, let release, release.updateAvailable, releaseCheckedAt.map({ Date().timeIntervalSince($0) < 900 }) == true,
           automation.lastAutomaticManifest != release.latest {
            guard playerCount == 0 else { automationMessage = "Update waiting for a confirmed empty server."; return }
            automation.lastAutomaticManifest = release.latest
            do { try engine.saveAutomation(automation) } catch { self.error = error.localizedDescription; return }
            automationAttempt = Date(); automationMessage = "Automatic server update started."
            run("update"); return
        }
        if automation.restartEnabled {
            if automation.nextRestart == nil { automation.nextRestart = automation.next(after: Date()); try? engine.saveAutomation(automation) }
            if let due = automation.nextRestart, Date() >= due {
                guard playerCount == 0 else { automationMessage = "Scheduled restart waiting for a confirmed empty server."; return }
                automation.nextRestart = automation.next(after: Date())
                do { try engine.saveAutomation(automation) } catch { self.error = error.localizedDescription; return }
                automationAttempt = Date(); automationMessage = "Scheduled restart started."
                run("restart")
            }
        }
    }
    func saveAutomation(_ value: HostingAutomation) {
        do {
            var value = value
            guard !value.restartEnabled || (value.everyDays ?? 1) > 1 || !value.weekdays.isEmpty else { throw EngineError("Choose at least one restart weekday") }
            value.nextRestart = value.next(after: Date())
            if var schedule = value.scheduledBackups {
                guard (0...23).contains(schedule.hour), (0...59).contains(schedule.minute) else { throw EngineError("Choose a valid backup time") }
                let previous = automation.scheduledBackups
                if schedule.enabled != previous?.enabled || schedule.hour != previous?.hour || schedule.minute != previous?.minute {
                    schedule.nextRun = schedule.next(after: Date())
                }
                value.scheduledBackups = schedule
            }
            if value.startAtLogin && SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            if !value.startAtLogin && automation.startAtLogin && !fleetEngines.contains(where: { $0.home != engine.home && $0.loadAutomation().startAtLogin }) { try SMAppService.mainApp.unregister() }
            try engine.saveAutomation(value); automation = value; automationMessage = "Hosting automation saved."
        } catch { self.error = "Could not save automation: \(error.localizedDescription)" }
    }
    func chooseManagerUpdate() { managerUpdateHandler?() }
}
