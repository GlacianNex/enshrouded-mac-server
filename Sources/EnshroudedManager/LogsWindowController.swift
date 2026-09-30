import AppKit
import SwiftUI

/// One independent log window per source, shared by every log entry point.
@MainActor final class LogsWindowController: NSWindowController, NSWindowDelegate {
    private static var openWindows: [String: LogsWindowController] = [:]
    private let serverID: String
    private var showsSetup = false

    static func close(_ model: Model) { openWindows[model.engine.home.path]?.window?.performClose(nil) }
    static func show(model: Model) {
        let key = model.engine.home.path
        let setup = model.installationPending || model.setupProgress != nil
        if let existing = openWindows[key], existing.showsSetup != setup { existing.window?.close() }
        let controller = openWindows[key] ?? LogsWindowController(model: model)
        openWindows[key] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close(updateLog: URL) { openWindows["update:" + updateLog.standardizedFileURL.path]?.window?.performClose(nil) }
    static func show(updateLog: URL) {
        let key = "update:" + updateLog.standardizedFileURL.path
        let controller = openWindows[key] ?? LogsWindowController(key: key, title: "Manager Update Log") { close in
            AnyView(LogsView(updateLog: updateLog, close: close))
        }
        openWindows[key] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private convenience init(model: Model) {
        self.init(key: model.engine.home.path, title: "Server Logs — " + model.name) { close in
            AnyView(LogsView(model: model, close: close))
        }
        showsSetup = model.installationPending || model.setupProgress != nil
    }
    private init(key: String, title: String, content: (@escaping () -> Void) -> AnyView) {
        serverID = key
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 620, height: 400)
        window.center()
        window.setFrameAutosaveName("ServerLogs-\(serverID)")
        window.contentView = NSHostingView(rootView: content { [weak window] in window?.performClose(nil) })
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        // Release the view so its log polling task is cancelled on close.
        window?.contentView = nil
        Self.openWindows.removeValue(forKey: serverID)
    }
}
