import XCTest
@testable import EnshroudedCore

final class ServerDeletionTests: XCTestCase {
    private func fixture() throws -> (URL, Engine, ProfileStore, [ServerProfile]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("first")
        let engine = Engine(home: home, resources: root.appendingPathComponent("Bundle"))
        for path in ["Bundle/Lima/bin", "Bundle/Runtime", "first/lima/engine", "first/data/server/savegame", "first/cache", "second"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        for name in ["guest.sh", "stop-server.py", "download.py", "build-progress.py"] { try Data().write(to: engine.resources.appendingPathComponent("Runtime/" + name)) }
        for path in ["lima/engine/lima.yaml", "data/server/enshrouded_server.exe", "cache/ubuntu.img"] {
            try Data("reusable".utf8).write(to: home.appendingPathComponent(path))
        }
        try "#!/bin/sh\necho Stopped\n".write(to: engine.lima, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.lima.path)
        try Data("world-progress".utf8).write(to: engine.world.appendingPathComponent("world"))
        try Data("{\"password\":\"private\"}".utf8).write(to: engine.serverConfig)
        let profiles = [ServerProfile(id: "first", name: "First", home: home.path, port: 15637), ServerProfile(id: "second", name: "Second", home: root.appendingPathComponent("second").path, port: 15638)]
        for profile in profiles { try JSONEncoder().encode(profile).write(to: URL(fileURLWithPath: profile.home).appendingPathComponent("profile.json")) }
        let store = ProfileStore(registry: root.appendingPathComponent("profiles.json"))
        try store.save(profiles)
        return (root, engine, store, profiles)
    }

    func testDeletionArchivesIdentityAndWorldButRetainsInstallationAndOtherServer() throws {
        let (root, engine, store, profiles) = try fixture()
        let other = root.appendingPathComponent("second/profile.json")
        let originalOther = try Data(contentsOf: other)
        XCTAssertEqual(try engine.deleteServer(store: store), [profiles[1]])
        XCTAssertEqual(try store.load(), [profiles[1]])
        XCTAssertEqual(try store.retainedInstallations(), [profiles[0]])
        XCTAssertEqual(try Data(contentsOf: other), originalOther)
        for path in ["lima/engine/lima.yaml", "data/server/enshrouded_server.exe", "cache/ubuntu.img"] {
            XCTAssertEqual(try String(contentsOf: engine.home.appendingPathComponent(path)), "reusable")
        }
        for path in ["profile.json", "data/server/enshrouded_server.json", "data/server/savegame"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: engine.home.appendingPathComponent(path).path))
        }
        let archives = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("deleted-server-data"), includingPropertiesForKeys: nil)
        XCTAssertEqual(archives.count, 1)
        let archive = try XCTUnwrap(archives.first)
        XCTAssertEqual(try String(contentsOf: archive.appendingPathComponent("data/server/savegame/world")), "world-progress")
        XCTAssertEqual(try String(contentsOf: archive.appendingPathComponent("data/server/enshrouded_server.json")), "{\"password\":\"private\"}")
        XCTAssertEqual(try JSONDecoder().decode(ServerProfile.self, from: Data(contentsOf: archive.appendingPathComponent("profile.json"))), profiles[0])
    }

    func testRegistryFailureRestoresSavedFilesAndLeavesProfileRegistered() throws {
        let (_, engine, store, profiles) = try fixture()
        XCTAssertThrowsError(try engine.deleteServer(store: store, saveProfiles: { _ in throw EngineError("fixture registry failure") }))
        XCTAssertEqual(try store.load(), profiles)
        XCTAssertTrue(try store.retainedInstallations().isEmpty)
        XCTAssertEqual(try String(contentsOf: engine.world.appendingPathComponent("world")), "world-progress")
        XCTAssertEqual(try String(contentsOf: engine.serverConfig), "{\"password\":\"private\"}")
        XCTAssertEqual(try JSONDecoder().decode(ServerProfile.self, from: Data(contentsOf: engine.home.appendingPathComponent("profile.json"))), profiles[0])
    }

    func testLinkedSavedDataOutsideServerIsRejectedWithoutChangingEitherProfile() throws {
        let (root, engine, store, profiles) = try fixture()
        let outside = root.appendingPathComponent("outside-world")
        try FileManager.default.moveItem(at: engine.world, to: outside)
        try FileManager.default.createSymbolicLink(at: engine.world, withDestinationURL: outside)
        XCTAssertThrowsError(try engine.deleteServer(store: store))
        XCTAssertEqual(try store.load(), profiles)
        XCTAssertEqual(try String(contentsOf: outside.appendingPathComponent("world")), "world-progress")
        XCTAssertTrue(try store.retainedInstallations().isEmpty)
    }
}
