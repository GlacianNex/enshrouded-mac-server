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

/// A chart series ends at a missing interval or a server restart. Retaining the
/// original point ID keeps SwiftUI from treating every refresh as new samples.
public struct PerformanceChartPoint: Identifiable {
    public let point: PerformancePoint
    public let segment: Int
    public var id: UUID { point.id }
    public var date: Date { point.date }
    public var value: Double { point.value }
}

extension PerformanceHistory {
    /// Set the gap to the cadence of this metric: memory buckets, simulation
    /// reports, and connection reports arrive at different intervals.
    public static func chartPoints(_ points: [PerformancePoint], maximumGap: TimeInterval) -> [PerformanceChartPoint] {
        var previous: PerformancePoint?
        var segment = 0
        return points.compactMap { point in
            guard point.value.isFinite, point.value >= 0 else {
                previous = nil
                segment += 1
                return nil
            }
            if let last = previous {
                let elapsed = point.date.timeIntervalSince(last.date)
                if last.segment != point.segment || elapsed > maximumGap || elapsed < 0 { segment += 1 }
            }
            previous = point
            return PerformanceChartPoint(point: point, segment: segment)
        }
    }
}
