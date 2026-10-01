import Foundation
import Darwin

/// One server startup at a time across manager and login-helper processes.
/// The OS releases the slot if its owner exits, including an unexpected exit.
enum ServerStartupLock {
    static func run<T>(at url: URL, timeout: TimeInterval = 900,
                       output: (String) -> Void, work: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw EngineError("Could not prepare the server startup queue.") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw EngineError("The server startup lock must be a regular file.")
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var announced = false
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN || errno == EINTR else {
                throw EngineError("Could not enter the server startup queue.")
            }
            if !announced {
                output("Waiting for another server to finish starting…\n")
                announced = true
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw EngineError("Another server has not finished starting. Try Start Server again when it finishes.")
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        defer { flock(fd, LOCK_UN) }
        output("Starting server…\n")
        return try work()
    }
}
