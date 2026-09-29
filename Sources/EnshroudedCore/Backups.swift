import Foundation
import Darwin

public struct WorldBackup: Identifiable {
    public let id: String
    public let name: String
    public let date: Date
    public let url: URL
}

extension Engine {
    func withOperationLock<T>(name: String = "operation.lock", _ body: () throws -> T) throws -> T {
        let fd = open(home.appendingPathComponent(name).path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw EngineError("Install the server first") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw EngineError("Another operation is running") }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
    public var world: URL { data.appendingPathComponent("server/savegame") }
    public var backupDirectory: URL { data.appendingPathComponent("backups/worlds") }
    public func backups() -> [WorldBackup] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)) ?? []
        return entries.compactMap { url in
            guard !url.lastPathComponent.hasPrefix("."),
                  let bytes = try? Data(contentsOf: url.appendingPathComponent("manifest.json")),
                  let manifest = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let name = manifest["name"] as? String, let timestamp = manifest["created"] as? Double else { return nil }
            return WorldBackup(id: url.lastPathComponent, name: name, date: Date(timeIntervalSince1970: timestamp), url: url)
        }.sorted { $0.date > $1.date }
    }
    // Never follow links into unrelated files while copying or restoring a world.
    func validateTree(_ url: URL) throws {
        let fm = FileManager.default
        let root = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard root.isSymbolicLink != true, root.isDirectory == true else { throw EngineError("Expected a world folder, not a link") }
        guard let entries = fm.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]) else { throw EngineError("Cannot read world folder") }
        for case let item as URL in entries {
            let v = try item.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            guard v.isSymbolicLink != true, v.isRegularFile == true || v.isDirectory == true else { throw EngineError("World contains an unsupported file or symbolic link") }
        }
    }
    func requireStoppedWorld() throws {
        guard ["INSTALLED", "VM_STOPPED"].contains(try status()) else { throw EngineError("Save and stop the server before managing backups") }
        let config = try readConfiguration()
        guard ["./savegame", "savegame"].contains(config["saveDirectory"] as? String ?? "./savegame") else { throw EngineError("Backups require the managed savegame folder; custom save paths are not supported") }
    }
    @discardableResult public func createBackup(name: String) throws -> URL {
        try withOperationLock { try requireStoppedWorld(); return try copyBackup(name: name) }
    }
    func copyBackup(name: String) throws -> URL {
        let fm = FileManager.default
        try validateTree(world)
        try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let id = UUID().uuidString
        let staging = backupDirectory.appendingPathComponent(".\(id)")
        let final = backupDirectory.appendingPathComponent(id)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: world, to: staging.appendingPathComponent("savegame"))
        try fm.copyItem(at: serverConfig, to: staging.appendingPathComponent("enshrouded_server.json"))
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let manifest: [String: Any] = ["name": label.isEmpty ? "World backup" : String(label.prefix(100)), "created": Date().timeIntervalSince1970]
        try JSONSerialization.data(withJSONObject: manifest).write(to: staging.appendingPathComponent("manifest.json"))
        try fm.moveItem(at: staging, to: final)
        return final
    }
    public func restoreBackup(id: String) throws {
        try withOperationLock {
            try requireStoppedWorld()
            guard let backup = backups().first(where: { $0.id == id }) else { throw EngineError("Backup not found") }
            try validateTree(backup.url)
            try validateTree(backup.url.appendingPathComponent("savegame"))
            let configBytes = try Data(contentsOf: backup.url.appendingPathComponent("enshrouded_server.json"))
            guard let config = try JSONSerialization.jsonObject(with: configBytes) as? [String: Any],
                  ["./savegame", "savegame"].contains(config["saveDirectory"] as? String ?? "./savegame") else { throw EngineError("Backup configuration is invalid") }
            let fm = FileManager.default
            let recovery = try copyBackup(name: "Before restoring \(backup.name)")
            let stage = data.appendingPathComponent("server/.restore-\(UUID().uuidString)")
            let previous = data.appendingPathComponent("server/.previous-\(UUID().uuidString)")
            try fm.copyItem(at: backup.url.appendingPathComponent("savegame"), to: stage)
            defer { try? fm.removeItem(at: stage) }
            try fm.moveItem(at: world, to: previous)
            do {
                try fm.moveItem(at: stage, to: world)
                try configBytes.write(to: serverConfig, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: serverConfig.path)
            } catch {
                try? fm.removeItem(at: world)
                try fm.moveItem(at: previous, to: world)
                try Data(contentsOf: recovery.appendingPathComponent("enshrouded_server.json")).write(to: serverConfig, options: .atomic)
                throw error
            }
            try? fm.removeItem(at: previous)
        }
    }
}

extension Engine {
    public func importWorld(primaryFile: URL) throws {
        try withOperationLock {
            try requireStoppedWorld()
            let stem = primaryFile.lastPathComponent
            guard stem.range(of: #"^[0-9a-fA-F]{8}$"#, options: .regularExpression) != nil else { throw EngineError("Choose the main Enshrouded world file: an eight-character hexadecimal filename, without a suffix") }
            let fm = FileManager.default
            let source = primaryFile.deletingLastPathComponent()
            let entries = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            let selected = entries.filter { $0.lastPathComponent.range(of: "^" + stem + #"(?:-\d+|-index|_info)?$"#, options: .regularExpression) != nil }
            guard selected.contains(where: { $0.lastPathComponent == stem }), (try primaryFile.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 > 0 else { throw EngineError("The selected world file is empty or missing") }
            for item in selected {
                let values = try item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw EngineError("World imports cannot contain symbolic links") }
            }
            let stage = data.appendingPathComponent("server/.import-\(UUID().uuidString)")
            try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? fm.removeItem(at: stage) }
            for item in selected {
                let name = "3ad85aea" + item.lastPathComponent.dropFirst(stem.count)
                try fm.copyItem(at: item, to: stage.appendingPathComponent(name))
            }
            let previous = data.appendingPathComponent("server/.before-import-\(UUID().uuidString)")
            let hadWorld = fm.fileExists(atPath: world.path)
            if hadWorld { _ = try copyBackup(name: "Before world import"); try fm.moveItem(at: world, to: previous) }
            do { try fm.moveItem(at: stage, to: world) }
            catch { if hadWorld { try fm.moveItem(at: previous, to: world) }; throw error }
            if hadWorld { try? fm.removeItem(at: previous) }
        }
    }
}

/// Hold the engine operation lock across stopping, copying, and resuming.
public enum BackupWorkflow {
    public static func run(initialState: String, empty: () throws -> Bool,
                           execute: (String) throws -> Void, backup: () throws -> Void) throws {
        guard ["RUNNING", "INSTALLED", "VM_STOPPED"].contains(initialState) else { throw EngineError("Install the server before backing it up") }
        let running = initialState == "RUNNING"
        if running {
            guard try empty() else { throw EngineError("Scheduled backup waits until the server is empty") }
            try execute("stop")
        }
        do { try backup() }
        catch {
            let backupError = error
            if running {
                do { try execute("start") }
                catch { throw EngineError("Backup failed: \(backupError.localizedDescription). Restart also failed: \(error.localizedDescription)") }
            }
            throw backupError
        }
        if running { try execute("start") }
    }
}
