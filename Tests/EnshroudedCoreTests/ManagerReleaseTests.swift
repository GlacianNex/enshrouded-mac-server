import XCTest
@testable import EnshroudedCore

final class ManagerReleaseTests: XCTestCase {
    private func release(version: String = "v1.2.0", draft: Bool = false, prerelease: Bool = false,
                         url: String? = nil, digest: String? = "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                         size: Int = 3) throws -> ManagerRelease {
        var asset: [String: Any] = ["name": "Enshrouded-Server-Manager-for-Mac.zip", "size": size,
            "browser_download_url": url ?? "https://github.com/GlacianNex/enshrouded-mac-server/releases/download/\(version)/Enshrouded-Server-Manager-for-Mac.zip"]
        if let digest { asset["digest"] = digest }
        return try JSONDecoder().decode(ManagerRelease.self, from: JSONSerialization.data(withJSONObject:
            ["tag_name": version, "draft": draft, "prerelease": prerelease, "assets": [asset]]))
    }
    func testStableVersionsOnlyAndNumericOrdering() throws {
        XCTAssertTrue(try release(version: "v1.10.0").isNewer(than: "1.9.0"))
        XCTAssertFalse(try release().isNewer(than: "1.2.0"))
        XCTAssertFalse(try release().isNewer(than: "2.0.0"))
        XCTAssertFalse(try release(draft: true).isNewer(than: "1.0.0"))
        XCTAssertFalse(try release(prerelease: true).isNewer(than: "1.0.0"))
        XCTAssertFalse(try release(version: "v1.3.0-beta").isNewer(than: "1.0.0"))
        XCTAssertFalse(try release().isNewer(than: "Development"))
    }
    func testRejectsUntrustedOrUnverifiableAssets() throws {
        XCTAssertThrowsError(try release(url: "https://example.com/update.zip").downloadAsset())
        XCTAssertThrowsError(try release(url: "https://github.com/other/repo/releases/download/v1.2.0/Enshrouded-Server-Manager-for-Mac.zip").downloadAsset())
        XCTAssertThrowsError(try release(digest: nil).downloadAsset())
        XCTAssertThrowsError(try release(digest: "sha256:invalid").downloadAsset())
        XCTAssertThrowsError(try release(size: 256_000_001).downloadAsset())
        XCTAssertThrowsError(try release(prerelease: true).downloadAsset())
    }
    func testRejectsCredentialsPortsQueriesAndFragments() throws {
        let path = "/GlacianNex/enshrouded-mac-server/releases/download/v1.2.0/Enshrouded-Server-Manager-for-Mac.zip"
        for url in ["http://github.com" + path, "https://user@github.com" + path,
                    "https://github.com:443" + path, "https://github.com" + path + "?other=1",
                    "https://github.com" + path + "#other"] {
            XCTAssertThrowsError(try release(url: url).downloadAsset(), url)
        }
        XCTAssertThrowsError(try release(draft: true).downloadAsset())
        XCTAssertThrowsError(try release(size: 0).downloadAsset())
        XCTAssertThrowsError(try release(size: -1).downloadAsset())
        XCTAssertNoThrow(try release(size: 256_000_000).downloadAsset())
    }
    func testChecksumAndSizeMustMatchBeforeExtraction() throws {
        let value = try release()
        XCTAssertNoThrow(try value.verifyDownload(Data("abc".utf8)))
        XCTAssertThrowsError(try value.verifyDownload(Data("abd".utf8)))
        XCTAssertThrowsError(try value.verifyDownload(Data("abcd".utf8)))
    }
}
