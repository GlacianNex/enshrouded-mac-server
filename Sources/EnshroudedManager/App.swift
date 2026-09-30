import SwiftUI
import EnshroudedCore

@MainActor enum EnshroudedApp {
    static func main() {
        let delegate = ManagerAppDelegate()
        NSApp.delegate = delegate
        installMainMenu()
        // AppKit owns the lifetime; no SwiftUI scene opens a window implicitly.
        withExtendedLifetime(delegate) { NSApp.run() }
    }
    static func installMainMenu() {
        let bar = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title); item.submenu = menu; bar.addItem(item)
            return menu
        }
        let app = submenu("Enshrouded")
        app.addItem(withTitle: "About Enshrouded", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Enshrouded", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Enshrouded", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = submenu("Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        let windows = submenu("Window")
        windows.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windows.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windows
        NSApp.mainMenu = bar
    }
}

@MainActor enum MenuBranding {
    static func image(running: Bool, busy: Bool) -> NSImage {
        let branding = Bundle.main.url(forResource: "Enshrouded", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
        let image = NSImage(size: NSSize(width: 34, height: 18), flipped: false) { _ in
            branding?.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            (busy ? NSColor.systemOrange : running ? NSColor.systemGreen : NSColor.systemRed).setFill()
            NSBezierPath(ovalIn: NSRect(x: 22, y: 4, width: 10, height: 10)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}


@MainActor enum ApplicationLifetime {
    static var activeOperations: () -> [String] = { [] }
    static var isBusy: Bool { !activeOperations().isEmpty }
    static var allowTermination = false
}
@MainActor final class ManagerAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private(set) var fleet: FleetModel?
    private(set) var managementWindow: NSWindow?
    private(set) var quitNotice: NSAlert?
    private var quitNoticeTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        start(fleet: FleetModel(), afterUpdate: ProcessInfo.processInfo.environment["ESM_RELAUNCH_FROM_PID"].flatMap(Int32.init) != nil)
        // AppKit's default quit Apple event can remain pending behind a sheet.
        // Handle the external request before the normal termination guard.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleQuit(_:reply:)),
                                                     forEventClass: AEEventClass(kCoreEventClass),
                                                     andEventID: AEEventID(kAEQuitApplication))
    }
    func start(fleet: FleetModel, afterUpdate: Bool) {
        self.fleet = fleet
        fleet.statusMenu = StatusMenu(fleet: fleet, showManagement: { [weak self] in self?.showManagement() })
        if !afterUpdate { showManagement() }
    }
    func showManagement() {
        guard let fleet else { return }
        if managementWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 860),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Server Management"
            window.identifier = NSUserInterfaceItemIdentifier("management")
            window.isReleasedWhenClosed = false; window.delegate = self
            window.contentView = NSHostingView(rootView: FleetView(fleet: fleet))
            window.center()
            managementWindow = window
        }
        managementWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === managementWindow else { return }
        window.contentView = nil
        managementWindow = nil
    }
    @objc private func handleQuit(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard ApplicationLifetime.allowTermination || !ApplicationLifetime.isBusy else {
            reply.setParam(NSAppleEventDescriptor(int32: Int32(userCanceledErr)), forKeyword: AEKeyword(keyErrorNumber))
            return
        }
        for window in NSApp.windows {
            if let parent = window.sheetParent { parent.endSheet(window, returnCode: .cancel) }
        }
        if NSApp.modalWindow != nil { NSApp.abortModal() }
        NSApp.terminate(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing a window is never a request to quit this menu-bar app.
        // Keep the fleet and its in-flight operations alive without a window.
        false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !ApplicationLifetime.allowTermination, ApplicationLifetime.isBusy else {
            dismissQuitNotice()
            return .terminateNow
        }
        if quitNotice == nil {
            let alert = NSAlert()
            alert.messageText = "An Operation Is Still Running"
            let button = alert.addButton(withTitle: "Keep Manager Open")
            button.target = self
            button.action = #selector(dismissQuitNotice)
            quitNotice = alert
            refreshQuitNotice()
            alert.window.center()
            alert.window.makeKeyAndOrderFront(nil)
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshQuitNotice() }
            }
            RunLoop.main.add(timer, forMode: .common)
            quitNoticeTimer = timer
        } else { quitNotice?.window.makeKeyAndOrderFront(nil) }
        // Never enter runModal here: server completions must keep executing,
        // and the notice must disappear as soon as the operation finishes.
        return .terminateCancel
    }
    func refreshQuitNotice() {
        let operations = ApplicationLifetime.activeOperations()
        guard !ApplicationLifetime.allowTermination, !operations.isEmpty else {
            dismissQuitNotice()
            return
        }
        let message = operations.joined(separator: "\n") + "\n\nWait for this to finish before quitting. This message closes automatically."
        if quitNotice?.informativeText != message {
            quitNotice?.informativeText = message
            quitNotice?.layout()
        }
    }
    @objc func dismissQuitNotice() {
        quitNoticeTimer?.invalidate(); quitNoticeTimer = nil
        quitNotice?.window.close(); quitNotice = nil
    }
}
