import Foundation

extension Engine {
    /// Keep lifecycle operations excluded until the registry and recovery move
    /// agree. A failed registry write restores the original home.
    public func moveToRecovery(store: ProfileStore) throws -> [ServerProfile] {
        try moveToRecovery(store: store, saveProfiles: store.save)
    }

    func moveToRecovery(store: ProfileStore, saveProfiles: ([ServerProfile]) throws -> Void) throws -> [ServerProfile] {
        try withOperationLock {
            let fm = FileManager.default
            func canonical(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }
            let homePath = canonical(home)
            var profiles = try store.load()
            guard let profile = profiles.first(where: { canonical(URL(fileURLWithPath: $0.home)) == homePath }) else {
                throw EngineError("Server profile is missing")
            }
            let recovery = store.registry.deletingLastPathComponent().appendingPathComponent("deleted-servers/\(UUID().uuidString)")
            let recoveryPath = canonical(recovery)
            guard !profiles.contains(where: {
                let path = canonical(URL(fileURLWithPath: $0.home))
                return recoveryPath == path || recoveryPath.hasPrefix(path + "/")
            }) else { throw EngineError("The recovery folder must be outside every server data folder") }
            guard try home.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw EngineError("A linked server folder cannot be moved to recovery")
            }
            try performLocked("shutdown", output: { _ in })
            guard ["VM_STOPPED", "NOT_INSTALLED"].contains(try status()) else {
                throw EngineError("The server environment is still running. Its files were not moved.")
            }
            try fm.createDirectory(at: recovery, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let destination = recovery.appendingPathComponent("data")
            do {
                try JSONEncoder().encode(profile).write(to: recovery.appendingPathComponent("profile.json"), options: .atomic)
                try fm.moveItem(at: home, to: destination)
            } catch {
                try? fm.removeItem(at: recovery)
                throw error
            }
            profiles.removeAll { $0.id == profile.id }
            do { try saveProfiles(profiles) }
            catch {
                let saveError = error
                do { try fm.moveItem(at: destination, to: home) }
                catch {
                    throw EngineError("The server could not be removed or restored to its original folder. Its files are preserved at \(destination.path).")
                }
                try? fm.removeItem(at: recovery)
                throw saveError
            }
            return profiles
        }
    }
}
