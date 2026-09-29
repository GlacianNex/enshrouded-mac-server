import Foundation

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
    public var lastAutomaticManifest: String?
    public init() {}
    public func next(after date: Date, calendar: Calendar = .current) -> Date? {
        guard restartEnabled, (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        if let days = everyDays, days > 1 {
            let anchor = calendar.startOfDay(for: anchorDate ?? date)
            let today = calendar.startOfDay(for: date)
            let elapsed = max(0, calendar.dateComponents([.day], from: anchor, to: today).day ?? 0)
            let remainder = elapsed % days
            let advance = remainder == 0 ? 0 : days - remainder
            guard let targetDay = calendar.date(byAdding: .day, value: advance, to: today), let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: targetDay) else { return nil }
            return candidate > date ? candidate : calendar.date(byAdding: .day, value: days, to: candidate)
        }
        return weekdays.filter { (1...7).contains($0) }.compactMap { day in
            calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute, weekday: day), matchingPolicy: .nextTime, repeatedTimePolicy: .first)
        }.min()
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
