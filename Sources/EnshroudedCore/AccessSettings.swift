import Foundation

public struct AccessRole: Identifiable {
    public let id = UUID()
    public var name: String
    public var password: String
    public var permissions: [String: Bool]
    public var reservedSlots: Int
    var original: [String: Any]
    public static let keys = ["canKickBan", "canAccessInventories", "canEditWorld", "canEditBase", "canExtendBase"]
    public init(_ original: [String: Any] = [:]) {
        self.original = original; name = original["name"] as? String ?? "New role"; password = original["password"] as? String ?? ""
        permissions = Dictionary(uniqueKeysWithValues: Self.keys.map { ($0, original[$0] as? Bool ?? false) })
        reservedSlots = original["reservedSlots"] as? Int ?? 0
    }
    func json() -> [String: Any] {
        var json = original; json["name"] = name; json["password"] = password; json["reservedSlots"] = reservedSlots
        for (key, value) in permissions { json[key] = value }
        return json
    }
}
public struct SavedBan: Identifiable {
    public let id: Int
    public let displayName: String
    public let characterName: String
    public init(id: Int, value: [String: Any]) { self.id = id; displayName = value["displayName"] as? String ?? "Unnamed account"; characterName = value["characterName"] as? String ?? "" }
}
extension Engine {
    public func accessRoles() throws -> [AccessRole] { (try readConfiguration()["userGroups"] as? [[String: Any]] ?? []).map(AccessRole.init) }
    public func savedBans() throws -> [SavedBan] { (try readConfiguration()["bans"] as? [[String: Any]] ?? []).enumerated().map { SavedBan(id: $0.offset, value: $0.element) } }
    public func saveAccess(_ roles: [AccessRole], removingBans: Set<Int>) throws {
        try withOperationLock {
            guard ["INSTALLED", "VM_STOPPED"].contains(try status()) else { throw EngineError("Stop the server before editing roles and bans") }
            guard !roles.isEmpty, Set(roles.map(\.name)).count == roles.count, Set(roles.map(\.password)).count == roles.count,
                  roles.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.password.count >= 8 && (0...16).contains($0.reservedSlots) }),
                  roles.contains(where: { $0.permissions["canKickBan"] == true }) else { throw EngineError("Use unique role names and different passwords of at least 8 characters, retain an admin role, and use 0–16 reserved slots") }
            var config = try readConfiguration()
            config["userGroups"] = roles.map { $0.json() }
            let bans = config["bans"] as? [[String: Any]] ?? []
            config["bans"] = bans.enumerated().filter { !removingBans.contains($0.offset) }.map(\.element)
            try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]).write(to: serverConfig, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: serverConfig.path)
        }
    }
}
