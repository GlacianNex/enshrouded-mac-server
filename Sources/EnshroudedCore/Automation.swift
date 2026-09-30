import Foundation

public enum OccupiedRestartPolicy: String, Codable, CaseIterable {
    case wait, skip
}

public struct HostingAutomation: Codable, Equatable {
    public var scheduledBackups: BackupSchedule?
    public var startAtLogin = false
    public var automaticUpdates = false
    public var restartEnabled = false
    public var hour = 4
    public var minute = 0
    public var weekdays = [1,2,3,4,5,6,7]
    public var everyDays: Int? = nil
    public var anchorDate: Date? = nil
    public var nextRestart: Date?
    // Only an occurrence observed while waiting for players may run late.
    public var waitingRestart: Date?
    /// Missing in older settings; retain their wait-until-empty behavior.
    public var occupiedRestartPolicy: OccupiedRestartPolicy?
    public var lastAutomaticManifest: String?
    public init() {}
    public var effectiveOccupiedRestartPolicy: OccupiedRestartPolicy { occupiedRestartPolicy ?? .wait }
    public func next(after date: Date, calendar: Calendar = .current) -> Date? {
        guard restartEnabled, (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        if let days = everyDays, days > 1 {
            let anchor = calendar.startOfDay(for: anchorDate ?? date)
            let today = calendar.startOfDay(for: date)
            let elapsed = calendar.dateComponents([.day], from: anchor, to: today).day ?? 0
            let advance = elapsed <= 0 ? 0 : elapsed + (days - elapsed % days) % days
            guard let targetDay = calendar.date(byAdding: .day, value: advance, to: anchor) else { return nil }
            func occurrence(on day: Date) -> Date? {
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day,
                              matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
            }
            guard let candidate = occurrence(on: targetDay) else { return nil }
            if candidate > date { return candidate }
            // Rebuild the requested local time after a DST gap; adding days to
            // its adjusted time would incorrectly shift future occurrences.
            return calendar.date(byAdding: .day, value: days, to: targetDay).flatMap { occurrence(on: $0) }
        }
        return weekdays.filter { (1...7).contains($0) }.compactMap { day in
            calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute, weekday: day), matchingPolicy: .nextTime, repeatedTimePolicy: .first)
        }.min()
    }

    /// Settings unrelated to restarts must not cancel a pending occurrence.
    public func reconcilingRestart(with previous: HostingAutomation, now: Date = Date(), calendar: Calendar = .current) -> HostingAutomation {
        var result = self
        let changed = restartEnabled != previous.restartEnabled || hour != previous.hour || minute != previous.minute ||
            Set(weekdays) != Set(previous.weekdays) || everyDays != previous.everyDays || anchorDate != previous.anchorDate ||
            effectiveOccupiedRestartPolicy != previous.effectiveOccupiedRestartPolicy
        if changed {
            result.nextRestart = next(after: now, calendar: calendar)
            result.waitingRestart = nil
        } else {
            result.nextRestart = previous.nextRestart
            result.waitingRestart = previous.waitingRestart
        }
        return result
    }
}

public enum ScheduledRestartPolicy {
    public enum Decision: Equatable { case none, waiting, skip, run }
    /// Matches Valheim's missed-occurrence policy without unsupported game warnings.
    public static func decide(automation: HostingAutomation, now: Date, running: Bool, players: Int?) -> Decision {
        guard automation.restartEnabled, let due = automation.nextRestart, due <= now else { return .none }
        guard running else { return .skip }
        if now.timeIntervalSince(due) > 60 && automation.waitingRestart != due { return .skip }
        guard players != 0 else { return .run }
        // Unknown player counts are never treated as an empty server.
        return automation.effectiveOccupiedRestartPolicy == .skip ? .skip : .waiting
    }
}
extension Engine {
    public func loadAutomation() -> HostingAutomation {
        guard let data = try? Data(contentsOf: home.appendingPathComponent("automation.json")), let value = try? JSONDecoder().decode(HostingAutomation.self, from: data) else { return HostingAutomation() }
        return value
    }
    public func saveAutomation(_ value: HostingAutomation) throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: home.appendingPathComponent("automation.json"), options: .atomic)
    }
}

public struct BackupSchedule: Codable, Equatable {
    public var enabled = false
    public var hour = 3
    public var minute = 0
    public var nextRun: Date?
    public init() {}
    public func next(after date: Date, calendar: Calendar = .current) -> Date? {
        guard enabled, (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute),
                                 matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }
}
