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

    func testDeletionArchivesSavedDataAndRemovesEntireInstallationOnly() throws {
        let (root, engine, store, profiles) = try fixture()
        let other = root.appendingPathComponent("second/profile.json")
        let originalOther = try Data(contentsOf: other)
        for path in ["data/backups/worlds/backup", "data/previous-install/savegame/world", "data/previous-install/enshrouded_server.exe"] {
            let file = engine.home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: file)
        }
        let result = try engine.deleteServer(store: store)
        XCTAssertEqual(result.remaining, [profiles[1]])
        XCTAssertNotNil(result.savedData)
        XCTAssertNil(result.cleanupWarning)
        XCTAssertEqual(try store.load(), [profiles[1]])
        XCTAssertTrue(try store.retainedInstallations().isEmpty)
        XCTAssertEqual(try Data(contentsOf: other), originalOther)
        XCTAssertFalse(FileManager.default.fileExists(atPath: engine.home.path))
        for path in ["profile.json", "data/server/enshrouded_server.json", "data/server/savegame"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: engine.home.appendingPathComponent(path).path))
        }
        let archives = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("deleted-server-data"), includingPropertiesForKeys: nil)
        XCTAssertEqual(archives.count, 1)
        let archive = try XCTUnwrap(archives.first)
        XCTAssertEqual(try String(contentsOf: archive.appendingPathComponent("data/backups/worlds/backup")), "fixture")
        XCTAssertEqual(try String(contentsOf: archive.appendingPathComponent("data/previous-install/savegame/world")), "fixture")
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.appendingPathComponent("data/previous-install/enshrouded_server.exe").path))
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
    func testDeleteGameDataRemovesInstallationSaveAndBackupsWithoutArchive() throws {
        let (root, engine, store, profiles) = try fixture()
        let backup = engine.data.appendingPathComponent("backups/worlds/old-save")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try Data("backup".utf8).write(to: backup.appendingPathComponent("world"))
        let shared = root.appendingPathComponent("downloads")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try Data("shared cache".utf8).write(to: shared.appendingPathComponent("ubuntu.img"))
        let result = try engine.deleteServer(store: store, deleteGameData: true)
        XCTAssertEqual(result.remaining, [profiles[1]])
        XCTAssertNil(result.savedData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: engine.home.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("deleted-server-data").path))
        XCTAssertEqual(try String(contentsOf: shared.appendingPathComponent("ubuntu.img")), "shared cache")
        XCTAssertTrue(FileManager.default.fileExists(atPath: profiles[1].home))
    }

    func testDeleteGameDataRegistryFailureRestoresEntireInstallation() throws {
        let (_, engine, store, profiles) = try fixture()
        XCTAssertThrowsError(try engine.deleteServer(store: store, deleteGameData: true, saveProfiles: { _ in throw EngineError("fixture failure") }))
        XCTAssertEqual(try store.load(), profiles)
        XCTAssertEqual(try String(contentsOf: engine.world.appendingPathComponent("world")), "world-progress")
        XCTAssertEqual(try String(contentsOf: engine.home.appendingPathComponent("cache/ubuntu.img")), "reusable")
    }

    func testDeletionReportsCleanupFailureWithoutRestoringRemovedProfile() throws {
        let (_, engine, store, profiles) = try fixture()
        let result = try engine.deleteServer(store: store, saveProfiles: store.save, removeInstallation: { _ in throw EngineError("fixture cleanup failure") })
        XCTAssertEqual(result.remaining, [profiles[1]])
        XCTAssertEqual(try store.load(), [profiles[1]])
        XCTAssertTrue(result.cleanupWarning?.contains("fixture cleanup failure") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: engine.home.path))
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(result.savedData).appendingPathComponent("data/server/savegame/world")), "world-progress")
    }

    func testShutdownFailureLeavesServerAndDataRegistered() throws {
        let (_, engine, store, profiles) = try fixture()
        try "#!/bin/sh\nif [ \"$1\" = list ]; then echo Running; else exit 13; fi\n".write(to: engine.lima, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.lima.path)
        XCTAssertThrowsError(try engine.deleteServer(store: store, deleteGameData: true))
        XCTAssertEqual(try store.load(), profiles)
        XCTAssertEqual(try String(contentsOf: engine.world.appendingPathComponent("world")), "world-progress")
    }

}
