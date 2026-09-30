import XCTest
@testable import EnshroudedCore

final class LogSnapshotTests: XCTestCase {
    private let stats = "[ecss] Stats: Upd:3,000 Time:60,000ms Max:40ms Avg:13.4ms\n"
    private func fixture() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("server.log")
    }
    private func append(_ text: String, to url: URL) throws {
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.seekToEnd(); try file.write(contentsOf: Data(text.utf8))
    }
    func testIdenticalSuccessiveReportsHaveDistinctIdentities() throws {
        let url = try fixture()
        try Data(stats.utf8).write(to: url)
        let first = LogTailSnapshot.read(url)
        try append(stats, to: url)
        let second = LogTailSnapshot.read(url)
        XCTAssertEqual(first.parsed.statsLine, second.parsed.statsLine)
        XCTAssertNotEqual(first.identityFor(relativeEnd: first.parsed.statsReportEnd), second.identityFor(relativeEnd: second.parsed.statsReportEnd))
    }
    func testUnrelatedAppendsDoNotMakeOldReportsFresh() throws {
        let url = try fixture()
        try Data(stats.utf8).write(to: url)
        let first = LogTailSnapshot.read(url)
        try append("An unrelated event\n", to: url)
        let second = LogTailSnapshot.read(url)
        XCTAssertEqual(first.identityFor(relativeEnd: first.parsed.statsReportEnd), second.identityFor(relativeEnd: second.parsed.statsReportEnd))
        XCTAssertEqual(first.fileSize, UInt64(stats.utf8.count))
    }
    func testIncompleteStatsAndSessionReportsWaitForNewline() throws {
        let url = try fixture()
        try Data(stats.dropLast().utf8).write(to: url)
        XCTAssertNil(LogTailSnapshot.read(url).parsed.updateRate)
        try append("\n-------------- Session ----------------\nm#1(129): lost 0, ping 20 ms, OperatingNormally\n---------------------------------------", to: url)
        XCTAssertEqual(LogTailSnapshot.read(url).parsed.updateRate, 50)
        XCTAssertEqual(LogTailSnapshot.read(url).parsed.peerReportEnd, 0)
        try append("\n", to: url)
        let complete = LogTailSnapshot.read(url)
        XCTAssertEqual(complete.parsed.peers.first?.ping, 20)
        XCTAssertEqual(complete.identityFor(relativeEnd: complete.parsed.peerReportEnd), "\(complete.fileIdentifier):\(complete.fileSize)")
    }
    func testRotationAndTruncationDiscardPreviousReports() throws {
        let url = try fixture()
        try Data(stats.utf8).write(to: url)
        let first = LogTailSnapshot.read(url)
        // Atomic replacement changes the file identity even at the same length.
        try Data(stats.utf8).write(to: url, options: .atomic)
        let rotated = LogTailSnapshot.read(url)
        XCTAssertNotEqual(first.identityFor(relativeEnd: first.parsed.statsReportEnd), rotated.identityFor(relativeEnd: rotated.parsed.statsReportEnd))
        let writer = try FileHandle(forWritingTo: url)
        try writer.truncate(atOffset: 0); try writer.close()
        let truncated = LogTailSnapshot.read(url)
        XCTAssertEqual(truncated.fileSize, 0)
        XCTAssertNil(truncated.parsed.updateRate)
        XCTAssertNil(truncated.identityFor(relativeEnd: 0))
    }
    func testTailOffsetsRemainByteAccurateWithCRLFAndUnicode() throws {
        let url = try fixture()
        let report = stats.replacingOccurrences(of: "\n", with: "\r\n")
        let text = "An older line with 🐉\r\n" + report
        try Data(text.utf8).write(to: url)
        let snapshot = LogTailSnapshot.read(url, maxBytes: report.utf8.count + 4)
        XCTAssertEqual(snapshot.text, report)
        XCTAssertEqual(snapshot.identityFor(relativeEnd: snapshot.parsed.statsReportEnd), "\(snapshot.fileIdentifier):\(text.utf8.count)")
    }
    func testNativePrefixParsesStatsAndExactPeerDelimiter() {
        let text = "[I 01:02:03,250] " + stats + "[I 01:02:04,000] -------------- Session ----------------\n[I 01:02:04,001] m#1(129): lost 0, ping 20 ms, OperatingNormally\n[I 01:02:04,002] ---------------------------------------\n"
        let parsed = LogSnapshot.parse(text, completeLinesOnly: true)
        XCTAssertEqual(parsed.updateRate, 50)
        XCTAssertEqual(parsed.statsElapsed, 3723.25)
        XCTAssertEqual(parsed.lastElapsed, 3724.002)
        XCTAssertEqual(parsed.peers.first?.ping, 20)
        XCTAssertEqual(parsed.peerReportEnd, text.utf8.count)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = LogTailSnapshot(text: text, fileIdentifier: "test", startOffset: 0, fileSize: UInt64(text.utf8.count), modifiedAt: now.addingTimeInterval(-300))
        XCTAssertEqual(snapshot.peerReportDate(at: now), now.addingTimeInterval(-300))
        XCTAssertEqual(parsed.peerElapsed, 3724.002)
    }
    func testReportDateUsesElapsedDeltaAndRejectsUnknownOrInconsistentClocks() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func snapshot(_ ending: String, modifiedAt: Date? = nil) -> LogTailSnapshot {
            let text = "[I 01:00:00,000] " + stats + ending
            return LogTailSnapshot(text: text, fileIdentifier: "test", startOffset: 0, fileSize: UInt64(text.utf8.count), modifiedAt: modifiedAt)
        }
        XCTAssertEqual(snapshot("[I 01:05:00,000] event\n", modifiedAt: now).reportDate(at: now), now.addingTimeInterval(-300))
        XCTAssertNil(snapshot("[I 01:05:00,000] event\n").reportDate(at: now))
        XCTAssertNil(snapshot("[I 00:00:00,000] restarted\n", modifiedAt: now).reportDate(at: now))
        XCTAssertNil(snapshot("[I 999:00:00,000] invalid\n", modifiedAt: now).reportDate(at: now))
        XCTAssertNil(snapshot("", modifiedAt: now.addingTimeInterval(1)).reportDate(at: now))
        let plain = LogTailSnapshot(text: stats, fileIdentifier: "test", startOffset: 0, fileSize: UInt64(stats.utf8.count), modifiedAt: now)
        XCTAssertNil(plain.reportDate(at: now))
    }
    func testIncompleteNativeLineDoesNotAdvanceElapsedClock() {
        let parsed = LogSnapshot.parse("[I 00:01:00,000] " + stats + "[I 00:09:00,000] incomplete", completeLinesOnly: true)
        XCTAssertEqual(parsed.lastElapsed, 60)
        XCTAssertEqual(parsed.statsElapsed, 60)
    }
    func testNativeLogPreferenceFallsBackWithoutTimestampedContent() throws {
        let root = try fixture().deletingLastPathComponent()
        let engine = Engine(home: root, resources: root)
        let stdout = engine.data.appendingPathComponent("logs/server.log")
        let native = engine.data.appendingPathComponent("server/logs/enshrouded_server.log")
        for file in [stdout, native] { try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true) }
        try Data(stats.utf8).write(to: stdout)
        XCTAssertEqual(engine.logTailSnapshot().text, stats)
        XCTAssertEqual(engine.serverLogFolder, stdout.deletingLastPathComponent())
        try Data().write(to: native)
        XCTAssertEqual(engine.logTailSnapshot().text, stats)
        try Data("banner only\n".utf8).write(to: native)
        XCTAssertEqual(engine.logTailSnapshot().text, stats)
        let timestamped = "[I 00:01:00,000] " + stats
        try Data(timestamped.utf8).write(to: native)
        let snapshot = engine.logTailSnapshot()
        XCTAssertEqual(snapshot.text, timestamped)
        XCTAssertEqual(engine.serverLogFolder, native.deletingLastPathComponent())
        XCTAssertNotNil(snapshot.modifiedAt)
        XCTAssertNotNil(snapshot.reportDate())
    }

}
