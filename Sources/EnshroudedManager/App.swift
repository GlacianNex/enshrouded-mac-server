import SwiftUI
import EnshroudedCore

struct EnshroudedApp: App {
    @NSApplicationDelegateAdaptor(ManagerAppDelegate.self) private var delegate
    @StateObject private var fleet = FleetModel()
    var body: some Scene {
        Window("Server Management", id: "management") { FleetView(fleet: fleet) }
            .defaultSize(width: 640, height: 860)
            .windowResizability(.contentSize)
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
@MainActor final class ManagerAppDelegate: NSObject, NSApplicationDelegate {
    private(set) var quitNotice: NSAlert?
    private var quitNoticeTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // AppKit's default quit Apple event can remain pending behind a sheet.
        // Handle the external request before the normal termination guard.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleQuit(_:reply:)),
                                                     forEventClass: AEEventClass(kCoreEventClass),
                                                     andEventID: AEEventID(kAEQuitApplication))
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
