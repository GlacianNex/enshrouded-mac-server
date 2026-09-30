import Foundation
import Darwin

extension Engine {
    public func withSharedDownloads<T>(_ work: () throws -> T) throws -> T {
        guard let sharedDownloads else { return try work() }
        try FileManager.default.createDirectory(at: sharedDownloads, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(sharedDownloads.deletingLastPathComponent().appendingPathComponent("downloads.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw EngineError("Cannot open the shared downloads folder") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw EngineError("Another server is preparing shared downloads. Wait for it to finish.") }
        defer { flock(fd, LOCK_UN) }
        return try work()
    }

    /// Do not repopulate a deliberately cleared cache from older installations.
    public func canReuseInstallation(at home: URL) -> Bool {
        guard let sharedDownloads else { return true }
        let marker = sharedDownloads.deletingLastPathComponent().appendingPathComponent("downloads-reset")
        guard FileManager.default.fileExists(atPath: marker.path) else { return true }
        guard let data = try? Data(contentsOf: marker), let excluded = try? JSONDecoder().decode([String].self, from: data) else { return false }
        return !excluded.contains(home.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    public func clearSharedDownloads() throws {
        guard let sharedDownloads else { return }
        try withSharedDownloads {
            let fm = FileManager.default
            guard try sharedDownloads.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw EngineError("Cannot clear a linked downloads folder")
            }
            let store = ProfileStore(registry: sharedDownloads.deletingLastPathComponent().appendingPathComponent("profiles.json"))
            let oldHomes = try (store.load() + store.retainedInstallations()).map { URL(fileURLWithPath: $0.home) } + [home]
            let excluded = oldHomes.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
            try JSONEncoder().encode(excluded).write(to: sharedDownloads.deletingLastPathComponent().appendingPathComponent("downloads-reset"), options: .atomic)
            // Preserve the directory: existing VMs may have it mounted.
            for file in try fm.contentsOfDirectory(at: sharedDownloads, includingPropertiesForKeys: nil) {
                try fm.removeItem(at: file)
            }
        }
    }

    static func reusableServerFile(_ name: String) -> Bool {
        name == ".DepotDownloader" || name == "_CommonRedist" || name.hasSuffix(".dll") ||
            name == "enshrouded_server.exe" || name == "enshrouded_server.kfc" ||
            name == "enshrouded_server.kfc_resources" ||
            (name.hasPrefix("enshrouded_server_") && name.hasSuffix(".dat"))
    }

    /// Copy binaries only. Never seed another server with passwords, worlds, or bans.
    func copyReusableServerFiles(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return }
        guard try source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw EngineError("Cannot reuse a linked server folder") }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) where Self.reusableServerFile(file.lastPathComponent) {
            let kind = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            guard kind.isSymbolicLink != true else { throw EngineError("Cannot reuse linked server files") }
            if kind.isDirectory == true { try validateTree(file) }
            else if kind.isRegularFile != true { throw EngineError("Cannot reuse this server file") }
            let target = destination.appendingPathComponent(file.lastPathComponent)
            if !fm.fileExists(atPath: target.path) { try fm.copyItem(at: file, to: target) }
        }
    }

    func prepareSharedDownloads(output: @escaping (String) -> Void) throws {
        guard let sharedDownloads else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: sharedDownloads.appendingPathComponent("components"), withIntermediateDirectories: true)
        try fm.createDirectory(at: sharedDownloads.appendingPathComponent("packages/partial"), withIntermediateDirectories: true)
        let store = ProfileStore(registry: sharedDownloads.deletingLastPathComponent().appendingPathComponent("profiles.json"))
        let sources = try (store.load() + store.retainedInstallations()).filter { canReuseInstallation(at: URL(fileURLWithPath: $0.home)) }
        let image = sharedDownloads.appendingPathComponent("ubuntu.img")
        let seed = sharedDownloads.appendingPathComponent("server")
        // Import verified legacy archives without booting or stopping another VM.
        let script = (try? String(contentsOf: resources.appendingPathComponent("Runtime/guest.sh"))) ?? ""
        let pattern = #"fetch https:\S+ ([a-f0-9]{64}) "\$ROOT/cache/([^"]+)""#
        let expression = try NSRegularExpression(pattern: pattern)
        let components = expression.matches(in: script, range: NSRange(script.startIndex..., in: script)).compactMap { match -> (String, String)? in
            guard let hash = Range(match.range(at: 1), in: script), let name = Range(match.range(at: 2), in: script) else { return nil }
            return (String(script[hash]), String(script[name]))
        }
        for profile in sources {
            let source = URL(fileURLWithPath: profile.home)
            if !fm.fileExists(atPath: image.path) {
                let old = source.appendingPathComponent("cache/ubuntu.img")
                if fm.fileExists(atPath: old.path), try SetupDownload.digest(old) == Self.environmentDigest {
                    try fm.copyItem(at: old, to: image)
                }
            }
            if !fm.fileExists(atPath: seed.appendingPathComponent("enshrouded_server.exe").path), source != home {
                output(SetupEvent(.environment, "Reusing server files already on this Mac; Valve will check for updates.").line)
                try copyReusableServerFiles(from: source.appendingPathComponent("data/server"), to: seed)
            }
            let missing = components.filter { !fm.fileExists(atPath: sharedDownloads.appendingPathComponent("components/" + $0.0).path) }
            if !missing.isEmpty {
                let donor = Engine(home: source, resources: resources)
                if let state = try? donor.status(), state == "RUNNING" || state == "INSTALLED" {
                    for (hash, name) in missing {
                        let destination = sharedDownloads.appendingPathComponent("components/" + hash)
                        let temporary = sharedDownloads.appendingPathComponent("components/import-" + UUID().uuidString)
                        defer { try? fm.removeItem(at: temporary) }
                        if (try? donor.command(["copy", "--backend=scp", "engine:/opt/esm/cache/" + name, temporary.path], timeout: 60, output: { _ in })) != nil,
                           (try? SetupDownload.digest(temporary)) == hash {
                            try fm.moveItem(at: temporary, to: destination)
                        }
                    }
                }
            }
        }
        if !fm.fileExists(atPath: data.appendingPathComponent("server/enshrouded_server.exe").path) {
            try copyReusableServerFiles(from: seed, to: data.appendingPathComponent("server"))
        }
    }

    func publishSharedServerFiles() throws {
        guard let sharedDownloads else { return }
        let fm = FileManager.default
        let temporary = sharedDownloads.appendingPathComponent("server-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temporary) }
        try copyReusableServerFiles(from: data.appendingPathComponent("server"), to: temporary)
        let destination = sharedDownloads.appendingPathComponent("server")
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: temporary, to: destination)
    }
}
