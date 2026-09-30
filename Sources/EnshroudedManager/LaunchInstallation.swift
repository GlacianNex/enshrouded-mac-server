import AppKit
import EnshroudedCore

/// Runs before constructing FleetModel: a downloaded app is an installer, not
/// a second controller for the same servers.
@main enum ManagerLauncher {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        if arguments.count == 3, ["--hosting-guard", "--start-at-login"].contains(arguments[1]) {
            let engine = Engine(home: URL(fileURLWithPath: arguments[2]), resources: ProcessInfo.processInfo.environment["ESM_RESOURCES"].map { URL(fileURLWithPath: $0) } ?? Bundle.main.resourceURL!)
            do {
                if arguments[1] == "--hosting-guard" { try HostingGuard.run(engine: engine) }
                else if engine.loadAutomation().startAtLogin {
                    if try engine.status() != "RUNNING" { try engine.perform("start") { try? engine.appendActivity($0) } }
                    try HostingGuard.ensure(engine: engine, executable: Bundle.main.executableURL!)
                }
            } catch { try? engine.appendActivity("Background hosting failed: \(error.localizedDescription)\n") }
            return
        }
        _ = NSApplication.shared
        if LaunchInstallation.prepare() { EnshroudedApp.main() }
    }
}

@MainActor enum LaunchInstallation {
    static let identifier = "com.glaciannex.enshrouded-manager"
    static func prepare() -> Bool {
        // Command-line development and isolated runtime previews do not install.
        guard ProcessInfo.processInfo.environment["ESM_HOME"] == nil,
              Bundle.main.bundleURL.pathExtension == "app" else { return true }
        let source = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let destination = URL(fileURLWithPath: "/Applications/Enshrouded Server Manager.app")
        let replacing = FileManager.default.fileExists(atPath: destination.path)
        let predecessor = ProcessInfo.processInfo.environment["ESM_RELAUNCH_FROM_PID"].flatMap(Int32.init)
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).filter {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.processIdentifier != predecessor && !$0.isTerminated
        }
        let existing = others.first(where: { $0.bundleURL.map { ManagerInstallation.sameLocation($0, destination) } == true })
        let plan = ManagerLaunchPlan.decide(source: source, destination: destination, destinationIsRunning: existing != nil)
        if plan != .install {
            if let existing, plan == .activateExisting {
                existing.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                return false
            }
            return true
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        var managerWasClosed = false
        let installLog = Engine(home: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Enshrouded Manager/Installer"), resources: Bundle.main.resourceURL!)
        try? installLog.appendActivity("\nManager installation started: \(Date())\nSource: \(source.path)\n")
        do {
            _ = replacing ? try ManagerInstallation.validate(source, replacing: destination) : try BuildInfo.read(app: source)
            let alert = NSAlert()
            alert.messageText = replacing ? "Update Enshrouded Server Manager?" : "Install Enshrouded Server Manager?"
            alert.informativeText = replacing
                ? "Updating the manager will stop all running servers. They will start back up once the update finishes."
                : "Install Enshrouded Server Manager in Applications. The manager will open after installation."
            alert.addButton(withTitle: replacing ? "Stop, Update & Relaunch" : "Install & Open")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            let registry = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Enshrouded Manager/profiles.json")
            let profiles = try ProfileStore(registry: registry).load()
            let fallback = UserDefaults.standard.string(forKey: "serverHome") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/EnshroudedServer").path
            let homes = profiles.isEmpty ? [fallback] : profiles.map(\.home)
            let engines = homes.map { Engine(home: URL(fileURLWithPath: $0), resources: Bundle.main.resourceURL!) }
            let progress = ManagerInstallProgressWindow(logURL: installLog.home.appendingPathComponent("manager-activity.log"))
            defer { progress.close() }
            var result: Result<URL, Error>?
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome = Result {
                    try ManagerInstallation.replaceManagingServers(source, destination: destination, engines: engines, output: { try? installLog.appendActivity($0) }, progress: { stage in
                        try? installLog.appendActivity(stage.title + "\n")
                        DispatchQueue.main.async { progress.advance(stage) }
                    }) {
                        // AppKit can retain stale isTerminated values, especially
                        // during installer run loops. Capture kernel identities first.
                        var lifetimes: [ProcessLifetime] = []
                        DispatchQueue.main.sync {
                            for app in others {
                                guard let lifetime = ProcessLifetime(pid: app.processIdentifier) else { continue }
                                lifetimes.append(lifetime)
                                if app.terminate() { managerWasClosed = true }
                            }
                        }
                        try ManagerQuitWait.wait(lifetimes, timeout: 15)

                    }
                }
                DispatchQueue.main.async { result = outcome }
            }
            while result == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
            let previous = try result!.get()
            progress.advance(.opening)
            try reopen(destination)
            do { try ManagerInstallation.cleanupSuccessfulReplacement(previous: previous, destination: destination) }
            catch { try? installLog.appendActivity("Update completed; previous app cleanup failed: \(error.localizedDescription)\n") }
            try? installLog.appendActivity("Manager replacement and relaunch completed.\n")
        } catch {
            try? installLog.appendActivity("Installation failed: \(error.localizedDescription)\n")
            let alert = NSAlert(); alert.messageText = "Manager Update Could Not Finish"
            alert.informativeText = error.localizedDescription + (managerWasClosed ? "\nThe installed manager will reopen when you close this message." : "\nThe installed manager has not been closed.")
            alert.addButton(withTitle: "OK"); alert.runModal()
            if managerWasClosed {
                do { try reopen(destination); try? installLog.appendActivity("Reopened the installed manager after failed update.\n") }
                catch {
                    try? installLog.appendActivity("Recovery launch failed: \(error.localizedDescription)\n")
                    let recovery = NSAlert(); recovery.messageText = "Open the Manager from Applications"
                    recovery.informativeText = "The manager could not reopen automatically. Your installation and server data are preserved."
                    recovery.addButton(withTitle: "OK"); recovery.runModal()
                }
            }
        }
        return false
    }
    private static func reopen(_ destination: URL) throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.environment = ["ESM_RELAUNCH_FROM_PID": String(ProcessInfo.processInfo.processIdentifier)]
        var completed = false
        var failure: Error?
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
            DispatchQueue.main.async { failure = error; completed = true }
        }
        while !completed { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        if let failure { throw failure }
    }
}
