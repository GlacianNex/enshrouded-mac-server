import Foundation

extension Engine {
    /// Removes only this server's disposable installation. Saved data stays in place.
    public func uninstallServerFiles(output: @escaping (String) -> Void) throws {
        try withOperationLock {
            let files = FileManager.default
            let protectedRoot = home.standardizedFileURL.resolvingSymlinksInPath().path
            guard home.pathComponents.count > 2 else { throw EngineError("Invalid server folder") }
            // Never follow a linked runtime or data folder into another server.
            for relative in ["lima", "runtime", "cache", "data", "data/server", "data/previous-install"] {
                let url = home.appendingPathComponent(relative)
                let resolved = url.standardizedFileURL.resolvingSymlinksInPath().path
                guard resolved.hasPrefix(protectedRoot + "/"),
                      (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
                    throw EngineError("Cannot uninstall through a linked server folder: \(relative)")
                }
            }
            output("Saving and stopping this server…\n")
            try performLocked("shutdown", output: output)
            guard ["VM_STOPPED", "NOT_INSTALLED"].contains(try status()) else {
                throw EngineError("The environment is still running. No server files were removed.")
            }
            let server = data.appendingPathComponent("server")
            // Capture a recovery copy before removing any binaries. Backups are never deleted.
            if files.fileExists(atPath: server.appendingPathComponent("savegame").path) {
                output("Backing up saved world and settings…\n")
                _ = try copyBackup(name: "Before Uninstall")
            }
            if files.fileExists(atPath: home.appendingPathComponent("lima/engine/lima.yaml").path) {
                output("Removing the VM, Wine, Box64 and tools inside it…\n")
                // No --force: a running VM must not be killed to make deletion succeed.
                try command(["delete", "--tty=false", "engine"], output: output)
                guard !files.fileExists(atPath: home.appendingPathComponent("lima/engine/lima.yaml").path) else {
                    throw EngineError("The VM could not be removed. Saved data is unchanged.")
                }
            }
            output("Removing downloaded server files and caches…\n")
            if files.fileExists(atPath: server.path) {
                for entry in try files.contentsOfDirectory(at: server, includingPropertiesForKeys: nil) {
                    guard !["savegame", "enshrouded_server.json", "logs"].contains(entry.lastPathComponent) else { continue }
                    try files.removeItem(at: entry)
                }
            }
            // A retained previous installation also contains world data: keep its
            // saves/configuration, and remove only its disposable binaries.
            let previous = data.appendingPathComponent("previous-install")
            if files.fileExists(atPath: previous.path) {
                for entry in try files.contentsOfDirectory(at: previous, includingPropertiesForKeys: nil) {
                    if !["savegame", "enshrouded_server.json", "logs"].contains(entry.lastPathComponent) { try files.removeItem(at: entry) }
                }
            }
            for relative in ["runtime", "cache", "data/installed-manifest.txt", "internet-forward-v1", "resume-after-manager-update", "engine.yaml"] {
                let path = home.appendingPathComponent(relative)
                if files.fileExists(atPath: path.path) { try files.removeItem(at: path) }
            }
            output("Server files uninstalled. Worlds, settings and backups are kept. Choose Set Up Server to reinstall.\n")
        }
    }
}
