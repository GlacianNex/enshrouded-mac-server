import Foundation
import Darwin
import CryptoKit

public struct EngineError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

public struct Engine {
    public let home: URL
    public let resources: URL
    // Overridden only by isolated timeout tests; never terminates the VM itself.
    var environmentShutdownTimeout: TimeInterval = 60
    var serverReleaseTimeout: TimeInterval = 45
    public let sharedDownloads: URL?
    public init(home: URL, resources: URL, sharedDownloads: URL? = nil) { self.home = home; self.resources = resources; self.sharedDownloads = sharedDownloads }
    public var data: URL { home.appendingPathComponent("data") }
    public var lima: URL { resources.appendingPathComponent("Lima/bin/limactl") }
    public var serverConfig: URL { data.appendingPathComponent("server/enshrouded_server.json") }

    public static let environmentImage = URL(string: "https://cloud-images.ubuntu.com/releases/noble/release-20260705/ubuntu-24.04-server-cloudimg-arm64.img")!
    public static let environmentDigest = "7df0201546f75b8bcc1044594c806c35749421ad3c9bc1be2a3ab806cfae39cc"

    public static func yamlString(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(data: try! encoder.encode(value), encoding: .utf8)!
    }
    public func vmConfiguration(image: URL? = nil) -> String {
        let sharedMount = sharedDownloads.map { "- location: \(Self.yamlString($0.path))\n  mountPoint: /mnt/esm-downloads\n  writable: true\n" } ?? ""
        return """
        vmType: vz
        arch: aarch64
        cpus: 4
        memory: 8GiB
        disk: 40GiB
        images:
        - location: \(Self.yamlString(image?.path ?? Self.environmentImage.absoluteString))
          arch: aarch64
          digest: sha256:7df0201546f75b8bcc1044594c806c35749421ad3c9bc1be2a3ab806cfae39cc
        mountType: virtiofs
        mounts:
        - location: \(Self.yamlString(home.appendingPathComponent("runtime").path))
          mountPoint: /mnt/esm-runtime
          writable: false
        - location: \(Self.yamlString(data.path))
          mountPoint: /mnt/esm-data
          writable: true
        \(sharedMount)containerd:
          system: false
          user: false
        vmOpts:
          vz:
            rosetta:
              enabled: false
              binfmt: false
        portForwards:
        - guestPort: 15637
          hostPort: \(hostPort)
          hostIP: 0.0.0.0
          proto: udp
        - guestIP: 0.0.0.0
          proto: any
          ignore: true
        """
    }

    @discardableResult
    public func command(_ args: [String], timeout: TimeInterval? = nil, timeoutMessage: String = "Status check timed out. Try again; the server was not stopped.", output: @escaping (String) -> Void) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = lima
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["LIMA_HOME"] = home.appendingPathComponent("lima").path
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        if let timeout {
            return try DiagnosticCommand.run(executable: lima, arguments: args, environment: env, directory: home, timeout: timeout, timeoutMessage: timeoutMessage, output: output)
        }
        process.environment = env
        process.currentDirectoryURL = home
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        var result = ""
        while true {
            let bytes = pipe.fileHandleForReading.availableData
            if bytes.isEmpty { break }
            let chunk = String(decoding: bytes, as: UTF8.self)
            result += chunk
            // Keep command memory bounded while retaining diagnostic context.
            if result.count > 128_000 { result = String(result.suffix(128_000)) }
            output(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let diagnostic = result.components(separatedBy: .newlines).filter { !$0.contains("[ESM_SETUP] ") }.joined(separator: "\n")
            throw EngineError("Operation failed (\(process.terminationStatus)). \(diagnostic.suffix(1500))")
        }
        return result
    }

    public func status() throws -> String {
        guard FileManager.default.fileExists(atPath: home.appendingPathComponent("lima/engine/lima.yaml").path) else { return "NOT_INSTALLED" }
        let list = try command(["list", "engine", "--format={{.Status}}"], timeout: 15, output: {_ in})
        guard list.trimmingCharacters(in: .whitespacesAndNewlines) == "Running" else { return "VM_STOPPED" }
        return try command(["shell", "engine", "bash", runtimeGuestScript, "status"], timeout: 15, output: {_ in}).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Change only the application's game-port rule, preserving other VM settings.
    public static let internetForwardEdit = "(.portForwards[] | select(.guestPort == 15637 and .proto == \"udp\")).hostIP = \"0.0.0.0\""

    private func enableInternetForwarding(output: @escaping (String) -> Void) throws {
        let fm = FileManager.default
        let config = home.appendingPathComponent("lima/engine/lima.yaml")
        guard fm.fileExists(atPath: config.path) else { return }
        let marker = home.appendingPathComponent("internet-forward-v1")
        guard !fm.fileExists(atPath: marker.path) else { return }
        let current = try status()
        output("Enabling network access on UDP 15637…\n")
        if current == "RUNNING" {
            try command(["shell", "engine", "bash", runtimeGuestScript, "stop"], output: output)
        }
        if current != "VM_STOPPED" {
            try command(["stop", "engine"], output: output)
        }
        let backup = home.appendingPathComponent("lima-network-before-v1.yaml")
        if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: config, to: backup) }
        try command(["edit", "--tty=false", "--set", Self.internetForwardEdit, "engine"], output: output)
        try Data("UDP 15637 enabled on all host IPv4 interfaces\n".utf8).write(to: marker, options: .atomic)
    }

    var runtimeGuestScript: String {
        let version = (try? String(contentsOf: home.appendingPathComponent("runtime-version"))) ?? ""
        guard version.count == 64, version.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            return "/mnt/esm-runtime/guest.sh"
        }
        return "/mnt/esm-runtime/\(version)/guest.sh"
    }

    func syncRuntimeHelpers() throws {
        let files = FileManager.default
        let runtime = home.appendingPathComponent("runtime")
        let helpers = try ["guest.sh", "stop-server.py", "download.py"].map { name in
            (name, try Data(contentsOf: resources.appendingPathComponent("Runtime/" + name)))
        }
        var digest = SHA256()
        for (name, bytes) in helpers { digest.update(data: Data((name + "\0").utf8)); digest.update(data: bytes) }
        let version = digest.finalize().map { String(format: "%02x", $0) }.joined()
        let destination = runtime.appendingPathComponent(version)
        try files.createDirectory(at: runtime, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if !files.fileExists(atPath: destination.path) {
            let staging = runtime.appendingPathComponent(".prepare-" + UUID().uuidString)
            try files.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? files.removeItem(at: staging) }
            for (name, bytes) in helpers { try bytes.write(to: staging.appendingPathComponent(name)) }
            // Never replace a file already visible through VirtioFS. Its guest
            // inode cache can report ENOENT after a host-side atomic replacement.
            try files.moveItem(at: staging, to: destination)
        }
        for (name, bytes) in helpers {
            guard try Data(contentsOf: destination.appendingPathComponent(name)) == bytes else {
                throw EngineError("The runtime helper cache failed validation. Server files were not changed.")
            }
        }
        // This receipt is read only on the Mac, never through the VM mount.
        try Data(version.utf8).write(to: home.appendingPathComponent("runtime-version"), options: .atomic)
    }

    public func perform(_ action: String, output: @escaping (String) -> Void) throws {
        guard ["install", "update", "rollback", "restart", "start", "stop", "shutdown"].contains(action) else { throw EngineError("Unknown operation") }
        let fm = FileManager.default
        try fm.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(home.appendingPathComponent("operation.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw EngineError("Cannot create operation lock") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw EngineError("Another server operation is already running") }
        defer { flock(fd, LOCK_UN) }
        if action == "install" || action == "update" {
            try withSharedDownloads { try performLocked(action, output: output) }
        } else { try performLocked(action, output: output) }
    }

    public func scheduledBackup() throws {
        try withOperationLock {
            try BackupWorkflow.run(initialState: status(), empty: { try queryServer().players == 0 },
                                   execute: { try performLocked($0, output: { _ in }) },
                                   backup: { try requireStoppedWorld(); _ = try copyBackup(name: "Scheduled Backup") })
        }
    }

    func performLocked(_ action: String, output: @escaping (String) -> Void) throws {
        let fm = FileManager.default
        if action == "rollback" {
            try requireStoppedWorld()
            let previous = data.appendingPathComponent("previous-install")
            guard fm.fileExists(atPath: previous.appendingPathComponent("enshrouded_server.exe").path) else { throw EngineError("No previous installation is available") }
            try validateTree(previous)
            _ = try copyBackup(name: "Before installation rollback")
            let server = data.appendingPathComponent("server")
            let temporary = data.appendingPathComponent(".rollback-\(UUID().uuidString)")
            try fm.moveItem(at: server, to: temporary)
            do { try fm.moveItem(at: previous, to: server) }
            catch { try fm.moveItem(at: temporary, to: server); throw error }
            try fm.moveItem(at: temporary, to: previous)
            let receipt = data.appendingPathComponent("installed-manifest.txt")
            if let manifest = try? Data(contentsOf: server.appendingPathComponent(".esm-manifest.txt")) { try manifest.write(to: receipt, options: .atomic) }
            else if fm.fileExists(atPath: receipt.path) { try fm.removeItem(at: receipt) }
            output("Previous installation and its saved world restored. Current world preserved in a recovery backup.\n")
            return
        }
        if action == "update" || action == "restart" {
            do {
                try MaintenanceWorkflow.run(action: action, initialState: status(), empty: { try queryServer().players == 0 }, execute: { try performLocked($0, output: output) }, output: output)
            } catch {
                throw EngineError("Maintenance did not finish: \(error.localizedDescription). Check status and logs before retrying; no forced restart was attempted.")
            }
            return
        }
        if ["start", "stop", "shutdown", "install"].contains(action) { try syncRuntimeHelpers() }
        if action == "stop" || action == "shutdown" {
            let current = try status()
            if current == "NOT_INSTALLED" || current == "VM_STOPPED" { output("Server is already stopped.\n"); return }
        }
        if action == "install" {
            let current = try status()
            guard current != "RUNNING" else { throw EngineError("Stop the server before installing or repairing it") }
            guard fm.isExecutableFile(atPath: lima.path) else { throw EngineError("Bundled runtime is missing. Rebuild or reinstall the app.") }
            for name in ["data", "data/server", "data/logs", "data/backups", "runtime", "lima"] {
                try fm.createDirectory(at: home.appendingPathComponent(name), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
            let config = home.appendingPathComponent("engine.yaml")
            if !fm.fileExists(atPath: home.appendingPathComponent("lima/engine/lima.yaml").path) {
                #if !arch(arm64)
                throw EngineError("This runtime requires an Apple Silicon Mac")
                #endif
                let disk = try fm.attributesOfFileSystem(forPath: home.path)
                guard (disk[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0 >= 30 * 1_073_741_824 else { throw EngineError("Free at least 30 GB before setting up the server") }
            }
            try prepareSharedDownloads(output: output)
            let image = sharedDownloads?.appendingPathComponent("ubuntu.img") ?? home.appendingPathComponent("cache/ubuntu.img")
            if !fm.fileExists(atPath: home.appendingPathComponent("lima/engine/lima.yaml").path) {
                try SetupDownload.fetch(Self.environmentImage, destination: image, sha256: Self.environmentDigest, output: output)
            }
            try vmConfiguration(image: image).write(to: config, atomically: true, encoding: .utf8)
            output(SetupEvent(.environment, "Starting the private server environment…").line)
            if !fm.fileExists(atPath: home.appendingPathComponent("lima/engine/lima.yaml").path) {
                try command(["start", "--tty=false", "--name=engine", config.path], output: output)
                try Data("Network forwarding configured at creation\n".utf8).write(to: home.appendingPathComponent("internet-forward-v1"), options: .atomic)
            } else {
                try enableInternetForwarding(output: output)
                try command(["start", "--tty=false", "engine"], output: output)
            }
            try command(["shell", "engine", "bash", runtimeGuestScript, "install"], output: output)
            try publishSharedServerFiles()
            try? fm.removeItem(at: home.appendingPathComponent("needs-setup"))
            if !fm.fileExists(atPath: serverConfig.path) {
                try writeSettings(name: "Enshrouded Server", password: UUID().uuidString, adminPassword: UUID().uuidString)
            }
        } else if action == "shutdown" {
            try command(["shell", "engine", "bash", runtimeGuestScript, "stop"], output: output)
            output("Stopping the server environment…\n")
            // Power down through the guest first. Old host agents can wait on
            // exhausted networking streams before they ever ask the VM to stop.
            // This is a normal OS shutdown, only after the game has exited.
            do {
                try command(["shell", "engine", "sudo", "systemctl", "--no-block", "poweroff"], timeout: 10,
                            timeoutMessage: "Waiting for the environment shutdown request to finish.", output: output)
            } catch {
                // SSH may disappear before acknowledging poweroff. The bounded
                // stop client below remains responsible for confirming shutdown.
                output("Waiting for the server environment to finish shutting down…\n")
            }
            try command(["stop", "engine"], timeout: environmentShutdownTimeout,
                        timeoutMessage: "The game server has stopped, but its environment did not shut down within 60 seconds. The operation could not finish. Check the log and try again.", output: output)
        } else {
            if action == "start" {
                guard fm.fileExists(atPath: data.appendingPathComponent("server/enshrouded_server.exe").path) else { throw EngineError("Install the server first") }
                try enableInternetForwarding(output: output)
                try command(["start", "--tty=false", "engine"], output: output)
            }
            try command(["shell", "engine", "bash", runtimeGuestScript, action], output: output)
            if action == "start" {
                output("Waiting for the game server to answer…\n")
                let expected = try readSettings().name
                for attempt in 0..<15 {
                    if let query = try? queryServer(), query.name == expected {
                        output("Server ready: \(query.name), \(query.players)/\(query.capacity) players.\n")
                        return
                    }
                    if attempt < 14 { Thread.sleep(forTimeInterval: 1) }
                }
                throw EngineError("The process started, but the game server did not answer its internal readiness query. Check the server log. This check does not test router port forwarding.")
            }
        }
    }

    public func saveSettings(name: String, password: String, adminPassword: String) throws {
        let fd = open(home.appendingPathComponent("operation.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw EngineError("Install the server first") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw EngineError("Another server operation is already running") }
        defer { flock(fd, LOCK_UN) }
        let current = try status()
        guard ["INSTALLED", "VM_STOPPED"].contains(current) else { throw EngineError("Stop the server before changing settings") }
        try writeSettings(name: name, password: password, adminPassword: adminPassword)
    }

    private func writeSettings(name: String, password: String, adminPassword: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              password.count >= 8, adminPassword.count >= 8, password != adminPassword else {
            throw EngineError("Enter a server name and different player/admin passwords of at least 8 characters")
        }
        var config: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: serverConfig.path) { config = try readConfiguration() }
        var settings = ServerSettings(config: config)
        settings.name = name; settings.password = password; settings.adminPassword = adminPassword
        config = try settings.applying(to: config)
        config["saveDirectory"] = config["saveDirectory"] ?? "./savegame"
        config["logDirectory"] = config["logDirectory"] ?? "./logs"
        config["ip"] = config["ip"] ?? "0.0.0.0"
        config["queryPort"] = config["queryPort"] ?? 15637
        let bytes = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try bytes.write(to: serverConfig, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: serverConfig.path)
    }
}
