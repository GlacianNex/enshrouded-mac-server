import XCTest
@testable import EnshroudedCore

final class SetupDownloadTests: XCTestCase {
    func testPinnedImageAvoidsUbuntusHTTPOnlyArchiveRedirect() {
        XCTAssertEqual(Engine.environmentImage.scheme, "https")
        XCTAssertEqual(Engine.environmentImage.host, "s3.us-east-1.amazonaws.com")
        XCTAssertTrue(Engine.environmentImage.path.hasPrefix("/cloud-images-archive.ubuntu.com/releases/"))
        XCTAssertEqual(Engine.environmentDigest.count, 64)
    }
    func testInsecureDownloadFailsBeforeCreatingFiles() {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("ubuntu.img")
        XCTAssertThrowsError(try SetupDownload.fetch(URL(string: "http://example.invalid/image")!, destination: target, sha256: "unused", output: { _ in })) { error in
            XCTAssertTrue(error.localizedDescription.contains("HTTPS"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.deletingLastPathComponent().path))
    }
    func testFreshPinnedImageDownloadOverURLSessionHTTPS() throws {
        guard let directory = ProcessInfo.processInfo.environment["ESM_VERIFY_IMAGE_DOWNLOAD"] else {
            throw XCTSkip("Opt-in live 616 MB download; unit tests stay offline")
        }
        let destination = URL(fileURLWithPath: directory).appendingPathComponent("ubuntu.img")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), "Live verification must not use a cached image")
        try SetupDownload.fetch(Engine.environmentImage, destination: destination, sha256: Engine.environmentDigest, output: { _ in })
        XCTAssertEqual(try SetupDownload.digest(destination), Engine.environmentDigest)
    }
}
