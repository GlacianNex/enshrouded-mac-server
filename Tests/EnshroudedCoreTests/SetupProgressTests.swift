import XCTest
@testable import EnshroudedCore

final class SetupProgressTests: XCTestCase {
    func testSplitEventsAndByteCountersResetAcrossSteps() {
        var progress = SetupProgress()
        let line = SetupEvent(.wine, "Downloading…", received: 50, total: 100).line
        progress.consume(String(line.prefix(17)))
        XCTAssertNil(progress.received)
        progress.consume(String(line.dropFirst(17)))
        XCTAssertEqual(progress.percent, 50)
        progress.consume(SetupEvent(.downloader, "Preparing…").line)
        XCTAssertNil(progress.received); XCTAssertNil(progress.percent)
        XCTAssertEqual(progress.downloaded[.wine], 50)
    }
    func testSteamProgressIsNotMisrepresentedAsNetworkBytes() {
        var progress = SetupProgress()
        progress.consume(SetupEvent(.server, "Downloading").line)
        progress.consume(" 25.50% file.dll\r")
        XCTAssertEqual(progress.percent, 25.5); XCTAssertNil(progress.received)
        progress.consume("Total downloaded: 200 bytes (500 bytes uncompressed) from 1 depots\n")
        XCTAssertEqual(progress.received, 200); XCTAssertNil(progress.total)
        XCTAssertEqual(progress.downloaded[.server], 200)
    }
    func testUnknownTotalsInvalidEventsAndFailurePreserveEvidence() {
        var progress = SetupProgress()
        progress.consume(SetupEvent(.environment, "Downloading", received: 123).line)
        progress.consume("[ESM_SETUP] not json\n9999% bad\n")
        XCTAssertEqual(progress.received, 123); XCTAssertNil(progress.percent)
        progress.finish(success: false)
        XCTAssertTrue(progress.failed); XCTAssertFalse(progress.finished)
        XCTAssertEqual(progress.step, .environment)
    }
    func testPackageBatchesAreAddedAndRetriesResetCurrentFile() {
        var progress = SetupProgress()
        progress.consume(SetupEvent(.packages, "Packages").line)
        progress.consume("Fetched 10 MB in 2s\nFetched 20 kB in 1s\n")
        XCTAssertEqual(progress.received, 10_020_000)
        progress.consume(SetupEvent(.wine, "Downloading", received: 30, total: 100).line)
        progress.consume(SetupEvent(.wine, "Retry", received: 0).line)
        XCTAssertEqual(progress.received, 0)
    }
    func testLocalImagePathIsQuotedAndVerified() {
        let engine = Engine(home: URL(fileURLWithPath: "/tmp/test"), resources: URL(fileURLWithPath: "/tmp/resources"))
        let config = engine.vmConfiguration(image: URL(fileURLWithPath: "/tmp/a space/image.img"))
        XCTAssertTrue(config.contains("location: \"/tmp/a space/image.img\""))
        XCTAssertTrue(config.contains(Engine.environmentDigest))
    }
    func testCachedDownloadIsVerifiedAndDoesNotUseNetwork() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("known".utf8).write(to: file)
        var output = ""
        try SetupDownload.fetch(URL(string: "https://invalid.invalid/image")!, destination: file, sha256: SetupDownload.digest(file)) { output += $0 }
        XCTAssertTrue(output.contains("verified environment download"))
        XCTAssertEqual(try String(contentsOf: file), "known")
    }
    func testBuildPercentHeartbeatAndStaleStatusAreDistinctFromDownloads() {
        var progress = SetupProgress()
        let now = Date(timeIntervalSince1970: 1000)
        progress.consume(SetupEvent(.box64, "Downloading", received: 100, total: 100).line, at: now)
        progress.consume("[ESM_SETUP] {\"stage\":\"box64\",\"phase\":\"build\",\"message\":\"Compiling…\",\"percent\":42,\"running\":true,\"elapsedSeconds\":30,\"outputAgeSeconds\":2,\"cpuActive\":true}\n", at: now)
        XCTAssertEqual(progress.percent, 42)
        XCTAssertNil(progress.received)
        XCTAssertEqual(progress.downloaded[.box64], 100)
        XCTAssertEqual(progress.percentLabel, "Compilation: 42% of build steps")
        XCTAssertEqual(progress.processStatus(at: now.addingTimeInterval(3)), "CPU activity detected · Last output 5s ago · Step elapsed 33s")
        XCTAssertEqual(progress.processStatus(at: now.addingTimeInterval(20)), "No status update for 20s. Open Logs for details.")
        progress.consume("[ESM_SETUP] {\"stage\":\"box64\",\"phase\":\"build\",\"message\":\"Compiling…\",\"running\":true,\"elapsedSeconds\":35,\"outputAgeSeconds\":7,\"cpuActive\":false}\n", at: now.addingTimeInterval(5))
        XCTAssertEqual(progress.percent, 42, "Quiet heartbeat must retain the actual build percentage")
        XCTAssertTrue(progress.processStatus(at: now.addingTimeInterval(5))!.contains("No recent CPU activity"))
    }
    func testBuildSubstepsResetPercentageAndDoNotInventCompletion() {
        var progress = SetupProgress()
        progress.consume("[ESM_SETUP] {\"stage\":\"box64\",\"phase\":\"build\",\"message\":\"Compiling…\",\"percent\":57,\"running\":true}\n")
        progress.consume("[ESM_SETUP] {\"stage\":\"box64\",\"phase\":\"build\",\"message\":\"Compiling…\",\"percent\":101,\"running\":false}\n")
        XCTAssertEqual(progress.percent, 57)
        progress.finish(success: false)
        XCTAssertEqual(progress.percent, 57)
        XCTAssertTrue(progress.failed)
        var next = SetupProgress()
        next.consume("[ESM_SETUP] {\"stage\":\"box64\",\"phase\":\"build\",\"message\":\"Compiling…\",\"percent\":100}\n")
        next.consume("[ESM_SETUP] {\"stage\":\"box64\",\"phase\":\"install\",\"message\":\"Installing…\",\"running\":true}\n")
        XCTAssertNil(next.percent)
        XCTAssertEqual(next.phase, "install")
        next.consume(SetupEvent(.wine, "Downloading").line)
        XCTAssertNil(next.phase)
        XCTAssertNil(next.processStatus(at: Date()))
    }

}
