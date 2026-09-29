import Foundation

public struct ServerProfile: Codable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public let home: String
    public let port: Int
    public init(id: String, name: String, home: String, port: Int) { self.id = id; self.name = name; self.home = home; self.port = port }
}
public struct ProfileStore {
    public let registry: URL
    public init(registry: URL) { self.registry = registry }
    public func load() throws -> [ServerProfile] {
        guard FileManager.default.fileExists(atPath: registry.path) else { return [] }
        let profiles = try JSONDecoder().decode([ServerProfile].self, from: Data(contentsOf: registry))
        try validate(profiles)
        return profiles
    }
    public func save(_ profiles: [ServerProfile]) throws {
        try validate(profiles)
        try FileManager.default.createDirectory(at: registry.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(profiles).write(to: registry, options: .atomic)
    }
    private func validate(_ profiles: [ServerProfile]) throws {
        guard Set(profiles.map(\.id)).count == profiles.count,
              Set(profiles.map(\.port)).count == profiles.count,
              profiles.allSatisfy({ !$0.id.isEmpty && (1024...65535).contains($0.port) && $0.home.hasPrefix("/") && !$0.home.contains("\0") }) else {
            throw EngineError("Every server needs a unique data folder and UDP port from 1024–65535")
        }
        let homes = profiles.map { URL(fileURLWithPath: $0.home).standardizedFileURL.resolvingSymlinksInPath().path }
        guard !homes.contains("/"), Set(homes).count == homes.count else {
            throw EngineError("Each server must use its own data folder")
        }
        // Removing one profile moves its entire home. Nested homes would also
        // move another server, even when their original path strings differ.
        for (index, home) in homes.enumerated() {
            guard !homes.enumerated().contains(where: { $0.offset != index && $0.element.hasPrefix(home + "/") }) else {
                throw EngineError("Server data folders cannot contain another server's data folder")
            }
        }
    }
}
extension Engine {
    public var hostPort: UInt16 {
        guard let data = try? Data(contentsOf: home.appendingPathComponent("profile.json")), let profile = try? JSONDecoder().decode(ServerProfile.self, from: data), let port = UInt16(exactly: profile.port), port >= 1024 else { return 15637 }
        return port
    }
}
