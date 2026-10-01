import Foundation

/// User-facing progress for server work; percentages are reported by the downloader only.
public struct ServerOperationProgress {
    public private(set) var title: String
    public private(set) var message: String
    public private(set) var percent: Double?
    public var downloadDetail: String? { downloading ? setup.downloadDetail : nil }
    public let started: Date
    public private(set) var finished = false
    public private(set) var failed = false
    private let action: String
    private var setup = SetupProgress()
    private var pending = ""
    private var downloading = false

    public init(action: String, at: Date = Date()) {
        self.action = action
        started = at
        switch action {
        case "start": title = "Start Server"; message = "Starting the server…"
        case "stop", "shutdown": title = "Save & Stop"; message = "Saving the world and stopping the server…"
        case "restart": title = "Save & Stop"; message = "Preparing to save and restart the server…"
        case "update": title = "Check Server"; message = "Checking the server before updating…"
        default: title = "Prepare Installation"; message = "Preparing the server files…"
        }
    }

    public mutating func consume(_ chunk: String) {
        guard !finished && !failed else { return }
        pending += chunk.replacingOccurrences(of: "\r", with: "\n")
        while let end = pending.firstIndex(of: "\n") {
            let line = String(pending[..<end])
            pending.removeSubrange(...end)
            consumeLine(line)
        }
        if pending.count > 16_384 { pending = String(pending.suffix(16_384)) }
    }

    private mutating func stage(_ title: String, _ message: String) {
        self.title = title; self.message = message
        percent = nil; downloading = false
    }

    private mutating func consumeLine(_ line: String) {
        setup.consume(line + "\n")
        let text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("Waiting for another server to finish starting") {
            stage("Waiting to Start", "Waiting for another server to finish starting…")
        } else if text.hasPrefix("Saving and stopping server") {
            stage("Save & Stop", "Saving the world and stopping the server…")
        } else if text.hasPrefix("Backing up and updating server") {
            stage("Back Up", "Backing up the world before updating…")
        } else if text.hasPrefix("Starting server") || text.hasPrefix("Waiting for the game server to answer") {
            stage(action == "start" ? "Start Server" : "Restart Server", "Starting the server and checking that it responds…")
        } else if text.hasPrefix("Stopping the server environment") || text.hasPrefix("Waiting for the server environment to finish shutting down") {
            stage("Stop Environment", "Closing the server environment…")
        } else if text == "Installation complete." {
            stage("Verify Installation", "Server files are ready; finishing the operation…")
        } else if let range = line.range(of: "[ESM_SETUP] "),
                  let event = try? JSONDecoder().decode(SetupEvent.self, from: Data(line[range.upperBound...].utf8)) {
            switch event.stage {
            case .start:
                stage(action == "start" ? "Start Server" : "Restart Server", "Starting the server and checking that it responds…")
            case .configure:
                stage("Save Settings", "Saving the server settings…")
            default:
                title = [.server, .steam].contains(event.stage) ? "Download & Verify" : event.stage.title
                message = setup.message
                downloading = true; percent = setup.percent
            }
        } else if downloading {
            message = setup.message; percent = setup.percent
        }
    }

    public mutating func finish(success: Bool) {
        percent = nil; downloading = false
        finished = success; failed = !success
        if !success {
            message = "Stopped during \(title.lowercased()). Check the error and try again."
            title = "Operation Failed"
            return
        }
        title = "Complete"
        switch action {
        case "stop", "shutdown": message = "Server stopped."
        case "start": message = "Server started."
        case "restart": message = "Server restarted."
        case "update": message = "Server update complete."
        default: message = "Server installation complete."
        }
    }
}
