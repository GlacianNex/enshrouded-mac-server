import Foundation
import Compression

/// DepotDownloader's installed-depot map: raw DEFLATE containing a protobuf
/// dictionary (field 1; entry key 1 and value 2). Cached manifest filenames are
/// not installation receipts. Format: SteamRE/DepotDownloader/DepotConfigStore.cs.
enum InstalledDepotManifest {
    static func read(_ data: Data, depot: UInt64 = 2_278_521) -> String? {
        guard !data.isEmpty, data.count < 65_536 else { return nil }
        var output = [UInt8](repeating: 0, count: 65_536)
        let count = data.withUnsafeBytes { source in
            compression_decode_buffer(&output, 65_536, source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
        guard count > 0, count < output.count else { return nil }
        var reader = Reader(bytes: Array(output.prefix(count)))
        var installed: UInt64?
        do {
            while !reader.finished {
                let tag = try reader.varint()
                if tag == 10 {
                    var entry = Reader(bytes: try reader.blob())
                    var key: UInt64 = 0, value: UInt64 = 0
                    while !entry.finished {
                        let field = try entry.varint()
                        if field == 8 { key = try entry.varint() }
                        else if field == 16 { value = try entry.varint() }
                        else { try entry.skip(field) }
                    }
                    if key == depot { installed = value }
                } else { try reader.skip(tag) }
            }
        } catch { return nil }
        guard let installed, installed != 0, installed != UInt64.max else { return nil }
        return String(installed)
    }
    private struct Reader {
        let bytes: [UInt8]
        var offset = 0
        var finished: Bool { offset == bytes.count }
        enum Invalid: Error { case data }
        mutating func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for shift in stride(from: 0, through: 63, by: 7) {
                guard offset < bytes.count else { throw Invalid.data }
                let byte = bytes[offset]; offset += 1
                guard shift != 63 || byte <= 1 else { throw Invalid.data }
                value |= UInt64(byte & 127) << shift
                if byte & 128 == 0 { return value }
            }
            throw Invalid.data
        }
        mutating func take(_ count: UInt64) throws -> [UInt8] {
            guard count <= UInt64(bytes.count - offset) else { throw Invalid.data }
            defer { offset += Int(count) }
            return Array(bytes[offset..<(offset + Int(count))])
        }
        mutating func blob() throws -> [UInt8] { let length = try varint(); return try take(length) }
        mutating func skip(_ tag: UInt64) throws {
            guard tag >> 3 != 0 else { throw Invalid.data }
            switch tag & 7 {
            case 0: _ = try varint()
            case 1: _ = try take(8)
            case 2: _ = try blob()
            case 5: _ = try take(4)
            default: throw Invalid.data
            }
        }
    }
}
