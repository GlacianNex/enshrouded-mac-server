import XCTest
@testable import EnshroudedCore

final class ManagerInstallProgressTests: XCTestCase {
    func testLongWaitExplainsActualStageAndElapsedNeverResets() {
        let began = Date(timeIntervalSince1970: 1000)
        var progress = ManagerInstallProgress(at: began)
        progress.advance(to: .saving, at: began.addingTimeInterval(5))
        XCTAssertEqual(progress.detail(at: began.addingTimeInterval(20)), ManagerInstallStage.saving.explanation)
        XCTAssertEqual(progress.detail(at: began.addingTimeInterval(36)), ManagerInstallStage.saving.waitingMessage)
        progress.advance(to: .stoppingEnvironment, at: began.addingTimeInterval(40))
        XCTAssertEqual(progress.detail(at: began.addingTimeInterval(41)), ManagerInstallStage.stoppingEnvironment.explanation)
        progress.advance(to: .stoppingEnvironment, at: began.addingTimeInterval(65))
        XCTAssertEqual(progress.detail(at: began.addingTimeInterval(71)), ManagerInstallStage.stoppingEnvironment.waitingMessage)
        XCTAssertEqual(progress.elapsed(at: began.addingTimeInterval(71)), "Elapsed 1:11")
    }
    func testEnvironmentShutdownUsesGuestPoweroffBeforeStoppingHostAgent() throws {
        let engine = try ManagerTests().fixture()
        defer { try? FileManager.default.removeItem(at: engine.home) }
        let script = #"""
        #!/bin/sh
        printf '%s\n' "$*" >> "$LIMA_HOME/../commands"
        if [ "$1" = list ]; then echo Running
        elif [ "$5" = status ]; then echo RUNNING
        elif [ "$5" = stop ]; then echo 'Server stopped.'
        elif [ "$3" = sudo ] && [ "$6" = poweroff ]; then exit 0
        elif [ "$1" = stop ]; then echo Stopped
        else exit 1
        fi
        """#
        try script.write(to: engine.lima, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.lima.path)
        var output = ""
        try engine.perform("shutdown") { output += $0 }
        let commands = try String(contentsOf: engine.home.appendingPathComponent("commands")).components(separatedBy: .newlines)
        let guestStop = try XCTUnwrap(commands.firstIndex { $0.hasSuffix("guest.sh stop") })
        let guestPoweroff = try XCTUnwrap(commands.firstIndex { $0 == "shell engine sudo systemctl --no-block poweroff" })
        let hostStop = try XCTUnwrap(commands.firstIndex(of: "stop engine"))
        XCTAssertLessThan(guestStop, guestPoweroff); XCTAssertLessThan(guestPoweroff, hostStop)
        XCTAssertTrue(output.contains("Stopping the server environment"))
        XCTAssertFalse(commands.contains { $0.contains("--force") })
    }
    func testBoundedClientReportsShutdownSpecificError() {
        XCTAssertThrowsError(try DiagnosticCommand.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], environment: [:],
            directory: FileManager.default.temporaryDirectory, timeout: 0.05, timeoutMessage: "Environment shutdown did not finish.", output: { _ in })) {
            XCTAssertEqual($0.localizedDescription, "Environment shutdown did not finish.")
        }
    }
}
