import Foundation
import Darwin

public enum HostPortAvailability {
    /// The caller must verify that an optional PID belongs to this server's
    /// current host agent. This helper never discovers or guesses ownership.
    public static func ensureAvailable(port: UInt16, ownedHostAgentPID: Int32? = nil) throws {
        guard port > 0 else { throw EngineError("Choose a UDP port from 1–65535.") }
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { throw EngineError("Could not check UDP port \(port): \(String(cString: strerror(errno))).") }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if bound == 0 { return }
        let failure = errno
        guard failure == EADDRINUSE else {
            throw EngineError("Could not check UDP port \(port): \(String(cString: strerror(failure))).")
        }
        func occupied() -> EngineError {
            EngineError("UDP port \(port) is already in use. Choose another port or stop the app using it. No running server was changed.")
        }
        guard let owner = ownedHostAgentPID, owner > 0, let identity = ProcessLifetime(pid: owner) else { throw occupied() }
        let listing: String
        var outputBytes = 0
        do {
            listing = try DiagnosticCommand.run(executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
                arguments: ["-n", "-P", "-Fpn", "-iUDP:\(port)"],
                environment: ProcessInfo.processInfo.environment,
                directory: FileManager.default.temporaryDirectory, timeout: 5,
                timeoutMessage: "Could not verify who is using UDP port \(port). Try again; no server was changed.") {
                    outputBytes += $0.utf8.count
                }
        } catch {
            throw EngineError("Could not verify who is using UDP port \(port). Try again or choose another port. No running server was changed.")
        }
        // Truncated output cannot establish exclusive ownership. Check identity
        // again after lsof so a PID reused during the probe is never accepted.
        guard outputBytes < 128_000, identity.isRunning,
              localOwners(in: listing, port: port) == Set([owner]) else { throw occupied() }
    }

    static func localOwners(in listing: String, port: UInt16) -> Set<Int32> {
        var owners: Set<Int32> = [], current: Int32?
        for line in listing.split(separator: "\n") {
            if line.first == "p" { current = Int32(line.dropFirst()); continue }
            guard line.first == "n", let current else { continue }
            // lsof's -iUDP filter matches remote endpoints too. Only a local
            // endpoint bound to our requested port establishes port ownership.
            let local = line.dropFirst().components(separatedBy: "->")[0]
            guard let suffix = local.split(separator: ":").last,
                  UInt16(suffix) == port else { continue }
            owners.insert(current)
        }
        return owners
    }
}
