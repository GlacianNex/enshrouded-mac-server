import Foundation

public struct BuildInfo: Equatable {
    public let version: String
    public let build: String
    public let experimental: Bool
    public let builtAt: String
    public init(version: String, build: String, experimental: Bool, builtAt: String = "") {
        self.version = version; self.build = build; self.experimental = experimental; self.builtAt = builtAt
    }
    public init(bundle: Bundle = .main) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        experimental = bundle.object(forInfoDictionaryKey: "ESMReleaseChannel") as? String == "experimental"
        builtAt = bundle.object(forInfoDictionaryKey: "ESMBuildDate") as? String ?? ""
    }
    public var label: String { experimental ? "Experimental" : version }
    public var detail: String { "\(label) · build \(build)\(builtAt.isEmpty ? "" : " · " + builtAt)" }
    public func canReplace(_ installed: BuildInfo) -> Bool {
        if experimental { return true }
        if installed.experimental { return true }
        return version.compare(installed.version, options: .numeric) == .orderedDescending
    }
    public static func read(app: URL) throws -> BuildInfo {
        guard let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "com.glaciannex.enshrouded-manager",
              let version = info["CFBundleShortVersionString"] as? String,
              version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil,
              let build = info["CFBundleVersion"] as? String else { throw EngineError("Choose an Enshrouded Server Manager app") }
        return BuildInfo(version: version, build: build, experimental: info["ESMReleaseChannel"] as? String == "experimental", builtAt: info["ESMBuildDate"] as? String ?? "")
    }
}
