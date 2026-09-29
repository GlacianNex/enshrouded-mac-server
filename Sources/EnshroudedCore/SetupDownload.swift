import Foundation
import CryptoKit

/// Downloads directly into this server's cache. No Python or package manager is needed on macOS.
final class SetupDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let output: (String) -> Void
    private let done = DispatchSemaphore(value: 0)
    private var failure: Error?
    private var lastReport = Date.distantPast
    private init(destination: URL, output: @escaping (String) -> Void) { self.destination = destination; self.output = output }
    static func fetch(_ url: URL, destination: URL, sha256: String, output: @escaping (String) -> Void) throws {
        if FileManager.default.fileExists(atPath: destination.path), try digest(destination) == sha256 {
            output(SetupEvent(.environment, "Using the verified environment download already on this Mac.").line); return
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let delegate = SetupDownload(destination: destination, output: output)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 6 * 3600
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        output(SetupEvent(.environment, "Downloading Ubuntu server environment…", received: 0).line)
        session.downloadTask(with: url).resume()
        delegate.done.wait()
        if let failure = delegate.failure { throw failure }
        output(SetupEvent(.environment, "Checking the environment download…").line)
        guard try digest(destination) == sha256 else {
            try? FileManager.default.removeItem(at: destination)
            throw EngineError("Environment download failed its integrity check. Try setup again.")
        }
    }
    static func digest(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var hash = SHA256()
        while let block = try handle.read(upToCount: 1_048_576), !block.isEmpty { hash.update(data: block) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard Date().timeIntervalSince(lastReport) >= 0.5 || totalBytesWritten == totalBytesExpectedToWrite else { return }
        lastReport = Date()
        output(SetupEvent(.environment, "Downloading Ubuntu server environment…", received: totalBytesWritten,
                          total: totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil).line)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else { throw EngineError("The environment download failed. Check your internet connection and try again.") }
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch { failure = error }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { failure = error }; done.signal()
    }
}
