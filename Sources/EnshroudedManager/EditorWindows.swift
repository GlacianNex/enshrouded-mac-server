import AppKit
import SwiftUI

/// Editors own their windows, so closing management cannot destroy a draft.
@MainActor final class EditorWindows: NSWindowController, NSWindowDelegate {
    private static var editors: [String: EditorWindows] = [:]
    private let key: String
    static func closeSettings(_ model: Model) { editors["settings:" + model.engine.home.path]?.window?.performClose(nil) }
    static func showSettings(_ model: Model) {
        show(key: "settings:" + model.engine.home.path, title: "Server Settings — " + model.name, size: NSSize(width: 680, height: 740)) { close in
            AnyView(SettingsView(model: model, draft: model.settings, initiallyReadOnly: !model.stopped, close: close))
        }
    }
    static func showNew(_ fleet: FleetModel) {
        show(key: "new:" + fleet.store.registry.path, title: "New Enshrouded Server", size: NSSize(width: 600, height: 740)) { close in
            AnyView(NewServerView(fleet: fleet, close: close))
        }
    }
    private static func show(key: String, title: String, size: NSSize, content: (@escaping () -> Void) -> AnyView) {
        let controller: EditorWindows
        if let existing = editors[key] { controller = existing }
        else {
            controller = EditorWindows(key: key, title: title, size: size)
            let window = controller.window!
            window.contentView = NSHostingView(rootView: content { [weak window] in window?.performClose(nil) })
            editors[key] = controller
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private init(key: String, title: String, size: NSSize) {
        self.key = key
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = title; window.contentMinSize = size
        window.isReleasedWhenClosed = false; window.delegate = self; window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        Self.editors.removeValue(forKey: key)
    }
}
