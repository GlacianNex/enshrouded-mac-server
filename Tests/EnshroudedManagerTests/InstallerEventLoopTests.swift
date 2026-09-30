import XCTest
import AppKit
@testable import EnshroudedManager

final class InstallerEventLoopTests: XCTestCase {
    @MainActor func testLogButtonReceivesMouseEventsWhileInstallerWaitsForWorker() throws {
        _ = NSApplication.shared
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".log")
        try Data("Isolated installer log".utf8).write(to: log)
        defer { try? FileManager.default.removeItem(at: log) }
        var opened: URL?
        let progress = ManagerInstallProgressWindow(logURL: log, openURL: { opened = $0; return true })
        defer { progress.close() }
        let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.title == "Updating Enshrouded Server Manager" })
        let button = try XCTUnwrap(window.contentView?.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Open Update Log" })
        window.displayIfNeeded()
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        // Real queued events, not performClick: the regression is event dispatch
        // before NSApplication.run(), not the button's target/action wiring.
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            NSApp.postEvent(event, atStart: false)
        }
        var workerFinished = false
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            DispatchQueue.main.async { workerFinished = true }
        }
        let deadline = Date().addingTimeInterval(2)
        InstallerEventLoop.wait { (workerFinished && opened != nil) || Date() >= deadline }
        // Drain anything left behind so a failing regression cannot click later tests.
        while NSApp.nextEvent(matching: [.leftMouseDown, .leftMouseUp], until: .distantPast, inMode: .default, dequeue: true) != nil {}
        XCTAssertTrue(workerFinished, "The UI wait must also service background completion on the main queue")
        XCTAssertEqual(opened, log, "The log button must receive input while installation is still waiting")
    }
}
