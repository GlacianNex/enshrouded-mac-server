import XCTest
import AppKit
@testable import EnshroudedManager

final class QuitWarningTests: XCTestCase {
    @MainActor func testNoticeDoesNotBlockAndClearsWhenWorkFinishes() async throws {
        let app = NSApplication.shared
        let delegate = ManagerAppDelegate()
        var operations = ["Test Server: Saving & stopping…"]
        ApplicationLifetime.activeOperations = { operations }
        ApplicationLifetime.allowTermination = false
        defer { delegate.dismissQuitNotice(); ApplicationLifetime.activeOperations = { [] } }
        XCTAssertEqual(delegate.applicationShouldTerminate(app), .terminateCancel)
        XCTAssertNil(app.modalWindow)
        XCTAssertTrue(delegate.quitNotice?.informativeText.contains("Test Server: Saving & stopping…") == true)
        let first = delegate.quitNotice
        XCTAssertEqual(delegate.applicationShouldTerminate(app), .terminateCancel)
        XCTAssertTrue(delegate.quitNotice === first)
        operations = ["Test Server: Starting…"]
        delegate.refreshQuitNotice()
        XCTAssertTrue(delegate.quitNotice?.informativeText.contains("Starting…") == true)
        operations = []
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertNil(delegate.quitNotice)
        XCTAssertEqual(delegate.applicationShouldTerminate(app), .terminateNow)
    }
    @MainActor func testUpdateRelaunchBypassDismissesNotice() {
        let app = NSApplication.shared
        let delegate = ManagerAppDelegate()
        ApplicationLifetime.activeOperations = { ["Updating manager…"] }
        ApplicationLifetime.allowTermination = false
        defer {
            delegate.dismissQuitNotice()
            ApplicationLifetime.activeOperations = { [] }
            ApplicationLifetime.allowTermination = false
        }
        XCTAssertEqual(delegate.applicationShouldTerminate(app), .terminateCancel)
        ApplicationLifetime.allowTermination = true
        XCTAssertEqual(delegate.applicationShouldTerminate(app), .terminateNow)
        XCTAssertNil(delegate.quitNotice)
    }
}
