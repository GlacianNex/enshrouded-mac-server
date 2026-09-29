import XCTest
@testable import EnshroudedCore

final class AutomationPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/New_York")!
        return result
    }
    private func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }
    func testUnrelatedSettingsPreservePendingRestartAndWaitingReceipt() {
        var previous = HostingAutomation()
        previous.restartEnabled = true
        previous.nextRestart = date(9, 29, 4)
        previous.waitingRestart = previous.nextRestart
        var edited = previous
        edited.startAtLogin = true; edited.automaticUpdates = true
        var backup = BackupSchedule(); backup.enabled = true
        edited.scheduledBackups = backup
        let saved = edited.reconcilingRestart(with: previous, now: date(9, 29, 8), calendar: calendar)
        XCTAssertEqual(saved.nextRestart, previous.nextRestart)
        XCTAssertEqual(saved.waitingRestart, previous.waitingRestart)
        XCTAssertTrue(saved.startAtLogin); XCTAssertTrue(saved.automaticUpdates)
        XCTAssertTrue(saved.scheduledBackups?.enabled == true)
    }
    func testEditingRestartScheduleReplacesPendingOccurrenceAndDisablingClearsIt() {
        var previous = HostingAutomation(); previous.restartEnabled = true
        previous.nextRestart = date(9, 29, 4); previous.waitingRestart = previous.nextRestart
        var edited = previous; edited.hour = 5
        let saved = edited.reconcilingRestart(with: previous, now: date(9, 29, 4), calendar: calendar)
        XCTAssertEqual(saved.nextRestart, date(9, 29, 5)); XCTAssertNil(saved.waitingRestart)
        edited.restartEnabled = false
        let disabled = edited.reconcilingRestart(with: previous, now: date(9, 29, 4), calendar: calendar)
        XCTAssertNil(disabled.nextRestart); XCTAssertNil(disabled.waitingRestart)
    }
    func testMissedRestartIsSkippedButObservedWaitingOccurrenceSurvivesRelaunch() throws {
        var automation = HostingAutomation(); automation.restartEnabled = true
        let due = date(9, 29, 4); automation.nextRestart = due
        XCTAssertEqual(ScheduledRestartPolicy.decide(automation: automation, now: due.addingTimeInterval(3600), running: true, players: 0), .skip)
        XCTAssertEqual(ScheduledRestartPolicy.decide(automation: automation, now: due, running: true, players: 1), .waiting)
        automation.waitingRestart = due
        let restored = try JSONDecoder().decode(HostingAutomation.self, from: JSONEncoder().encode(automation))
        XCTAssertEqual(ScheduledRestartPolicy.decide(automation: restored, now: due.addingTimeInterval(3600), running: true, players: 0), .run)
        XCTAssertEqual(ScheduledRestartPolicy.decide(automation: restored, now: due.addingTimeInterval(3600), running: true, players: nil), .waiting)
        automation.waitingRestart = due.addingTimeInterval(-86400)
        XCTAssertEqual(ScheduledRestartPolicy.decide(automation: automation, now: due.addingTimeInterval(3600), running: true, players: 0), .skip)
    }
    func testStoppedDisabledFutureAndUnknownPlayerDecisions() {
        var automation = HostingAutomation(); let due = date(9, 29, 4)
        automation.nextRestart = due
        XCTAssertEqual(ScheduledRestartPolicy.decide(automation: automation, now: due, running: true, players: 0), .none)
        automation.restartEnabled = true
        XCTAssertEqual(ScheduledRestartPolicy.decide(automation: automation, now: due.addingTimeInterval(-1), running: true, players: 0), .none)
        XCTAssertEqual(ScheduledRestartPolicy.decide(automation: automation, now: due, running: false, players: 0), .skip)
        XCTAssertEqual(ScheduledRestartPolicy.decide(automation: automation, now: due, running: true, players: nil), .waiting)
        XCTAssertEqual(ScheduledRestartPolicy.decide(automation: automation, now: due, running: true, players: 0), .run)
    }
    func testIntervalKeepsRequestedTimeAfterSpringDSTGapAndHonorsFutureAnchor() {
        var automation = HostingAutomation(); automation.restartEnabled = true
        automation.everyDays = 2; automation.anchorDate = date(3, 8, 0)
        automation.hour = 2; automation.minute = 30
        XCTAssertEqual(automation.next(after: date(3, 7, 0), calendar: calendar), date(3, 8, 3))
        XCTAssertEqual(automation.next(after: date(3, 8, 3), calendar: calendar), date(3, 10, 2, 30))
        automation.anchorDate = date(9, 30, 0)
        XCTAssertEqual(automation.next(after: date(9, 29, 0), calendar: calendar), date(9, 30, 2, 30))
    }
    func testLegacyAutomationWithoutWaitingReceiptDecodes() throws {
        let bytes = try JSONEncoder().encode(HostingAutomation())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        object.removeValue(forKey: "waitingRestart")
        let decoded = try JSONDecoder().decode(HostingAutomation.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.waitingRestart)
    }
}
