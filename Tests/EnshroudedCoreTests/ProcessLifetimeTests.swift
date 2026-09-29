import XCTest
@testable import EnshroudedCore

final class ProcessLifetimeTests: XCTestCase {
    func sleeper() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        return process
    }
    func testNormalQuitDetectedWithoutAppKitStateRefresh() throws {
        let process = try sleeper()
        defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
        let lifetime = try XCTUnwrap(ProcessLifetime(pid: process.processIdentifier))
        XCTAssertTrue(lifetime.isRunning)
        process.terminate()
        try ManagerQuitWait.wait([lifetime], timeout: 3)
        XCTAssertFalse(lifetime.isRunning)
    }
    func testAlreadyExitedProcessDoesNotBlockUpdate() throws {
        let process = try sleeper()
        let lifetime = try XCTUnwrap(ProcessLifetime(pid: process.processIdentifier))
        process.terminate(); process.waitUntilExit()
        XCTAssertNil(ProcessLifetime(pid: process.processIdentifier))
        XCTAssertNoThrow(try ManagerQuitWait.wait([lifetime], timeout: 0))
    }
    func testLiveProcessBlocksWithoutBeingKilled() throws {
        let process = try sleeper()
        defer { process.terminate(); process.waitUntilExit() }
        let lifetime = try XCTUnwrap(ProcessLifetime(pid: process.processIdentifier))
        XCTAssertThrowsError(try ManagerQuitWait.wait([lifetime], timeout: 0.1))
        XCTAssertTrue(lifetime.isRunning)
    }
    func testAllOldProcessesMustExit() throws {
        let first = try sleeper(), second = try sleeper()
        defer { if first.isRunning { first.terminate() }; if second.isRunning { second.terminate() }; first.waitUntilExit(); second.waitUntilExit() }
        let lifetimes = try [XCTUnwrap(ProcessLifetime(pid: first.processIdentifier)), XCTUnwrap(ProcessLifetime(pid: second.processIdentifier))]
        first.terminate(); first.waitUntilExit()
        XCTAssertThrowsError(try ManagerQuitWait.wait(lifetimes, timeout: 0.1))
        second.terminate()
        XCTAssertNoThrow(try ManagerQuitWait.wait(lifetimes, timeout: 3))
    }
}
