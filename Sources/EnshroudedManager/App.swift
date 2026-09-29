import SwiftUI
import EnshroudedCore

struct EnshroudedApp: App {
    @NSApplicationDelegateAdaptor(ManagerAppDelegate.self) private var delegate
    @StateObject private var fleet = FleetModel()
    var body: some Scene {
        WindowGroup("Server Management", id: "management") { FleetView(fleet: fleet) }
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
    static var isBusy: () -> Bool = { false }
    static var allowTermination = false
}
@MainActor final class ManagerAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // AppKit's default quit Apple event can remain pending behind a sheet.
        // Handle the external request before the normal termination guard.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleQuit(_:reply:)),
                                                     forEventClass: AEEventClass(kCoreEventClass),
                                                     andEventID: AEEventID(kAEQuitApplication))
    }
    @objc private func handleQuit(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard !ApplicationLifetime.isBusy() else {
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
        guard !ApplicationLifetime.allowTermination, ApplicationLifetime.isBusy() else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "Server maintenance is still running"
        alert.informativeText = "Wait for setup, update, saving or recovery to finish before quitting the manager."
        alert.addButton(withTitle: "Keep Manager Open"); alert.runModal()
        return .terminateCancel
    }
}
