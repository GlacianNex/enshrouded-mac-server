import Foundation
import Darwin

extension Engine {
    /// Change the host mapping only. The guest always listens on UDP 15637.
    public func changeHostPort(to port: Int, store: ProfileStore) throws {
        try changeHostPort(to: port, store: store, saveProfiles: store.save)
    }

    func changeHostPort(to port: Int, store: ProfileStore, saveProfiles: ([ServerProfile]) throws -> Void) throws {
        guard (1024...65535).contains(port) else { throw EngineError("Choose a UDP port from 1024–65535.") }
        func requireUnlinked(_ url: URL) throws {
            guard url.standardizedFileURL.path == url.resolvingSymlinksInPath().standardizedFileURL.path else {
                throw EngineError("Cannot change ports through linked server files.")
            }
        }
        let profileURL = home.appendingPathComponent("profile.json")
        let config = home.appendingPathComponent("lima/engine/lima.yaml")
        let marker = home.appendingPathComponent("internet-forward-v1")
        let registryLock = store.registry.appendingPathExtension("port-change.lock")
        for url in [home, profileURL, config, marker, store.registry, registryLock, home.appendingPathComponent("operation.lock")] { try requireUnlinked(url) }
        try withOperationLock {
            let fd = open(registryLock.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw EngineError("Cannot lock the server registry.") }
            defer { close(fd) }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw EngineError("Another server port change is running.") }
            defer { flock(fd, LOCK_UN) }
            var profiles = try store.load()
            guard let index = profiles.firstIndex(where: { URL(fileURLWithPath: $0.home).standardizedFileURL == home.standardizedFileURL }) else { throw EngineError("This server is no longer registered.") }
            let current = profiles[index]
            let fm = FileManager.default
            let hadProfile = fm.fileExists(atPath: profileURL.path)
            if hadProfile {
                let disk = try JSONDecoder().decode(ServerProfile.self, from: Data(contentsOf: profileURL))
                guard disk == current else { throw EngineError("Server information changed. Reopen Server Settings and try again.") }
            }
            guard !profiles.contains(where: { $0.id != current.id && $0.port == port }) else { throw EngineError("Another server already uses UDP \(port).") }
            let state = try status()
            guard ["INSTALLED", "VM_STOPPED"].contains(state) else { throw EngineError("Stop the server before changing its UDP port.") }
            guard current.port != port else { return }
            // Validate the proposed host port before stopping the idle environment
            // or changing any persisted settings. The old mapping is a different port.
            try HostPortAvailability.ensureAvailable(port: UInt16(port))
            let files = try [profileURL, store.registry, config, marker].compactMap { url -> (URL, Data, NSNumber?)? in
                guard fm.fileExists(atPath: url.path) else {
                    if url == marker || (url == profileURL && !hadProfile) { return nil }
                    throw EngineError("Required server settings are missing.")
                }
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { throw EngineError("Expected a regular server settings file.") }
                return (url, try Data(contentsOf: url), try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
            }
            if state == "INSTALLED" {
                // The game is already stopped; ask the guest to shut down normally.
                // SSH may disconnect before acknowledging a successful shutdown.
                _ = try? command(["shell", "engine", "sudo", "systemctl", "--no-block", "poweroff"], timeout: 10, output: { _ in })
                _ = try command(["stop", "engine"], timeout: 60, timeoutMessage: "The server environment did not stop. The UDP port is unchanged.", output: { _ in })
                guard try status() == "VM_STOPPED" else { throw EngineError("The server environment has not stopped. The UDP port is unchanged.") }
            }
            let next = ServerProfile(id: current.id, name: current.name, home: current.home, port: port)
            var createdProfile: stat?
            var createdProfileHandle: FileHandle?
            defer { try? createdProfileHandle?.close() }
            do {
                let expression = "(.portForwards[] | select(.guestPort == 15637 and .proto == \"udp\")).hostPort = \(port)"
                _ = try command(["edit", "--tty=false", "--set", expression, "engine"], timeout: 30, timeoutMessage: "Changing the UDP port timed out.", output: { _ in })
                let profileBytes = try JSONEncoder().encode(next)
                if hadProfile {
                    try profileBytes.write(to: profileURL, options: .atomic)
                } else {
                    // Default/legacy servers may exist only in the central registry.
                    // Exclusive creation must never replace an external file.
                    let profileFD = open(profileURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
                    guard profileFD >= 0 else { throw EngineError("Could not create the server profile. Reopen Server Settings and try again.") }
                    let handle = FileHandle(fileDescriptor: profileFD, closeOnDealloc: true)
                    createdProfileHandle = handle
                    var identity = stat()
                    guard fstat(profileFD, &identity) == 0 else { throw EngineError("Could not verify the new server profile.") }
                    createdProfile = identity
                    try handle.write(contentsOf: profileBytes)
                }
                profiles[index] = next
                try saveProfiles(profiles)
                if files.contains(where: { $0.0 == marker }) {
                    try Data("UDP \(port) enabled on all host IPv4 interfaces\n".utf8).write(to: marker, options: .atomic)
                }
                for (url, _, mode) in files { if let mode { try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path) } }
            } catch {
                let failure = error
                var rollbackFailed = false
                for (url, bytes, mode) in files {
                    do {
                        try requireUnlinked(url)
                        try bytes.write(to: url, options: .atomic)
                        if let mode { try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path) }
                    } catch { rollbackFailed = true }
                }
                if let createdProfile {
                    do {
                        try requireUnlinked(profileURL)
                        var currentFile = stat()
                        guard lstat(profileURL.path, &currentFile) == 0,
                              currentFile.st_ino == createdProfile.st_ino,
                              currentFile.st_dev == createdProfile.st_dev,
                              currentFile.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
                            throw EngineError("The new server profile changed during rollback.")
                        }
                        try fm.removeItem(at: profileURL)
                    } catch { rollbackFailed = true }
                }
                if rollbackFailed { throw EngineError("The port change failed and settings could not be fully restored. Keep the server stopped and check its settings.") }
                throw failure
            }
        }
    }
}
