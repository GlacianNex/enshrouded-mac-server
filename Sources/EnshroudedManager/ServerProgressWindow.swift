import AppKit
import SwiftUI

@MainActor final class ServerProgressWindow: NSWindowController, NSWindowDelegate {
    private static var windows: [String: ServerProgressWindow] = [:]
    private let key: String
    static func close(_ model: Model) { windows[model.engine.home.path]?.window?.performClose(nil) }
    static func show(model: Model) {
        guard model.serverProgress != nil else { LogsWindowController.show(model: model); return }
        let key = model.engine.home.path
        let controller = windows[key] ?? ServerProgressWindow(model: model)
        windows[key] = controller
        controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private init(model: Model) {
        key = model.engine.home.path
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 250), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Server Progress — " + model.name
        window.isReleasedWhenClosed = false; window.delegate = self; window.center()
        window.contentView = NSHostingView(rootView: ServerProgressView(model: model))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) { window?.contentView = nil; Self.windows.removeValue(forKey: key) }
}
private struct ServerProgressView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let progress = model.serverProgress {
                Text(progress.title).font(.title2.bold())
                Text(progress.message).fixedSize(horizontal: false, vertical: true)
                if let detail = progress.downloadDetail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                if !progress.finished && !progress.failed {
                    if let percent = progress.percent { ProgressView(value: percent, total: 100); Text("\(Int(percent))% of this step").font(.caption) }
                    else { ProgressView().controlSize(.small) }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Elapsed: \(Int(context.date.timeIntervalSince(progress.started))) seconds").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error = model.error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
                HStack { Text(model.busy ? "You can close this window; work continues in the menu bar." : "").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Open Logs") { LogsWindowController.show(model: model) } }
            }
        }.padding(22).frame(width: 480)
    }
}
