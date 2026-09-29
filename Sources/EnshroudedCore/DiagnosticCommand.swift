import Foundation
import Darwin

/// Bounded, read-only runtime probes. Server lifecycle commands use their own
/// completion rules and must not be routed through this timeout policy.
public enum DiagnosticCommand {
    public static func run(executable: URL, arguments: [String], environment: [String: String],
                           directory: URL, timeout: TimeInterval,
                           output: (String) -> Void) throws -> String {
        guard timeout.isFinite, timeout > 0 else { throw EngineError("Diagnostic timeout must be positive") }
        let process = Process(), pipe = Pipe()
        process.executableURL = executable; process.arguments = arguments
        process.environment = environment; process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe; process.standardError = pipe
        defer {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
        let fd = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw EngineError("Cannot read diagnostic output")
        }
        try process.run()
        try pipe.fileHandleForWriting.close()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var captured = Data(), bytes = [UInt8](repeating: 0, count: 8192)
        var timedOut = false, streamClosed = false
        while true {
            // Limit work per iteration even if a child writes continuously.
            for _ in 0..<16 {
                let count = Darwin.read(fd, &bytes, bytes.count)
                if count > 0 {
                    let chunk = Data(bytes.prefix(count))
                    captured.append(chunk)
                    if captured.count > 128_000 { captured.removeFirst(captured.count - 128_000) }
                    output(String(decoding: chunk, as: UTF8.self))
                } else {
                    if count == 0 { streamClosed = true }
                    break
                }
            }
            if !process.isRunning { break }
            if ProcessInfo.processInfo.systemUptime >= deadline { timedOut = true; break }
            if streamClosed { Thread.sleep(forTimeInterval: 0.025) }
            else {
                var descriptor = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
                _ = Darwin.poll(&descriptor, 1, 25)
            }
            // An inherited pipe may remain open after the command exits. Only
            // the direct command's lifetime determines completion, never EOF.
        }
        if timedOut {
            // This is only the probe's Process, never a server PID or process
            // group. Killing its local client does not stop the guest service.
            if process.isRunning { process.terminate() }
            let grace = ProcessInfo.processInfo.systemUptime + 0.2
            while process.isRunning && ProcessInfo.processInfo.systemUptime < grace {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        let result = String(decoding: captured, as: UTF8.self)
        if timedOut { throw EngineError("Status check timed out. Try again; the server was not stopped.") }
        guard process.terminationStatus == 0 else {
            throw EngineError("Operation failed (\(process.terminationStatus)). \(result.suffix(1500))")
        }
        return result
    }
}
