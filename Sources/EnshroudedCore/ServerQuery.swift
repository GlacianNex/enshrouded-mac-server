import Foundation
import Darwin

public struct ServerQuery {
    public let name: String
    public let players: Int
    public let capacity: Int
    public static func parse(_ data: Data) throws -> ServerQuery {
        let bytes = Array(data)
        guard bytes.count >= 6, Array(bytes.prefix(5)) == [255,255,255,255,73] else { throw EngineError("Invalid Steam server query response") }
        var offset = 6
        func string() throws -> String {
            guard let end = bytes[offset...].firstIndex(of: 0) else { throw EngineError("Truncated server query") }
            let value = String(decoding: bytes[offset..<end], as: UTF8.self); offset = end + 1; return value
        }
        let name = try string()
        _ = try string(); _ = try string(); _ = try string()
        guard offset + 4 <= bytes.count else { throw EngineError("Truncated player count") }
        return ServerQuery(name: name, players: Int(bytes[offset + 2]), capacity: Int(bytes[offset + 3]))
    }
    public static func local(port: UInt16 = 15637) throws -> ServerQuery {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw EngineError("Cannot open server query socket") }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0 else { throw EngineError("Cannot set query timeout") }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian; address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard connected == 0 else { throw EngineError("Cannot connect to server query port") }
        func exchange(_ request: [UInt8]) throws -> Data {
            let sent = request.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
            guard sent == request.count else { throw EngineError("Server query send failed") }
            var response = [UInt8](repeating: 0, count: 65535)
            let count = recv(fd, &response, response.count, 0)
            guard count > 0 else { throw EngineError("Player count unavailable; server query timed out") }
            return Data(response.prefix(count))
        }
        let request: [UInt8] = [255,255,255,255,84] + Array("Source Engine Query".utf8) + [0]
        var response = try exchange(request)
        if response.count >= 9, response[4] == 65 { response = try exchange(request + Array(response[5..<9])) }
        return try parse(response)
    }
}


extension ServerQuery {
    static let guestQueryPython = #"""
def query_response():
 import socket
 s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
 try:
  s.settimeout(0.5);s.connect(('127.0.0.1',15637))
  p=b'\xff'*4+b'TSource Engine Query\0'
  s.send(p);r=s.recv(65535)
  if len(r)>=9 and r[4]==65:
   s.send(p+r[5:9]);r=s.recv(65535)
  return r
 finally: s.close()
"""#
}
extension Engine {
    public func queryServer() throws -> ServerQuery {
        let script = ServerQuery.guestQueryPython + "\nimport base64\nprint(base64.b64encode(query_response()).decode())"
        let reply = try command(["shell", "engine", "python3", "-c", script], output: {_ in})
        guard let data = Data(base64Encoded: reply.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw EngineError("Player count unavailable") }
        return try ServerQuery.parse(data)
    }
}
