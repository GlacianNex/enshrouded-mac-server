import Foundation

/// Average only observations actually received in each five-second interval.
/// Missing intervals and distinct server runs are not interpolated.
public struct PerformanceHistory {
    public static let duration: TimeInterval = 3 * 3600
    public static let interval: TimeInterval = 5
    private var bucket: TimeInterval?
    private var total = 0.0
    private var count = 0
    private var segment = 0
    public private(set) var points: [PerformancePoint] = []
    public init() {}
    public mutating func record(_ value: Double?, at date: Date, segment: Int) {
        let next = floor(date.timeIntervalSince1970 / Self.interval) * Self.interval
        if bucket != next || self.segment != segment {
            if let bucket, count > 0 { points.append(.init(date: Date(timeIntervalSince1970: bucket + Self.interval), value: total / Double(count), segment: self.segment)) }
            bucket = next; total = 0; count = 0; self.segment = segment
        }
        if let value, value.isFinite, value >= 0 { total += value; count += 1 }
        points.removeAll { date.timeIntervalSince($0.date) > Self.duration }
    }
}
