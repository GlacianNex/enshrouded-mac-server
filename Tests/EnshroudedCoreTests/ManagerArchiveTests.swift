import XCTest
@testable import EnshroudedCore

final class ManagerArchiveTests: XCTestCase {
    let root = ManagerArchive.root
    var base: [ManagerArchiveEntry] {
        [.init(path: root + "/Contents/Info.plist", kind: .file, size: 10),
         .init(path: root + "/Contents/MacOS/EnshroudedManager", kind: .file, size: 20),
         .init(path: root + "/Contents/Resources/Lima/share/lima/templates/", kind: .directory),
         .init(path: root + "/Contents/Resources/Lima/share/lima/templates/default.yaml", kind: .file, size: 5)]
    }
    func testLimaInternalDocumentationLinkIsAccepted() throws {
        try ManagerArchive.validate(base + [.init(path: root + "/Contents/Resources/Lima/share/doc/lima/templates", kind: .symbolicLink, linkTarget: "../../lima/templates")])
    }
    func testEscapingTargetsAndLinkChainsAreRejectedBeforeExtraction() {
        for target in ["/tmp/outside", "../../../../../../../../outside", "missing"] {
            XCTAssertThrowsError(try ManagerArchive.validate(base + [.init(path: root + "/Contents/link", kind: .symbolicLink, linkTarget: target)]))
        }
        XCTAssertThrowsError(try ManagerArchive.validate(base + [
            .init(path: root + "/Contents/first", kind: .symbolicLink, linkTarget: "second"),
            .init(path: root + "/Contents/second", kind: .symbolicLink, linkTarget: "Info.plist")]))
    }
    func testFileBelowSymlinkAndPathCollisionsAreRejected() {
        XCTAssertThrowsError(try ManagerArchive.validate(base + [
            .init(path: root + "/Contents/link", kind: .symbolicLink, linkTarget: "Resources/Lima/share/lima/templates"),
            .init(path: root + "/Contents/link/injected", kind: .file)]))
        XCTAssertThrowsError(try ManagerArchive.validate(base + [.init(path: root + "/Contents/info.plist", kind: .file)]))
        for path in ["/tmp/file", root + "/../outside", root + "/Contents/./Info.plist", root + "/Contents/evil\nfile", "Other.app/file"] {
            XCTAssertThrowsError(try ManagerArchive.validate(base + [.init(path: path, kind: .file)]))
        }
    }
    func testMissingExecutableAndExpansionLimitsAreRejected() {
        XCTAssertThrowsError(try ManagerArchive.validate(Array(base.dropFirst(2))))
        XCTAssertThrowsError(try ManagerArchive.validate(base + [.init(path: root + "/large", kind: .file, size: 1_000_000_001)]))
    }
}
