import XCTest
@testable import EnshroudedCore

final class ServerUninstallTests: XCTestCase {
    private func fixture(failDelete: Bool = false, failStop: Bool = false) throws -> Engine {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for path in ["Bundle/Runtime", "Bundle/Lima/bin", "lima/engine", "data/server/savegame", "data/previous-install/savegame", "data/backups", "cache"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        for file in ["guest.sh", "stop-server.py", "download.py"] { try Data().write(to: root.appendingPathComponent("Bundle/Runtime/" + file)) }
        for file in ["lima/engine/lima.yaml", "cache/ubuntu.img", "data/server/enshrouded_server.exe", "data/previous-install/old.exe"] {
            try Data("binary".utf8).write(to: root.appendingPathComponent(file))
        }
        for file in ["data/server/savegame/world", "data/previous-install/savegame/world", "data/backups/keep"] {
            try Data("saved".utf8).write(to: root.appendingPathComponent(file))
        }
        try Data("{}".utf8).write(to: root.appendingPathComponent("data/server/enshrouded_server.json"))
        let script = """
        #!/bin/sh
        case "$1" in
          list) if [ -f "$LIMA_HOME/stopped" ]; then echo Stopped; else echo Running; fi;;
          shell) if [ "$5" = status ]; then echo INSTALLED; else exit \(failStop ? 1 : 0); fi;;
          stop) touch "$LIMA_HOME/stopped";;
          delete) \(failDelete ? "exit 1" : "rm -rf \"$LIMA_HOME/engine\"");;
        esac
        """
        let engine = Engine(home: root, resources: root.appendingPathComponent("Bundle"))
        try script.write(to: engine.lima, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.lima.path)
        return engine
    }
    func testUninstallRemovesToolsAndBinariesButPreservesSavedData() throws {
        let engine = try fixture(); defer { try? FileManager.default.removeItem(at: engine.home) }
        try engine.uninstallServerFiles { _ in }
        for path in ["data/server/savegame/world", "data/previous-install/savegame/world", "data/backups/keep", "data/server/enshrouded_server.json"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: engine.home.appendingPathComponent(path).path), path)
        }
        for path in ["lima/engine", "runtime", "cache", "data/server/enshrouded_server.exe", "data/previous-install/old.exe"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: engine.home.appendingPathComponent(path).path), path)
        }
        XCTAssertEqual(try engine.status(), "NOT_INSTALLED")
        XCTAssertFalse(engine.backups().isEmpty)
        try engine.uninstallServerFiles { _ in } // repeat is safe and preserves data
    }
    func testFailedShutdownOrVMDeletionPreservesFiles() throws {
        for stop in [true, false] {
            let engine = try fixture(failDelete: !stop, failStop: stop)
            defer { try? FileManager.default.removeItem(at: engine.home) }
            XCTAssertThrowsError(try engine.uninstallServerFiles { _ in })
            XCTAssertTrue(FileManager.default.fileExists(atPath: engine.data.appendingPathComponent("server/enshrouded_server.exe").path))
            XCTAssertEqual(try String(contentsOf: engine.data.appendingPathComponent("server/savegame/world")), "saved")
        }
    }
    func testLinkedServerFolderIsRejectedBeforeDeletion() throws {
        let engine = try fixture(); defer { try? FileManager.default.removeItem(at: engine.home) }
        let outside = engine.home.appendingPathComponent("other-server")
        try FileManager.default.moveItem(at: engine.data.appendingPathComponent("server"), to: outside)
        try FileManager.default.createSymbolicLink(at: engine.data.appendingPathComponent("server"), withDestinationURL: outside)
        XCTAssertThrowsError(try engine.uninstallServerFiles { _ in })
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.appendingPathComponent("enshrouded_server.exe").path))
    }
}
