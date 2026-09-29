import Foundation

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
    public var peers: [PeerStatus] = []
    public var peerReportEnd = 0
    public var lastSaveCompleted = false
    public var online = false
    public init() {}
    public static func parse(_ text: String) -> LogSnapshot {
        var result = LogSnapshot()
        result.publicIP = ConnectionInfo.reportedPublicIP(in: text)
        func capture(_ pattern: String, _ line: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
            return (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: line).map { String(line[$0]) } ?? "" }
        }
        var pendingPeers: [PeerStatus] = []
        var inSession = false
        var offset = 0
        for line in text.components(separatedBy: .newlines) {
            offset += line.utf8.count + 1
            if line.contains("'HostOnline' (up)") { result.online = true }
            if line.contains("'HostOnline' (down)") { result.online = false; result.peers = [] }
            if line.contains("[server] Start Saving") { result.lastSaveCompleted = false }
            if line.contains("[server] Saved") { result.lastSaveCompleted = true }
            if line.contains("-------------- Session") { pendingPeers = []; inSession = true }
            if inSession && line == "---------------------------------------" {
                result.peers = pendingPeers; result.peerReportEnd = offset; inSession = false
            }
            if line.contains("OperatingNormally"), let c = capture(#"m#(\d+)\(.*lost (\d+), ping (\d+) ms"#, line), let lost = Int(c[1]), let ping = Double(c[2]) {
                pendingPeers.append(PeerStatus(id: c[0], ping: ping, lost: lost))
            }
            if let c = capture(#"\[ecss\] Stats:.*Upd:([\d,]+).*Time:([\d,]+)ms.*Max:([\d.]+)ms.*Avg:([\d.]+)ms"#, line),
               let updates = Double(c[0].replacingOccurrences(of: ",", with: "")), let milliseconds = Double(c[1].replacingOccurrences(of: ",", with: "")), milliseconds > 0 {
                result.updateRate = updates / (milliseconds / 1000)
                result.maxWorkMS = Double(c[2]); result.averageWorkMS = Double(c[3]); result.statsLine = line
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
    public func logTail(maxBytes: Int = 256_000) -> String {
        guard let file = try? FileHandle(forReadingFrom: data.appendingPathComponent("logs/server.log")) else { return "" }
        defer { try? file.close() }
        guard let size = try? file.seekToEnd() else { return "" }
        try? file.seek(toOffset: size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0)
        return String(decoding: (try? file.readToEnd()) ?? Data(), as: UTF8.self)
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
        let text = try command(["shell", "engine", "python3", "-c", script], output: {_ in})
        return try JSONDecoder().decode(RuntimeMetrics.self, from: Data(text.utf8))
    }
}
