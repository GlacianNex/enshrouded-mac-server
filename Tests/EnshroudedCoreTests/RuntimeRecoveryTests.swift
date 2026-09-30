import XCTest
@testable import EnshroudedCore

final class RuntimeRecoveryTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for path in ["runtime", "data/server", "data/logs", "tools/wine/bin", "bin"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var script = try String(contentsOf: repository.appendingPathComponent("Runtime/guest.sh"))
        script = script.replacingOccurrences(of: "ROOT=/opt/esm", with: "ROOT='\(root.path)/tools'")
            .replacingOccurrences(of: "DATA=/mnt/esm-data", with: "DATA='\(root.path)/data'")
        try executable(script, at: root.appendingPathComponent("runtime/guest.sh"))
        try executable("#!/bin/sh\nexit 0\n", at: root.appendingPathComponent("bin/flock"))
        try executable("#!/bin/sh\nexec \"$@\"\n", at: root.appendingPathComponent("bin/sudo"))
        try executable("#!/bin/sh\nif [ \"$1\" = is-active ]; then exit 3; fi\nif [ \"$1\" = show ]; then echo auto-restart; fi\n", at: root.appendingPathComponent("bin/systemctl"))
        try Data().write(to: root.appendingPathComponent("data/server/enshrouded_server.exe"))
        return root
    }
    private func executable(_ text: String, at file: URL) throws {
        try text.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
    }
    private func run(_ action: String, in root: URL) throws -> (Int32, String) {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent("runtime/guest.sh").path, action]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = root.appendingPathComponent("bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env; process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let result = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); return (process.terminationStatus, String(decoding: result, as: UTF8.self))
    }
    func testUnexpectedCleanAndFailureExitsRequestRecovery() throws {
        let root = try fixture()
        for code in [0, 17] {
            try executable("#!/bin/sh\nexit \(code)\n", at: root.appendingPathComponent("bin/xvfb-run"))
            let result = try run("run", in: root)
            XCTAssertEqual(result.0, 1)
            XCTAssertTrue(result.1.contains("exited unexpectedly (code \(code))"))
        }
    }
    func testStopReceiptPreventsPendingRecoveryFromLaunchingGame() throws {
        let root = try fixture(), launched = root.appendingPathComponent("launched")
        try executable("#!/bin/sh\ntouch '\(launched.path)'\n", at: root.appendingPathComponent("bin/xvfb-run"))
        let stopped = try run("stop", in: root)
        XCTAssertEqual(stopped.0, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("data/server-stop-request").path))
        XCTAssertEqual(try run("run", in: root).0, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: launched.path))
        XCTAssertEqual(try run("status", in: root).1.trimmingCharacters(in: .whitespacesAndNewlines), "INSTALLED")
    }
    func testGracefulExitAfterStopDoesNotRequestRecovery() throws {
        let root = try fixture()
        try executable("#!/bin/sh\ntouch '\(root.path)/data/server-stop-request'\nexit 130\n", at: root.appendingPathComponent("bin/xvfb-run"))
        let result = try run("run", in: root)
        XCTAssertEqual(result.0, 0)
        XCTAssertFalse(result.1.contains("exited unexpectedly"))
    }
    func testNewUnitConfiguresThrottledRecoveryAndClearsOldStopReceipt() throws {
        let root = try fixture()
        try Data().write(to: root.appendingPathComponent("tools/ready-v1"))
        try Data().write(to: root.appendingPathComponent("data/server-stop-request"))
        try executable("#!/bin/sh\nif [ \"$1\" = is-active ]; then test -f '\(root.path)/active'; else echo inactive; fi\n", at: root.appendingPathComponent("bin/systemctl"))
        try executable("#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(root.path)/unit-arguments'\ntouch '\(root.path)/active'\necho \"'HostOnline' (up)\" > '\(root.path)/data/logs/server.log'\n", at: root.appendingPathComponent("bin/systemd-run"))
        XCTAssertEqual(try run("start", in: root).0, 0)
        let arguments = try String(contentsOf: root.appendingPathComponent("unit-arguments"))
        for expected in ["--property=Restart=on-failure", "--property=RestartSec=30", "--property=StartLimitIntervalSec=300", "--property=StartLimitBurst=5", "--property=TimeoutStopSec=infinity"] {
            XCTAssertTrue(arguments.contains(expected))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("data/server-stop-request").path))
    }
    func testRecoveryBackoffIsReportedSeparatelyFromStopped() throws {
        let root = try fixture()
        XCTAssertEqual(try run("status", in: root).1.trimmingCharacters(in: .whitespacesAndNewlines), "RECOVERING")
    }
}
