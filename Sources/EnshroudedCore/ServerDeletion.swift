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

public struct ServerDeletionResult {
    public let remaining: [ServerProfile]
    public let savedData: URL?
    public let cleanupWarning: String?
}

extension Engine {
    public func deleteServer(store: ProfileStore, deleteGameData: Bool = false) throws -> ServerDeletionResult {
        try deleteServer(store: store, deleteGameData: deleteGameData, saveProfiles: store.save)
    }
    func deleteServer(store: ProfileStore, deleteGameData: Bool = false,
                      saveProfiles: ([ServerProfile]) throws -> Void,
                      removeInstallation: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) throws -> ServerDeletionResult {
        try withOperationLock {
            let fm = FileManager.default
            var profiles = try store.load()
            guard let profile = profiles.first(where: { $0.home == home.path }),
                  home.pathComponents.count > 2,
                  try home.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw EngineError("Server profile or folder is invalid")
            }
            let root = home.standardizedFileURL.resolvingSymlinksInPath().path
            let userHome = fm.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath().path
            guard root != userHome, root != userHome + "/Library",
                  !resources.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root + "/") else {
                throw EngineError("This folder is not safe to remove as a server installation")
            }
            let management = store.registry.deletingLastPathComponent()
            let archive = management.appendingPathComponent("deleted-server-data/" + UUID().uuidString)
            let staged = management.appendingPathComponent("pending-server-deletion/" + UUID().uuidString)
            for destination in [archive, staged] {
                guard !destination.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root + "/") else {
                    throw EngineError("Server deletion storage must be outside the server folder")
                }
            }
            let paths = ["profile.json", "initial-settings.json", "automation.json",
                         "data/server/enshrouded_server.json", "data/server/savegame", "data/server/logs",
                         "data/server/config", "data/logs", "data/backups",
                         "data/previous-install/savegame", "data/previous-install/enshrouded_server.json",
                         "data/previous-install/logs", "data/previous-install/config"]
            for path in paths {
                let url = home.appendingPathComponent(path)
                guard url.resolvingSymlinksInPath().standardizedFileURL.path == url.standardizedFileURL.path,
                      url.standardizedFileURL.path.hasPrefix(root + "/") else {
                    throw EngineError("Cannot delete through a linked server folder")
                }
            }
            try performLocked("shutdown", output: { _ in })
            guard ["VM_STOPPED", "NOT_INSTALLED"].contains(try status()) else { throw EngineError("The server has not stopped") }
            try fm.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var moved: [String] = []
            var stagedHome = false
            do {
                if !deleteGameData {
                    try fm.createDirectory(at: archive, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    for path in paths where fm.fileExists(atPath: home.appendingPathComponent(path).path) {
                        let destination = archive.appendingPathComponent(path)
                        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try fm.moveItem(at: home.appendingPathComponent(path), to: destination)
                        moved.append(path)
                    }
                    if !fm.fileExists(atPath: archive.appendingPathComponent("profile.json").path) {
                        try JSONEncoder().encode(profile).write(to: archive.appendingPathComponent("profile.json"))
                    }
                }
                try fm.moveItem(at: home, to: staged); stagedHome = true
                profiles.removeAll { $0.id == profile.id }
                try saveProfiles(profiles)
            } catch {
                let original = error
                do {
                    if stagedHome { try fm.moveItem(at: staged, to: home) }
                    for path in moved.reversed() {
                        try fm.moveItem(at: archive.appendingPathComponent(path), to: home.appendingPathComponent(path))
                    }
                    if !deleteGameData { try? fm.removeItem(at: archive) }
                } catch {
                    throw EngineError("Deletion could not finish. Files are preserved at \(staged.path) and \(archive.path).")
                }
                throw original
            }
            var warning: String?
            do { try removeInstallation(staged) }
            catch { warning = "Server removed, but some files could not be deleted at \(staged.path): \(error.localizedDescription)" }
            return ServerDeletionResult(remaining: profiles, savedData: deleteGameData ? nil : archive, cleanupWarning: warning)
        }
    }
}
