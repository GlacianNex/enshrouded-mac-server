import Foundation
import Darwin

public struct PeerStatus: Identifiable {
    public let id: String
    public let ping: Double
    public let lost: Int
}
public struct LogSnapshot {
    public var publicIP: String?
    public var updateRate: Double?
    public var averageWorkMS: Double?
    public var maxWorkMS: Double?
    public var statsLine: String?
    public var statsReportEnd = 0
    public var lastElapsed: TimeInterval?
    public var statsElapsed: TimeInterval?
    public var peerElapsed: TimeInterval?
    public var peers: [PeerStatus] = []
    public var peerReportEnd = 0
    public var lastSaveCompleted = false
    public var online = false
    public init() {}
    public static func parse(_ input: String, completeLinesOnly: Bool = false) -> LogSnapshot {
        let text: String
        if completeLinesOnly {
            text = input.utf8.lastIndex(of: 10).map { String(decoding: input.utf8[...$0], as: UTF8.self) } ?? ""
        } else { text = input }
        var result = LogSnapshot()
        result.publicIP = ConnectionInfo.reportedPublicIP(in: text)
        func capture(_ pattern: String, _ line: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
            return (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: line).map { String(line[$0]) } ?? "" }
        }
        var pendingPeers: [PeerStatus] = []
        var inSession = false
        var offset = 0
        for rawLine in text.components(separatedBy: "\n") {
            offset += rawLine.utf8.count + 1
            var line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
            var elapsed: TimeInterval?
            if let c = capture(#"^\[[A-Z] (\d+):([0-5]\d):([0-5]\d),(\d{3})\]\s?(.*)$"#, line),
               let hours = Double(c[0]), let minutes = Double(c[1]),
               let seconds = Double(c[2]), let milliseconds = Double(c[3]) {
                let value = hours * 3600 + minutes * 60 + seconds + milliseconds / 1000
                if value.isFinite { elapsed = value; result.lastElapsed = value }
                line = c[4]
            }
            if line.contains("'HostOnline' (up)") { result.online = true }
            if line.contains("'HostOnline' (down)") { result.online = false; result.peers = [] }
            if line.contains("[server] Start Saving") { result.lastSaveCompleted = false }
            if line.contains("[server] Saved") { result.lastSaveCompleted = true }
            if line.contains("-------------- Session") { pendingPeers = []; inSession = true }
            if inSession && line == "---------------------------------------" {
                result.peers = pendingPeers; result.peerReportEnd = offset; result.peerElapsed = elapsed; inSession = false
            }
            if line.contains("OperatingNormally"), let c = capture(#"m#(\d+)\(.*lost (\d+), ping (\d+) ms"#, line), let lost = Int(c[1]), let ping = Double(c[2]) {
                pendingPeers.append(PeerStatus(id: c[0], ping: ping, lost: lost))
            }
            if let c = capture(#"\[ecss\] Stats:.*Upd:([\d,]+).*Time:([\d,]+)ms.*Max:([\d.]+)ms.*Avg:([\d.]+)ms"#, line),
               let updates = Double(c[0].replacingOccurrences(of: ",", with: "")), let milliseconds = Double(c[1].replacingOccurrences(of: ",", with: "")), milliseconds > 0 {
                result.updateRate = updates / (milliseconds / 1000)
                result.maxWorkMS = Double(c[2]); result.averageWorkMS = Double(c[3]); result.statsLine = line; result.statsReportEnd = offset; result.statsElapsed = elapsed
            }
        }
        return result
    }
}
public struct RuntimeMetrics: Decodable {
    public let queryResponse: String?
    public var playerCount: Int? {
        guard let queryResponse, let data = Data(base64Encoded: queryResponse) else { return nil }
        return try? ServerQuery.parse(data).players
    }
    public let active: Bool
    public let cpuSeconds: Double
    public let memoryBytes: Double
    public let uptimeSeconds: Double
    public let invocation: String
}
public struct PerformancePoint: Identifiable {
    public let id = UUID()
    public let date: Date
    public let value: Double
    public let segment: Int
    public init(date: Date, value: Double, segment: Int = 0) { self.date = date; self.value = value; self.segment = segment }
}
extension Engine {
    public func logTail(maxBytes: Int = 256_000) -> String { logTailSnapshot(maxBytes: maxBytes).text }
    public func logTailSnapshot(maxBytes: Int = 256_000) -> LogTailSnapshot { logSource(maxBytes: maxBytes).0 }
    public var serverLogFolder: URL { logSource(maxBytes: 256_000).1.deletingLastPathComponent() }
    private func logSource(maxBytes: Int) -> (LogTailSnapshot, URL) {
        let nativeURL = data.appendingPathComponent("server/logs/enshrouded_server.log")
        let native = LogTailSnapshot.read(nativeURL, maxBytes: maxBytes)
        if !native.text.isEmpty, native.parsed.lastElapsed != nil { return (native, nativeURL) }
        let stdout = data.appendingPathComponent("logs/server.log")
        return (LogTailSnapshot.read(stdout, maxBytes: maxBytes), stdout)
    }
    public func metrics() throws -> RuntimeMetrics {
        let script = ServerQuery.guestQueryPython + "\n" + #"""
import subprocess,json,time,base64
try: reply=base64.b64encode(query_response()).decode()
except Exception: reply=None
keys=['ActiveState','CPUUsageNSec','MemoryCurrent','ActiveEnterTimestampMonotonic','InvocationID']
r=subprocess.run(['systemctl','show','esm-server']+['--property='+x for x in keys],capture_output=True,text=True,check=True)
p=dict(line.split('=',1) for line in r.stdout.splitlines() if '=' in line)
def n(k):
 try: return float(p.get(k,0))
 except ValueError: return 0
active=p.get('ActiveState')=='active'
print(json.dumps(dict(queryResponse=reply,active=active,cpuSeconds=n('CPUUsageNSec')/1e9 if active else 0,memoryBytes=n('MemoryCurrent') if active else 0,uptimeSeconds=max(0,time.monotonic()-n('ActiveEnterTimestampMonotonic')/1e6) if active else 0,invocation=p.get('InvocationID',''))))
"""#
        let text = try command(["shell", "engine", "python3", "-c", script], timeout: 15, output: {_ in})
        return try JSONDecoder().decode(RuntimeMetrics.self, from: Data(text.utf8))
    }
}

/// Text and offsets come from the same open file, so an append or rotation
/// between polling and rendering cannot make an old report look new.
public struct LogTailSnapshot {
    public let text: String
    public let fileIdentifier: String
    public let startOffset: UInt64
    public let fileSize: UInt64
    public let modifiedAt: Date?
    private let parsedSnapshot: LogSnapshot
    public init(text: String, fileIdentifier: String, startOffset: UInt64, fileSize: UInt64, modifiedAt: Date? = nil) {
        self.text = text; self.fileIdentifier = fileIdentifier
        self.startOffset = startOffset; self.fileSize = fileSize; self.modifiedAt = modifiedAt
        parsedSnapshot = LogSnapshot.parse(text, completeLinesOnly: true)
    }
    /// Estimate the last speed report's wall time from the file's last write and
    /// native elapsed timestamps. Missing or inconsistent clocks stay unknown.
    public func reportDate(at now: Date = Date()) -> Date? {
        date(for: parsed.statsElapsed, at: now)
    }
    public func peerReportDate(at now: Date = Date()) -> Date? { date(for: parsed.peerElapsed, at: now) }
    private func date(for elapsed: TimeInterval?, at now: Date) -> Date? {
        guard let modifiedAt, modifiedAt <= now, let last = parsed.lastElapsed,
              let elapsed, last.isFinite, elapsed.isFinite else { return nil }
        let age = last - elapsed
        guard age >= 0, age <= 7 * 86400 else { return nil }
        return modifiedAt.addingTimeInterval(-age)
    }
    public var parsed: LogSnapshot { parsedSnapshot }
    public func identityFor(relativeEnd: Int) -> String? {
        guard relativeEnd > 0, relativeEnd <= text.utf8.count else { return nil }
        return "\(fileIdentifier):\(startOffset + UInt64(relativeEnd))"
    }
    public static func read(_ url: URL, maxBytes: Int = 256_000) -> LogTailSnapshot {
        let empty = LogTailSnapshot(text: "", fileIdentifier: "", startOffset: 0, fileSize: 0)
        guard maxBytes > 0, let file = try? FileHandle(forReadingFrom: url) else { return empty }
        defer { try? file.close() }
        var info = stat()
        guard fstat(file.fileDescriptor, &info) == 0, info.st_size >= 0 else { return empty }
        let size = UInt64(info.st_size)
        var start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        do {
            try file.seek(toOffset: start)
            var bytes = try file.read(upToCount: Int(size - start)) ?? Data()
            if start > 0 {
                // A tail may begin in the middle of a UTF-8 character or report.
                guard let newline = bytes.firstIndex(of: 10) else { return empty }
                let skipped = bytes.distance(from: bytes.startIndex, to: newline) + 1
                bytes = Data(bytes.dropFirst(skipped)); start += UInt64(skipped)
            }
            // Reject invalid UTF-8 instead of changing the byte offsets during decoding.
            guard let text = String(data: bytes, encoding: .utf8) else { return empty }
            let identity = "\(info.st_dev):\(info.st_ino):\(info.st_birthtimespec.tv_sec):\(info.st_birthtimespec.tv_nsec)"
            return LogTailSnapshot(text: text, fileIdentifier: identity, startOffset: start, fileSize: size, modifiedAt: Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000))
        } catch { return empty }
    }
}
