import AppKit
import SwiftUI

/// One independent log window per server, shared by every log entry point.
@MainActor final class LogsWindowController: NSWindowController, NSWindowDelegate {
    private static var openWindows: [String: LogsWindowController] = [:]
    private let serverID: String

    static func show(model: Model) {
        let key = model.engine.home.path
        let controller = openWindows[key] ?? LogsWindowController(model: model)
        openWindows[key] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(model: Model) {
        serverID = model.engine.home.path
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Server Logs — \(model.name)"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 620, height: 400)
        window.center()
        window.setFrameAutosaveName("ServerLogs-\(serverID)")
        window.contentView = NSHostingView(rootView: LogsView(model: model, close: { [weak window] in window?.performClose(nil) }))
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        // Release the view so its log polling task is cancelled on close.
        window?.contentView = nil
        Self.openWindows.removeValue(forKey: serverID)
    }
}
