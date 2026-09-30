import XCTest
@testable import EnshroudedCore

final class WorldImportSourceTests: XCTestCase {
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }
    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    func testFileAndNestedFolderKeepWorldFamilyAvailable() throws {
        let root = try temporary(), primary = root.appendingPathComponent("export/savegames/3bd85c7d")
        try write("world", to: primary); try write("index", to: primary.appendingPathExtension("ignored"))
        try write("backup", to: primary.deletingLastPathComponent().appendingPathComponent("3bd85c7d-1"))
        for source in [root, primary] {
            try WorldImportSource.withPreparedWorld(at: source) { resolved in
                XCTAssertEqual(resolved.resolvingSymlinksInPath(), primary.resolvingSymlinksInPath())
                XCTAssertEqual(try String(contentsOf: resolved), "world")
                XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.path + "-1"))
            }
        }
    }
    func testMultipleWorldsFailBeforeImportButExplicitFileWorks() throws {
        let root = try temporary()
        for name in ["3bd85c7d", "3ad85aea"] { try write("world", to: root.appendingPathComponent(name)) }
        var called = false
        XCTAssertThrowsError(try WorldImportSource.withPreparedWorld(at: root) { _ in called = true }) {
            XCTAssertTrue($0.localizedDescription.contains("multiple worlds"))
        }
        XCTAssertFalse(called)
        try WorldImportSource.withPreparedWorld(at: root.appendingPathComponent("3bd85c7d")) { _ in called = true }
        XCTAssertTrue(called)
    }
    func testZIPNestedWorldFamilyAndTemporaryCleanup() throws {
        let root = try temporary(), archive = root.appendingPathComponent("world.zip")
        try zip([("export/3bd85c7d", "world", 0o100644), ("export/3bd85c7d-index", "index", 0o100644)]).write(to: archive)
        var prepared: URL?
        try WorldImportSource.withPreparedWorld(at: archive) { file in
            prepared = file
            XCTAssertEqual(try String(contentsOf: file), "world")
            XCTAssertEqual(try String(contentsOfFile: file.path + "-index"), "index")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(prepared).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
    }
    func testCleanupWhenImportTransactionThrows() throws {
        let archive = try temporary().appendingPathComponent("world.zip")
        try zip([("3bd85c7d", "world", 0o100644)]).write(to: archive)
        var prepared: URL?
        XCTAssertThrowsError(try WorldImportSource.withPreparedWorld(at: archive) { file in
            prepared = file; throw EngineError("Import rejected")
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(prepared).path))
    }
    func testUnsafeArchivesNeverInvokeImportOrChangeExistingWorld() throws {
        let root = try temporary(), archive = root.appendingPathComponent("world.zip"), existing = root.appendingPathComponent("existing/3ad85aea")
        try write("existing world", to: existing)
        let badEntries: [[(String, String, Int)]] = [
            [("../3bd85c7d", "world", 0o100644)], [("/3bd85c7d", "world", 0o100644)],
            [("folder/./3bd85c7d", "world", 0o100644)], [("folder\\3bd85c7d", "world", 0o100644)],
            [("3bd85c7d", "world", 0o120777)], [("3bd85c7d", "world", 0o010644)],
            [("3bd85c7d", "world", 0o100644), ("3BD85C7D", "world", 0o100644)],
            [("folder", "file", 0o100644), ("folder/3bd85c7d", "world", 0o100644)],
            [("3bd85c7d", "world", 0o100644), ("3ad85aea", "other", 0o100644)],
            [("3bd85c7d*", "world", 0o100644)]
        ]
        for entries in badEntries {
            try zip(entries).write(to: archive)
            XCTAssertThrowsError(try WorldImportSource.withPreparedWorld(at: archive) { _ in try self.write("changed", to: existing) })
            XCTAssertEqual(try String(contentsOf: existing), "existing world")
        }
    }
    func testCorruptionAndFalseExpansionSizeAreRejected() throws {
        let archive = try temporary().appendingPathComponent("world.zip")
        let original = zip([("3bd85c7d", "world", 0o100644)])
        var corrupt = original; corrupt[38] ^= 1
        var tooSmall = original
        let central = 30 + 8 + 5
        tooSmall[central + 24] = 1
        var bomb = original
        for i in 0..<4 { bomb[central + 24 + i] = 255 }
        for data in [corrupt, tooSmall, bomb, Data(original.dropLast())] {
            try data.write(to: archive)
            XCTAssertThrowsError(try WorldImportSource.withPreparedWorld(at: archive) { _ in XCTFail("Invalid archive reached import") })
        }
    }
    func testFolderLinksAndEmptyWorldAreRejected() throws {
        let root = try temporary(), file = root.appendingPathComponent("3bd85c7d")
        try write("", to: file)
        XCTAssertThrowsError(try WorldImportSource.withPreparedWorld(at: file) { _ in XCTFail() })
        try write("world", to: file)
        try FileManager.default.createSymbolicLink(atPath: file.path + "-1", withDestinationPath: file.path)
        XCTAssertThrowsError(try WorldImportSource.withPreparedWorld(at: file) { _ in XCTFail() })
        XCTAssertThrowsError(try WorldImportSource.withPreparedWorld(at: root) { _ in XCTFail() })
    }
    func testDeflatedSystemArchiveAndEntryLimit() throws {
        let root = try temporary(), archive = root.appendingPathComponent("world.zip")
        let file = root.appendingPathComponent("3bd85c7d")
        let contents = String(repeating: "world data", count: 1000)
        try write(contents, to: file)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", archive.path, "3bd85c7d"]
        process.currentDirectoryURL = root
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        try WorldImportSource.withPreparedWorld(at: archive) { XCTAssertEqual(try String(contentsOf: $0), contents) }
        let oversized = zip((0...WorldImportSource.maximumEntries).map { ("file\($0)", "", 0o100644) })
        XCTAssertThrowsError(try WorldImportSource.zipEntries(oversized))
    }
    private func zip(_ entries: [(String, String, Int)]) -> Data {
        func word(_ number: Int, _ bytes: Int) -> Data { Data((0..<bytes).map { UInt8(truncatingIfNeeded: number >> ($0 * 8)) }) }
        func crc(_ data: Data) -> Int {
            var value: UInt32 = 0xffffffff
            for byte in data { value ^= UInt32(byte); for _ in 0..<8 { value = (value >> 1) ^ (value & 1 == 1 ? 0xedb88320 : 0) } }
            return Int(value ^ 0xffffffff)
        }
        var local = Data(), central = Data()
        for (name, text, mode) in entries {
            let filename = Data(name.utf8), content = Data(text.utf8), checksum = crc(content), offset = local.count
            local += word(0x04034b50, 4) + word(20, 2) + Data(repeating: 0, count: 8)
            local += word(checksum, 4) + word(content.count, 4) + word(content.count, 4) + word(filename.count, 2) + word(0, 2) + filename + content
            central += word(0x02014b50, 4) + word(0x0314, 2) + word(20, 2) + Data(repeating: 0, count: 8)
            central += word(checksum, 4) + word(content.count, 4) + word(content.count, 4) + word(filename.count, 2)
            central += Data(repeating: 0, count: 8) + word(mode << 16, 4) + word(offset, 4) + filename
        }
        return local + central + word(0x06054b50, 4) + word(0, 4) + word(entries.count, 2) + word(entries.count, 2) + word(central.count, 4) + word(local.count, 4) + word(0, 2)
    }
}
