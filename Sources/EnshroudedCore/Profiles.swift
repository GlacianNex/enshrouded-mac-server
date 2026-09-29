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
        return try JSONDecoder().decode([ServerProfile].self, from: Data(contentsOf: registry))
    }
    public func save(_ profiles: [ServerProfile]) throws {
        guard Set(profiles.map(\.id)).count == profiles.count,
              Set(profiles.map(\.home)).count == profiles.count,
              Set(profiles.map(\.port)).count == profiles.count,
              profiles.allSatisfy({ (1024...65535).contains($0.port) && $0.home.hasPrefix("/") }) else { throw EngineError("Every server needs a unique data folder and UDP port from 1024–65535") }
        try FileManager.default.createDirectory(at: registry.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(profiles).write(to: registry, options: .atomic)
    }
}
extension Engine {
    public var hostPort: UInt16 {
        guard let data = try? Data(contentsOf: home.appendingPathComponent("profile.json")), let profile = try? JSONDecoder().decode(ServerProfile.self, from: data), let port = UInt16(exactly: profile.port), port >= 1024 else { return 15637 }
        return port
    }
}
