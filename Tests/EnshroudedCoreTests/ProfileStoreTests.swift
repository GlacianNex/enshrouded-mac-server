import XCTest
@testable import EnshroudedCore

final class ProfileStoreTests: XCTestCase {
    private func fixture() throws -> (URL, ProfileStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, ProfileStore(registry: root.appendingPathComponent("profiles.json")))
    }
    private func profile(_ id: String, _ home: URL, _ port: Int = 15637) -> ServerProfile {
        ServerProfile(id: id, name: id, home: home.path, port: port)
    }
    func testIndependentSiblingHomesRoundTripAndRejectFailedSaveWithoutChanges() throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let valid = [profile("one", root.appendingPathComponent("server")), profile("two", root.appendingPathComponent("server-two"), 15638)]
        try store.save(valid); XCTAssertEqual(try store.load(), valid)
        let before = try Data(contentsOf: store.registry)
        XCTAssertThrowsError(try store.save(valid + [profile("three", root.appendingPathComponent("third"))]))
        XCTAssertEqual(try Data(contentsOf: store.registry), before)
    }
    func testCanonicalAliasesAndNestedHomesCannotRepresentIndependentServers() throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("server")
        let first = profile("one", home)
        let alias = ServerProfile(id: "two", name: "two", home: home.path + "/../server", port: 15638)
        XCTAssertThrowsError(try store.save([first, alias]))
        XCTAssertThrowsError(try store.save([first, profile("two", home.appendingPathComponent("child"), 15638)]))
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: home)
        XCTAssertThrowsError(try store.save([first, profile("two", link, 15638)]))
    }
    func testLoadValidatesStoredProfilesWithoutRewritingInvalidRegistry() throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let invalid = [profile("one", root.appendingPathComponent("a")), profile("two", root.appendingPathComponent("b"))]
        let original = try JSONEncoder().encode(invalid)
        try original.write(to: store.registry)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.registry), original)
    }
    func testInvalidIdentityRelativeAndRootHomesAreRejected() throws {
        let (root, store) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try store.save([profile("", root.appendingPathComponent("a"))]))
        XCTAssertThrowsError(try store.save([profile("root", URL(fileURLWithPath: "/"))]))
        XCTAssertThrowsError(try store.save([ServerProfile(id: "relative", name: "relative", home: "somewhere", port: 15637)]))
        XCTAssertEqual(try store.load(), [])
    }
}
