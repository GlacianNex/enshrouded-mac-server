import Foundation
import CryptoKit

public struct ManagerRelease: Decodable {
    public let tag_name: String
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]
    public struct Asset: Decodable {
        public let name: String
        public let browser_download_url: URL
        public let digest: String?
        public let size: Int
    }
    public var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
    public static func validVersion(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil
    }
    public func isNewer(than current: String) -> Bool {
        !draft && !prerelease && Self.validVersion(version) && Self.validVersion(current)
            && version.compare(current, options: .numeric) == .orderedDescending
    }
    public func downloadAsset() throws -> Asset {
        guard !draft, !prerelease, Self.validVersion(version),
              let asset = assets.first(where: { $0.name == "Enshrouded-Server-Manager-for-Mac.zip" }),
              asset.size > 0, asset.size <= 256_000_000,
              asset.browser_download_url.scheme == "https",
              asset.browser_download_url.host == "github.com",
              asset.browser_download_url.user == nil, asset.browser_download_url.password == nil,
              asset.browser_download_url.port == nil,
              asset.browser_download_url.query == nil, asset.browser_download_url.fragment == nil,
              asset.browser_download_url.path == "/GlacianNex/enshrouded-mac-server/releases/download/\(tag_name)/\(asset.name)",
              let digest = asset.digest,
              digest.range(of: #"^sha256:[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
            throw EngineError("This release has no supported, verifiable Mac download. Please check the GitHub releases page.")
        }
        return asset
    }
    public func verifyDownload(_ data: Data) throws {
        let asset = try downloadAsset()
        let digest = "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == asset.size, digest == asset.digest else {
            throw EngineError("The downloaded update did not match its published checksum. Please retry.")
        }
    }
}

public struct ManagerArchiveEntry {
    public enum Kind { case file, directory, symbolicLink }
    public let path: String
    public let kind: Kind
    public let size: Int
    public let linkTarget: String?
    public init(path: String, kind: Kind, size: Int = 0, linkTarget: String? = nil) {
        self.path = path; self.kind = kind; self.size = size; self.linkTarget = linkTarget
    }
}

public enum ManagerArchive {
    public static let root = "Enshrouded Server Manager.app"
    public static func validate(_ entries: [ManagerArchiveEntry]) throws {
        func invalid() -> EngineError { EngineError("The update archive has an unsupported layout.") }
        guard !entries.isEmpty, entries.count <= 10_000 else { throw invalid() }
        var paths: [String: ManagerArchiveEntry] = [:]
        var expanded = 0
        func key(_ path: String) -> String { path.precomposedStringWithCanonicalMapping.lowercased() }
        for entry in entries {
            let components = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            guard !entry.path.contains("\\"), !entry.path.contains(where: { $0.isNewline || $0.asciiValue == 0 }),
                  components.first == Substring(root),
                  !components.contains(".."), !components.contains("."),
                  !components.dropLast().contains(""),
                  !(components.last == "" && entry.kind != .directory),
                  entry.size >= 0, entry.size <= 1_000_000_000 - expanded else { throw invalid() }
            expanded += entry.size
            let path = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
            guard paths.updateValue(entry, forKey: key(path)) == nil else { throw invalid() }
        }
        let links = Set(paths.filter { $0.value.kind == .symbolicLink }.keys)
        for (path, entry) in paths {
            let ancestors = path.split(separator: "/").dropLast()
            var prefix = ""
            for component in ancestors {
                prefix += (prefix.isEmpty ? "" : "/") + component
                if let ancestor = paths[prefix], ancestor.kind != .directory { throw invalid() }
            }
            guard entry.kind == .symbolicLink else { continue }
            guard let target = entry.linkTarget, !target.isEmpty, !target.hasPrefix("/"), !target.contains("\\"),
                  !target.contains(where: { $0.isNewline || $0.asciiValue == 0 }) else { throw invalid() }
            var resolved = entry.path.split(separator: "/").dropLast().map(String.init)
            for component in target.split(separator: "/") {
                if component == "." { continue }
                if component == ".." {
                    guard resolved.count > 1 else { throw invalid() }
                    resolved.removeLast()
                } else { resolved.append(String(component)) }
                // Do not allow link chains or traversing another link before '..'.
                if links.contains(key(resolved.joined(separator: "/"))) { throw invalid() }
            }
            let destination = key(resolved.joined(separator: "/"))
            guard destination != path,
                  paths[destination] != nil || paths.keys.contains(where: { $0.hasPrefix(destination + "/") }) else { throw invalid() }
        }
        guard paths[key(root + "/Contents/Info.plist")]?.kind == .file,
              paths[key(root + "/Contents/MacOS/EnshroudedManager")]?.kind == .file else { throw invalid() }
    }
}
