import Foundation

/// Resolves an exported save without touching the installed world. Temporary files
/// remain available for the entire import transaction, then are removed.
public enum WorldImportSource {
    static let maximumBytes = 1_000_000_000
    static let maximumEntries = 10_000
    public static func withPreparedWorld(at source: URL, body: (URL) throws -> Void) throws {
        let fm = FileManager.default
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
        guard values.isSymbolicLink != true else { throw EngineError("World imports cannot contain symbolic links.") }
        if values.isDirectory == true { try body(resolve(in: source)); return }
        guard values.isRegularFile == true else { throw EngineError("Choose a world file, folder, or ZIP archive.") }
        if primary(source.lastPathComponent) { try validateFamily(source); try body(source); return }
        guard source.pathExtension.lowercased() == "zip" else { throw EngineError("Choose an eight-character world file, a world folder, or a ZIP archive.") }
        let root = fm.temporaryDirectory.appendingPathComponent("Enshrouded-world-import-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: root) }
        // Snapshot the archive so it cannot change between validation and extraction.
        let archive = root.appendingPathComponent("source.zip")
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= maximumBytes else { throw EngineError("The world archive is empty or too large (limit: 1 GB).") }
        try fm.copyItem(at: source, to: archive)
        let entries = try zipEntries(Data(contentsOf: archive, options: .mappedIfSafe))
        let extracted = root.appendingPathComponent("world")
        try fm.createDirectory(at: extracted, withIntermediateDirectories: false)
        for entry in entries where !entry.directory {
            let destination = extracted.appendingPathComponent(entry.path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: destination.path, contents: nil) else { throw EngineError("Could not prepare the imported world.") }
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-p", archive.path, entry.path]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            try process.run()
            var bytes = 0
            do {
                while let chunk = try pipe.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
                    bytes += chunk.count
                    guard bytes <= entry.size else { throw EngineError("The world archive expands beyond its declared size.") }
                    try output.write(contentsOf: chunk)
                }
            } catch {
                try? pipe.fileHandleForReading.close()
                if process.isRunning { process.terminate() }
                process.waitUntilExit()
                throw error
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0, bytes == entry.size else { throw EngineError("The world archive is damaged or incomplete.") }
        }
        try body(resolve(in: extracted))
    }
    private static func primary(_ name: String) -> Bool {
        name.range(of: #"^[0-9a-fA-F]{8}$"#, options: .regularExpression) != nil
    }
    private static func validateFamily(_ file: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        for item in files where item.lastPathComponent.range(of: "^" + file.lastPathComponent + #"(?:-\d+|-index|_info)?$"#, options: .regularExpression) != nil {
            let value = try item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard value.isRegularFile == true, value.isSymbolicLink != true else { throw EngineError("World imports cannot contain symbolic links or special files.") }
        }
        guard (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 > 0 else { throw EngineError("The selected world file is empty.") }
    }
    private static func resolve(in root: URL) throws -> URL {
        var candidates: [URL] = [], count = 0
        var pending = [root]
        while let directory = pending.popLast() {
            for item in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]) {
                count += 1
                guard count <= maximumEntries else { throw EngineError("The world folder contains too many files.") }
                let value = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
                guard value.isSymbolicLink != true else { throw EngineError("World imports cannot contain symbolic links.") }
                if value.isDirectory == true { pending.append(item) }
                else if value.isRegularFile == true, primary(item.lastPathComponent) { candidates.append(item) }
            }
        }
        guard candidates.count == 1 else {
            throw EngineError(candidates.isEmpty ? "No Enshrouded world was found. Choose its eight-character world file." : "This folder or archive contains multiple worlds. Choose the specific eight-character world file to import.")
        }
        try validateFamily(candidates[0]); return candidates[0]
    }
    struct Entry { let path: String; let size: Int; let directory: Bool }
    static func zipEntries(_ data: Data) throws -> [Entry] {
        func invalid() -> EngineError { EngineError("The world ZIP archive is damaged or has an unsafe or unsupported layout.") }
        func number(_ offset: Int, _ length: Int) throws -> Int {
            guard offset >= 0, offset <= data.count - length else { throw invalid() }
            return (0..<length).reduce(0) { $0 | (Int(data[offset + $1]) << (8 * $1)) }
        }
        guard data.count >= 22, data.count <= maximumBytes else { throw invalid() }
        var end: Int?
        for offset in stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1) {
            if try number(offset, 4) == 0x06054b50, try offset + 22 + number(offset + 20, 2) == data.count { end = offset; break }
        }
        guard let end, try number(end + 4, 2) == 0, try number(end + 6, 2) == 0 else { throw invalid() }
        let count = try number(end + 10, 2), length = try number(end + 12, 4)
        var offset = try number(end + 16, 4)
        guard count > 0, count <= maximumEntries, try number(end + 8, 2) == count, offset + length == end else { throw invalid() }
        var entries: [Entry] = [], paths: [String: Bool] = [:], total = 0
        for _ in 0..<count {
            guard try number(offset, 4) == 0x02014b50 else { throw invalid() }
            let flags = try number(offset + 8, 2), method = try number(offset + 10, 2)
            let size = try number(offset + 24, 4), nameLength = try number(offset + 28, 2)
            let next = try offset + 46 + nameLength + number(offset + 30, 2) + number(offset + 32, 2)
            let mode = try number(offset + 38, 4) >> 16, local = try number(offset + 42, 4)
            guard flags & 1 == 0, [0, 8].contains(method), size <= maximumBytes - total,
                  next <= end, nameLength > 0, local < end, try number(local, 4) == 0x04034b50,
                  let name = String(data: data[(offset + 46)..<(offset + 46 + nameLength)], encoding: .utf8) else { throw invalid() }
            let directory = name.hasSuffix("/")
            let path = directory ? String(name.dropLast()) : name
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.hasPrefix("-"), !components.contains(""), !components.contains("."), !components.contains(".."),
                  !path.contains(where: { $0.asciiValue.map { $0 < 32 } == true || "\\*?[]:".contains($0) }),
                  [0, directory ? 0o040000 : 0o100000].contains(mode & 0o170000),
                  !directory || size == 0 else { throw invalid() }
            let key = path.precomposedStringWithCanonicalMapping.lowercased()
            guard paths.updateValue(directory, forKey: key) == nil else { throw invalid() }
            total += size; entries.append(Entry(path: path, size: size, directory: directory)); offset = next
        }
        guard offset == end else { throw invalid() }
        for key in paths.keys {
            var ancestor = ""
            for component in key.split(separator: "/").dropLast() {
                ancestor += (ancestor.isEmpty ? "" : "/") + component
                if paths[ancestor] == false { throw invalid() }
            }
        }
        return entries
    }
}
