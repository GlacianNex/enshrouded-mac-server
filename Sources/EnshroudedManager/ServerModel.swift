import SwiftUI
import AppKit
import IOKit.pwr_mgt
import ServiceManagement
import EnshroudedCore

@MainActor final class Model: ObservableObject {
    var setupStartsServer = true
    @Published var setupProgress: SetupProgress?
    @Published var serverProgress: ServerOperationProgress?
    private var telemetryPolling = false
    @Published var state = "Checking…"
    @Published var busy = false { didSet { if oldValue != busy { operationEpoch = UUID() } } }
    private var operationEpoch = UUID()
    private(set) var activeAction: String?
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
    @Published var releaseCheckQueued = false
    @Published var checkingRelease = false
    @Published var releaseCheckStarted: Date?
    @Published var releaseCheckStage = "Contacting Valve"
    @Published var releaseCheckedAt: Date?
    @Published var releaseError: String?
    @Published var automation = HostingAutomation()
    @Published var automationMessage = ""
    @Published var playerCount: Int?
    let build = BuildInfo()
    private var startupHandled = false
    private var automationAttempt: Date?
    private var nextReleaseCheck = Date.distantPast
    @Published var keepAwake: Bool { didSet { preferences.set(keepAwake, forKey: "keepAwake"); persistSleepPreference(); updateSleepAssertion() } }
    var managerUpdateHandler: (() -> Void)?
    var fleetEngines: [Engine] = []
    var profileStore: ProfileStore?
    let engine: Engine
    private let activityWriter = DispatchQueue(label: "EnshroudedManager.activity")
    private var timer: Timer?
    private var lastCounter: (Date, RuntimeMetrics)?
    private var memorySeries = PerformanceHistory()
    private var segment = 0
    private var lastPeerIdentity: String?
    private var speedSeries = ServerSpeedHistory()
    private var lastLogSize: UInt64 = 0
    private var assertion: IOPMAssertionID = 0
    private var lastGuardCheck = Date.distantPast
    private let preferences: UserDefaults
    init(homeOverride: URL? = nil, automaticStartup: Bool = true, sharedDownloads: URL? = nil) {
        startupHandled = !automaticStartup
        let env = ProcessInfo.processInfo.environment
        let home = homeOverride ?? (env["ESM_HOME"] ?? UserDefaults.standard.string(forKey: "serverHome")).map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/EnshroudedServer")
        let resources = env["ESM_RESOURCES"].map { URL(fileURLWithPath: $0) } ?? Bundle.main.resourceURL!
        engine = Engine(home: home, resources: resources, sharedDownloads: sharedDownloads)
        preferences = UserDefaults(suiteName: "com.glaciannex.enshrouded-manager.\(home.path.data(using: .utf8)!.base64EncodedString())")!
        keepAwake = preferences.object(forKey: "keepAwake") as? Bool ?? true
        activity = engine.activityTail()
        automation = engine.loadAutomation()
        loadSettings()
        if automation.startAtLogin && env["ESM_HOME"] == nil {
            do { try LoginStartup.configure(home: engine.home, enabled: true, executable: Bundle.main.executableURL!) }
            catch { self.error = "Login startup could not be configured: " + error.localizedDescription }
        }
        persistSleepPreference()
        refresh()
        let sampleTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        RunLoop.main.add(sampleTimer, forMode: .common); timer = sampleTimer
    }
    var name: String { settings.name }
    var stopped: Bool { ["INSTALLED", "VM_STOPPED"].contains(state) }
    var canEdit: Bool { stopped && !busy }
    var endpoint: String? { publicAddress.map { "\($0):\(engine.hostPort)" } }
    var installationPending: Bool { state == "NOT_INSTALLED" || setupProgress.map { !$0.finished } == true }
    var menuTitle: String { name + " — " + label + (peerSummary.isEmpty ? "" : " · " + peerSummary) }
    var label: String {
        if installationPending { return "Installation Pending" }
        if busy { return operationTitle }
        switch state {
        case "NOT_INSTALLED": return "Installation Pending"
        case "INSTALLED", "VM_STOPPED": return "Stopped"
        case "RUNNING": return "Running"
        case "RECOVERING": return "Recovering after a server crash…"
        default: return state
        }
    }
    var peerSummary: String {
        if installationPending { return "" }
        if stopped { return "0 players" }
        if state == "RUNNING", let playerCount { return "\(playerCount) player\(playerCount == 1 ? "" : "s")" }
        guard state == "RUNNING" else { return "" }
        guard let lastPeers, Date().timeIntervalSince(lastPeers) < 90 else { return "Players: checking…" }
        return "\(snapshot.peers.count) reported connection\(snapshot.peers.count == 1 ? "" : "s")"
    }
    var currentUpdateRate: Double? {
        guard state == "RUNNING" else { return nil }
        return speedSeries.current(at: Date())
    }
    var speedSummary: String {
        if state != "RUNNING" { return "Readings resume when the server is running." }
        guard let value = speedSeries.lastValue else { return "Waiting for Enshrouded’s first speed report…" }
        guard speedSeries.reportTimeKnown, let report = speedSeries.lastReport else { return String(format: "Last logged: %.1f updates/s · report time unavailable", value) }
        let seconds = max(0, Int(Date().timeIntervalSince(report)))
        let age = seconds < 60 ? "\(seconds)s ago" : "\(seconds / 60)m \(seconds % 60)s ago"
        return String(format: "Last reported: %.1f updates/s", value) + " · " + age
    }
    func loadSettings() {
        if let value = try? engine.readSettings() { settings = value }
        else if let data = try? Data(contentsOf: engine.home.appendingPathComponent("initial-settings.json")), let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { settings = ServerSettings(config: config) }
    }
    func refresh() {
        if busy { refreshBusyTelemetry(); return }
        guard !polling else { return }
        polling = true
        let engine = engine
        Task {
            do {
                let result = try await Task.detached { () -> (String, LogTailSnapshot, RuntimeMetrics?, [WorldBackup], Int?) in
                    let observedState = try engine.status()
                    let state = observedState != "RUNNING" && FileManager.default.fileExists(atPath: engine.home.appendingPathComponent("needs-setup").path) ? "NOT_INSTALLED" : observedState
                    let metrics = state == "RUNNING" ? try? engine.metrics() : nil
                    return (state, engine.logTailSnapshot(), metrics, engine.backups(), state == "RUNNING" ? metrics?.playerCount : 0)
                }.value
                let now = Date()
                playerCount = result.4
                state = result.0; serverLog = result.1.text; metrics = result.2; backups = result.3
                localAddresses = ConnectionInfo.localAddresses()
                applyTelemetry(result.1, metrics: result.2, running: state == "RUNNING", at: now)
                lastCheck = now
                updateSleepAssertion()
            } catch {
                metrics = nil; playerCount = nil; lastCounter = nil; lastPeers = nil; self.error = "Status check failed: " + error.localizedDescription
                // Preserve an existing sleep assertion during a transient monitoring failure.
            }
            polling = false
            afterRefresh()
        }
    }
    private func applyTelemetry(_ log: LogTailSnapshot, metrics: RuntimeMetrics?, running: Bool?, at now: Date) {
        let parsed = log.parsed
        if let ip = parsed.publicIP { publicAddress = ip }
        speedSeries.observe(log, running: running, invocation: metrics?.invocation, at: now)
        updateHistory = speedSeries.points; lastStats = speedSeries.lastReport
        if running == true, let m = metrics, m.active {
            if let old = lastCounter, old.1.invocation == m.invocation, now.timeIntervalSince(old.0) < 20, m.cpuSeconds >= old.1.cpuSeconds {
                // 100% is all four configured vCPUs, rather than one core.
                let cpu = max(0, min(100, (m.cpuSeconds - old.1.cpuSeconds) / now.timeIntervalSince(old.0) / 4 * 100))
                cpuHistory.append(.init(date: now, value: cpu, segment: segment))
            } else { segment += 1 }
            memorySeries.record(m.memoryBytes / 1_073_741_824, at: now, segment: segment)
            memoryHistory = memorySeries.points
            lastCounter = (now, m)
            if log.fileSize < lastLogSize { lastPeerIdentity = nil }
            lastLogSize = log.fileSize
            if let identity = log.identityFor(relativeEnd: parsed.peerReportEnd).map({ m.invocation + ":" + $0 }), identity != lastPeerIdentity {
                lastPeerIdentity = identity; lastPeers = log.peerReportDate(at: now)
                if let report = lastPeers, now.timeIntervalSince(report) < 90 {
                    for peer in parsed.peers { pingHistory[peer.id, default: []].append(.init(date: report, value: peer.ping, segment: segment)) }
                }
            }
        } else { lastCounter = nil; lastPeers = nil }
        snapshot = parsed
        let cutoff = now.addingTimeInterval(-PerformanceHistory.duration)
        memoryHistory.removeAll { $0.date < cutoff }; cpuHistory.removeAll { $0.date < cutoff }; updateHistory.removeAll { $0.date < cutoff }
        for key in Array(pingHistory.keys) {
            pingHistory[key]?.removeAll { $0.date < cutoff }
            if pingHistory[key]?.isEmpty == true { pingHistory.removeValue(forKey: key) }
        }
    }
    var visiblePingIDs: [String] {
        guard state == "RUNNING", playerCount != 0, let lastPeers, Date().timeIntervalSince(lastPeers) < 90 else { return [] }
        return snapshot.peers.map(\.id).filter { !(pingHistory[$0] ?? []).isEmpty }.sorted()
    }
    private func refreshBusyTelemetry() {
        guard !telemetryPolling, !polling, state == "RUNNING", activeAction != "install" else { return }
        telemetryPolling = true
        let epoch = operationEpoch
        let engine = engine
        Task {
            let sample = await Task.detached(priority: .utility) { (engine.logTailSnapshot(), try? engine.metrics()) }.value
            // A completed operation owns the next full refresh. Discard a late probe.
            if busy && operationEpoch == epoch {
                metrics = sample.1
                applyTelemetry(sample.0, metrics: sample.1, running: sample.1.map(\.active), at: Date())
            }
            telemetryPolling = false
        }
    }
    private func persistSleepPreference() {
        let marker = engine.home.appendingPathComponent("prevent-sleep.disabled")
        guard FileManager.default.fileExists(atPath: engine.home.path) else { return }
        do {
            if keepAwake { if FileManager.default.fileExists(atPath: marker.path) { try FileManager.default.removeItem(at: marker) } }
            else { try Data().write(to: marker, options: .atomic) }
        } catch { self.error = "Could not save sleep protection: " + error.localizedDescription }
    }
    func operation(_ title: String, action: String? = nil, preservingSetupProgress: Bool = false, work: @escaping (Engine) throws -> Void, completion: ((Bool) -> Void)? = nil) {
        guard !busy else { completion?(false); return }
        activeAction = action
        if !preservingSetupProgress { setupProgress = nil }
        serverProgress = action.map { ServerOperationProgress(action: $0) }
        busy = true; operationTitle = (polling || checkingRelease) ? "Waiting for status check…" : title; error = nil; recordActivity("\n\(title)…\n")
        let engine = engine
        Task {
            while polling || checkingRelease { try? await Task.sleep(for: .milliseconds(100)) }
            operationTitle = title
            var succeeded = false
            do { try await Task.detached { try work(engine) }.value; recordActivity("\(title) completed.\n"); succeeded = true }
            catch { self.error = error.localizedDescription; recordActivity("\(title) failed: \(error.localizedDescription)\n") }
            activity = String(activity.suffix(40_000))
            if succeeded, let cached = release { release = ServerRelease(installed: engine.installedManifest, latest: cached.latest) }
            if succeeded, ProcessInfo.processInfo.environment["ESM_HOME"] == nil, Bundle.main.bundleIdentifier == LaunchInstallation.identifier, let executable = Bundle.main.executableURL {
                do { try HostingGuard.ensure(engine: engine, executable: executable) }
                catch { recordActivity("Sleep protection could not start: \(error.localizedDescription)\n") }
            }
            serverProgress?.finish(success: succeeded)
            activeAction = nil; busy = false; loadSettings(); completion?(succeeded); refresh()
        }
    }
    func flushActivity() async {
        await withCheckedContinuation { continuation in
            activityWriter.async { continuation.resume() }
        }
    }
    func resetSetupLog() {
        let log = engine.setupLogEngine.home.appendingPathComponent("manager-activity.log")
        activityWriter.async { try? FileManager.default.removeItem(at: log) }
    }
    func recordActivity(_ text: String) {
        activity = String((activity + text).suffix(256_000))
        let engine = engine
        let setup = busy && setupProgress != nil
        activityWriter.async {
            try? engine.appendActivity(text)
            if setup { try? engine.setupLogEngine.appendActivity(text) }
        }
    }
    func run(_ action: String, completion: ((Bool) -> Void)? = nil) {
        let titles = ["start": "Starting…", "stop": "Saving & stopping…", "restart": "Restarting…", "update": "Updating server…", "install": "Setting up server…", "shutdown": "Shutting down…"]
        operation(titles[action] ?? action.capitalized, action: action, work: { engine in
            try engine.perform(action) { chunk in Task { @MainActor in
                self.recordActivity(chunk)
                self.serverProgress?.consume(chunk)
                if chunk.hasPrefix("Saving and stopping") { self.operationTitle = "Saving & stopping…" }
                if chunk.hasPrefix("Backing up and updating") { self.operationTitle = "Updating server…" }
                if chunk.hasPrefix("Waiting for another server to finish starting") { self.operationTitle = "Waiting to start…" }
                if chunk.hasPrefix("Starting server") { self.operationTitle = "Starting…" }
            } }
        }, completion: completion)
    }
    func save(_ value: ServerSettings) { operation("Save settings") { try $0.saveSettings(value) } }
    func backup(_ name: String) { operation("Create backup") { try $0.createBackup(name: name) } }
    func restore(_ id: String) { operation("Restore backup") { try $0.restoreBackup(id: id) } }
    func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
    func retire(forgettingPreferences: Bool = false) {
        if forgettingPreferences {
            preferences.removePersistentDomain(forName: "com.glaciannex.enshrouded-manager.\(engine.home.path.data(using: .utf8)!.base64EncodedString())")
        }
        timer?.invalidate(); timer = nil
        if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
    }
    func updateSleepAssertion() {
        if ["RUNNING", "RECOVERING"].contains(state), ProcessInfo.processInfo.environment["ESM_HOME"] == nil, Bundle.main.bundleIdentifier == LaunchInstallation.identifier, Date().timeIntervalSince(lastGuardCheck) > 30, let executable = Bundle.main.executableURL {
            lastGuardCheck = Date()
            try? HostingGuard.ensure(engine: engine, executable: executable)
        }
        if keepAwake && ["RUNNING", "RECOVERING"].contains(state) && assertion == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Hosting Enshrouded" as CFString, &assertion)
        } else if (!keepAwake || stopped || state == "NOT_INSTALLED") && assertion != 0 {
            IOPMAssertionRelease(assertion); assertion = 0
        }
    }
}

extension Model {
    var menuValue: String { busy ? operationTitle : state == "RUNNING" ? playerCount.map(String.init) ?? "—" : "—" }
    var releaseCheckSummary: String {
        let seconds = Int(Date().timeIntervalSince(releaseCheckStarted ?? Date()))
        return "\(releaseCheckStage)… \(seconds)s"
    }
    var canRequestReleaseCheck: Bool {
        ["INSTALLED", "RUNNING", "VM_STOPPED"].contains(state) &&
            (!busy || ["start", "stop", "restart"].contains(activeAction ?? ""))
    }
    func checkUpdates(allowBoot: Bool = true) {
        if busy {
            if allowBoot && canRequestReleaseCheck { releaseCheckQueued = true }
            return
        }
        guard !checkingRelease, ["INSTALLED", "RUNNING", "VM_STOPPED"].contains(state), allowBoot || state != "VM_STOPPED" else { return }
        releaseCheckQueued = false
        checkingRelease = true; releaseCheckStarted = Date(); releaseCheckStage = "Contacting Valve"; releaseError = nil; nextReleaseCheck = Date().addingTimeInterval(600)
        let engine = engine
        Task {
            do {
                let progress: (String) -> Void = { [weak self] stage in
                    Task { @MainActor in self?.releaseCheckStage = stage }
                }
                release = try await Task.detached { try engine.checkServerRelease(progress: progress) }.value
                releaseCheckedAt = Date()
            }
            catch { releaseError = error.localizedDescription; releaseCheckedAt = nil }
            checkingRelease = false
        }
    }
    func afterRefresh() {
        guard !busy, !polling else { return }
        if !startupHandled && ["INSTALLED", "VM_STOPPED", "RUNNING", "NOT_INSTALLED"].contains(state) {
            startupHandled = true
            let resume = engine.home.appendingPathComponent("resume-after-manager-update")
            let shouldResume = FileManager.default.fileExists(atPath: resume.path)
            if state == "RUNNING" && shouldResume { try? FileManager.default.removeItem(at: resume) }
            if stopped && shouldResume {
                run("start") { success in
                    if success { try? FileManager.default.removeItem(at: resume) }
                }
                return
            }
        }
        if releaseCheckQueued {
            releaseCheckQueued = false
            checkUpdates()
        } else if Date() >= nextReleaseCheck { checkUpdates(allowBoot: false) }
        if stopped, let due = automation.nextRestart, Date() >= due {
            var updated = automation; updated.nextRestart = updated.next(after: Date()); updated.waitingRestart = nil
            do { try engine.saveAutomation(updated); automation = updated }
            catch { self.error = error.localizedDescription; return }
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
        if automation.automaticUpdates, releaseError == nil, let release, release.updateAvailable, releaseCheckedAt.map({ Date().timeIntervalSince($0) < 900 }) == true,
           automation.lastAutomaticManifest != release.latest {
            guard playerCount == 0 else { automationMessage = "Update waiting for a confirmed empty server."; return }
            var updated = automation; updated.lastAutomaticManifest = release.latest
            do { try engine.saveAutomation(updated); automation = updated } catch { self.error = error.localizedDescription; return }
            automationAttempt = Date(); automationMessage = "Automatic server update started."
            run("update"); return
        }
        if automation.restartEnabled {
            if automation.nextRestart == nil {
                var updated = automation; updated.nextRestart = updated.next(after: Date())
                do { try engine.saveAutomation(updated); automation = updated }
                catch { self.error = error.localizedDescription; return }
            }
            let decision = ScheduledRestartPolicy.decide(automation: automation, now: Date(), running: true, players: playerCount)
            if decision == .waiting {
                if automation.waitingRestart != automation.nextRestart {
                    var updated = automation; updated.waitingRestart = updated.nextRestart
                    do { try engine.saveAutomation(updated); automation = updated }
                    catch { self.error = error.localizedDescription; return }
                }
                automationMessage = "Scheduled restart waiting for a confirmed empty server."
            } else if decision == .run || decision == .skip {
                var updated = automation; updated.nextRestart = updated.next(after: Date()); updated.waitingRestart = nil
                do { try engine.saveAutomation(updated); automation = updated }
                catch { self.error = error.localizedDescription; return }
                if decision == .run {
                    automationAttempt = Date(); automationMessage = "Scheduled restart started."; run("restart")
                } else { automationMessage = playerCount == 0 ? "Missed scheduled restart skipped." : "Scheduled restart skipped: the server was occupied or its player count was unavailable." }
            }
        }
    }
    func saveAutomation(_ value: HostingAutomation) {
        do {
            var value = value.reconcilingRestart(with: automation)
            guard !value.restartEnabled || (value.everyDays ?? 1) > 1 || !value.weekdays.isEmpty else { throw EngineError("Choose at least one restart weekday") }
            if value.automaticUpdates && !automation.automaticUpdates { value.lastAutomaticManifest = nil }
            if var schedule = value.scheduledBackups {
                guard (0...23).contains(schedule.hour), (0...59).contains(schedule.minute) else { throw EngineError("Choose a valid backup time") }
                let previous = automation.scheduledBackups
                if schedule.enabled != previous?.enabled || schedule.hour != previous?.hour || schedule.minute != previous?.minute {
                    schedule.nextRun = schedule.next(after: Date())
                }
                value.scheduledBackups = schedule
            }
            guard ProcessInfo.processInfo.environment["ESM_HOME"] == nil || value.startAtLogin == automation.startAtLogin else {
                throw EngineError("Login startup is unavailable in an isolated test environment.")
            }
            if value.startAtLogin != automation.startAtLogin {
                try LoginStartup.configure(home: engine.home, enabled: value.startAtLogin, executable: Bundle.main.executableURL!)
            }
            do { try engine.saveAutomation(value) }
            catch {
                if value.startAtLogin != automation.startAtLogin { try? LoginStartup.configure(home: engine.home, enabled: automation.startAtLogin, executable: Bundle.main.executableURL!) }
                throw error
            }
            automation = value; automationMessage = "Hosting automation saved."
        } catch { self.error = "Could not save automation: \(error.localizedDescription)" }
    }
    func chooseManagerUpdate() { managerUpdateHandler?() }
}
