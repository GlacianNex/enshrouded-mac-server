import XCTest
import AppKit
@testable import EnshroudedManager

final class InstallerEventLoopTests: XCTestCase {
    @MainActor func testLogButtonReceivesMouseEventsWhileInstallerWaitsForWorker() throws {
        _ = NSApplication.shared
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".log")
        try Data("Isolated installer log".utf8).write(to: log)
        defer { try? FileManager.default.removeItem(at: log) }
        let progress = ManagerInstallProgressWindow(logURL: log)
        defer { LogsWindowController.close(updateLog: log) }
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
        InstallerEventLoop.wait { (workerFinished && NSApp.windows.contains { $0.isVisible && $0.title == "Manager Update Log" }) || Date() >= deadline }
        // Drain anything left behind so a failing regression cannot click later tests.
        while NSApp.nextEvent(matching: [.leftMouseDown, .leftMouseUp], until: .distantPast, inMode: .default, dequeue: true) != nil {}
        XCTAssertTrue(workerFinished, "The UI wait must also service background completion on the main queue")
        let viewer = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.title == "Manager Update Log" })
        XCTAssertTrue(viewer.styleMask.contains(.resizable))
        XCTAssertNil(viewer.sheetParent)
        let content = viewer.contentView
        button.performClick(nil)
        XCTAssertEqual(NSApp.windows.filter { $0.isVisible && $0.title == "Manager Update Log" }.count, 1)
        XCTAssertTrue(viewer.contentView === content, "Repeated clicks must preserve the existing viewer and its filters")
    }
    @MainActor func testBuiltInUpdateViewerReadsExactFileAndRefreshesAfterFileAppears() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let log = directory.appendingPathComponent("installer-test.log")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { LogsWindowController.close(updateLog: log); try? FileManager.default.removeItem(at: directory) }
        LogsWindowController.show(updateLog: log)
        let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.title == "Manager Update Log" })
        @MainActor func text(_ view: NSView) -> String {
            if let editor = view as? NSTextView, !editor.isEditable { return editor.string }
            return view.subviews.map(text).joined(separator: "\n")
        }
        @MainActor func waitFor(_ expected: String) async throws {
            for _ in 0..<60 {
                if text(window.contentView!).contains(expected) { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTFail("Built-in update viewer did not display: " + expected)
        }
        try await waitFor("No manager activity recorded yet.")
        try Data("First update stage\n".utf8).write(to: log)
        try await waitFor("First update stage")
        try Data("First update stage\nSecond update stage\n".utf8).write(to: log, options: .atomic)
        try await waitFor("Second update stage")
        XCTAssertTrue(text(window.contentView!).contains("First update stage"))
        window.close()
        XCTAssertNil(window.contentView)
    }

}
