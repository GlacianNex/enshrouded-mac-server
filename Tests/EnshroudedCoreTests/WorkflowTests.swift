import XCTest
@testable import EnshroudedCore

final class WorkflowTests: XCTestCase {
    func testExperimentalBuildsAndReturnToStableUseExplicitReplacement() {
        let stable = BuildInfo(version: "1.0.0", build: "1", experimental: false)
        let experimental = BuildInfo(version: "0.2.0", build: "2", experimental: true)
        XCTAssertTrue(experimental.canReplace(stable))
        XCTAssertTrue(experimental.canReplace(experimental))
        XCTAssertTrue(stable.canReplace(experimental))
        XCTAssertFalse(stable.canReplace(stable))
        XCTAssertTrue(BuildInfo(version: "1.0.1", build: "3", experimental: false).canReplace(stable))
    }
    func testUpdateRestartsOnlyOriginallyRunningServer() throws {
        for (state, expected) in [("RUNNING", ["stop", "install", "start"]), ("INSTALLED", ["install"]), ("VM_STOPPED", ["install", "shutdown"])] {
            var steps: [String] = []
            try MaintenanceWorkflow.run(action: "update", initialState: state, empty: { true }, execute: { steps.append($0) }, output: {_ in})
            XCTAssertEqual(steps, expected)
        }
    }
    func testFailedDownloadDoesNotRestartAndOccupiedOrUnknownDoesNotStop() {
        var steps: [String] = []
        XCTAssertThrowsError(try MaintenanceWorkflow.run(action: "update", initialState: "RUNNING", empty: { true }, execute: { steps.append($0); if $0 == "install" { throw EngineError("download failed") } }, output: {_ in}))
        XCTAssertEqual(steps, ["stop", "install"])
        for unknown in [false, true] {
            steps = []
            XCTAssertThrowsError(try MaintenanceWorkflow.run(action: "restart", initialState: "RUNNING", empty: { if unknown { throw EngineError("timeout") }; return false }, execute: { steps.append($0) }, output: {_ in}))
            XCTAssertTrue(steps.isEmpty)
        }
    }
    func testSteamQueryRejectsTruncationAndReadsPlayerCount() throws {
        var bytes: [UInt8] = [255,255,255,255,73,17]
        for value in ["Test server", "Embervale", "enshrouded", "Enshrouded"] { bytes += Array(value.utf8) + [0] }
        bytes += [0,0,3,16,0,100]
        let result = try ServerQuery.parse(Data(bytes))
        XCTAssertEqual(result.name, "Test server"); XCTAssertEqual(result.players, 3); XCTAssertEqual(result.capacity, 16)
        for length in 0..<bytes.count-4 { XCTAssertThrowsError(try ServerQuery.parse(Data(bytes.prefix(length)))) }
    }
    func testManifestIsExactStringNotFloatingPoint() {
        XCTAssertEqual(ServerRelease.manifest(in: "Manifest 2174935030716737236 (05/11/2026 11:40:33)\n"), "2174935030716737236")
        XCTAssertNil(ServerRelease.manifest(in: "Failed to download Manifest 10"))
    }
    func testScheduleHonorsWeekdayAndFutureTime() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-28T04:00:00Z"))
        var settings = HostingAutomation(); settings.restartEnabled = true; settings.hour = 4; settings.minute = 0; settings.weekdays = [2]
        XCTAssertEqual(settings.next(after: monday, calendar: calendar), calendar.date(byAdding: .day, value: 7, to: monday))
        settings.restartEnabled = false; XCTAssertNil(settings.next(after: monday, calendar: calendar))
    }
    func testImportCopiesRollingFilesRenamesSlotAndKeepsRecovery() throws {
        let engine = try ManagerTests().fixture(); defer { try? FileManager.default.removeItem(at: engine.home) }
        let source = engine.home.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        for name in ["3bd85c7d", "3bd85c7d-index", "3bd85c7d-1"] { try Data(name.utf8).write(to: source.appendingPathComponent(name)) }
        try Data("character".utf8).write(to: source.appendingPathComponent("characters"))
        try engine.importWorld(primaryFile: source.appendingPathComponent("3bd85c7d"))
        XCTAssertEqual(try String(contentsOf: engine.world.appendingPathComponent("3ad85aea")), "3bd85c7d")
        XCTAssertTrue(FileManager.default.fileExists(atPath: engine.world.appendingPathComponent("3ad85aea-index").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: engine.world.appendingPathComponent("characters").path))
        XCTAssertEqual(engine.backups().first?.name, "Before world import")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("3bd85c7d").path))
    }
    func testProfilesRejectDuplicatePortsAndPreserveIndependentHomes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(registry: root.appendingPathComponent("profiles.json"))
        let one = ServerProfile(id: "a", name: "One", home: "/one", port: 15637)
        let two = ServerProfile(id: "b", name: "Two", home: "/two", port: 15638)
        try store.save([one, two]); XCTAssertEqual(try store.load(), [one, two])
        XCTAssertThrowsError(try store.save([one, .init(id: "b", name: "Two", home: "/two", port: 15637)]))
        XCTAssertEqual(try store.load(), [one, two])
    }
}
