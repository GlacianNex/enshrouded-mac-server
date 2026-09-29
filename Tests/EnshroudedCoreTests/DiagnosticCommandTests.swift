import XCTest
import Darwin
@testable import EnshroudedCore

final class DiagnosticCommandTests: XCTestCase {
    private func run(_ script: String, timeout: TimeInterval = 2, output: (String) -> Void = { _ in }) throws -> String {
        try DiagnosticCommand.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script],
                                  environment: ["PATH": "/usr/bin:/bin", "ESM_TEST_VALUE": "expected"],
                                  directory: FileManager.default.temporaryDirectory, timeout: timeout, output: output)
    }
    func testSuccessCapturesBothStreamsAndEnvironment() throws {
        var streamed = ""
        let result = try run("printf '%s' \"$ESM_TEST_VALUE\"; printf ' stderr' >&2", output: { streamed += $0 })
        XCTAssertEqual(result, "expected stderr"); XCTAssertEqual(streamed, result)
    }
    func testNonzeroExitIncludesDiagnosticOutput() {
        XCTAssertThrowsError(try run("printf 'probe failed' >&2; exit 7")) { error in
            XCTAssertTrue(error.localizedDescription.contains("7"))
            XCTAssertTrue(error.localizedDescription.contains("probe failed"))
        }
    }
    func testSleepTimesOutAndReapsOnlyItsOwnCommand() {
        let began = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try DiagnosticCommand.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"],
                                                      environment: [:], directory: FileManager.default.temporaryDirectory,
                                                      timeout: 0.1, output: { _ in })) { error in
            XCTAssertTrue(error.localizedDescription.contains("timed out"))
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - began, 2)
    }
    func testInheritedPipeDoesNotWaitForBackgroundChild() throws {
        // This descendant is a test-owned sleep, explicitly cleaned up below.
        let began = ProcessInfo.processInfo.systemUptime
        let result = try run("sleep 10 & echo $!", timeout: 0.5)
        let child = try XCTUnwrap(Int32(result.trimmingCharacters(in: .whitespacesAndNewlines)))
        defer { _ = Darwin.kill(child, SIGTERM) }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - began, 2)
        XCTAssertEqual(Darwin.kill(child, 0), 0, "The runner must not terminate descendants or process groups")
    }
    func testOutputCaptureIsBoundedWhileStreamingRemainsComplete() throws {
        var streamedBytes = 0
        let result = try run("/usr/bin/head -c 300000 /dev/zero | /usr/bin/tr '\\000' x", output: { streamedBytes += $0.utf8.count })
        XCTAssertEqual(result.utf8.count, 128_000)
        XCTAssertEqual(streamedBytes, 300_000)
        XCTAssertTrue(result.allSatisfy { $0 == "x" })
    }
    func testClosedOutputStillTimesOutAndIgnoringTerminationIsBounded() {
        let began = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try run("trap '' TERM; exec 1>&- 2>&-; while :; do :; done", timeout: 0.1))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - began, 2)
    }
}
