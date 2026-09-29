import Foundation
import Darwin

public enum ManagerInstallation {
    public static func sameLocation(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.resolvingSymlinksInPath().standardizedFileURL.path == rhs.resolvingSymlinksInPath().standardizedFileURL.path
    }

    public static func validate(_ source: URL, replacing destination: URL) throws -> BuildInfo {
        guard !sameLocation(source, destination) else { throw EngineError("That is the app already running") }
        let incoming = try BuildInfo.read(app: source)
        let installed = try BuildInfo.read(app: destination)
        guard incoming.canReplace(installed) else { throw EngineError("This stable version is already installed or newer.") }
        try verify(source)
        return incoming
    }
    public static func verify(_ app: URL) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", app.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw EngineError("The selected app failed its code-signature integrity check") }
    }
    private static func prepareInstalledCopy(_ app: URL) throws {
        func clearQuarantine(_ url: URL) throws {
            // Lima includes symbolic links. Never follow them outside the copy.
            if removexattr(url.path, "com.apple.quarantine", XATTR_NOFOLLOW) != 0 {
                let code = errno
                if code != ENOATTR { throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
            }
        }
        try clearQuarantine(app)
        var enumerationError: Error?
        guard let entries = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil,
            errorHandler: { _, error in enumerationError = error; return false }) else {
            throw EngineError("Could not prepare the installed app")
        }
        for case let entry as URL in entries { try clearQuarantine(entry) }
        if let enumerationError { throw enumerationError }
    }
    static func replacePrepared(_ staged: URL, destination: URL, previous: URL, replacing: Bool,
                                move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }) throws {
        if replacing { try move(destination, previous) }
        do { try move(staged, destination) }
        catch {
            do { if replacing { try move(previous, destination) } }
            catch { throw EngineError("App replacement failed. Previous app remains at \(previous.path)") }
            throw error
        }
    }
    /// Keep Previous.app for recovery until the new build has been used successfully.
    public static func replace(_ source: URL, destination: URL, beforeReplace: () throws -> Void) throws -> URL {
        let fm = FileManager.default
        let lock = destination.deletingLastPathComponent().appendingPathComponent(".enshrouded-manager-update.lock")
        let fd = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw EngineError("Cannot prepare the application update lock") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw EngineError("Another manager upgrade is in progress") }
        defer { flock(fd, LOCK_UN) }
        let replacing = fm.fileExists(atPath: destination.path)
        if replacing { _ = try validate(source, replacing: destination) }
        else { _ = try BuildInfo.read(app: source); try verify(source) }
        let transaction = destination.deletingLastPathComponent().appendingPathComponent(".enshrouded-update-\(UUID().uuidString)")
        try fm.createDirectory(at: transaction, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let staged = transaction.appendingPathComponent("New.app"), previous = transaction.appendingPathComponent("Previous.app")
        do {
            try fm.copyItem(at: source, to: staged)
            try verify(staged)
            // The user has approved installing this verified app. FileManager
            // preserves download quarantine, which can translocate the installed
            // copy on relaunch and send it back into the installer. Normalize only
            // this staged copy, retaining the download and system security policy.
            try prepareInstalledCopy(staged)
            try beforeReplace()
            try replacePrepared(staged, destination: destination, previous: previous, replacing: replacing)
            return previous
        } catch {
            if !fm.fileExists(atPath: previous.path) { try? fm.removeItem(at: transaction) }
            throw error
        }
    }
}


public enum ManagerLaunchPlan: Equatable {
    case manage, activateExisting, install
    public static func decide(source: URL, destination: URL, destinationIsRunning: Bool) -> Self {
        if !ManagerInstallation.sameLocation(source, destination) { return .install }
        return destinationIsRunning ? .activateExisting : .manage
    }
}

extension ManagerInstallation {
    /// Both downloaded installers and in-app updates use the same save/resume contract.
    public static func replaceManagingServers(_ source: URL, destination: URL, engines: [Engine], closeManager: () throws -> Void = {}) throws -> URL {
        var stopped: [Engine] = []
        do {
            return try replace(source, destination: destination) {
                let active = try engines.filter { try $0.status() == "RUNNING" }
                try closeManager()
                for engine in active {
                    try engine.perform("stop", output: {_ in}); stopped.append(engine)
                    try Data("resume\n".utf8).write(to: engine.home.appendingPathComponent("resume-after-manager-update"), options: .atomic)
                }
            }
        } catch {
            var failures: [String] = []
            for engine in stopped {
                do {
                    try engine.perform("start", output: {_ in})
                    try? FileManager.default.removeItem(at: engine.home.appendingPathComponent("resume-after-manager-update"))
                } catch { failures.append(engine.home.lastPathComponent) }
            }
            if !failures.isEmpty {
                throw EngineError("\(error.localizedDescription) Could not restart: \(failures.joined(separator: ", ")). Reopen the manager to retry.")
            }
            throw error
        }
    }
}
