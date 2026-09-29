import Foundation

/// Simulation reports have their own cadence and run identity. A failed memory
/// probe must not invalidate an otherwise valid log reading or split its series.
public struct ServerSpeedHistory {
    public static let freshness: TimeInterval = 90
    public private(set) var points: [PerformancePoint] = []
    public private(set) var lastReport: Date?
    public private(set) var lastValue: Double?
    private var identity: String?
    private var fileIdentifier: String?
    private var fileSize: UInt64 = 0
    private var invocation: String?
    private var segment = 0
    private var stopped = false
    public init() {}

    public mutating func observe(_ log: LogTailSnapshot, running: Bool?, invocation: String?, at now: Date) {
        points.removeAll { now.timeIntervalSince($0.date) > PerformanceHistory.duration }
        // Unknown status is a temporary observation failure, not a new run.
        guard let running else { return }
        guard running else {
            if !stopped { segment += 1 }
            stopped = true; lastReport = nil; lastValue = nil
            // Do not reread an old report as fresh after restarting.
            identity = log.identityFor(relativeEnd: log.parsed.statsReportEnd) ?? identity
            return
        }
        stopped = false
        let changedLog = fileIdentifier != nil && !log.fileIdentifier.isEmpty && fileIdentifier != log.fileIdentifier
        let changedRun = invocation != nil && self.invocation != nil && invocation != self.invocation
        let truncated = !log.fileIdentifier.isEmpty && log.fileIdentifier == fileIdentifier && log.fileSize < fileSize
        if changedLog || changedRun || truncated {
            segment += 1; lastReport = nil; lastValue = nil
            if changedLog || truncated { identity = nil }
        }
        if let invocation { self.invocation = invocation }
        if !log.fileIdentifier.isEmpty { fileIdentifier = log.fileIdentifier; fileSize = log.fileSize }
        guard let next = log.identityFor(relativeEnd: log.parsed.statsReportEnd), next != identity,
              let value = log.parsed.updateRate, value.isFinite, value >= 0 else { return }
        identity = next; lastReport = now; lastValue = value
        points.append(.init(date: now, value: value, segment: segment))
    }
    public func current(at now: Date) -> Double? {
        guard let lastReport, now.timeIntervalSince(lastReport) <= Self.freshness else { return nil }
        return lastValue
    }
}
