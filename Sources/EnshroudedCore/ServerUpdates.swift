import Foundation

public struct ServerRelease: Equatable {
    public let installed: String?
    public let latest: String
    public init(installed: String?, latest: String) { self.installed = installed; self.latest = latest }
    public var updateAvailable: Bool { installed != nil && installed != latest }
    public static func manifest(in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: #"(?m)^Manifest (\d+) \("#), let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
extension Engine {
    public var installedManifest: String? {
        let config = data.appendingPathComponent("server/.DepotDownloader/depot.config")
        if FileManager.default.fileExists(atPath: config.path) {
            // The downloader marks incomplete installations invalid. Never fall
            // back to an older receipt or cached manifest in that case.
            guard let bytes = try? Data(contentsOf: config) else { return nil }
            return InstalledDepotManifest.read(bytes)
        }
        for path in ["server/.esm-manifest.txt", "installed-manifest.txt"] {
            if let receipt = try? String(contentsOf: data.appendingPathComponent(path)) {
                let value = receipt.trimmingCharacters(in: .whitespacesAndNewlines)
                if let number = UInt64(value), number > 0, number != UInt64.max { return value }
            }
        }
        // Legacy installs without a downloader record can use one unambiguous manifest.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: data.appendingPathComponent("server/.DepotDownloader").path)) ?? []
        let manifests = names.filter { $0.hasPrefix("2278521_") && $0.hasSuffix(".manifest") }
        guard manifests.count == 1 else { return nil }
        return String(manifests[0].dropFirst(8).dropLast(9))
    }
    public func checkServerRelease(progress: @escaping (String) -> Void = { _ in }) throws -> ServerRelease {
        try withOperationLock(name: "version-check.lock") {
            let current = try status()
            guard current != "NOT_INSTALLED" else { throw EngineError("Install the server before checking Valve for updates") }
            if current == "VM_STOPPED" {
                return try withOperationLock {
                    let booted = try status() == "VM_STOPPED"
                    if booted { progress("Starting the server environment"); try command(["start", "--tty=false", "engine"], timeout: 60, timeoutMessage: "The server environment did not start in time. Try the update check again.", output: {_ in}) }
                    defer { if booted { progress("Closing the server environment"); _ = try? command(["stop", "engine"], timeout: 30, output: {_ in}) } }
                    return try fetchServerRelease(progress: progress)
                }
            }
            return try fetchServerRelease(progress: progress)
        }
    }
    private func fetchServerRelease(progress: @escaping (String) -> Void) throws -> ServerRelease {
            progress("Checking Valve’s server version")
            let script = "mkdir -p /opt/esm/version-check; exec timeout 40 /opt/esm/downloader/DepotDownloader -app 2278520 -depot 2278521 -os windows -osarch 64 -manifest-only -dir /opt/esm/version-check"
            let output: String
            do {
                output = try command(["shell", "engine", "bash", "-lc", script], timeout: serverReleaseTimeout, timeoutMessage: "Valve’s update check took too long. Try again. Your server is unchanged.", output: {_ in})
            } catch {
                if error.localizedDescription.hasPrefix("Operation failed (124)") {
                    throw EngineError("Valve’s update check took too long. Try again. Your server is unchanged.")
                }
                throw error
            }
            guard let latest = ServerRelease.manifest(in: output) else { throw EngineError("Valve did not return a server manifest. Existing files are unaffected.") }
            return ServerRelease(installed: installedManifest, latest: latest)
    }
}
