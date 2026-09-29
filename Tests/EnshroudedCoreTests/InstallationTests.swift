import XCTest
@testable import EnshroudedCore

final class InstallationTests: XCTestCase {
    func testApprovedInstallClearsOnlyCopiedQuarantine() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try app(at: root, name: "Downloaded", experimental: false, build: "1")
        let destination = root.appendingPathComponent("Installed.app")
        let quarantine = "0083;6bbb1234;Safari;C94F979C-7D26-48E9-A261-A86250773913"
        func xattr(_ arguments: [String]) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            return process.terminationStatus
        }
        XCTAssertEqual(try xattr(["-w", "-r", "com.apple.quarantine", quarantine, source.path]), 0)
        _ = try ManagerInstallation.replace(source, destination: destination, beforeReplace: {})
        XCTAssertEqual(try xattr(["-p", "com.apple.quarantine", source.path]), 0)
        XCTAssertNotEqual(try xattr(["-p", "com.apple.quarantine", destination.path]), 0)
        XCTAssertNotEqual(try xattr(["-p", "com.apple.quarantine", destination.appendingPathComponent("Contents/MacOS/Test").path]), 0)
        try ManagerInstallation.verify(destination)
    }
    func testManagerUpdateStopsRunningServerWithoutPlayerQuery() throws {
        for stopFails in [false, true] {
            let engine = try ManagerTests().fixture()
            defer { try? FileManager.default.removeItem(at: engine.home) }
            let old = try app(at: engine.home, name: "Installed", experimental: true, build: "1")
            let new = try app(at: engine.home, name: "Downloaded", experimental: true, build: "2")
            let script = """
            #!/bin/sh
            if [ "$1" = list ]; then echo Running
            elif [ "$5" = status ]; then echo RUNNING
            elif [ "$5" = stop ]; then touch "$LIMA_HOME/../stop-requested"; exit \(stopFails ? 9 : 0)
            else echo 'Unexpected call, including player query' >&2; exit 7
            fi
            """
            try script.write(to: engine.lima, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.lima.path)
            if stopFails {
                XCTAssertThrowsError(try ManagerInstallation.replaceManagingServers(new, destination: old, engines: [engine]))
            } else {
                _ = try ManagerInstallation.replaceManagingServers(new, destination: old, engines: [engine])
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: engine.home.appendingPathComponent("stop-requested").path))
            XCTAssertEqual(try BuildInfo.read(app: old).build, stopFails ? "1" : "2")
            XCTAssertEqual(FileManager.default.fileExists(atPath: engine.home.appendingPathComponent("resume-after-manager-update").path), !stopFails)
        }
    }
    func testDownloadedAppInstallsInsteadOfManagingRegardlessOfRunningState() {
        let installed = URL(fileURLWithPath: "/Applications/Enshrouded Server Manager.app")
        let downloaded = URL(fileURLWithPath: "/Users/example/Downloads/Enshrouded Server Manager.app")
        for running in [false, true] {
            XCTAssertEqual(ManagerLaunchPlan.decide(source: downloaded, destination: installed, destinationIsRunning: running), .install)
        }
        XCTAssertEqual(ManagerLaunchPlan.decide(source: installed, destination: installed, destinationIsRunning: true), .activateExisting)
        XCTAssertEqual(ManagerLaunchPlan.decide(source: installed, destination: installed, destinationIsRunning: false), .manage)
    }
    func testManagerRefusingQuitAbortsReplacement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try app(at: root, name: "Installed", experimental: true, build: "1")
        let new = try app(at: root, name: "Downloaded", experimental: true, build: "2")
        XCTAssertThrowsError(try ManagerInstallation.replaceManagingServers(new, destination: old, engines: []) {
            throw EngineError("Manager is busy and refused to quit")
        })
        XCTAssertEqual(try BuildInfo.read(app: old).build, "1")
    }
    func testUpgradeWaitsForQuitBeforeReplacingAndRetainsPrevious() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try app(at: root, name: "Installed", experimental: true, build: "1")
        let new = try app(at: root, name: "Downloaded", experimental: true, build: "2")
        var closed = false
        let previous = try ManagerInstallation.replaceManagingServers(new, destination: old, engines: []) {
            XCTAssertEqual(try BuildInfo.read(app: old).build, "1")
            closed = true
        }
        XCTAssertTrue(closed)
        XCTAssertEqual(try BuildInfo.read(app: old).build, "2")
        XCTAssertEqual(try BuildInfo.read(app: previous).build, "1")
    }
    func testConcurrentUpgradeCannotReplaceApp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try app(at: root, name: "Installed", experimental: true, build: "1")
        let new = try app(at: root, name: "Downloaded", experimental: true, build: "2")
        _ = try ManagerInstallation.replace(new, destination: old) {
            XCTAssertThrowsError(try ManagerInstallation.replace(new, destination: old, beforeReplace: {}))
            XCTAssertEqual(try BuildInfo.read(app: old).build, "1")
        }
        XCTAssertEqual(try BuildInfo.read(app: old).build, "2")
    }
    func app(at root: URL, name: String, experimental: Bool, build: String) throws -> URL {
        let app = root.appendingPathComponent(name + ".app")
        let macos = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: macos.appendingPathComponent("Test").path)
        let info: [String: Any] = ["CFBundleIdentifier": "com.glaciannex.enshrouded-manager", "CFBundleExecutable": "Test", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "0.2.0", "CFBundleVersion": build, "ESMReleaseChannel": experimental ? "experimental" : "stable"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); process.arguments = ["--force", "--sign", "-", app.path]
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        return app
    }
    func testReplacementRetainsPreviousAppAndRunsPreparationAfterValidation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try app(at: root, name: "Old", experimental: false, build: "1")
        let new = try app(at: root, name: "New", experimental: true, build: "2")
        var prepared = false
        let backup = try ManagerInstallation.replace(new, destination: old) { prepared = true }
        XCTAssertTrue(prepared)
        XCTAssertEqual(try BuildInfo.read(app: old).build, "2")
        XCTAssertEqual(try BuildInfo.read(app: backup).build, "1")
        try ManagerInstallation.verify(old)
    }
    func testFailedPreparationLeavesOldAppUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try app(at: root, name: "Old", experimental: false, build: "1")
        let new = try app(at: root, name: "New", experimental: true, build: "2")
        XCTAssertThrowsError(try ManagerInstallation.replace(new, destination: old) { throw EngineError("players joined") })
        XCTAssertEqual(try BuildInfo.read(app: old).build, "1")
        try ManagerInstallation.verify(old)
    }
    func testGameplayMinutesAndBounds() throws {
        let data = Data(#"{"key":"dayTimeDuration","label":"Daytime","kind":"number","default":"1800000000000","minimum":2,"maximum":60,"choices":[],"minutes":true}"#.utf8)
        let rule = try JSONDecoder().decode(GameplayRule.self, from: data)
        XCTAssertEqual(rule.display(nil), "30.0")
        XCTAssertEqual(try rule.parse("45") as? Double, 2_700_000_000_000)
        XCTAssertThrowsError(try rule.parse("90")); XCTAssertThrowsError(try rule.parse("nan"))
    }
    func testRollbackPreservesCurrentWorldInRecovery() throws {
        let engine = try ManagerTests().fixture(); defer { try? FileManager.default.removeItem(at: engine.home) }
        let previous = engine.data.appendingPathComponent("previous-install")
        try FileManager.default.createDirectory(at: previous.appendingPathComponent("savegame"), withIntermediateDirectories: true)
        try Data("exe".utf8).write(to: previous.appendingPathComponent("enshrouded_server.exe"))
        try Data("older progress".utf8).write(to: previous.appendingPathComponent("savegame/3ad85aea"))
        try Data("{\"name\":\"Older\",\"saveDirectory\":\"./savegame\"}".utf8).write(to: previous.appendingPathComponent("enshrouded_server.json"))
        try Data("123\n".utf8).write(to: previous.appendingPathComponent(".esm-manifest.txt"))
        try engine.perform("rollback", output: {_ in})
        XCTAssertEqual(try engine.readSettings().name, "Older")
        XCTAssertEqual(engine.installedManifest, "123")
        XCTAssertEqual(try String(contentsOf: engine.world.appendingPathComponent("3ad85aea")), "older progress")
        let backup = try XCTUnwrap(engine.backups().first)
        XCTAssertEqual(try String(contentsOf: backup.url.appendingPathComponent("savegame/3ad85aea")), "original progress")
    }
    func testRoleEditsPreserveUnknownFieldsAndRejectDuplicatePasswords() throws {
        let engine = try ManagerTests().fixture(); defer { try? FileManager.default.removeItem(at: engine.home) }
        var config = try engine.readConfiguration()
        config["userGroups"] = [["name":"Admin", "password":"admin-secret", "canKickBan":true, "futurePermission":7], ["name":"Friend", "password":"friend-secret", "canKickBan":false]]
        config["bans"] = [["displayName":"Banned", "accountIDHash":"opaque-id"]]
        config["futureSetting"] = 99
        try JSONSerialization.data(withJSONObject: config).write(to: engine.serverConfig)
        var roles = try engine.accessRoles(); roles[1].permissions["canEditBase"] = false
        try engine.saveAccess(roles, removingBans: [0])
        let saved = try engine.readConfiguration()
        XCTAssertEqual(saved["futureSetting"] as? Int, 99)
        XCTAssertEqual((saved["userGroups"] as? [[String:Any]])?.first?["futurePermission"] as? Int, 7)
        XCTAssertEqual((saved["bans"] as? [[String:Any]])?.count, 0)
        roles[1].password = roles[0].password
        XCTAssertThrowsError(try engine.saveAccess(roles, removingBans: []))
    }

}
