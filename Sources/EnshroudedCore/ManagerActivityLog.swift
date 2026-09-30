import Foundation
import Darwin

public enum ManagerActivityLog {
    public static let limit = 256 * 1024

    /// Keep complete trailing lines when possible, without splitting UTF-8 characters.
    static func bounded(_ bytes: Data) -> Data {
        guard bytes.count > limit else { return bytes }
        var tail = Data(bytes.suffix(limit))
        while let first = tail.first, first & 0xC0 == 0x80 { tail.removeFirst() }
        if let newline = tail.firstIndex(of: 10), newline < tail.index(before: tail.endIndex) {
            tail = Data(tail[tail.index(after: newline)...])
        }
        return tail
    }

    public static func read(_ url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        if descriptor < 0 {
            if errno == ENOENT { return Data() }
            throw EngineError("Could not read manager activity")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw EngineError("Manager activity must be a regular file") }
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: size > UInt64(limit) ? size - UInt64(limit) : 0)
        let bytes = try handle.readToEnd() ?? Data()
        return size > UInt64(limit) ? bounded(Data([0]) + bytes) : bytes
    }
}

extension Engine {
    public func activityTail() -> String {
        String(decoding: (try? ManagerActivityLog.read(home.appendingPathComponent("manager-activity.log"))) ?? Data(), as: UTF8.self)
    }

    public func appendActivity(_ text: String) throws {
        guard !text.isEmpty else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lock = home.appendingPathComponent("manager-activity.lock")
        let descriptor = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard descriptor >= 0 else { throw EngineError("Could not lock manager activity") }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              fchmod(descriptor, 0o600) == 0, flock(descriptor, LOCK_EX) == 0 else { throw EngineError("Could not lock manager activity") }
        defer { flock(descriptor, LOCK_UN) }
        let destination = home.appendingPathComponent("manager-activity.log")
        var bytes = try ManagerActivityLog.read(destination)
        bytes.append(contentsOf: text.utf8)
        bytes = ManagerActivityLog.bounded(bytes)
        let stage = home.appendingPathComponent(".manager-activity-\(UUID().uuidString)")
        let stageDescriptor = open(stage.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        guard stageDescriptor >= 0 else { throw EngineError("Could not save manager activity") }
        let handle = FileHandle(fileDescriptor: stageDescriptor, closeOnDealloc: true)
        defer { try? handle.close(); try? fm.removeItem(at: stage) }
        try handle.write(contentsOf: bytes)
        try handle.synchronize()
        // Atomic replacement preserves the existing log if writing the new copy fails.
        guard rename(stage.path, destination.path) == 0 else { throw EngineError("Could not save manager activity") }
    }
}
