import Foundation

extension ProfileStore {
    public var retainedDirectory: URL { registry.deletingLastPathComponent().appendingPathComponent("retained-installations") }
    public func retainedInstallations() throws -> [ServerProfile] {
        guard FileManager.default.fileExists(atPath: retainedDirectory.path) else { return [] }
        let active = try load()
        let retained = try FileManager.default.contentsOfDirectory(at: retainedDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(ServerProfile.self, from: Data(contentsOf: $0)) }
            .filter { retained in !active.contains { $0.home == retained.home } }
        var homes = Set<String>()
        return retained.filter { homes.insert($0.home).inserted }
    }
}

extension Engine {
    /// Remove one server's identity and saved state, retaining its reusable installation.
    /// Saved data is archived outside the installation before the registry changes.
    public func deleteServer(store: ProfileStore) throws -> [ServerProfile] {
        try deleteServer(store: store, saveProfiles: store.save)
    }
    func deleteServer(store: ProfileStore, saveProfiles: ([ServerProfile]) throws -> Void) throws -> [ServerProfile] {
        try withOperationLock {
            let fm = FileManager.default
            var profiles = try store.load()
            guard let profile = profiles.first(where: { $0.home == home.path }),
                  home.pathComponents.count > 2,
                  try home.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw EngineError("Server profile or folder is invalid")
            }
            let root = home.standardizedFileURL.resolvingSymlinksInPath().path
            let archive = store.registry.deletingLastPathComponent().appendingPathComponent("deleted-server-data/" + UUID().uuidString)
            guard !archive.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root + "/") else {
                throw EngineError("Saved-data archive must be outside the server folder")
            }
            let paths = ["profile.json", "initial-settings.json", "automation.json", "resume-after-manager-update",
                         "data/server/enshrouded_server.json", "data/server/savegame", "data/server/logs",
                         "data/server/config", "data/server/appcache", "data/logs", "data/backups", "data/previous-install"]
            for path in paths {
                let url = home.appendingPathComponent(path)
                guard url.resolvingSymlinksInPath().standardizedFileURL.path == url.standardizedFileURL.path, url.standardizedFileURL.path.hasPrefix(root + "/") else {
                    throw EngineError("Cannot delete through a linked server folder")
                }
            }
            try performLocked("shutdown", output: { _ in })
            guard ["VM_STOPPED", "NOT_INSTALLED"].contains(try status()) else { throw EngineError("The server has not stopped") }
            try fm.createDirectory(at: archive, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.createDirectory(at: store.retainedDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let receipt = store.retainedDirectory.appendingPathComponent(UUID().uuidString + ".json")
            var moved: [String] = []
            do {
                for path in paths where fm.fileExists(atPath: home.appendingPathComponent(path).path) {
                    let destination = archive.appendingPathComponent(path)
                    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: home.appendingPathComponent(path), to: destination)
                    moved.append(path)
                }
                try JSONEncoder().encode(profile).write(to: receipt, options: .atomic)
                profiles.removeAll { $0.id == profile.id }
                try saveProfiles(profiles)
            } catch {
                let original = error
                for path in moved.reversed() {
                    do { try fm.moveItem(at: archive.appendingPathComponent(path), to: home.appendingPathComponent(path)) }
                    catch { throw EngineError("Deletion failed. Saved data remains at \(archive.path).") }
                }
                try? fm.removeItem(at: receipt); try? fm.removeItem(at: archive)
                throw original
            }
            return profiles
        }
    }
}
