import XCTest
@testable import EnshroudedCore

final class ServerUpdateCheckTests: XCTestCase {
    private func fixture(response: String) throws -> Engine {
        let engine = try ManagerTests().fixture()
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$LIMA_HOME/../commands"
        if [ "$1" = list ]; then echo Running
        elif [ "$5" = status ]; then echo RUNNING
        elif [ "$3" = bash ] && [ "$4" = -lc ]; then \(response)
        else exit 1
        fi
        """
        try script.write(to: engine.lima, atomically: true, encoding: .utf8)
        return engine
    }
    func testCheckReportsStageAndNeverStopsRunningServer() throws {
        let engine = try fixture(response: "echo 'Manifest 123456 (test)'")
        defer { try? FileManager.default.removeItem(at: engine.home) }
        var stages: [String] = []
        XCTAssertEqual(try engine.checkServerRelease { stages.append($0) }.latest, "123456")
        XCTAssertEqual(stages, ["Checking Valve’s server version"])
        let commands = try String(contentsOf: engine.home.appendingPathComponent("commands"))
        XCTAssertTrue(commands.contains("-manifest-only"))
        XCTAssertFalse(commands.contains("guest.sh stop"))
        XCTAssertFalse(commands.contains("stop engine"))
    }
    func testSlowCheckHasBoundedWaitAndClearError() throws {
        var engine = try fixture(response: "exec sleep 10")
        engine.serverReleaseTimeout = 0.05
        defer { try? FileManager.default.removeItem(at: engine.home) }
        let started = Date()
        XCTAssertThrowsError(try engine.checkServerRelease()) {
            XCTAssertEqual($0.localizedDescription, "Valve’s update check took too long. Try again. Your server is unchanged.")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }
    func testGuestTimeoutUsesTheSameClearError() throws {
        let engine = try fixture(response: "exit 124")
        defer { try? FileManager.default.removeItem(at: engine.home) }
        XCTAssertThrowsError(try engine.checkServerRelease()) {
            XCTAssertEqual($0.localizedDescription, "Valve’s update check took too long. Try again. Your server is unchanged.")
        }
    }
}
