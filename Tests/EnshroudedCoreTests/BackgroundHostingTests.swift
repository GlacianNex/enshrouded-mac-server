import XCTest
import Darwin
@testable import EnshroudedCore

final class BackgroundHostingTests: XCTestCase {
    func testLoginConfigurationAndEnableNeverStartServerImmediately() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("Server With Spaces")
        let executable = URL(fileURLWithPath: "/Applications/Enshrouded Server Manager.app/Contents/MacOS/EnshroudedManager")
        let config = LoginStartup.configuration(home: home, executable: executable)
        XCTAssertEqual(config["ProgramArguments"] as? [String], [executable.path, "--start-at-login", home.path])
        XCTAssertEqual(config["RunAtLoad"] as? Bool, true)
        XCTAssertNotEqual(LoginStartup.label(home: home), LoginStartup.label(home: root.appendingPathComponent("Other")))
        let agents = root.appendingPathComponent("FakeAgents")
        var commands: [[String]] = []
        try LoginStartup.configure(home: home, enabled: true, executable: executable, directory: agents) { commands.append($0) }
        XCTAssertEqual(commands.map { $0[0] }, ["enable"])
        let plist = agents.appendingPathComponent(LoginStartup.label(home: home) + ".plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: plist.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.path))
        try LoginStartup.configure(home: home, enabled: false, executable: executable, directory: agents) { commands.append($0) }
        XCTAssertEqual(commands.map { $0[0] }, ["enable", "disable"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: plist.path))
    }

    func testFailedLoginEnableDoesNotLeaveAnAutostartJobBehind() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("Server")
        let agents = root.appendingPathComponent("FakeAgents")
        XCTAssertThrowsError(try LoginStartup.configure(home: home, enabled: true, executable: URL(fileURLWithPath: "/fake/manager"), directory: agents) { _ in
            throw EngineError("Enable failed")
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: agents.appendingPathComponent(LoginStartup.label(home: home) + ".plist").path))
    }

    func testGuardRetainsSleepProtectionThroughUnknownAndReleasesOnStop() throws {
        let engine = try ManagerTests().fixture()
        defer { try? FileManager.default.removeItem(at: engine.home) }
        let statuses: [String?] = ["RECOVERING", nil, "RUNNING", "INSTALLED", "RUNNING", "VM_STOPPED"]
        var index = 0, acquired = 0
        var released: [UInt32] = []
        HostingGuard.watch(home: engine.home, status: { statuses[index] }, enabled: { true },
            pause: {
                if index <= 2 { XCTAssertTrue(released.isEmpty, "Recovery and unknown status must retain sleep protection") }
                index += 1
            }, acquire: { acquired += 1; return UInt32(acquired) }, release: { released.append($0) })
        XCTAssertEqual(acquired, 2)
        XCTAssertEqual(released, [1, 2])
    }

    func testGuardReleasesWhenDisabledAndExitsAfterStoppedGracePeriod() throws {
        let engine = try ManagerTests().fixture()
        defer { try? FileManager.default.removeItem(at: engine.home) }
        var tick = 0
        var releases = 0
        HostingGuard.watch(home: engine.home, status: { tick < 2 ? "RUNNING" : "INSTALLED" }, enabled: { tick == 0 },
            now: { Date(timeIntervalSince1970: Double(tick * 30)) }, pause: { tick += 1 },
            acquire: { 123 }, release: { XCTAssertEqual($0, 123); releases += 1 })
        XCTAssertEqual(releases, 1)
        XCTAssertEqual(tick, 3)
    }

    func testGuardProcessSurvivesLauncherExitAndRejectsDuplicate() throws {
        let files = FileManager.default
        let engine = try ManagerTests().fixture()
        defer { try? files.removeItem(at: engine.home) }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let executable = root.appendingPathComponent(".build/debug/EnshroudedManager")
        guard files.isExecutableFile(atPath: executable.path) else { throw XCTSkip("Build the manager helper before this process test") }
        let state = engine.home.appendingPathComponent("guard-state")
        try "RUNNING".write(to: state, atomically: true, encoding: .utf8)
        let script = """
        #!/bin/sh
        state=$(cat "$LIMA_HOME/../guard-state")
        if [ "$1" = list ]; then
          if [ "$state" = VM_STOPPED ]; then echo Stopped; else echo Running; fi
        else
          printf '%s\\n' "$state"
        fi
        """
        try script.write(to: engine.lima, atomically: true, encoding: .utf8)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.lima.path)
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        launcher.arguments = ["-c", "\"$1\" --hosting-guard \"$2\" >/dev/null 2>&1 &", "guard-launcher", executable.path, engine.home.path]
        launcher.environment = ProcessInfo.processInfo.environment.merging(["ESM_HOME": engine.home.path, "ESM_RESOURCES": engine.resources.path]) { _, new in new }
        try launcher.run(); launcher.waitUntilExit()
        XCTAssertEqual(launcher.terminationStatus, 0)
        let receipt = engine.home.appendingPathComponent("hosting-guard.pid")
        try waitUntil { files.fileExists(atPath: receipt.path) }
        let pid = try XCTUnwrap(Int32(String(contentsOf: receipt)))
        let lifetime = try XCTUnwrap(ProcessLifetime(pid: pid))
        defer { if lifetime.isRunning { kill(pid, SIGTERM) } }
        XCTAssertTrue(lifetime.isRunning, "The helper must survive the launching process exiting")
        let fd = open(engine.home.appendingPathComponent("hosting-guard.lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { if fd >= 0 { close(fd) } }
        XCTAssertNotEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        let duplicate = Process()
        duplicate.executableURL = executable
        duplicate.arguments = ["--hosting-guard", engine.home.path]
        duplicate.environment = launcher.environment
        try duplicate.run()
        defer { if duplicate.isRunning { duplicate.terminate() } }
        try waitUntil { !duplicate.isRunning }
        XCTAssertEqual(duplicate.terminationStatus, 0)
        XCTAssertEqual(try String(contentsOf: receipt), String(pid))
        try "VM_STOPPED".write(to: state, atomically: true, encoding: .utf8)
        try waitUntil { !lifetime.isRunning }
        XCTAssertFalse(files.fileExists(atPath: receipt.path))
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        flock(fd, LOCK_UN)
    }

    private func waitUntil(_ condition: () throws -> Bool) throws {
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if try condition() { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTFail("Background helper did not reach its expected state")
        throw EngineError("Timed out waiting for isolated helper")
    }
}
