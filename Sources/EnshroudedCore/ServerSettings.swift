import Foundation

public struct ServerSettings {
    public var name = "Enshrouded Server"
    public var password = ""
    public var adminPassword = ""
    public var slots = 4
    public var preset = "Default"
    public var voice = false
    public var textChat = false
    public var voiceMode = "Proximity"
    public static let presets = ["Default", "Relaxed", "Hard", "Survival", "Custom"]
    public init() {}
    public init(config: [String: Any]) {
        name = config["name"] as? String ?? name
        slots = config["slotCount"] as? Int ?? slots
        preset = config["gameSettingsPreset"] as? String ?? preset
        voice = config["enableVoiceChat"] as? Bool ?? voice
        textChat = config["enableTextChat"] as? Bool ?? textChat
        voiceMode = config["voiceChatMode"] as? String ?? voiceMode
        for group in config["userGroups"] as? [[String: Any]] ?? [] {
            if group["name"] as? String == "Friend" { password = group["password"] as? String ?? "" }
            if group["name"] as? String == "Admin" { adminPassword = group["password"] as? String ?? "" }
        }
    }
    public func applying(to original: [String: Any]) throws -> [String: Any] {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              password.count >= 8, adminPassword.count >= 8, password != adminPassword,
              (1...16).contains(slots), Self.presets.contains(preset), ["Proximity", "Global"].contains(voiceMode)
        else { throw EngineError("Enter a name, 1–16 slots, and different player/admin passwords of at least 8 characters.") }
        var result = original
        result["name"] = name; result["slotCount"] = slots; result["gameSettingsPreset"] = preset
        result["enableVoiceChat"] = voice; result["enableTextChat"] = textChat; result["voiceChatMode"] = voiceMode
        // Preserve custom roles, new game fields, bans, tags, and existing role permissions.
        var groups = original["userGroups"] as? [[String: Any]] ?? []
        for (role, secret) in [("Admin", adminPassword), ("Friend", password)] {
            if let index = groups.firstIndex(where: { $0["name"] as? String == role }) {
                groups[index]["password"] = secret
            } else {
                groups.append(["name": role, "password": secret, "canKickBan": role == "Admin", "canAccessInventories": true, "canEditWorld": true, "canEditBase": true, "canExtendBase": true, "reservedSlots": 0])
            }
        }
        let secrets = groups.compactMap { $0["password"] as? String }
        guard Set(secrets).count == secrets.count else {
            throw EngineError("Use a different password for every role, including custom roles.")
        }
        result["userGroups"] = groups
        return result
    }
}

extension Engine {
    public func readSettings() throws -> ServerSettings {
        ServerSettings(config: try readConfiguration())
    }
    func readConfiguration() throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: Data(contentsOf: serverConfig)) as? [String: Any] else { throw EngineError("Invalid server configuration") }
        return value
    }
    public func saveSettings(_ settings: ServerSettings, worldRules: [String: String] = [:], expectedConfiguration: Data? = nil) throws {
        try withOperationLock {
            guard ["INSTALLED", "VM_STOPPED"].contains(try status()) else { throw EngineError("Stop the server before changing settings") }
            let configuration = try Data(contentsOf: serverConfig)
            if let expectedConfiguration, configuration != expectedConfiguration {
                throw EngineError("Settings changed since this window opened. Close and reopen Server Settings.")
            }
            guard let current = try JSONSerialization.jsonObject(with: configuration) as? [String: Any] else { throw EngineError("Invalid server configuration") }
            var value = try settings.applying(to: current)
            if !worldRules.isEmpty {
                guard settings.preset == "Custom" else { throw EngineError("Select Custom difficulty to change individual world rules.") }
                var existing = value["gameSettings"] as? [String: Any] ?? [:]
                let rules = try gameplayRules()
                guard Set(worldRules.keys).isSubset(of: Set(rules.map(\.key))) else { throw EngineError("Unknown world rule") }
                for rule in rules {
                    if let text = worldRules[rule.key] { existing[rule.key] = try rule.parse(text) }
                }
                value["gameSettings"] = existing
            }
            let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: serverConfig, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: serverConfig.path)
        }
    }
}
