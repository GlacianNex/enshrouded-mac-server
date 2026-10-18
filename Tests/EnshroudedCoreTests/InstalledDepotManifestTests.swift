import XCTest
@testable import EnshroudedCore

final class InstalledDepotManifestTests: XCTestCase {
    // Real three-depot record from an installation with four cached game manifests.
    private var fixture: Data {
        let hex = "013000cfff0a0d08ec071093e287f2d6ad8bc4690a0e08fdfc0d10b6eda2bfeac1b5ec4f0a0f08f9888b0110c6dcbf8effb3cfd85e"
        return Data(stride(from: 0, to: hex.count, by: 2).map { index in
            let start = hex.index(hex.startIndex, offsetBy: index)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        })
    }
    func testReadsActualInstalledManifestNotAnotherDepot() {
        XCTAssertEqual(InstalledDepotManifest.read(fixture), "6823302667609042502")
        XCTAssertNil(InstalledDepotManifest.read(fixture, depot: 123))
    }
    func testRejectsMalformedAndIncompleteRecords() {
        for bytes in [Data(), Data("invalid".utf8), Data(fixture.dropLast()), stored([10, 127]), stored([10, 2, 8, 128])] {
            XCTAssertNil(InstalledDepotManifest.read(bytes))
        }
        let key: [UInt8] = [8, 249, 136, 139, 1, 16]
        for invalid: [UInt8] in [[0], Array(repeating: 255, count: 9) + [1]] {
            let entry = key + invalid
            XCTAssertNil(InstalledDepotManifest.read(stored([10, UInt8(entry.count)] + entry)))
        }
    }
    func testConfigOverridesOldReceiptsAndMultipleCachedManifests() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let engine = Engine(home: home, resources: home)
        let folder = engine.data.appendingPathComponent("server/.DepotDownloader")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for id in ["2174935030716737236", "6823302667609042502", "9999999999999999999"] {
            try Data().write(to: folder.appendingPathComponent("2278521_\(id).manifest"))
        }
        try Data("123\n".utf8).write(to: engine.data.appendingPathComponent("installed-manifest.txt"))
        try fixture.write(to: folder.appendingPathComponent("depot.config"))
        XCTAssertEqual(engine.installedManifest, "6823302667609042502")
        XCTAssertFalse(ServerRelease(installed: engine.installedManifest, latest: "6823302667609042502").updateAvailable)
        XCTAssertTrue(ServerRelease(installed: engine.installedManifest, latest: "999").updateAvailable)
        try Data("broken".utf8).write(to: folder.appendingPathComponent("depot.config"))
        XCTAssertNil(engine.installedManifest, "An invalid installation record must not fall back to stale receipts")
    }
    func testInstallerRecordsBothCachedAndDownloadedManifestOutput() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("Runtime/guest.sh"))
        let assignment = try XCTUnwrap(script.components(separatedBy: "\n").first { $0.contains("game_manifest=$(sed") })
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent("logs"), withIntermediateDirectories: true)
        for line in ["Already have manifest 6823302667609042502 for depot 2278521.", "Got manifest for depot 2278521 from app 2278520, manifest 6823302667609042502, created today"] {
            try Data(("Already have manifest 111 for depot 1004.\n" + line + "\n").utf8).write(to: home.appendingPathComponent("logs/latest-install.log"))
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.environment = ["DATA": home.path, "PATH": "/usr/bin:/bin"]
            p.arguments = ["-c", assignment + "\nprintf '%s' \"$game_manifest\""]
            let pipe = Pipe(); p.standardOutput = pipe
            try p.run(); let output = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            XCTAssertEqual(p.terminationStatus, 0)
            XCTAssertEqual(String(data: output, encoding: .utf8), "6823302667609042502")
        }
    }
    private func stored(_ bytes: [UInt8]) -> Data {
        let count = UInt16(bytes.count), inverse = ~count
        return Data([1, UInt8(count & 255), UInt8(count >> 8), UInt8(inverse & 255), UInt8(inverse >> 8)] + bytes)
    }
}
