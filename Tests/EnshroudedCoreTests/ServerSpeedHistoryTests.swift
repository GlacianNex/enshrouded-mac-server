import XCTest
@testable import EnshroudedCore

final class ServerSpeedHistoryTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_000_000)
    private let line = "[ecss] Stats: Upd:3,600 Time:60,000ms Max:35ms Avg:2.7ms\n"
    private func log(_ count: Int, file: String = "run-1", reportAt: Date? = nil) -> LogTailSnapshot {
        let text = (0..<count).map { "[I 00:" + String(format: "%02d", $0) + ":00,000] " + line }.joined()
        return .init(text: text, fileIdentifier: file, startOffset: 0, fileSize: UInt64(text.utf8.count), modifiedAt: reportAt ?? date.addingTimeInterval(Double(count - 1) * 60))
    }
    func testFailedMetricsDoNotEraseReadingOrSplitMinuteReports() {
        var history = ServerSpeedHistory()
        history.observe(log(1), running: true, invocation: "a", at: date)
        history.observe(log(1), running: true, invocation: nil, at: date.addingTimeInterval(30))
        XCTAssertEqual(history.current(at: date.addingTimeInterval(30)), 60)
        history.observe(log(2), running: true, invocation: nil, at: date.addingTimeInterval(60))
        XCTAssertEqual(history.points.count, 2)
        XCTAssertEqual(history.points[0].segment, history.points[1].segment)
        XCTAssertEqual(history.current(at: date.addingTimeInterval(90)), 60)
    }
    func testUnknownStatusAndUnrelatedLogDoNotRefreshOrClearTheLastReport() {
        var history = ServerSpeedHistory()
        history.observe(log(1), running: true, invocation: "a", at: date)
        history.observe(log(1), running: nil, invocation: nil, at: date.addingTimeInterval(10))
        history.observe(.init(text: "", fileIdentifier: "", startOffset: 0, fileSize: 0), running: true, invocation: nil, at: date.addingTimeInterval(20))
        XCTAssertEqual(history.current(at: date.addingTimeInterval(20)), 60)
        let empty = LogTailSnapshot(text: "unrelated\n", fileIdentifier: "run-1", startOffset: 1000, fileSize: 1010)
        history.observe(empty, running: true, invocation: "a", at: date.addingTimeInterval(30))
        XCTAssertEqual(history.current(at: date.addingTimeInterval(89)), 60)
        XCTAssertNil(history.current(at: date.addingTimeInterval(91)))
        XCTAssertEqual(history.points.count, 1)
    }
    func testRealRestartCreatesGapAndDoesNotReuseOldReport() {
        var history = ServerSpeedHistory()
        history.observe(log(1), running: true, invocation: "a", at: date)
        history.observe(log(1), running: false, invocation: nil, at: date.addingTimeInterval(10))
        XCTAssertNil(history.current(at: date.addingTimeInterval(11)))
        history.observe(log(1), running: true, invocation: "b", at: date.addingTimeInterval(20))
        XCTAssertEqual(history.points.count, 1)
        history.observe(log(1, file: "run-2"), running: true, invocation: "b", at: date.addingTimeInterval(60))
        XCTAssertEqual(history.points.count, 2)
        XCTAssertNotEqual(history.points[0].segment, history.points[1].segment)
    }
    func testMissingMinuteReportsRemainGapsAndHistoryExpires() {
        var history = ServerSpeedHistory()
        history.observe(log(1), running: true, invocation: "a", at: date)
        history.observe(log(2, reportAt: date.addingTimeInterval(180)), running: true, invocation: "a", at: date.addingTimeInterval(180))
        let chart = PerformanceHistory.chartPoints(history.points, maximumGap: ServerSpeedHistory.freshness)
        XCTAssertNotEqual(chart[0].segment, chart[1].segment)
        history.observe(log(2), running: nil, invocation: nil, at: date.addingTimeInterval(11_000))
        XCTAssertTrue(history.points.isEmpty)
    }
    func testReopenedNativeLogKeepsActualOldReportDate() {
        var history = ServerSpeedHistory()
        let text = "[I 00:00:00,000] " + line + "[I 00:05:00,000] unrelated event\n"
        let snapshot = LogTailSnapshot(text: text, fileIdentifier: "run-1", startOffset: 0, fileSize: UInt64(text.utf8.count), modifiedAt: date)
        history.observe(snapshot, running: true, invocation: "a", at: date)
        XCTAssertTrue(history.reportTimeKnown)
        XCTAssertEqual(history.lastReport, date.addingTimeInterval(-300))
        XCTAssertEqual(history.points.first?.date, date.addingTimeInterval(-300))
        XCTAssertNil(history.current(at: date))
        // An unchanged report never becomes fresh on a later polling pass.
        history.observe(snapshot, running: true, invocation: "a", at: date.addingTimeInterval(30))
        XCTAssertEqual(history.points.count, 1)
        XCTAssertEqual(history.lastReport, date.addingTimeInterval(-300))
        history.observe(log(2, reportAt: date.addingTimeInterval(60)), running: true, invocation: "a", at: date.addingTimeInterval(60))
        XCTAssertEqual(history.current(at: date.addingTimeInterval(60)), 60)
    }
    func testUnknownReportTimeDoesNotCreateFreshReadingOrGraphPoint() {
        var history = ServerSpeedHistory()
        let snapshot = LogTailSnapshot(text: line, fileIdentifier: "plain", startOffset: 0, fileSize: UInt64(line.utf8.count), modifiedAt: date)
        history.observe(snapshot, running: true, invocation: "a", at: date)
        XCTAssertEqual(history.lastValue, 60)
        XCTAssertFalse(history.reportTimeKnown)
        XCTAssertNil(history.lastReport)
        XCTAssertNil(history.current(at: date))
        XCTAssertTrue(history.points.isEmpty)
    }
    func testReportsOlderThanHistoryAreNotInsertedAndStopClearsAge() {
        var history = ServerSpeedHistory()
        history.observe(log(1, reportAt: date.addingTimeInterval(-11_000)), running: true, invocation: "a", at: date)
        XCTAssertTrue(history.reportTimeKnown)
        XCTAssertTrue(history.points.isEmpty)
        XCTAssertNil(history.current(at: date))
        history.observe(log(1), running: false, invocation: "a", at: date)
        XCTAssertFalse(history.reportTimeKnown)
        XCTAssertNil(history.lastValue)
    }

}
