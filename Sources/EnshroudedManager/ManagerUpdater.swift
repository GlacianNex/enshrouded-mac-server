import Foundation
import EnshroudedCore

/// Discovery and validation only. FleetModel owns installation and server recovery.
enum ManagerUpdater {
    static var downloadCache: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EnshroudedServerManagerUpdates")
    }
    static let endpoint = URL(string: "https://api.github.com/repos/GlacianNex/enshrouded-mac-server/releases/latest")!
    static func latest() async throws -> ManagerRelease {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Enshrouded-Server-Manager-for-Mac", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw EngineError("Could not check for manager updates. Try again later.")
        }
        let release = try JSONDecoder().decode(ManagerRelease.self, from: data)
        _ = try release.downloadAsset()
        return release
    }
    static func download(_ release: ManagerRelease, progress: @escaping (ManagerInstallStage) -> Void = { _ in }) async throws -> URL {
        progress(.downloading)
        let asset = try release.downloadAsset()
        var request = URLRequest(url: asset.browser_download_url)
        request.timeoutInterval = 120
        let (temporary, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize == asset.size else {
            throw EngineError("The manager download is incomplete. Try again.")
        }
        progress(.checking)
        return try await Task.detached {
            try release.verifyDownload(Data(contentsOf: temporary, options: .mappedIfSafe))
            let files = FileManager.default
            let root = downloadCache.appendingPathComponent(UUID().uuidString)
            try files.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            do {
                let listing = try command("/usr/bin/unzip", ["-Z1", temporary.path])
                let paths = listing.split(separator: "\n").map(String.init)
                let details = try command("/usr/bin/unzip", ["-Z", "-l", temporary.path])
                var entries: [ManagerArchiveEntry] = []
                for line in details.split(separator: "\n") {
                    guard let first = line.first, "-dl".contains(first) else { continue }
                    let fields = line.split(maxSplits: 9, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
                    guard fields.count == 10, let size = Int(fields[3]) else { throw EngineError("Could not inspect the update archive.") }
                    let path = String(fields[9])
                    let kind: ManagerArchiveEntry.Kind = first == "l" ? .symbolicLink : first == "d" ? .directory : .file
                    // Unzip treats arguments as patterns; reject metacharacters before requesting link contents.
                    guard !path.contains(where: { "*?[]".contains($0) }) else { throw EngineError("The update archive has an unsupported path.") }
                    let target = kind == .symbolicLink ? try command("/usr/bin/unzip", ["-p", temporary.path, path], limit: 4096) : nil
                    entries.append(.init(path: path, kind: kind, size: size, linkTarget: target))
                }
                guard entries.map(\.path) == paths else { throw EngineError("The update archive has an unsupported layout.") }
                try ManagerArchive.validate(entries)
                _ = try command("/usr/bin/ditto", ["-x", "-k", temporary.path, root.path])
                let app = root.appendingPathComponent(ManagerArchive.root)
                let build = try BuildInfo.read(app: app)
                guard build.version == release.version, !build.experimental else {
                    throw EngineError("The app version does not match the stable release.")
                }
                let requirement = "anchor apple generic and identifier \"com.glaciannex.enshrouded-manager\" and certificate leaf[subject.OU] = \"AB6C5XALCV\""
                _ = try command("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", "=" + requirement, app.path])
                _ = try command("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
                return app
            } catch {
                try? files.removeItem(at: root)
                throw error
            }
        }.value
    }
    private static func command(_ executable: String, _ arguments: [String], limit: Int = 8_000_000) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        var data = Data()
        while true {
            let part = pipe.fileHandleForReading.availableData
            if part.isEmpty { break }
            guard data.count <= limit - part.count else {
                process.terminate(); process.waitUntilExit()
                throw EngineError("The update archive is too large to inspect.")
            }
            data.append(part)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            throw EngineError("The manager update failed validation. Download it again.")
        }
        return text
    }
}
