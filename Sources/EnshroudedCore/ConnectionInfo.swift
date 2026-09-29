import Foundation
import Darwin

public enum ConnectionInfo {
    public static func isIPv4(_ value: String) -> Bool {
        var address = in_addr()
        return value.withCString { inet_pton(AF_INET, $0, &address) } == 1
    }

    public static func reportedPublicIP(in log: String) -> String? {
        for line in log.split(separator: "\n").reversed() {
            guard let range = line.range(of: "[online] Public ipv4: ") else { continue }
            let value = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if isIPv4(value), value != "0.0.0.0" { return value }
        }
        return nil
    }

    public static func localAddresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var values: [String] = []
        var pointer = head
        while let item = pointer {
            defer { pointer = item.pointee.ifa_next }
            let entry = item.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  entry.ifa_flags & UInt32(IFF_UP) != 0,
                  String(cString: entry.ifa_name).hasPrefix("en") else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                values.append(String(cString: buffer))
            }
        }
        return Array(Set(values)).sorted()
    }
}
