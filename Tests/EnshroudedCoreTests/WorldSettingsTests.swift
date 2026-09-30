import XCTest
@testable import EnshroudedCore

final class WorldSettingsTests: XCTestCase {
    func testStaleWindowCannotOverwriteExternalSettingsOrWorldRules() throws {
        let engine = try ManagerTests().fixture()
        defer { try? FileManager.default.removeItem(at: engine.home) }
        let opened = try Data(contentsOf: engine.serverConfig)
        var draft = try engine.readSettings()
        draft.name = "Stale Draft"; draft.password = "player-secret"; draft.adminPassword = "admin-secret"; draft.preset = "Custom"
        var external = try engine.readConfiguration()
        external["name"] = "Changed Elsewhere"
        external["gameSettings"] = ["playerHealthFactor": 3, "futureRule": 77]
        let changed = try JSONSerialization.data(withJSONObject: external, options: .sortedKeys)
        try changed.write(to: engine.serverConfig)
        XCTAssertThrowsError(try engine.saveSettings(draft, worldRules: ["playerHealthFactor": "2"], expectedConfiguration: opened)) {
            XCTAssertEqual($0.localizedDescription, "Settings changed since this window opened. Close and reopen Server Settings.")
        }
        XCTAssertEqual(try Data(contentsOf: engine.serverConfig), changed)
        XCTAssertEqual(try engine.gameplayValues()["playerHealthFactor"] as? Int, 3)
        XCTAssertEqual(try engine.gameplayValues()["futureRule"] as? Int, 77)
    }
    func testUnchangedExpectedConfigurationAllowsSaveAndUsesExactBytes() throws {
        let engine = try ManagerTests().fixture()
        defer { try? FileManager.default.removeItem(at: engine.home) }
        let opened = try Data(contentsOf: engine.serverConfig)
        var draft = try engine.readSettings()
        draft.name = "New Name"; draft.password = "player-secret"; draft.adminPassword = "admin-secret"
        // Even a byte-only external edit invalidates a window's snapshot.
        let reformatted = opened + Data("\n".utf8)
        try reformatted.write(to: engine.serverConfig)
        XCTAssertThrowsError(try engine.saveSettings(draft, expectedConfiguration: opened))
        XCTAssertEqual(try Data(contentsOf: engine.serverConfig), reformatted)
        try engine.saveSettings(draft, expectedConfiguration: reformatted)
        XCTAssertEqual(try engine.readSettings().name, "New Name")
    }
    func testCombinedSettingsSaveIsAtomicAndPreservesUnknownRules() throws {
        let engine = try ManagerTests().fixture()
        defer { try? FileManager.default.removeItem(at: engine.home) }
        let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Assets/game-rules.json")
        try FileManager.default.copyItem(at: assets, to: engine.resources.appendingPathComponent("game-rules.json"))
        var config = try engine.readConfiguration()
        config["gameSettings"] = ["futureRule": 7, "playerHealthFactor": 1]
        try JSONSerialization.data(withJSONObject: config).write(to: engine.serverConfig)
        var settings = ServerSettings(config: config)
        settings.password = "player-secret"; settings.adminPassword = "admin-secret"; settings.preset = "Custom"
        try engine.saveSettings(settings, worldRules: ["playerHealthFactor": "2", "dayTimeDuration": "45"])
        let saved = try Data(contentsOf: engine.serverConfig)
        let values = try engine.gameplayValues()
        XCTAssertEqual(values["futureRule"] as? Int, 7)
        XCTAssertEqual(values["playerHealthFactor"] as? Double, 2)
        XCTAssertEqual(values["dayTimeDuration"] as? Double, 2_700_000_000_000)
        settings.name = "Must not persist"
        XCTAssertThrowsError(try engine.saveSettings(settings, worldRules: ["playerHealthFactor": "99"]))
        XCTAssertEqual(try Data(contentsOf: engine.serverConfig), saved)
        settings.preset = "Hard"
        XCTAssertThrowsError(try engine.saveSettings(settings, worldRules: ["playerHealthFactor": "2"]))
        XCTAssertEqual(try Data(contentsOf: engine.serverConfig), saved)
        try engine.saveSettings(settings)
        XCTAssertEqual(try engine.readSettings().preset, "Hard")
        XCTAssertEqual(try engine.gameplayValues()["playerHealthFactor"] as? Double, 2)
        let rules = try engine.gameplayRules()
        XCTAssertEqual(rules.count, 37)
        XCTAssertTrue(rules.allSatisfy { !($0.category ?? "").isEmpty && !($0.explanation ?? "").isEmpty })
    }
}
