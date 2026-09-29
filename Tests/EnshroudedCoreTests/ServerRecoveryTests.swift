import XCTest
@testable import EnshroudedCore

final class ServerRecoveryTests: XCTestCase {
    private func registry(for engine: Engine) throws -> (URL, ProfileStore, [ServerProfile]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ProfileStore(registry: root.appendingPathComponent("profiles.json"))
        let profiles = [ServerProfile(id: "one", name: "One", home: engine.home.path, port: 15637),
                        ServerProfile(id: "two", name: "Two", home: root.appendingPathComponent("other-server").path, port: 15638)]
        try store.save(profiles)
        try FileManager.default.createDirectory(atPath: profiles[1].home, withIntermediateDirectories: true)
        try Data("other world".utf8).write(to: URL(fileURLWithPath: profiles[1].home).appendingPathComponent("sentinel"))
        return (root, store, profiles)
    }
    func testRemovalPreservesWorldAndOtherProfile() throws {
        let engine = try ManagerTests().fixture()
        let (root, store, profiles) = try registry(for: engine)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: engine.home) }
        XCTAssertEqual(try engine.moveToRecovery(store: store), [profiles[1]])
        XCTAssertEqual(try store.load(), [profiles[1]])
        XCTAssertFalse(FileManager.default.fileExists(atPath: engine.home.path))
        let recoveryRoot = root.appendingPathComponent("deleted-servers")
        let recovery = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: recoveryRoot, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try String(contentsOf: recovery.appendingPathComponent("data/data/server/savegame/3ad85aea")), "original progress")
        XCTAssertEqual(try JSONDecoder().decode(ServerProfile.self, from: Data(contentsOf: recovery.appendingPathComponent("profile.json"))), profiles[0])
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: profiles[1].home).appendingPathComponent("sentinel")), "other world")
    }
    func testShutdownFailureNeverMovesWorldOrChangesRegistry() throws {
        let engine = try ManagerTests().fixture()
        let (root, store, profiles) = try registry(for: engine)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: engine.home) }
        try "#!/bin/sh\nif [ \"$1\" = list ]; then echo Running; elif [ \"$5\" = status ]; then echo RUNNING; else echo 'stop refused' >&2; exit 1; fi\n".write(to: engine.lima, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.lima.path)
        XCTAssertThrowsError(try engine.moveToRecovery(store: store))
        XCTAssertEqual(try store.load(), profiles)
        XCTAssertEqual(try String(contentsOf: engine.world.appendingPathComponent("3ad85aea")), "original progress")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("deleted-servers").path))
    }
    func testRegistryFailureRestoresOriginalHomeAndWorld() throws {
        let engine = try ManagerTests().fixture()
        let (root, store, profiles) = try registry(for: engine)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: engine.home) }
        XCTAssertThrowsError(try engine.moveToRecovery(store: store, saveProfiles: { _ in throw EngineError("registry unavailable") }))
        XCTAssertEqual(try store.load(), profiles)
        XCTAssertEqual(try String(contentsOf: engine.world.appendingPathComponent("3ad85aea")), "original progress")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("deleted-servers").path), [])
    }
    func testNestedRecoveryIsRejectedBeforeShutdown() throws {
        let engine = try ManagerTests().fixture(); defer { try? FileManager.default.removeItem(at: engine.home) }
        let store = ProfileStore(registry: engine.home.appendingPathComponent("profiles.json"))
        try store.save([ServerProfile(id: "one", name: "One", home: engine.home.path, port: 15637)])
        XCTAssertThrowsError(try engine.moveToRecovery(store: store))
        XCTAssertEqual(try String(contentsOf: engine.world.appendingPathComponent("3ad85aea")), "original progress")
    }
}
