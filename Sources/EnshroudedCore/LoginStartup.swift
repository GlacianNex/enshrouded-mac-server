import Foundation
import CryptoKit
import Darwin

/// Login jobs launch a server without launching or depending on the manager UI.
public enum LoginStartup {
    public static func label(home: URL) -> String {
        let digest = SHA256.hash(data: Data(home.standardizedFileURL.path.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return "com.glaciannex.enshrouded-server.login." + digest
    }
    public static func configuration(home: URL, executable: URL) -> [String: Any] {
        ["Label": label(home: home), "ProgramArguments": [executable.path, "--start-at-login", home.path],
         "RunAtLoad": true, "ProcessType": "Background", "ExitTimeOut": 130,
         "StandardOutPath": home.appendingPathComponent("login-start.log").path,
         "StandardErrorPath": home.appendingPathComponent("login-start.log").path]
    }
    public static func configure(home: URL, enabled: Bool, executable: URL) throws {
        guard ProcessInfo.processInfo.environment["ESM_HOME"] == nil else {
            throw EngineError("Login startup is unavailable in an isolated test environment.")
        }
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        try configure(home: home, enabled: enabled, executable: executable, directory: directory) { arguments in
            _ = try DiagnosticCommand.run(executable: URL(fileURLWithPath: "/bin/launchctl"), arguments: arguments, environment: ProcessInfo.processInfo.environment, directory: home.deletingLastPathComponent(), timeout: 10, output: { _ in })
        }
    }
    static func configure(home: URL, enabled: Bool, executable: URL, directory: URL, launchctl: ([String]) throws -> Void) throws {
        let file = directory.appendingPathComponent(label(home: home) + ".plist")
        if enabled {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: configuration(home: home, executable: executable), format: .xml, options: 0)
            let previous = try? Data(contentsOf: file)
            if previous != data { try data.write(to: file, options: .atomic) }
            // Do not bootstrap: RunAtLoad would start a stopped server right now.
            // launchd loads this user's LaunchAgents at their next login.
            do { try launchctl(["enable", "gui/\(getuid())/\(label(home: home))"]) }
            catch {
                if let previous { try previous.write(to: file, options: .atomic) }
                else { try FileManager.default.removeItem(at: file) }
                throw error
            }
        } else if FileManager.default.fileExists(atPath: file.path) {
            try launchctl(["disable", "gui/\(getuid())/\(label(home: home))"])
            try FileManager.default.removeItem(at: file)
        }
    }
}
