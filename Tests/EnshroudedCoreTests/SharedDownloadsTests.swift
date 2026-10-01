import XCTest
@testable import EnshroudedCore

final class SharedDownloadsTests: XCTestCase {
    private func fixture() throws -> (URL, Engine, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        return (root, Engine(home: root.appendingPathComponent("home"), resources: root, sharedDownloads: root.appendingPathComponent("shared")), source, destination)
    }

    func testReuseCopiesKnownBinariesWithoutWorldsPasswordsOrConfiguration() throws {
        let (_, engine, source, destination) = try fixture()
        let binaries = ["enshrouded_server.exe", "enshrouded_server.kfc", "enshrouded_server.kfc_resources", "enshrouded_server_0000.dat", "steam_api64.dll", ".DepotDownloader/depot_2278520.manifest", "_CommonRedist/readme.txt"]
        let privateFiles = ["enshrouded_server.json", "savegame/world", "config/bans.json", "logs/private.log", "password.txt", "profile.json", "unrelated.dat"]
        for path in binaries + privateFiles {
            let file = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(path.utf8).write(to: file)
        }
        try engine.copyReusableServerFiles(from: source, to: destination)
        for path in binaries { XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent(path)), path) }
        for path in privateFiles { XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent(path).path), path) }
        try Data("existing version".utf8).write(to: destination.appendingPathComponent("enshrouded_server.exe"))
        try engine.copyReusableServerFiles(from: source, to: destination)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("enshrouded_server.exe")), "existing version")
    }

    func testReusableFileAndNestedSymlinksAreRejected() throws {
        for nested in [false, true] {
            let (root, engine, source, destination) = try fixture()
            let outside = root.appendingPathComponent("private")
            try Data("private data".utf8).write(to: outside)
            let link = source.appendingPathComponent(nested ? "_CommonRedist/link" : "enshrouded_server.exe")
            try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
            XCTAssertThrowsError(try engine.copyReusableServerFiles(from: source, to: destination))
            XCTAssertEqual(try String(contentsOf: outside), "private data")
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent(nested ? "_CommonRedist/link" : "enshrouded_server.exe").path))
        }
    }

    func testSharedDownloadLockRejectsConcurrentPreparationAndReleasesAfterFailure() throws {
        let (_, engine, _, _) = try fixture()
        try engine.withSharedDownloads {
            XCTAssertThrowsError(try engine.withSharedDownloads { XCTFail("Concurrent shared downloads must not enter") })
        }
        XCTAssertThrowsError(try engine.withSharedDownloads { throw EngineError("fixture failure") })
        XCTAssertNoThrow(try engine.withSharedDownloads { })
    }
    func testClearDownloadsKeepsServersAndPreventsLegacyReseeding() throws {
        let (root, engine, source, _) = try fixture()
        let shared = try XCTUnwrap(engine.sharedDownloads)
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        for name in ["ubuntu.img", "components/archive", "packages/package.deb", "server/enshrouded_server.exe"] {
            let file = shared.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("cached".utf8).write(to: file)
        }
        let binary = source.appendingPathComponent("data/server/enshrouded_server.exe")
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("installed".utf8).write(to: binary)
        let store = ProfileStore(registry: root.appendingPathComponent("profiles.json"))
        try store.save([ServerProfile(id: "donor", name: "Existing", home: source.path, port: 15637)])
        try engine.withSharedDownloads { XCTAssertThrowsError(try engine.clearSharedDownloads()) }
        XCTAssertTrue(engine.canReuseInstallation(at: source))
        try engine.clearSharedDownloads()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: shared.path), [])
        XCTAssertEqual(try String(contentsOf: binary), "installed")
        XCTAssertFalse(engine.canReuseInstallation(at: source))
        XCTAssertTrue(engine.canReuseInstallation(at: root.appendingPathComponent("future-server")))
        try engine.prepareSharedDownloads { _ in }
        XCTAssertFalse(FileManager.default.fileExists(atPath: engine.data.appendingPathComponent("server/enshrouded_server.exe").path))
        // Downloads from future setups can still be shared normally.
        try FileManager.default.createDirectory(at: engine.data.appendingPathComponent("server"), withIntermediateDirectories: true)
        try Data("fresh".utf8).write(to: engine.data.appendingPathComponent("server/enshrouded_server.exe"))
        try engine.publishSharedServerFiles()
        XCTAssertEqual(try String(contentsOf: shared.appendingPathComponent("server/enshrouded_server.exe")), "fresh")
    }

    func testClearingAllDownloadCachesPreservesInstalledServerFiles() throws {
        let (root, engine, source, _) = try fixture()
        let updateCache = root.appendingPathComponent("manager-updates")
        let store = ProfileStore(registry: root.appendingPathComponent("profiles.json"))
        try store.save([ServerProfile(id: "source", name: "Existing", home: source.path, port: 15637)])
        let caches = [source.appendingPathComponent("cache"), engine.home.appendingPathComponent("cache"), updateCache]
        for cache in caches {
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try Data("download".utf8).write(to: cache.appendingPathComponent("archive"))
        }
        let protected = ["lima/engine/disk", "data/server/savegame/world", "data/server/enshrouded_server.exe", "data/server/enshrouded_server.json", "data/backups/world"]
        for name in protected {
            let file = source.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("keep".utf8).write(to: file)
        }
        try engine.clearSharedDownloads(managerUpdateCache: updateCache)
        for cache in caches { XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path)) }
        for name in protected { XCTAssertEqual(try String(contentsOf: source.appendingPathComponent(name)), "keep") }
    }

}
