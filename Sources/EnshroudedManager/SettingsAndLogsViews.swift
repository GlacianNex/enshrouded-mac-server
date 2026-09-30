import SwiftUI
import AppKit
import EnshroudedCore

struct SettingsView: View {
    @ObservedObject var model: Model
    @State var draft: ServerSettings
    let initiallyReadOnly: Bool
    @State private var originalConfiguration: Data?
    @State private var originalPort: UInt16 = 0
    private var canEdit: Bool { !initiallyReadOnly && model.canEdit }
    @State private var reveal = false
    @State private var rules: [GameplayRule] = []
    @State private var ruleValues: [String: String] = [:]
    @State private var originalRules: [String: String] = [:]
    @State private var rulesLoaded = false
    @State private var error: String?
    var close: () -> Void
    @State private var port = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(initiallyReadOnly || !model.stopped ? "Server Settings · Read Only" : "Server Settings").font(.title2.bold())
                Spacer()
            }
            if initiallyReadOnly { Text("Close this window, stop the server, then reopen settings to edit.").foregroundStyle(.secondary) }
            Form {
                Section("Server") {
                    if initiallyReadOnly { LabeledContent("Server Name", value: draft.name).textSelection(.enabled) }
                    else { TextField("Server name", text: $draft.name).help("The name players see in Enshrouded’s dedicated server browser.") }
                    TextField("UDP Port", text: $port).disabled(!canEdit).help("Forward this UDP port on your router. Changing it shuts down this server’s idle environment; start the server to apply it.")
                    Stepper("Player slots: \(draft.slots)", value: $draft.slots, in: 1...16).disabled(!canEdit).help("Maximum simultaneous players. Applies the next time this server starts.")
                    Text("Maximum number of players who can join (1–16).").font(.caption).foregroundStyle(.secondary)
                    Button("Import World…") { model.chooseWorldImport() }.disabled(!canEdit)
                }.disabled(!canEdit && !initiallyReadOnly)
                Section("World Rules") {
                    Picker("Difficulty preset", selection: $draft.preset) {
                        ForEach(ServerSettings.presets, id: \.self) { Text($0).tag($0) }
                    }.disabled(!canEdit).help("Choose a preset managed by the game. Editing an individual rule automatically selects Custom.")
                    Text(presetHelp).font(.caption).foregroundStyle(.secondary)
                    if draft.preset == "Custom" {
                        Text("Edit the saved rules below. Multipliers use 1× for normal; durations are in minutes.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Changing a rule below automatically selects Custom. These are your saved custom values; presets apply their own values when the server starts.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    GameplayRulesView(rules: rules, values: Binding(
                        get: { ruleValues },
                        set: { ruleValues = $0; draft.preset = "Custom" }
                    ), original: originalRules, canEdit: canEdit)
                }
                Section("Role Passwords") {
                    if reveal && initiallyReadOnly {
                        LabeledContent("Player (Friend)", value: draft.password).textSelection(.enabled)
                        LabeledContent("Admin", value: draft.adminPassword).textSelection(.enabled)
                    } else if reveal { TextField("Player (Friend)", text: $draft.password).disabled(!canEdit); TextField("Admin", text: $draft.adminPassword).disabled(!canEdit) }
                    else { SecureField("Player (Friend)", text: $draft.password).disabled(!canEdit); SecureField("Admin", text: $draft.adminPassword).disabled(!canEdit) }
                    Toggle("Show passwords", isOn: $reveal).disabled(false)
                    Text("Use different player and admin passwords, each at least 8 characters.").font(.caption).foregroundStyle(.secondary)
                        .help("The Friend password grants normal play; the Admin password grants server administration. Never share the Admin password with ordinary players.")
                }
                Section("Chat") {
                    Toggle("Enable text chat", isOn: $draft.textChat).help("Allow players to send text messages in this server’s chat.")
                    Toggle("Enable voice chat", isOn: $draft.voice).help("Allow players to speak using Enshrouded’s voice chat.")
                    Picker("Voice range", selection: $draft.voiceMode) { Text("Proximity").tag("Proximity"); Text("Server-wide").tag("Global") }.disabled(!draft.voice).help("Proximity limits voice to nearby players. Server-wide lets everyone hear it.")
                }.disabled(!canEdit)
            }.formStyle(.grouped)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Text("Changes take effect on the next server start.").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button(canEdit ? "Cancel" : "Close") { close() }
                if canEdit { Button("Save Settings", action: save).disabled(!rulesLoaded).keyboardShortcut(.defaultAction) }
            }
        }.padding(22).frame(minWidth: 640, minHeight: 680)
        .onAppear {
            originalPort = model.engine.hostPort
            port = String(originalPort)
            do {
                let configuration = try Data(contentsOf: model.engine.serverConfig)
                guard let value = try JSONSerialization.jsonObject(with: configuration) as? [String: Any] else { throw EngineError("Invalid server configuration") }
                originalConfiguration = configuration
                draft = ServerSettings(config: value)
                rules = try model.engine.gameplayRules()
                let saved = value["gameSettings"] as? [String: Any] ?? [:]
                originalRules = Dictionary(uniqueKeysWithValues: rules.map { ($0.key, $0.display(saved[$0.key])) })
                ruleValues = originalRules
                rulesLoaded = true
            } catch { self.error = error.localizedDescription }
        }
    }
    private func save() {
        do {
            _ = try draft.applying(to: [:])
            let changed = draft.preset == "Custom" ? ruleValues.filter { originalRules[$0.key] != $0.value } : [:]
            for rule in rules { if let value = changed[rule.key] { _ = try rule.parse(value) } }
            guard let newPort = Int(port), (1024...65535).contains(newPort) else { throw EngineError("Enter a UDP port from 1024–65535.") }
            guard model.engine.hostPort == originalPort, let originalConfiguration else { throw EngineError("Settings changed or are unavailable. Close and reopen Server Settings.") }
            let oldPort = Int(originalPort)
            let store = model.profileStore
            let settings = draft
            error = nil
            model.operation("Save settings", work: { engine in
                guard try Data(contentsOf: engine.serverConfig) == originalConfiguration else { throw EngineError("Settings changed since this window opened. Close and reopen Server Settings.") }
                if newPort != oldPort {
                    guard let store else { throw EngineError("Server registration is unavailable. Reopen the manager and try again.") }
                    try engine.changeHostPort(to: newPort, store: store)
                }
                do { try engine.saveSettings(settings, worldRules: changed, expectedConfiguration: originalConfiguration) }
                catch {
                    if newPort != oldPort, let store {
                        do { try engine.changeHostPort(to: oldPort, store: store) }
                        catch { throw EngineError("Settings were not saved; the UDP port is now \(engine.hostPort). Review the port before starting.") }
                    }
                    throw error
                }
            }, completion: { success in
                if success { close() }
                else { error = model.error ?? "Settings could not be saved. Try again." }
            })
        } catch { self.error = error.localizedDescription }
    }
    var presetHelp: String {
        switch draft.preset {
        case "Relaxed": return "Fewer enemies and more resources, for building and lighter adventuring."
        case "Hard": return "More enemies and more aggressive combat."
        case "Survival": return "Additional survival mechanics and more aggressive enemies."
        case "Custom": return "Set individual rules for everyone playing on this server. Starts from your saved custom values."
        default: return "The standard Enshrouded experience, recommended for a first playthrough."
        }
    }
}
struct LogsView: View {
    private let engine: Engine?
    private let updateLog: URL?
    @State private var selected = "Server"
    @State private var filter = ""
    @State private var autoScroll = true
    @State private var wrapText = true
    @State private var currentServerLog = ""
    @State private var currentManagerLog = ""
    @State private var currentSetupLog = ""
    @State private var loading = true
    var close: () -> Void
    init(model: Model, close: @escaping () -> Void) {
        engine = model.engine; updateLog = nil; self.close = close
        _selected = State(initialValue: model.installationPending || model.setupProgress != nil ? "Setup" : "Server")
    }
    init(updateLog: URL, close: @escaping () -> Void) {
        engine = nil; self.updateLog = updateLog; self.close = close
        _selected = State(initialValue: "Manager")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(updateLog == nil ? "Server Logs" : "Manager Update Log").font(.title2.bold()); Spacer(); Button("Done", action: close) }
            if updateLog == nil {
                Picker("Log", selection: $selected) { Text("Server").tag("Server"); Text("Manager Activity").tag("Manager"); Text("Installation").tag("Setup") }.pickerStyle(.segmented)
            }
            TextField("Filter log lines", text: $filter)
            HStack(spacing: 16) {
                Toggle("Auto-scroll", isOn: $autoScroll).toggleStyle(.checkbox)
                    .help("Follow new log lines. Turn off to read earlier lines.")
                Toggle("Wrap Text", isOn: $wrapText).toggleStyle(.checkbox)
                    .help("Wrap long lines to fit the window. Copy keeps the original line breaks.")
                Spacer()
            }
            LogTextPane(text: displayed, wrap: wrapText, follow: autoScroll)
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            HStack {
                Text(selected == "Server" ? "Latest 256 KB · refreshes every second" : selected == "Setup" ? "Server installation output · refreshes every second" : "Server manager activity · refreshes every second")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("Open Log Folder") {
                    if let updateLog { NSWorkspace.shared.open(updateLog.deletingLastPathComponent()) }
                    else if let engine { NSWorkspace.shared.open(selected == "Server" ? engine.serverLogFolder : selected == "Setup" ? engine.setupLogEngine.home : engine.home) }
                }
            }
        }.padding(20).frame(minWidth: 620, minHeight: 400)
        .task {
            while !Task.isCancelled {
                let logs = await Task.detached(priority: .utility) { () -> (String, String, String) in
                    if let updateLog {
                        do { return ("", String(decoding: try ManagerActivityLog.read(updateLog), as: UTF8.self), "") }
                        catch { return ("", "Could not read update log: " + error.localizedDescription, "") }
                    }
                    guard let engine else { return ("", "", "") }
                    return (engine.logTail(), engine.activityTail(), engine.setupLogEngine.activityTail())
                }.value
                guard !Task.isCancelled else { return }
                if currentServerLog != logs.0 { currentServerLog = logs.0 }
                if currentManagerLog != logs.1 { currentManagerLog = logs.1 }
                if currentSetupLog != logs.2 { currentSetupLog = logs.2 }
                loading = false
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }
    }
    var filtered: String {
        LogDisplay.readable(selected == "Server" ? currentServerLog : selected == "Setup" ? currentSetupLog : currentManagerLog, filter: filter)
    }
    private var displayed: String {
        if loading { return "Loading logs…" }
        if !filtered.isEmpty { return filtered }
        if !filter.isEmpty { return "No matching log lines." }
        return selected == "Server" ? "No server log yet. Start the server to create one." : selected == "Setup" ? "No installation output recorded yet." : "No manager activity recorded yet."
    }
}

private struct LogTextPane: NSViewRepresentable {
    let text: String
    let wrap: Bool
    let follow: Bool
    func makeNSView(context: Context) -> LogTextScrollView { LogTextScrollView() }
    func updateNSView(_ view: LogTextScrollView, context: Context) {
        view.update(text: text, wrap: wrap, follow: follow)
    }
}

/// Native plain-text selection preserves original line breaks when copying wrapped text.
private final class LogTextScrollView: NSScrollView {
    private let logText = NSTextView(frame: .zero)
    private var wrapping = true
    private var following = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        hasVerticalScroller = true
        borderType = .bezelBorder
        logText.isEditable = false
        logText.isSelectable = true
        logText.isRichText = false
        logText.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logText.textColor = .textColor
        logText.backgroundColor = .textBackgroundColor
        logText.textContainerInset = NSSize(width: 8, height: 8)
        logText.minSize = .zero
        logText.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        logText.isVerticallyResizable = true
        documentView = logText
        let gutter = LogLineRuler(scrollView: self, orientation: .verticalRuler)
        gutter.clientView = logText
        gutter.ruleThickness = 56
        verticalRulerView = gutter
        hasVerticalRuler = true
        rulersVisible = true
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: contentView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func scrolled() { verticalRulerView?.needsDisplay = true }
    override func tile() {
        super.tile()
        if wrapping {
            logText.setFrameSize(NSSize(width: contentSize.width, height: logText.frame.height))
            logText.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        }
        verticalRulerView?.needsDisplay = true
    }
    func update(text: String, wrap: Bool, follow: Bool) {
        let changed = logText.string != text
        let shouldFollow = follow && (changed || !following || wrapping != wrap)
        let origin = contentView.bounds.origin
        let selection = logText.selectedRange()
        wrapping = wrap
        following = follow
        hasHorizontalScroller = !wrap
        logText.isHorizontallyResizable = !wrap
        logText.autoresizingMask = wrap ? [.width] : []
        logText.textContainer?.widthTracksTextView = wrap
        logText.textContainer?.containerSize = NSSize(width: wrap ? contentSize.width : CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if changed {
            logText.string = text
            let count = (text as NSString).length
            let start = min(selection.location, count)
            logText.setSelectedRange(NSRange(location: start, length: min(selection.length, count - start)))
        }
        tile()
        if let container = logText.textContainer { logText.layoutManager?.ensureLayout(for: container) }
        logText.sizeToFit()
        if shouldFollow && selection.length == 0 {
            logText.scrollRangeToVisible(NSRange(location: (text as NSString).length, length: 0))
        } else if changed {
            contentView.scroll(to: origin)
            reflectScrolledClipView(contentView)
        }
        verticalRulerView?.needsDisplay = true
    }
}

/// Draw line numbers separately so Copy contains only the original log text.
private final class LogLineRuler: NSRulerView {
    override func drawHashMarksAndLabels(in rect: NSRect) {
        // SwiftUI hosting can disable ancestor clipping. Confine all ruler
        // drawing, including its background, to this scroll view’s gutter.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds.intersection(rect)).addClip()
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard let textView = clientView as? NSTextView, let layout = textView.layoutManager else { return }
        let source = textView.string as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        var offset = 0, number = 1
        while offset < source.length {
            let glyph = layout.glyphIndexForCharacter(at: offset)
            let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let point = convert(NSPoint(x: 0, y: fragment.minY + textView.textContainerOrigin.y), from: textView)
            if point.y > bounds.maxY { break }
            if point.y + fragment.height >= bounds.minY {
                let label = String(number) as NSString
                label.draw(at: NSPoint(x: ruleThickness - label.size(withAttributes: attributes).width - 8, y: point.y), withAttributes: attributes)
            }
            offset = NSMaxRange(source.lineRange(for: NSRange(location: offset, length: 0)))
            number += 1
        }
    }
}
