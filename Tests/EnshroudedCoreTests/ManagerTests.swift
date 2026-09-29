import XCTest
@testable import EnshroudedCore

final class ManagerTests: XCTestCase {
    func testSettingsRejectPasswordsAlreadyUsedByCustomRoles() throws {
        var settings = ServerSettings()
        settings.password = "player-secret"; settings.adminPassword = "admin-secret"
        let original: [String: Any] = ["userGroups": [["name": "Visitor", "password": "admin-secret"]]]
        XCTAssertThrowsError(try settings.applying(to: original))
        settings.adminPassword = "different-admin"
        XCTAssertNoThrow(try settings.applying(to: original))
    }
    func testSettingsPreserveRolesBansAndCustomDifficulty() throws {
        let original: [String: Any] = ["name": "World", "slotCount": 7, "gameSettings": ["health": 2], "bans": [["displayName": "blocked"]], "userGroups": [["name": "Friend", "password": "old-password", "canEditBase": false, "futurePermission": 7], ["name": "Visitor", "password": "visitor-pass"]]]
        var settings = ServerSettings(config: original)
        settings.password = "new-password"; settings.adminPassword = "admin-secret"; settings.preset = "Relaxed"
        let result = try settings.applying(to: original)
        let groups = try XCTUnwrap(result["userGroups"] as? [[String: Any]])
        XCTAssertEqual(groups[0]["canEditBase"] as? Bool, false)
        XCTAssertEqual(groups[0]["futurePermission"] as? Int, 7)
        XCTAssertEqual(groups[1]["password"] as? String, "visitor-pass")
        XCTAssertEqual((result["gameSettings"] as? [String: Int])?["health"], 2)
        XCTAssertEqual((result["bans"] as? [[String: String]])?.first?["displayName"], "blocked")
        settings.slots = 17
        XCTAssertThrowsError(try settings.applying(to: original))
    }
    func testLogsUseLatestSessionAndActualUpdateCount() {
        let log = """
        [Session] 'HostOnline' (up)!
        -------------- Session ----------------
        m#1(129): up 20, lost 3, ping 22 ms, OperatingNormally
        ---------------------------------------
        [ecss] Stats:  Upd:3,000  (20ms)  Time:60,000ms  Total:42,000ms  Max:40ms  Avg:13.4ms
        -------------- Session ----------------
        m#0(128): up 0, lost 0, ping 0 ms, EstablishingBaseline
        m#2(130): up 20, lost 0, ping 31 ms, OperatingNormally
        ---------------------------------------
        [server] Start Saving
        [server] Saved
        """
        let result = LogSnapshot.parse(log)
        XCTAssertEqual(result.updateRate, 50)
        XCTAssertEqual(result.peers.map(\.id), ["2"])
        XCTAssertEqual(result.peers.first?.ping, 31)
        XCTAssertEqual(LogSnapshot.parse(log + "\n-------------- Session ----------------\nm#3(131): lost 0, ping 99 ms, OperatingNormally").peers.first?.id, "2")
        XCTAssertTrue(result.lastSaveCompleted)
        XCTAssertTrue(LogSnapshot.parse(log).online)
        XCTAssertFalse(LogSnapshot.parse(log + "\n[Session] 'HostOnline' (down)!").online)
        XCTAssertTrue(LogSnapshot.parse(log + "\n[Session] 'HostOnline' (down)!").peers.isEmpty)
    }
    func fixture() throws -> Engine {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let engine = Engine(home: root, resources: root)
        for path in ["Lima/bin", "lima/engine", "data/server/savegame", "Runtime"] { try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true) }
        for name in ["guest.sh", "stop-server.py"] { try Data("fixture".utf8).write(to: root.appendingPathComponent("Runtime/" + name)) }
        try Data().write(to: root.appendingPathComponent("lima/engine/lima.yaml"))
        try "#!/bin/sh\necho Stopped\n".write(to: engine.lima, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.lima.path)
        try Data("{\"name\":\"Original\",\"saveDirectory\":\"./savegame\"}".utf8).write(to: engine.serverConfig)
        try Data("original progress".utf8).write(to: engine.world.appendingPathComponent("3ad85aea"))
        return engine
    }
    func testBackupRestoreKeepsRecoveryAndRestoresConfig() throws {
        let engine = try fixture(); defer { try? FileManager.default.removeItem(at: engine.home) }
        let backup = try engine.createBackup(name: "Before adventure")
        try Data("later progress".utf8).write(to: engine.world.appendingPathComponent("3ad85aea"))
        try Data("{\"name\":\"Later\",\"saveDirectory\":\"./savegame\"}".utf8).write(to: engine.serverConfig)
        try engine.restoreBackup(id: backup.lastPathComponent)
        XCTAssertEqual(try String(contentsOf: engine.world.appendingPathComponent("3ad85aea")), "original progress")
        XCTAssertEqual(try engine.readSettings().name, "Original")
        let recovery = try XCTUnwrap(engine.backups().first { $0.name.hasPrefix("Before restoring") })
        XCTAssertEqual(try String(contentsOf: recovery.url.appendingPathComponent("savegame/3ad85aea")), "later progress")
        XCTAssertThrowsError(try engine.restoreBackup(id: "../../elsewhere"))
    }
    func testBackupRejectsLinksAndRunningServer() throws {
        let engine = try fixture(); defer { try? FileManager.default.removeItem(at: engine.home) }
        let link = engine.world.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: engine.serverConfig)
        XCTAssertThrowsError(try engine.createBackup(name: "linked"))
        try FileManager.default.removeItem(at: link)
        try "#!/bin/sh\nif [ \"$1\" = list ]; then echo Running; else echo RUNNING; fi\n".write(to: engine.lima, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.lima.path)
        XCTAssertThrowsError(try engine.createBackup(name: "live"))
        XCTAssertTrue(engine.backups().isEmpty)
    }
    func testInvalidRestoreLeavesCurrentWorldUntouched() throws {
        let engine = try fixture(); defer { try? FileManager.default.removeItem(at: engine.home) }
        let backup = try engine.createBackup(name: "Test")
        try Data("bad json".utf8).write(to: backup.appendingPathComponent("enshrouded_server.json"))
        XCTAssertThrowsError(try engine.restoreBackup(id: backup.lastPathComponent))
        XCTAssertEqual(try String(contentsOf: engine.world.appendingPathComponent("3ad85aea")), "original progress")
    }
}
