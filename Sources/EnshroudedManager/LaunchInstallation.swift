import AppKit
import EnshroudedCore

/// Runs before constructing FleetModel: a downloaded app is an installer, not
/// a second controller for the same servers.
@main enum ManagerLauncher {
    @MainActor static func main() {
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
        let existing = others.first(where: { $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == destination })
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
            let progress = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 110), styleMask: [.titled], backing: .buffered, defer: false)
            progress.isReleasedWhenClosed = false; progress.title = "Updating Enshrouded Server Manager"
            let label = NSTextField(wrappingLabelWithString: "Updating the manager… Running servers will restart when finished.")
            label.frame = NSRect(x: 20, y: 25, width: 420, height: 60)
            progress.contentView?.addSubview(label); progress.center(); progress.makeKeyAndOrderFront(nil)
            defer { progress.close() }
            var result: Result<URL, Error>?
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome = Result {
                    try ManagerInstallation.replaceManagingServers(source, destination: destination, engines: engines) {
                        // AppKit can retain stale isTerminated values, especially
                        // during installer run loops. Capture kernel identities first.
                        var lifetimes: [ProcessLifetime] = []
                        DispatchQueue.main.sync {
                            for app in others {
                                guard let lifetime = ProcessLifetime(pid: app.processIdentifier) else { continue }
                                lifetimes.append(lifetime)
                                _ = app.terminate()
                            }
                        }
                        try ManagerQuitWait.wait(lifetimes, timeout: 15)

                    }
                }
                DispatchQueue.main.async { result = outcome }
            }
            while result == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
            _ = try result!.get()
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
        } catch {
            let alert = NSAlert(); alert.messageText = "Manager upgrade needs attention"
            alert.informativeText = error.localizedDescription + "\nOpen the manager from Applications to continue."
            alert.addButton(withTitle: "OK"); alert.runModal()
        }
        return false
    }
}
