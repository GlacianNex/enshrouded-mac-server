import Foundation
import Darwin
import IOKit.pwr_mgt

/// The guard owns sleep protection outside the UI. It never starts/stops a VM.
public enum HostingGuard {
    public static func ensure(engine: Engine, executable: URL) throws {
        let file = engine.home.appendingPathComponent("hosting-guard.lock")
        let fd = open(file.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw EngineError("Could not prepare hosting sleep protection") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return }
        flock(fd, LOCK_UN)
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--hosting-guard", engine.home.path]
        process.environment = ProcessInfo.processInfo.environment.merging(["ESM_RESOURCES": engine.resources.path]) { _, new in new }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
    public static func run(engine: Engine) throws {
        let fd = open(engine.home.appendingPathComponent("hosting-guard.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return }
        let receipt = engine.home.appendingPathComponent("hosting-guard.pid")
        try String(getpid()).write(to: receipt, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: receipt) }
        watch(home: engine.home, status: { try? engine.status() }, enabled: {
            !FileManager.default.fileExists(atPath: engine.home.appendingPathComponent("prevent-sleep.disabled").path)
        }, acquire: {
            var assertion: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Hosting Enshrouded" as CFString, &assertion)
            return assertion
        }, release: { IOPMAssertionRelease($0) })
    }
    static func watch(home: URL, status: () -> String?, enabled: () -> Bool, now: () -> Date = Date.init,
                      pause: () -> Void = { Thread.sleep(forTimeInterval: 5) }, acquire: () -> IOPMAssertionID,
                      release: (IOPMAssertionID) -> Void) {
        var assertion: IOPMAssertionID = 0
        defer { if assertion != 0 { release(assertion) } }
        var lastRunning = now()
        while FileManager.default.fileExists(atPath: home.path) {
            let status = status()
            let enabled = enabled()
            let hosting = status == "RUNNING" || status == "RECOVERING"
            if hosting { lastRunning = now() }
            if enabled && hosting && assertion == 0 {
                assertion = acquire()
            } else if (!enabled || status == "INSTALLED" || status == "VM_STOPPED" || status == "NOT_INSTALLED") && assertion != 0 {
                release(assertion); assertion = 0
            }
            if status == "VM_STOPPED" || status == "NOT_INSTALLED" { return }
            // Keep observing through the 30-second crash recovery interval,
            // but hold no sleep assertion while the game is stopped.
            if status == "INSTALLED" && now().timeIntervalSince(lastRunning) >= 60 { return }
            pause()
        }
    }
}
