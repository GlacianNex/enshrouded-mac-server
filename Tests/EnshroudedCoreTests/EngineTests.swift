import XCTest
@testable import EnshroudedCore

final class EngineTests: XCTestCase {
    func testRuntimeHelpersRefreshAfterManagerUpgradeWithoutChangingWorld() throws {
        let engine = try ManagerTests().fixture()
        defer { try? FileManager.default.removeItem(at: engine.home) }
        try engine.syncRuntimeHelpers()
        let guest = engine.resources.appendingPathComponent("Runtime/guest.sh")
        try Data("new helper".utf8).write(to: guest)
        try engine.syncRuntimeHelpers()
        XCTAssertEqual(try String(contentsOf: engine.home.appendingPathComponent("runtime/guest.sh")), "new helper")
        XCTAssertEqual(try String(contentsOf: engine.world.appendingPathComponent("3ad85aea")), "original progress")
    }

    func testStartUsesInternalReadinessWithoutRequiringAHostPortListener() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = Engine(home: root, resources: root)
        for path in ["Lima/bin", "lima/engine", "data/server", "Runtime"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        for name in ["guest.sh", "stop-server.py", "download.py"] { try Data("fixture".utf8).write(to: root.appendingPathComponent("Runtime/" + name)) }
        for path in ["lima/engine/lima.yaml", "internet-forward-v1", "data/server/enshrouded_server.exe"] {
            try Data().write(to: root.appendingPathComponent(path))
        }
        try Data(#"{"name":"Ready Test"}"#.utf8).write(to: engine.serverConfig)
        var packet: [UInt8] = [255,255,255,255,73,17]
        for value in ["Ready Test", "World", "Game", "Enshrouded"] { packet += Array(value.utf8) + [0] }
        packet += [0,0,0,16]
        let encoded = Data(packet).base64EncodedString()
        let script = "#!/bin/sh\nif [ \"$3\" = python3 ]; then echo \(encoded); else echo 'Server reports online'; fi\n"
        try script.write(to: engine.lima, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.lima.path)
        var output = ""
        try engine.perform("start") { output += $0 }
        XCTAssertTrue(output.contains("Server ready: Ready Test, 0/16 players."))
    }
    func testMountPathsRemainQuotedData() throws {
        let path = "/tmp/a \"quoted\"\npath: true"
        let quoted = Engine.yamlString(path)
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: Data(quoted.utf8)), path)
        XCTAssertFalse(quoted.contains("\n"))
        XCTAssertFalse(quoted.contains("\\/"), "YAML double-quoted scalars do not support JSON slash escapes")
    }
    func testVMDoesNotExposeHostHomeOrEnableRosetta() {
        let engine = Engine(home: URL(fileURLWithPath: "/tmp/private-engine"), resources: URL(fileURLWithPath: "/tmp/resources"))
        let yaml = engine.vmConfiguration()
        XCTAssertTrue(yaml.contains("enabled: false"))
        XCTAssertTrue(yaml.contains("hostIP: 0.0.0.0"))
        XCTAssertFalse(yaml.contains("hostIP: 127.0.0.1"))
        XCTAssertTrue(yaml.contains("ignore: true"))
        XCTAssertFalse(yaml.contains("location: ~"))
        XCTAssertTrue(yaml.contains("digest: sha256:"))
    }
    func testReportedAddressUsesLatestValidSteamAddress() {
        XCTAssertEqual(ConnectionInfo.reportedPublicIP(in: "[online] Public ipv4: 203.0.113.10\n[online] Public ipv4: 198.51.100.22\n"), "198.51.100.22")
        XCTAssertNil(ConnectionInfo.reportedPublicIP(in: "[online] Public ipv4: bad:15637"))
        XCTAssertNil(ConnectionInfo.reportedPublicIP(in: "[online] Public ipv4: 999.1.1.1"))
    }
    func testUninstalledStateNeedsNoRuntimeExecution() throws {
        let engine = Engine(home: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), resources: URL(fileURLWithPath: "/missing"))
        XCTAssertEqual(try engine.status(), "NOT_INSTALLED")
        XCTAssertThrowsError(try engine.saveSettings(name: "test", password: "12345678", adminPassword: "87654321"))
    }
    func testUnknownOperationCannotCreateState() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let engine = Engine(home: home, resources: URL(fileURLWithPath: "/missing"))
        XCTAssertThrowsError(try engine.perform("delete") { _ in })
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.path))
    }
    func testSettingsPreserveUnknownKeysAndRejectRunningServer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = Engine(home: root, resources: root)
        for path in ["Lima/bin", "lima/engine", "data/server"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        try Data().write(to: root.appendingPathComponent("lima/engine/lima.yaml"))
        let fake = "#!/bin/sh\nif [ \"$1\" = list ]; then echo Running; else echo INSTALLED; fi\n"
        try fake.write(to: engine.lima, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.lima.path)
        try Data("{\"futureSetting\":42}".utf8).write(to: engine.serverConfig)
        try engine.saveSettings(name: "Test", password: "player-password", adminPassword: "admin-password")
        let saved = try Data(contentsOf: engine.serverConfig)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual(object["futureSetting"] as? Int, 42)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: engine.serverConfig.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try fake.replacingOccurrences(of: "INSTALLED", with: "RUNNING").write(to: engine.lima, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.lima.path)
        XCTAssertThrowsError(try engine.saveSettings(name: "Other", password: "player-password", adminPassword: "admin-password"))
        XCTAssertEqual(try Data(contentsOf: engine.serverConfig), saved)
    }
}
