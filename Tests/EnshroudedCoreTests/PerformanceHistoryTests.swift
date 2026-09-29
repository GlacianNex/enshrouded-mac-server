import XCTest
@testable import EnshroudedCore

final class PerformanceHistoryTests: XCTestCase {
    func testFiveSecondAverageUsesOnlyReceivedSamples() {
        var series = PerformanceHistory()
        let start = Date(timeIntervalSince1970: 100)
        series.record(2, at: start, segment: 0)
        series.record(4, at: start.addingTimeInterval(1), segment: 0)
        series.record(nil, at: start.addingTimeInterval(2), segment: 0)
        XCTAssertTrue(series.points.isEmpty)
        series.record(8, at: start.addingTimeInterval(5), segment: 0)
        XCTAssertEqual(series.points.count, 1)
        XCTAssertEqual(series.points[0].value, 3)
        XCTAssertEqual(series.points[0].date, start.addingTimeInterval(5))
    }
    func testThreeHourRetentionAndNoInventedEmptyBuckets() {
        var series = PerformanceHistory()
        series.record(2, at: Date(timeIntervalSince1970: 0), segment: 0)
        series.record(nil, at: Date(timeIntervalSince1970: 10), segment: 0)
        series.record(4, at: Date(timeIntervalSince1970: 10800), segment: 0)
        XCTAssertEqual(series.points.count, 1)
        series.record(nil, at: Date(timeIntervalSince1970: 10810), segment: 0)
        XCTAssertEqual(series.points.count, 1)
        XCTAssertEqual(series.points[0].value, 4)
    }
    func testRestartsDoNotMixBuckets() {
        var series = PerformanceHistory()
        series.record(2, at: Date(timeIntervalSince1970: 100), segment: 1)
        series.record(8, at: Date(timeIntervalSince1970: 101), segment: 2)
        series.record(nil, at: Date(timeIntervalSince1970: 105), segment: 2)
        XCTAssertEqual(series.points.map(\.value), [2, 8])
        XCTAssertEqual(series.points.map(\.segment), [1, 2])
    }
    func testTelemetryDistinguishesZeroFromUnavailablePlayers() throws {
        var packet: [UInt8] = [255,255,255,255,73,17]
        for value in ["Test", "World", "Game", "Enshrouded"] { packet += Array(value.utf8) + [0] }
        packet += [0,0,0,16]
        var json: [String: Any] = ["active":true,"cpuSeconds":1,"memoryBytes":10,"uptimeSeconds":1,"invocation":"test","queryResponse":Data(packet).base64EncodedString()]
        let metrics = try JSONDecoder().decode(RuntimeMetrics.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(metrics.playerCount, 0)
        json["queryResponse"] = NSNull()
        let missing = try JSONDecoder().decode(RuntimeMetrics.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(missing.playerCount)
    }
}
