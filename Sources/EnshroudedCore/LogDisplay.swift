import Foundation

/// Display-only cleanup: status parsing continues to use the original log.
public enum LogDisplay {
    public static func readable(_ text: String, filter: String = "") -> String {
        let terminalCodes = try! NSRegularExpression(pattern: "\\u001B\\[[0-?]*[ -/]*[@-~]")
        let clean = terminalCodes.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\0", with: "")
        guard !filter.isEmpty else { return clean }
        return clean.components(separatedBy: "\n").filter { $0.localizedCaseInsensitiveContains(filter) }.joined(separator: "\n")
    }
}
