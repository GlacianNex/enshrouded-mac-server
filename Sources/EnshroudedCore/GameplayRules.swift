import Foundation

public struct GameplayRule: Decodable, Identifiable {
    public let key: String
    public let label: String
    public let kind: String
    public let defaultValue: String
    public let minimum: Double?
    public let maximum: Double?
    public let choices: [String]
    public let minutes: Bool
    public let category: String?
    public let explanation: String?
    public var id: String { key }
    enum CodingKeys: String, CodingKey { case key, label, kind, minimum, maximum, choices, minutes, category, explanation; case defaultValue = "default" }
    public func parse(_ text: String) throws -> Any {
        if kind == "bool" {
            guard text == "true" || text == "false" else { throw EngineError("Invalid value for \(label)") }
            return text == "true"
        }
        if kind == "choice" {
            guard choices.contains(text) else { throw EngineError("Choose a supported value for \(label)") }; return text
        }
        guard let number = Double(text), number.isFinite, minimum.map({ number >= $0 }) ?? true, maximum.map({ number <= $0 }) ?? true else { throw EngineError("\(label) must be between \(minimum ?? 0) and \(maximum ?? 0)") }
        return minutes ? number * 60_000_000_000 : number
    }
    public func display(_ value: Any?) -> String {
        if let number = value as? NSNumber { return minutes ? String(number.doubleValue / 60_000_000_000) : kind == "bool" ? (number.boolValue ? "true" : "false") : number.stringValue }
        if let string = value as? String { return string }
        if minutes, let raw = Double(defaultValue) { return String(raw / 60_000_000_000) }
        return defaultValue
    }
}
extension Engine {
    public func gameplayRules() throws -> [GameplayRule] {
        try JSONDecoder().decode([GameplayRule].self, from: Data(contentsOf: resources.appendingPathComponent("game-rules.json")))
    }
    public func gameplayValues() throws -> [String: Any] { try readConfiguration()["gameSettings"] as? [String: Any] ?? [:] }
    public func saveGameplay(_ values: [String: String]) throws {
        try withOperationLock {
            guard ["INSTALLED", "VM_STOPPED"].contains(try status()) else { throw EngineError("Stop the server before changing world rules") }
            var config = try readConfiguration(), existing = config["gameSettings"] as? [String: Any] ?? [:]
            for rule in try gameplayRules() { if let value = values[rule.key] { existing[rule.key] = try rule.parse(value) } }
            config["gameSettings"] = existing; config["gameSettingsPreset"] = "Custom"
            try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]).write(to: serverConfig, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: serverConfig.path)
        }
    }
}
