import Foundation

/// Simulation reports have their own cadence and run identity. A failed memory
/// probe must not invalidate an otherwise valid log reading or split its series.
public struct ServerSpeedHistory {
    public static let freshness: TimeInterval = 90
    public private(set) var points: [PerformancePoint] = []
    public private(set) var lastReport: Date?
    public private(set) var lastValue: Double?
    public private(set) var reportTimeKnown = false
    private var consumedOffset: UInt64?
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
            stopped = true; lastReport = nil; lastValue = nil; reportTimeKnown = false
            // Do not reread an old report as fresh after restarting.
            if log.parsed.statsReportEnd > 0 { consumedOffset = log.startOffset + UInt64(log.parsed.statsReportEnd) }
            return
        }
        stopped = false
        let changedLog = fileIdentifier != nil && !log.fileIdentifier.isEmpty && fileIdentifier != log.fileIdentifier
        let changedRun = invocation != nil && self.invocation != nil && invocation != self.invocation
        let truncated = !log.fileIdentifier.isEmpty && log.fileIdentifier == fileIdentifier && log.fileSize < fileSize
        if changedLog || changedRun || truncated {
            segment += 1; lastReport = nil; lastValue = nil; reportTimeKnown = false
            if changedLog || truncated { consumedOffset = nil }
        }
        if let invocation { self.invocation = invocation }
        if !log.fileIdentifier.isEmpty { fileIdentifier = log.fileIdentifier; fileSize = log.fileSize }
        // Consume every complete report in the tail, not just the newest one.
        // Byte offsets deduplicate overlapping tails and allow history recovery
        // after a delayed poll or manager relaunch.
        for report in log.parsed.speedReports {
            guard log.identityFor(relativeEnd: report.relativeEnd) != nil else { continue }
            let offset = log.startOffset + UInt64(report.relativeEnd)
            guard consumedOffset.map({ offset > $0 }) ?? true else { continue }
            consumedOffset = offset
            let value = report.value
            guard value.isFinite, value >= 0 else { continue }
            lastValue = value
            lastReport = log.date(for: report.elapsed, at: now)
            reportTimeKnown = lastReport != nil
            if let lastReport, now.timeIntervalSince(lastReport) <= PerformanceHistory.duration {
                points.append(.init(date: lastReport, value: value, segment: segment))
            }
        }
    }

    public func current(at now: Date) -> Double? {
        guard reportTimeKnown, let lastReport, (0...Self.freshness).contains(now.timeIntervalSince(lastReport)) else { return nil }
        return lastValue
    }
}
