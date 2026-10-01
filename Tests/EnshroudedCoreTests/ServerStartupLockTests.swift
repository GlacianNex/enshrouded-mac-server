import XCTest
@testable import EnshroudedCore

final class ServerStartupLockTests: XCTestCase {
    private func lockURL() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root.appendingPathComponent("server-startup.lock")
    }

    func testSecondStartupWaitsUntilFirstFailsThenCanProceed() throws {
        let url = try lockURL()
        let firstEntered = expectation(description: "First startup entered")
        let secondWaiting = expectation(description: "Second startup queued")
        let firstFinished = expectation(description: "First startup failed")
        let secondFinished = expectation(description: "Second startup completed")
        let releaseFirst = DispatchSemaphore(value: 0)
        defer { releaseFirst.signal() }
        DispatchQueue.global().async {
            do {
                try ServerStartupLock.run(at: url, output: { _ in }) {
                    firstEntered.fulfill()
                    XCTAssertEqual(releaseFirst.wait(timeout: .now() + 5), .success)
                    throw EngineError("First startup failed")
                }
                XCTFail("Expected fixture failure")
            } catch { XCTAssertEqual(error.localizedDescription, "First startup failed") }
            firstFinished.fulfill()
        }
        wait(for: [firstEntered], timeout: 3)
        DispatchQueue.global().async {
            do {
                try ServerStartupLock.run(at: url, output: { message in
                    if message.hasPrefix("Waiting for another server") { secondWaiting.fulfill() }
                }) { }
            } catch { XCTFail(error.localizedDescription) }
            secondFinished.fulfill()
        }
        wait(for: [secondWaiting], timeout: 3)
        releaseFirst.signal()
        wait(for: [firstFinished, secondFinished], timeout: 3)
    }

    func testTimeoutDoesNotStartServerAndLockRemainsReusable() throws {
        let url = try lockURL()
        try ServerStartupLock.run(at: url, output: { _ in }) {
            XCTAssertThrowsError(try ServerStartupLock.run(at: url, timeout: 0, output: { _ in }) {
                XCTFail("A waiting startup must not overlap the active one")
            })
        }
        XCTAssertNoThrow(try ServerStartupLock.run(at: url, output: { _ in }) { })
    }

    func testLinkedLockIsRejectedWithoutChangingTarget() throws {
        let url = try lockURL(), target = url.appendingPathExtension("target")
        try Data("unchanged".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        XCTAssertThrowsError(try ServerStartupLock.run(at: url, output: { _ in }) { XCTFail("Linked lock accepted") })
        XCTAssertEqual(try String(contentsOf: target), "unchanged")
    }

    func testEngineStartupUsesSharedQueueBeforeTouchingRuntime() throws {
        let url = try lockURL(), root = url.deletingLastPathComponent()
        let engine = Engine(home: root.appendingPathComponent("server-b"), resources: root.appendingPathComponent("missing-resources"), sharedDownloads: root.appendingPathComponent("downloads"))
        let queued = expectation(description: "Engine waits for another server")
        let finished = expectation(description: "Engine releases slot on failure")
        try ServerStartupLock.run(at: url, output: { _ in }) {
            DispatchQueue.global().async {
                do {
                    try engine.performLocked("start") { message in
                        if message.hasPrefix("Waiting for another server") { queued.fulfill() }
                    }
                    XCTFail("Missing runtime must fail")
                } catch { }
                finished.fulfill()
            }
            wait(for: [queued], timeout: 3)
            XCTAssertFalse(FileManager.default.fileExists(atPath: engine.home.path))
        }
        wait(for: [finished], timeout: 3)
        XCTAssertNoThrow(try ServerStartupLock.run(at: url, output: { _ in }) { })
    }

    func testQueuedProgressTransitionsIntoStartup() {
        var progress = ServerOperationProgress(action: "start")
        progress.consume("Waiting for another server to finish starting…\n")
        XCTAssertEqual(progress.title, "Waiting to Start")
        XCTAssertEqual(progress.message, "Waiting for another server to finish starting…")
        progress.consume("Starting server…\n")
        XCTAssertEqual(progress.title, "Start Server")
        XCTAssertFalse(progress.message.contains("another server"))
    }
}
