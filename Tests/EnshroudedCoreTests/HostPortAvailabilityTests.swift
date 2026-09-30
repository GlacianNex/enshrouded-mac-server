import XCTest
import Darwin
@testable import EnshroudedCore

final class HostPortAvailabilityTests: XCTestCase {
    private func listener() throws -> (Int32, UInt16) {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw EngineError("Test socket failed") }
        addTeardownBlock { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = INADDR_ANY
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else { throw EngineError("Test bind failed") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { throw EngineError("Test port lookup failed") }
        return (fd, UInt16(bigEndian: address.sin_port))
    }
    func testFreePortAccepted() throws {
        // Reserve a candidate with a separate temporary socket, then release it.
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        XCTAssertGreaterThanOrEqual(fd, 0)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound: Int32 = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                guard Darwin.bind(fd, $0, length) == 0 else { return Int32(-1) }
                return getsockname(fd, $0, &length)
            }
        }
        XCTAssertEqual(bound, 0)
        close(fd)
        XCTAssertNoThrow(try HostPortAvailability.ensureAvailable(port: UInt16(bigEndian: address.sin_port)))
    }
    func testOccupiedPortRefusedWithoutAffectingListener() throws {
        let (fd, port) = try listener()
        XCTAssertThrowsError(try HostPortAvailability.ensureAvailable(port: port)) {
            XCTAssertTrue($0.localizedDescription.contains("UDP port \(port) is already in use"))
        }
        XCTAssertGreaterThanOrEqual(fcntl(fd, F_GETFD), 0)
        XCTAssertThrowsError(try HostPortAvailability.ensureAvailable(port: port, ownedHostAgentPID: getppid()))
        XCTAssertGreaterThanOrEqual(fcntl(fd, F_GETFD), 0)
    }
    func testExplicitVerifiedOwnerCanRetainItsExistingPort() throws {
        let (fd, port) = try listener()
        XCTAssertNoThrow(try HostPortAvailability.ensureAvailable(port: port, ownedHostAgentPID: getpid()))
        XCTAssertGreaterThanOrEqual(fcntl(fd, F_GETFD), 0)
    }
    func testOwnershipParserIgnoresRemotePortAndRequiresAllLocalOwners() {
        let listing = "p101\nn*:15637\np202\nn127.0.0.1:54321->127.0.0.1:15637\np303\nn[::1]:15637->127.0.0.1:54321\n"
        XCTAssertEqual(HostPortAvailability.localOwners(in: listing, port: 15637), [101, 303])
        XCTAssertEqual(HostPortAvailability.localOwners(in: "p202\nn127.0.0.1:54321->127.0.0.1:15637\n", port: 15637), [])
        XCTAssertEqual(HostPortAvailability.localOwners(in: "p101\nn*:15637\nn[::]:15637\n", port: 15637), [101])
    }
    func testInvalidOrDeadOwnerNeverAuthorizesOccupiedPort() throws {
        let (_, port) = try listener()
        for owner: Int32 in [0, -1, Int32.max] {
            XCTAssertThrowsError(try HostPortAvailability.ensureAvailable(port: port, ownedHostAgentPID: owner))
        }
        XCTAssertThrowsError(try HostPortAvailability.ensureAvailable(port: 0))
    }
}
