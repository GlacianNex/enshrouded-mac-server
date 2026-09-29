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
        // The receipt is written only after a successful install. Existing installs
        // with exactly one depot manifest can be recognized without guessing newest.
        if let receipt = try? String(contentsOf: data.appendingPathComponent("installed-manifest.txt")) { return receipt.trimmingCharacters(in: .whitespacesAndNewlines) }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: data.appendingPathComponent("server/.DepotDownloader").path)) ?? []
        let manifests = names.filter { $0.hasPrefix("2278521_") && $0.hasSuffix(".manifest") }
        guard manifests.count == 1 else { return nil }
        return String(manifests[0].dropFirst(8).dropLast(9))
    }
    public func checkServerRelease() throws -> ServerRelease {
        try withOperationLock(name: "version-check.lock") {
            let current = try status()
            guard current != "NOT_INSTALLED" else { throw EngineError("Install the server before checking Valve for updates") }
            if current == "VM_STOPPED" {
                return try withOperationLock {
                    let booted = try status() == "VM_STOPPED"
                    if booted { try command(["start", "--tty=false", "engine"], output: {_ in}) }
                    defer { if booted { try? command(["stop", "engine"], output: {_ in}) } }
                    return try fetchServerRelease()
                }
            }
            return try fetchServerRelease()
        }
    }
    private func fetchServerRelease() throws -> ServerRelease {
            let script = "mkdir -p /opt/esm/version-check; exec timeout 90 /opt/esm/downloader/DepotDownloader -app 2278520 -depot 2278521 -os windows -osarch 64 -manifest-only -dir /opt/esm/version-check"
            let output = try command(["shell", "engine", "bash", "-lc", script], timeout: 120, output: {_ in})
            guard let latest = ServerRelease.manifest(in: output) else { throw EngineError("Valve did not return a server manifest. Existing files are unaffected.") }
            return ServerRelease(installed: installedManifest, latest: latest)
    }
}
