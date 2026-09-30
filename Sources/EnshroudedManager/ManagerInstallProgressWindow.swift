import AppKit
import EnshroudedCore

@MainActor final class ManagerInstallProgressWindow {
    private let window: NSWindow
    private let status = NSTextField(wrappingLabelWithString: "Checking the update…")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let elapsed = NSTextField(labelWithString: "Elapsed 0:00")
    private var progress = ManagerInstallProgress()
    private var timer: Timer?
    private let logURL: URL

    init(logURL: URL) {
        self.logURL = logURL
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 205), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Updating Enshrouded Server Manager"
        status.font = .boldSystemFont(ofSize: 15)
        status.frame = NSRect(x: 24, y: 147, width: 472, height: 30)
        let bar = NSProgressIndicator(frame: NSRect(x: 24, y: 119, width: 472, height: 16))
        bar.style = .bar; bar.isIndeterminate = true; bar.usesThreadedAnimation = true; bar.startAnimation(nil)
        detail.frame = NSRect(x: 24, y: 57, width: 472, height: 50)
        detail.font = .systemFont(ofSize: 12); detail.textColor = .secondaryLabelColor
        elapsed.frame = NSRect(x: 24, y: 24, width: 200, height: 20)
        elapsed.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let logs = NSButton(title: "Open Update Log", target: self, action: #selector(openLog))
        logs.bezelStyle = .rounded; logs.frame = NSRect(x: 350, y: 17, width: 150, height: 30)
        for view in [status, bar, detail, elapsed, logs] { window.contentView?.addSubview(view) }
        render(); window.center(); window.makeKeyAndOrderFront(nil)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.render() }
        }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func advance(_ stage: ManagerInstallStage) { progress.advance(to: stage); render() }
    func close() { timer?.invalidate(); timer = nil; window.close() }
    private func render() {
        status.stringValue = progress.stage.title
        detail.stringValue = progress.detail()
        elapsed.stringValue = progress.elapsed()
    }
    @objc private func openLog() {
        LogsWindowController.show(updateLog: logURL)
    }
}
