import XCTest
@testable import EnshroudedCore

final class BackupIntegrityTests: XCTestCase {
    func testTamperingIsRejectedBeforeChangingCurrentWorldOrCreatingRecovery() throws {
        for change in ["changed", "truncated", "missing", "extra", "configuration"] {
            let engine = try ManagerTests().fixture()
            defer { try? FileManager.default.removeItem(at: engine.home) }
            let backup = try engine.createBackup(name: "Verified")
            XCTAssertTrue(try XCTUnwrap(engine.backups().first).hasIntegrityManifest)
            let saved = backup.appendingPathComponent("savegame/3ad85aea")
            switch change {
            case "changed": try Data("corrupted world".utf8).write(to: saved)
            case "truncated": try Data().write(to: saved)
            case "missing": try FileManager.default.removeItem(at: saved)
            case "extra": try Data("unexpected".utf8).write(to: backup.appendingPathComponent("savegame/extra"))
            default: try Data("{\"name\":\"Altered\",\"saveDirectory\":\"./savegame\"}".utf8).write(to: backup.appendingPathComponent("enshrouded_server.json"))
            }
            let worldBefore = try Data(contentsOf: engine.world.appendingPathComponent("3ad85aea"))
            let configBefore = try Data(contentsOf: engine.serverConfig)
            XCTAssertThrowsError(try engine.restoreBackup(id: backup.lastPathComponent), change)
            XCTAssertEqual(try Data(contentsOf: engine.world.appendingPathComponent("3ad85aea")), worldBefore, change)
            XCTAssertEqual(try Data(contentsOf: engine.serverConfig), configBefore, change)
            XCTAssertEqual(engine.backups().count, 1, change)
        }
    }

    func testLegacyBackupRemainsRestorableAndIsMarkedUnverified() throws {
        let engine = try ManagerTests().fixture()
        defer { try? FileManager.default.removeItem(at: engine.home) }
        let backup = try engine.createBackup(name: "Legacy")
        let manifestURL = backup.appendingPathComponent("manifest.json")
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        manifest.removeValue(forKey: "files")
        manifest.removeValue(forKey: "integrityVersion")
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        XCTAssertFalse(try XCTUnwrap(engine.backups().first).hasIntegrityManifest)
        try Data("later progress".utf8).write(to: engine.world.appendingPathComponent("3ad85aea"))
        try engine.restoreBackup(id: backup.lastPathComponent)
        XCTAssertEqual(try String(contentsOf: engine.world.appendingPathComponent("3ad85aea")), "original progress")
        XCTAssertTrue(try XCTUnwrap(engine.backups().first { $0.id != backup.lastPathComponent }).hasIntegrityManifest)
    }

    func testMalformedIntegrityManifestCannotDowngradeToLegacy() throws {
        let engine = try ManagerTests().fixture()
        defer { try? FileManager.default.removeItem(at: engine.home) }
        let backup = try engine.createBackup(name: "Verified")
        let manifestURL = backup.appendingPathComponent("manifest.json")
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        manifest["files"] = "invalid"
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        XCTAssertThrowsError(try engine.restoreBackup(id: backup.lastPathComponent))
        XCTAssertEqual(engine.backups().count, 1)
    }
}
