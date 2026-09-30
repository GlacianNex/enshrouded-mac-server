import XCTest
import AppKit
import SwiftUI
@testable import EnshroudedManager

final class SetupPresentationTests: XCTestCase {
    @MainActor func testDownloadSectionTitleRowExpandsAndCollapses() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 650), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        var expanded = false
        let binding = Binding(get: { expanded }, set: { expanded = $0 })
        let host = NSHostingView(rootView: SetupDownloadInfo(expanded: binding).frame(width: 550).fixedSize(horizontal: false, vertical: true))
        // Fit the exact content so the disclosure header is the last row when collapsed.
        let height = host.fittingSize.height
        window.setContentSize(NSSize(width: 550, height: height))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        for expected in [true, false] {
            // The two-line explanatory text sits above the disclosure header.
            // Retain the collapsed frame so its title row stays at y=18.
            let point = NSPoint(x: 220, y: 18)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                NSApp.postEvent(event, atStart: false)
            }
            let deadline = Date().addingTimeInterval(1)
            InstallerEventLoop.wait { expanded == expected || Date() >= deadline }
            XCTAssertEqual(expanded, expected, "Clicking the download title row must toggle its binding")
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @MainActor func testSetupWindowShrinksToContentAndCapsLongContentToScreen() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 740), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let sizing = ContentFittingWindow.SizingView()
        window.contentView = sizing
        sizing.fit(480)
        XCTAssertEqual(window.contentLayoutRect.height, 480, accuracy: 1)
        sizing.fit(320)
        XCTAssertEqual(window.contentLayoutRect.height, 320, accuracy: 1, "A shorter error/progress state must not retain the original form's empty height")
        sizing.fit(5000)
        let available = try XCTUnwrap(window.screen ?? NSScreen.main).visibleFrame.height
        XCTAssertLessThanOrEqual(window.frame.height, available)
    }
}
