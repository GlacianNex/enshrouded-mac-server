import XCTest
@testable import EnshroudedCore

final class ServerSpeedHistoryTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_000_000)
    private let line = "[ecss] Stats: Upd:3,600 Time:60,000ms Max:35ms Avg:2.7ms\n"
    private func log(_ count: Int, file: String = "run-1") -> LogTailSnapshot {
        let text = String(repeating: line, count: count)
        return .init(text: text, fileIdentifier: file, startOffset: 0, fileSize: UInt64(text.utf8.count))
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
        history.observe(log(2), running: true, invocation: "a", at: date.addingTimeInterval(180))
        let chart = PerformanceHistory.chartPoints(history.points, maximumGap: ServerSpeedHistory.freshness)
        XCTAssertNotEqual(chart[0].segment, chart[1].segment)
        history.observe(log(2), running: nil, invocation: nil, at: date.addingTimeInterval(11_000))
        XCTAssertTrue(history.points.isEmpty)
    }
}
