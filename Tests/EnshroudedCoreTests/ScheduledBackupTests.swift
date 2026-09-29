import XCTest
@testable import EnshroudedCore

final class ScheduledBackupTests: XCTestCase {
    func testDailyScheduleAndLegacySettings() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-29T03:00:00Z"))
        var schedule = BackupSchedule()
        XCTAssertNil(schedule.next(after: now, calendar: calendar))
        schedule.enabled = true
        XCTAssertEqual(schedule.next(after: now, calendar: calendar), now.addingTimeInterval(86400))
        schedule.minute = 30
        XCTAssertEqual(schedule.next(after: now, calendar: calendar), now.addingTimeInterval(1800))
        let encoded = try JSONEncoder().encode(HostingAutomation())
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "scheduledBackups"); legacy["restartEnabled"] = true
        let decoded = try JSONDecoder().decode(HostingAutomation.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(decoded.restartEnabled); XCTAssertNil(decoded.scheduledBackups)
    }
    func testBackupRestartsOnlyRunningServers() throws {
        for (state, expected) in [("RUNNING", ["stop", "backup", "start"]), ("INSTALLED", ["backup"]), ("VM_STOPPED", ["backup"])] {
            var steps: [String] = []
            try BackupWorkflow.run(initialState: state, empty: { true }, execute: { steps.append($0) }, backup: { steps.append("backup") })
            XCTAssertEqual(steps, expected)
        }
    }
    func testOccupiedUnknownAndFailedStopNeverCopy() {
        for mode in 0...2 {
            var steps: [String] = []
            XCTAssertThrowsError(try BackupWorkflow.run(initialState: "RUNNING", empty: {
                if mode == 1 { throw EngineError("query unavailable") }; return mode == 2
            }, execute: { steps.append($0); throw EngineError("stop failed") }, backup: { steps.append("backup") }))
            XCTAssertEqual(steps, mode == 2 ? ["stop"] : [])
        }
    }
    func testFailedBackupResumesRunningServer() {
        var steps: [String] = []
        XCTAssertThrowsError(try BackupWorkflow.run(initialState: "RUNNING", empty: { true }, execute: { steps.append($0) }, backup: {
            steps.append("backup"); throw EngineError("disk full")
        }))
        XCTAssertEqual(steps, ["stop", "backup", "start"])
    }
    func testStoppedEngineCreatesUsableBackup() throws {
        let engine = try ManagerTests().fixture()
        defer { try? FileManager.default.removeItem(at: engine.home) }
        try engine.scheduledBackup()
        let backup = try XCTUnwrap(engine.backups().first)
        XCTAssertEqual(backup.name, "Scheduled Backup")
        XCTAssertEqual(try String(contentsOf: backup.url.appendingPathComponent("savegame/3ad85aea")), "original progress")
    }
}
