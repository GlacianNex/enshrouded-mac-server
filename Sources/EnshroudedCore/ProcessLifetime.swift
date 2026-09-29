import Foundation
import Darwin

/// Kernel process identity, unaffected by cached NSRunningApplication properties.
public struct ProcessLifetime {
    public let pid: Int32
    private let seconds: UInt64
    private let microseconds: UInt64

    public init?(pid: Int32) {
        guard let info = Self.info(pid), info.pbi_status != SZOMB else { return nil }
        self.pid = pid
        seconds = info.pbi_start_tvsec
        microseconds = info.pbi_start_tvusec
    }

    public var isRunning: Bool {
        guard let info = Self.info(pid), info.pbi_status != SZOMB else { return false }
        return info.pbi_start_tvsec == seconds && info.pbi_start_tvusec == microseconds
    }

    private static func info(_ pid: Int32) -> proc_bsdinfo? {
        var value = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &value, size) == size else { return nil }
        return value
    }
}


public enum ManagerQuitWait {
    /// Call off the main thread so AppKit can deliver normal quit events.
    /// Never force-kill a manager that still owns a live process identity.
    public static func wait(_ lifetimes: [ProcessLifetime], timeout: TimeInterval) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while lifetimes.contains(where: { $0.isRunning }) {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw EngineError("The running manager has not quit. Close any open settings or log windows in the running manager and wait for maintenance to finish, then open this download again. The installed app was not replaced.")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}
