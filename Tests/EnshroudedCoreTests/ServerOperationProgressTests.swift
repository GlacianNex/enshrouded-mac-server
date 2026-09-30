import XCTest
@testable import EnshroudedCore

final class ServerOperationProgressTests: XCTestCase {
    func testUpdateStagesConsumePartialChunksInOrder() {
        var progress = ServerOperationProgress(action: "update")
        XCTAssertEqual(progress.title, "Check Server")
        progress.consume("Saving and stop")
        XCTAssertEqual(progress.title, "Check Server")
        progress.consume("ping server…\n")
        XCTAssertEqual(progress.title, "Save & Stop")
        progress.consume("Backing up and updating server…\n")
        XCTAssertEqual(progress.title, "Back Up")
        let event = SetupEvent(.server, "Downloading official server files…").line
        progress.consume(String(event.prefix(12)))
        XCTAssertEqual(progress.title, "Back Up")
        progress.consume(String(event.dropFirst(12)) + "42")
        XCTAssertEqual(progress.title, "Download & Verify")
        XCTAssertNil(progress.percent)
        progress.consume(".5% downloaded\r")
        XCTAssertEqual(progress.percent, 42.5)
        progress.consume("Starting server…\n")
        XCTAssertEqual(progress.title, "Restart Server")
        XCTAssertNil(progress.percent)
        progress.finish(success: true)
        XCTAssertEqual(progress.title, "Complete")
        XCTAssertTrue(progress.finished)
    }

    func testPercentResetsBetweenDownloadStagesAndVerification() {
        var progress = ServerOperationProgress(action: "update")
        progress.consume(SetupEvent(.server, "Downloading…").line + "90% files\n")
        XCTAssertEqual(progress.percent, 90)
        progress.consume(SetupEvent(.steam, "Checking support files…").line)
        XCTAssertNil(progress.percent)
        progress.consume("10% files\n")
        XCTAssertEqual(progress.percent, 10)
        progress.consume("Installation complete.\n")
        XCTAssertNil(progress.percent)
        XCTAssertEqual(progress.title, "Verify Installation")
    }

    func testFailurePreservesStageContextWithoutInventedCompletion() {
        var progress = ServerOperationProgress(action: "update")
        progress.consume(SetupEvent(.server, "Downloading…").line + "30% files\n")
        progress.finish(success: false)
        XCTAssertTrue(progress.failed)
        XCTAssertFalse(progress.finished)
        XCTAssertNil(progress.percent)
        XCTAssertTrue(progress.message.contains("download & verify"))
        progress.consume("Starting server…\n")
        XCTAssertEqual(progress.title, "Operation Failed")
    }

    func testStopNeverPromisesRestart() {
        var progress = ServerOperationProgress(action: "stop")
        XCTAssertEqual(progress.title, "Save & Stop")
        progress.finish(success: true)
        XCTAssertEqual(progress.message, "Server stopped.")
        XCTAssertNil(progress.percent)
    }

    func testStartTimeIsPreservedAcrossStagesAndCompletion() {
        let began = Date(timeIntervalSince1970: 1234)
        var progress = ServerOperationProgress(action: "start", at: began)
        XCTAssertEqual(progress.title, "Start Server")
        progress.consume("Waiting for the game server to answer…\n")
        XCTAssertEqual(progress.title, "Start Server")
        progress.finish(success: true)
        XCTAssertEqual(progress.started, began)
        XCTAssertEqual(progress.message, "Server started.")
    }
}
