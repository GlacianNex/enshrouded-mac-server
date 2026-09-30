import XCTest
import Darwin
@testable import EnshroudedCore

final class ProfilePortChangeTests: XCTestCase {
    private func fixture(state: String = "VM_STOPPED") throws -> (Engine, ProfileStore) {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let engine = Engine(home: root.appendingPathComponent("first"), resources: root.appendingPathComponent("Bundle"))
        for path in ["first/lima/engine", "Bundle/Lima/bin", "second"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        let profiles = [ServerProfile(id: "first", name: "First", home: engine.home.path, port: 15637), ServerProfile(id: "second", name: "Second", home: root.appendingPathComponent("second").path, port: 15638)]
        let store = ProfileStore(registry: root.appendingPathComponent("profiles.json"))
        try store.save(profiles)
        for profile in profiles { try JSONEncoder().encode(profile).write(to: URL(fileURLWithPath: profile.home).appendingPathComponent("profile.json")) }
        try "cpus: 4\nportForwards:\n- guestPort: 15637\n  hostPort: 15637\n  proto: udp\n  hostIP: 0.0.0.0\n".write(to: engine.home.appendingPathComponent("lima/engine/lima.yaml"), atomically: true, encoding: .utf8)
        try Data("forwarding enabled".utf8).write(to: engine.home.appendingPathComponent("internet-forward-v1"))
        try Data(state.utf8).write(to: engine.home.appendingPathComponent("state"))
        let script = #"""
        #!/bin/sh
        echo "$1" >> commands
        case "$1" in
          list) if [ "$(cat state)" = VM_STOPPED ]; then echo Stopped; else echo Running; fi ;;
          shell) if [ "$3" = bash ]; then cat state; fi ;;
          stop) echo VM_STOPPED > state ;;
          edit)
            port="${4##* = }"
            /usr/bin/sed -i '' "s/hostPort: 15637/hostPort: $port/" lima/engine/lima.yaml
            if [ -f fail-edit ]; then exit 1; fi ;;
          *) exit 1 ;;
        esac
        """#
        try script.write(to: engine.lima, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.lima.path)
        return (engine, store)
    }
    private func socketPort() throws -> (Int32, Int) {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result: Int32 = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                guard Darwin.bind(fd, $0, length) == 0 else { return -1 }
                return getsockname(fd, $0, &length)
            }
        }
        guard result == 0 else { close(fd); throw EngineError("Test socket failed") }
        return (fd, Int(UInt16(bigEndian: address.sin_port)))
    }
    private func freePort() throws -> Int {
        let (fd, port) = try socketPort(); close(fd); return port
    }
    func testForeignListenerRefusedBeforeShutdownOrSettingsMutation() throws {
        let (engine, store) = try fixture(state: "INSTALLED")
        let (fd, port) = try socketPort(); defer { close(fd) }
        let before = try snapshot(engine, store)
        XCTAssertThrowsError(try engine.changeHostPort(to: port, store: store)) {
            XCTAssertTrue($0.localizedDescription.contains("UDP port \(port) is already in use"))
        }
        XCTAssertEqual(try snapshot(engine, store), before)
        XCTAssertEqual(try engine.status(), "INSTALLED")
        let commands = try String(contentsOf: engine.home.appendingPathComponent("commands")).split(separator: "\n")
        XCTAssertFalse(commands.contains("stop")); XCTAssertFalse(commands.contains("edit"))
        XCTAssertGreaterThanOrEqual(fcntl(fd, F_GETFD), 0)
    }
    private func snapshot(_ engine: Engine, _ store: ProfileStore) throws -> [Data] {
        try [engine.home.appendingPathComponent("profile.json"), store.registry, engine.home.appendingPathComponent("lima/engine/lima.yaml"), engine.home.appendingPathComponent("internet-forward-v1")].map { try Data(contentsOf: $0) }
    }
    func testDefaultPrimaryWithoutLocalProfileCanChangePort() throws {
        let (engine, store) = try fixture()
        let profile = engine.home.appendingPathComponent("profile.json")
        try FileManager.default.removeItem(at: profile)
        let target = try freePort()
        try engine.changeHostPort(to: target, store: store)
        XCTAssertEqual(Int(engine.hostPort), target)
        XCTAssertEqual(try JSONDecoder().decode(ServerProfile.self, from: Data(contentsOf: profile)), try store.load().first)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: profile.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testMissingPrimaryProfileRollbackRemovesOnlyCreatedProfile() throws {
        let (engine, store) = try fixture()
        let profile = engine.home.appendingPathComponent("profile.json")
        try FileManager.default.removeItem(at: profile)
        let world = engine.home.appendingPathComponent("world-fixture")
        try Data("preserved world".utf8).write(to: world)
        let files = [store.registry, engine.home.appendingPathComponent("lima/engine/lima.yaml"), engine.home.appendingPathComponent("internet-forward-v1"), world]
        let before = try files.map { try Data(contentsOf: $0) }
        XCTAssertThrowsError(try engine.changeHostPort(to: freePort(), store: store, saveProfiles: { _ in throw EngineError("fixture registry failure") }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.path))
        XCTAssertEqual(try files.map { try Data(contentsOf: $0) }, before)
    }
    func testPortChangePreservesOtherServerAndGuestPortWithoutStartingVM() throws {
        let (engine, store) = try fixture()
        let other = try XCTUnwrap(store.load().last)
        let otherURL = URL(fileURLWithPath: other.home).appendingPathComponent("profile.json")
        let original = try Data(contentsOf: otherURL)
        let target = try freePort()
        try engine.changeHostPort(to: target, store: store)
        XCTAssertEqual(Int(engine.hostPort), target)
        XCTAssertEqual(try store.load().first?.port, target)
        XCTAssertEqual(try store.load().last, other)
        XCTAssertEqual(try Data(contentsOf: otherURL), original)
        let yaml = try String(contentsOf: engine.home.appendingPathComponent("lima/engine/lima.yaml"))
        XCTAssertTrue(yaml.contains("hostPort: \(target)")); XCTAssertTrue(yaml.contains("guestPort: 15637")); XCTAssertTrue(yaml.contains("cpus: 4"))
        XCTAssertFalse(try String(contentsOf: engine.home.appendingPathComponent("commands")).contains("start"))
    }
    func testStoppedGameShutsEnvironmentDownBeforeEditing() throws {
        let (engine, store) = try fixture(state: "INSTALLED")
        try engine.changeHostPort(to: try freePort(), store: store)
        let commands = try String(contentsOf: engine.home.appendingPathComponent("commands")).split(separator: "\n").map(String.init)
        XCTAssertLessThan(try XCTUnwrap(commands.firstIndex(of: "stop")), try XCTUnwrap(commands.firstIndex(of: "edit")))
        XCTAssertEqual(try engine.status(), "VM_STOPPED")
    }
    func testInvalidOccupiedAndRunningPortsLeaveAllSettingsUntouched() throws {
        for state in ["VM_STOPPED", "RUNNING"] {
            let (engine, store) = try fixture(state: state)
            let before = try snapshot(engine, store)
            for port in [80, 65536, 15638] { XCTAssertThrowsError(try engine.changeHostPort(to: port, store: store)) }
            if state == "RUNNING" { XCTAssertThrowsError(try engine.changeHostPort(to: try freePort(), store: store)) }
            XCTAssertEqual(try snapshot(engine, store), before)
        }
    }
    func testFailedEditAndRegistryWriteRollbackOriginalBytes() throws {
        let (engine, store) = try fixture()
        let before = try snapshot(engine, store)
        let failure = engine.home.appendingPathComponent("fail-edit")
        try Data().write(to: failure)
        XCTAssertThrowsError(try engine.changeHostPort(to: try freePort(), store: store))
        XCTAssertEqual(try snapshot(engine, store), before)
        try FileManager.default.removeItem(at: failure)
        XCTAssertThrowsError(try engine.changeHostPort(to: try freePort(), store: store, saveProfiles: { _ in throw EngineError("fixture write failure") }))
        XCTAssertEqual(try snapshot(engine, store), before)
    }
    func testLinkedConfigurationAndUnregisteredHomeAreRejected() throws {
        let (engine, store) = try fixture()
        let config = engine.home.appendingPathComponent("lima/engine/lima.yaml")
        let outside = engine.home.appendingPathComponent("outside.yaml")
        try FileManager.default.moveItem(at: config, to: outside)
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: outside)
        let bytes = try Data(contentsOf: outside)
        XCTAssertThrowsError(try engine.changeHostPort(to: try freePort(), store: store))
        XCTAssertEqual(try Data(contentsOf: outside), bytes)
        try FileManager.default.removeItem(at: config)
        try FileManager.default.moveItem(at: outside, to: config)
        try store.save(Array(store.load().dropFirst()))
        XCTAssertThrowsError(try engine.changeHostPort(to: try freePort(), store: store))
    }
    func testOperationLockPreventsConcurrentChanges() throws {
        let (engine, store) = try fixture()
        let before = try snapshot(engine, store)
        try engine.withOperationLock {
            XCTAssertThrowsError(try engine.changeHostPort(to: try freePort(), store: store))
        }
        XCTAssertEqual(try snapshot(engine, store), before)
    }
    func testLinkedProfileAndRegistryAreRejectedBeforeMutation() throws {
        for registry in [false, true] {
            let (engine, store) = try fixture()
            let file = registry ? store.registry : engine.home.appendingPathComponent("profile.json")
            let outside = file.appendingPathExtension("original")
            try FileManager.default.moveItem(at: file, to: outside)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
            let bytes = try Data(contentsOf: outside)
            XCTAssertThrowsError(try engine.changeHostPort(to: try freePort(), store: store))
            XCTAssertEqual(try Data(contentsOf: outside), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: engine.home.appendingPathComponent("commands").path))
        }
    }

}
