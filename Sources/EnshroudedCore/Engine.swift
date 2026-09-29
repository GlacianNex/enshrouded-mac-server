import Foundation
import Darwin

public struct EngineError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

public struct Engine {
    public let home: URL
    public let resources: URL
    public init(home: URL, resources: URL) { self.home = home; self.resources = resources }
    public var data: URL { home.appendingPathComponent("data") }
    public var lima: URL { resources.appendingPathComponent("Lima/bin/limactl") }
    public var serverConfig: URL { data.appendingPathComponent("server/enshrouded_server.json") }

    public static func yamlString(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(data: try! encoder.encode(value), encoding: .utf8)!
    }
    public func vmConfiguration() -> String {
        """
        vmType: vz
        arch: aarch64
        cpus: 4
        memory: 8GiB
        disk: 40GiB
        images:
        - location: https://cloud-images.ubuntu.com/releases/noble/release-20260705/ubuntu-24.04-server-cloudimg-arm64.img
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
        containerd:
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
    public func command(_ args: [String], output: @escaping (String) -> Void) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = lima
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["LIMA_HOME"] = home.appendingPathComponent("lima").path
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
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
            throw EngineError("Operation failed (\(process.terminationStatus)). \(result.suffix(1500))")
        }
        return result
    }

    public func status() throws -> String {
        guard FileManager.default.fileExists(atPath: home.appendingPathComponent("lima/engine/lima.yaml").path) else { return "NOT_INSTALLED" }
        let list = try command(["list", "engine", "--format={{.Status}}"], output: {_ in})
        guard list.trimmingCharacters(in: .whitespacesAndNewlines) == "Running" else { return "VM_STOPPED" }
        return try command(["shell", "engine", "bash", "/mnt/esm-runtime/guest.sh", "status"], output: {_ in}).trimmingCharacters(in: .whitespacesAndNewlines)
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
            try command(["shell", "engine", "bash", "/mnt/esm-runtime/guest.sh", "stop"], output: output)
        }
        if current != "VM_STOPPED" {
            try command(["stop", "engine"], output: output)
        }
        let backup = home.appendingPathComponent("lima-network-before-v1.yaml")
        if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: config, to: backup) }
        try command(["edit", "--tty=false", "--set", Self.internetForwardEdit, "engine"], output: output)
        try Data("UDP 15637 enabled on all host IPv4 interfaces\n".utf8).write(to: marker, options: .atomic)
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
        try performLocked(action, output: output)
    }

    public func scheduledBackup() throws {
        try withOperationLock {
            try BackupWorkflow.run(initialState: status(), empty: { try queryServer().players == 0 },
                                   execute: { try performLocked($0, output: { _ in }) },
                                   backup: { try requireStoppedWorld(); _ = try copyBackup(name: "Scheduled Backup") })
        }
    }

    private func performLocked(_ action: String, output: @escaping (String) -> Void) throws {
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
            for name in ["guest.sh", "stop-server.py"] {
                let source = try Data(contentsOf: resources.appendingPathComponent("Runtime/\(name)"))
                try source.write(to: home.appendingPathComponent("runtime/\(name)"), options: .atomic)
            }
            let config = home.appendingPathComponent("engine.yaml")
            try vmConfiguration().write(to: config, atomically: true, encoding: .utf8)
            if !fm.fileExists(atPath: home.appendingPathComponent("lima/engine/lima.yaml").path) {
                #if !arch(arm64)
                throw EngineError("This runtime requires an Apple Silicon Mac")
                #endif
                let disk = try fm.attributesOfFileSystem(forPath: home.path)
                guard (disk[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0 >= 30 * 1_073_741_824 else { throw EngineError("Free at least 30 GB before setting up the server") }
            }
            output("Starting the private server environment…\n")
            if !fm.fileExists(atPath: home.appendingPathComponent("lima/engine/lima.yaml").path) {
                try command(["start", "--tty=false", "--name=engine", config.path], output: output)
                try Data("Network forwarding configured at creation\n".utf8).write(to: home.appendingPathComponent("internet-forward-v1"), options: .atomic)
            } else {
                try enableInternetForwarding(output: output)
                try command(["start", "--tty=false", "engine"], output: output)
            }
            try command(["shell", "engine", "bash", "/mnt/esm-runtime/guest.sh", "install"], output: output)
            if !fm.fileExists(atPath: serverConfig.path) {
                try writeSettings(name: "Enshrouded Server", password: UUID().uuidString, adminPassword: UUID().uuidString)
            }
        } else if action == "shutdown" {
            try command(["shell", "engine", "bash", "/mnt/esm-runtime/guest.sh", "stop"], output: output)
            try command(["stop", "engine"], output: output)
        } else {
            if action == "start" {
                guard fm.fileExists(atPath: data.appendingPathComponent("server/enshrouded_server.exe").path) else { throw EngineError("Install the server first") }
                try enableInternetForwarding(output: output)
                try command(["start", "--tty=false", "engine"], output: output)
            }
            try command(["shell", "engine", "bash", "/mnt/esm-runtime/guest.sh", action], output: output)
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
