import XCTest
@testable import EnshroudedCore

final class ManagerActivityLogTests: XCTestCase {
    func testActivityPersistsAcrossManagerInstancesWithPrivatePermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = Engine(home: root, resources: root)
        XCTAssertEqual(engine.activityTail(), "")
        try engine.appendActivity("Starting…\n")
        try engine.appendActivity("Ready\n")
        XCTAssertEqual(Engine(home: root, resources: root).activityTail(), "Starting…\nReady\n")
        let permissions = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("manager-activity.log").path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testActivityBoundsBytesAndKeepsRecentCompleteLines() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = Engine(home: root, resources: root)
        let line = "🔵 Status updated\n"
        try engine.appendActivity(String(repeating: line, count: 30_000) + "Latest\n")
        let bytes = try Data(contentsOf: root.appendingPathComponent("manager-activity.log"))
        XCTAssertLessThanOrEqual(bytes.count, ManagerActivityLog.limit)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        XCTAssertTrue(text.hasPrefix(line))
        XCTAssertTrue(text.hasSuffix("Latest\n"))
    }

    func testActivityRejectsSymlinkWithoutChangingTarget() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("unrelated")
        try Data("Keep me".utf8).write(to: target)
        let engine = Engine(home: root, resources: root)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("manager-activity.log"), withDestinationURL: target)
        XCTAssertThrowsError(try engine.appendActivity("Overwrite"))
        XCTAssertEqual(engine.activityTail(), "")
        XCTAssertEqual(try String(contentsOf: target), "Keep me")
    }

    func testFailedActivityWritePreservesPreviousLog() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = Engine(home: root, resources: root)
        try engine.appendActivity("Previous\n")
        let lock = root.appendingPathComponent("manager-activity.lock")
        try FileManager.default.removeItem(at: lock)
        try FileManager.default.createSymbolicLink(at: lock, withDestinationURL: root.appendingPathComponent("manager-activity.log"))
        XCTAssertThrowsError(try engine.appendActivity("New\n"))
        XCTAssertEqual(engine.activityTail(), "Previous\n")
    }

    func testReadableLogsPreserveSpacingAndRemoveTerminalCodes() {
        XCTAssertEqual(LogDisplay.readable("\u{1B}[31mError\u{1B}[0m\r\n  at Stack\r\nOK\0", filter: "error"), "Error")
        XCTAssertEqual(LogDisplay.readable("a\r\n  b\rprogress"), "a\n  b\nprogress")
        XCTAssertEqual(LogDisplay.readable("line 1\nline 2"), "line 1\nline 2")
        XCTAssertEqual(LogDisplay.readable("nothing", filter: "missing"), "")
    }
}
