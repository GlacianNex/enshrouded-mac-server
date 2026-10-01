import Foundation

public enum SetupStep: String, CaseIterable, Codable {
    case environment, packages, box64, wine, downloader, server, steam, configure, start
    public var title: String {
        switch self {
        case .environment: return "Server Environment"
        case .packages: return "System Packages"
        case .box64: return "Processor Compatibility"
        case .wine: return "Windows Compatibility"
        case .downloader: return "Server Download Tool"
        case .server: return "Enshrouded Server"
        case .steam: return "Steam Support Files"
        case .configure: return "World & Settings"
        case .start: return "Start & Check Server"
        }
    }
    public var downloadDescription: String {
        switch self {
        case .environment: return "Ubuntu 24.04 ARM64 image from Canonical; runs in a private VM."
        case .packages: return "Linux libraries and build tools from Ubuntu’s package repositories."
        case .box64: return "Box64 0.4.4 from GitHub; built inside the server VM."
        case .wine: return "Wine 11.18 from GitHub; runs the Windows server inside the VM."
        case .downloader: return "DepotDownloader 3.4.0 from GitHub; downloads official server files."
        case .server: return "Latest public dedicated server from Valve (Steam app 2278520)."
        case .steam: return "Steam support libraries from Valve (app 1007), if needed."
        case .configure: return "Save settings and create or import a world; no download."
        case .start: return "Start the server and check readiness; no download."
        }
    }
}

public struct SetupEvent: Codable {
    public var stage: SetupStep
    public var message: String
    public var received: Int64?
    public var total: Int64?
    public var phase: String?
    public var percent: Double?
    public var elapsedSeconds: Int?
    public var outputAgeSeconds: Int?
    public var cpuActive: Bool?
    public var running: Bool?
    public init(_ stage: SetupStep, _ message: String, received: Int64? = nil, total: Int64? = nil) {
        self.stage = stage; self.message = message; self.received = received; self.total = total
    }
    public var line: String { "[ESM_SETUP] " + String(decoding: try! JSONEncoder().encode(self), as: UTF8.self) + "\n" }
}

public struct SetupProgress {
    public private(set) var step: SetupStep = .environment
    public private(set) var message = "Preparing setup…"
    public private(set) var received: Int64?
    public private(set) var total: Int64?
    public private(set) var percent: Double?
    public private(set) var downloaded: [SetupStep: Int64] = [:]
    public private(set) var finished = false
    public private(set) var failed = false
    public private(set) var started = Date()
    public private(set) var phase: String?
    public private(set) var processHeartbeat: Date?
    public private(set) var phaseElapsed = 0
    public private(set) var outputAge = 0
    public private(set) var cpuActive: Bool?
    public private(set) var processRunning: Bool?
    private var pending = ""
    public init() {}
    public mutating func finish(success: Bool) {
        finished = success; failed = !success
        message = success ? "Setup complete." : "Setup stopped during \(step.title). Check the error below, then retry."
    }
    public mutating func consume(_ chunk: String, at now: Date = Date()) {
        pending += chunk.replacingOccurrences(of: "\r", with: "\n")
        while let end = pending.firstIndex(of: "\n") {
            let line = String(pending[..<end]); pending.removeSubrange(...end)
            parse(line, at: now)
        }
        if pending.count > 16_384 { pending = String(pending.suffix(16_384)) }
    }
    private mutating func parse(_ raw: String, at now: Date) {
        if let range = raw.range(of: "[ESM_SETUP] "),
           let event = try? JSONDecoder().decode(SetupEvent.self, from: Data(raw[range.upperBound...].utf8)) {
            if event.stage != step || event.phase != phase {
                received = nil; total = nil; percent = nil
                phase = event.phase; processHeartbeat = nil; processRunning = nil
                phaseElapsed = 0; outputAge = 0; cpuActive = nil
            }
            step = event.stage; message = event.message
            if let n = event.received, n >= 0 { received = n; downloaded[step] = n }
            if let n = event.total, n > 0 { total = n }
            if event.phase != nil {
                processHeartbeat = now
                phaseElapsed = max(0, event.elapsedSeconds ?? 0)
                outputAge = max(0, event.outputAgeSeconds ?? 0)
                cpuActive = event.cpuActive; processRunning = event.running
                if let value = event.percent, value.isFinite, (0...100).contains(value) { percent = max(percent ?? 0, value) }
            } else if event.received == nil { percent = nil }
            else if let n = received, let t = total { percent = min(100, Double(n) / Double(t) * 100) }
            return
        }
        let text = LogDisplay.readable(raw).trimmingCharacters(in: .whitespaces)
        if step == .server || step == .steam {
            if let match = text.range(of: #"^\d{1,3}(?:\.\d+)?%"#, options: .regularExpression),
               let value = Double(text[match].dropLast()), (0...100).contains(value) {
                percent = value; message = "Downloading and checking files…"
            }
            if let expression = try? NSRegularExpression(pattern: #"^Total downloaded: (\d+) bytes"#),
               let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text), let value = Int64(text[range]) {
                received = value; downloaded[step] = value; total = nil; percent = nil; message = "Download complete; finishing installation…"
            }
        }
        if step == .packages,
           let expression = try? NSRegularExpression(pattern: #"^Fetched ([0-9.]+) (B|kB|MB|GB) in"#),
           let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(match.range(at: 1), in: text), let u = Range(match.range(at: 2), in: text), let n = Double(text[r]) {
            let multiplier: Double = ["B": 1, "kB": 1_000, "MB": 1_000_000, "GB": 1_000_000_000][String(text[u])] ?? 1
            if n.isFinite, n >= 0, n * multiplier < Double(Int64.max) { received = (received ?? 0) + Int64(n * multiplier); downloaded[step] = received }
            message = "Installing system packages…"
        }
    }
    public func processStatus(at now: Date) -> String? {
        guard phase != nil, let processHeartbeat else { return nil }
        let age = max(0, Int(now.timeIntervalSince(processHeartbeat)))
        if age >= 15 { return "No status update for \(age)s. Open Logs for details." }
        if processRunning == false { return "Process finished; waiting for the next setup step…" }
        let activity = cpuActive == true ? "CPU activity detected" : cpuActive == false ? "No recent CPU activity" : "Process running"
        return "\(activity) · Last output \(outputAge + age)s ago · Step elapsed \(phaseElapsed + age)s"
    }
    public var percentLabel: String {
        phase == "build" ? "Compilation: \(Int(percent ?? 0))% of build steps" : "Current step: \(Int(percent ?? 0))%"
    }
    public var downloadDetail: String {
        let format: (Int64) -> String = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        if let received, let total { return "\(format(received)) of \(format(total)) downloaded" }
        if let received { return "\(format(received)) downloaded · total not reported" }
        if step == .server || step == .steam { return "Valve reports file progress; downloaded bytes are reported when the download finishes." }
        if step == .packages { return "Package download sizes are reported by Ubuntu as each batch finishes." }
        return "Download size appears when the source reports it."
    }
}
