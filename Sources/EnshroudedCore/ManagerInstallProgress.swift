import Foundation

public enum ManagerInstallStage: String {
    case downloading, checking, copying, checkingServers, closing, saving, stoppingEnvironment, replacing, recovering, opening
    public var title: String {
        switch self {
        case .downloading: return "Downloading the manager…"
        case .checking: return "Checking the update…"
        case .copying: return "Preparing the new app…"
        case .checkingServers: return "Checking running servers…"
        case .closing: return "Closing the previous manager…"
        case .saving: return "Saving and stopping servers…"
        case .stoppingEnvironment: return "Stopping the server environment…"
        case .replacing: return "Installing the new manager…"
        case .recovering: return "Restoring the previous session…"
        case .opening: return "Opening the manager…"
        }
    }
    public var explanation: String {
        switch self {
        case .downloading: return "Getting the update from GitHub. Servers keep running for now."
        case .checking: return "Verifying the update and its code signature."
        case .copying: return "Preparing a verified copy before stopping servers."
        case .checkingServers: return "Checking which servers should restart after the update."
        case .closing: return "Waiting for the previous manager to close."
        case .saving: return "Saving worlds and waiting for each server to exit."
        case .stoppingEnvironment: return "The game server has stopped. Closing its hosting environment."
        case .replacing: return "Replacing the app in Applications. The previous copy is kept for recovery."
        case .recovering: return "The update could not finish. Restarting previously running servers with the installed manager."
        case .opening: return "The manager will open and resume previously running servers."
        }
    }
    public var waitingMessage: String {
        switch self {
        case .downloading: return "Still downloading. Connection failures will be reported here."
        case .saving: return "Still waiting for the server to finish saving. Do not force quit."
        case .stoppingEnvironment: return "The game server has stopped. Waiting for its environment to shut down. A timeout will be reported if it cannot finish."
        case .opening: return "Waiting for the installed manager to open. It will resume previously running servers."
        default: return "This step is taking longer than usual. See the update log for details."
        }
    }
}

public struct ManagerInstallProgress {
    public private(set) var stage: ManagerInstallStage = .checking
    public let started: Date
    public private(set) var stageStarted: Date
    public init(at now: Date = Date()) { started = now; stageStarted = now }
    public mutating func advance(to stage: ManagerInstallStage, at now: Date = Date()) {
        guard self.stage != stage else { return }
        self.stage = stage; stageStarted = now
    }
    public func detail(at now: Date = Date()) -> String {
        if now.timeIntervalSince(stageStarted) >= 30 { return stage.waitingMessage }
        return stage.explanation
    }
    public func elapsed(at now: Date = Date()) -> String {
        let total = max(0, Int(now.timeIntervalSince(started)))
        return String(format: "Elapsed %d:%02d", total / 60, total % 60)
    }
}
