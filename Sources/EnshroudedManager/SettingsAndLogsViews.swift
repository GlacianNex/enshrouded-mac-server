import SwiftUI
import AppKit
import EnshroudedCore

struct SettingsView: View {
    @ObservedObject var model: Model
    @State var draft: ServerSettings
    @State private var reveal = false
    @State private var rules: [GameplayRule] = []
    @State private var ruleValues: [String: String] = [:]
    @State private var originalRules: [String: String] = [:]
    @State private var rulesLoaded = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(model.stopped ? "Server Settings" : "Server Settings · Read Only").font(.title2.bold())
                Spacer()
            }
            if !model.stopped { Text("Save and stop the server to edit settings.").foregroundStyle(.secondary) }
            Form {
                Section("Server") {
                    TextField("Server name", text: $draft.name)
                    Stepper("Player slots: \(draft.slots)", value: $draft.slots, in: 1...16)
                    Text("Maximum number of players who can join (1–16).").font(.caption).foregroundStyle(.secondary)
                    Button("Import World…") { model.chooseWorldImport() }
                }.disabled(!model.canEdit)
                Section("World Rules") {
                    Picker("Difficulty preset", selection: $draft.preset) {
                        ForEach(ServerSettings.presets, id: \.self) { Text($0).tag($0) }
                    }.disabled(!model.canEdit).help("Choose a preset managed by the game. Editing an individual rule automatically selects Custom.")
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
                    ), original: originalRules, canEdit: model.canEdit)
                }
                Section("Role Passwords") {
                    if reveal { TextField("Player (Friend)", text: $draft.password); TextField("Admin", text: $draft.adminPassword) }
                    else { SecureField("Player (Friend)", text: $draft.password); SecureField("Admin", text: $draft.adminPassword) }
                    Toggle("Show passwords", isOn: $reveal)
                    Text("Use different player and admin passwords, each at least 8 characters.").font(.caption).foregroundStyle(.secondary)
                }.disabled(!model.canEdit)
                Section("Chat") {
                    Toggle("Enable text chat", isOn: $draft.textChat)
                    Toggle("Enable voice chat", isOn: $draft.voice)
                    Picker("Voice range", selection: $draft.voiceMode) { Text("Proximity").tag("Proximity"); Text("Server-wide").tag("Global") }.disabled(!draft.voice)
                }.disabled(!model.canEdit)
            }.formStyle(.grouped)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Text("Changes take effect on the next server start.").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("Cancel") { dismiss() }.disabled(model.busy)
                Button("Save Settings", action: save).disabled(!model.canEdit || !rulesLoaded).keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 640, height: 680)
        .onAppear {
            do {
                rules = try model.engine.gameplayRules()
                let saved = try model.engine.gameplayValues()
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
            let settings = draft
            error = nil
            model.operation("Save settings", work: { try $0.saveSettings(settings, worldRules: changed) }, completion: { success in
                if success { dismiss() }
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
    @ObservedObject var model: Model
    @State private var selected = "Server"
    @State private var filter = ""
    @State private var autoScroll = true
    @State private var wrapText = true
    @State private var currentServerLog = ""
    @State private var loading = true
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Server Logs").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            Picker("Log", selection: $selected) { Text("Server").tag("Server"); Text("Manager Activity").tag("Manager") }.pickerStyle(.segmented)
            TextField("Filter log lines", text: $filter)
            HStack(spacing: 16) {
                Toggle("Auto-scroll", isOn: $autoScroll).toggleStyle(.checkbox)
                    .help("Follow new log lines. Turn off to read earlier lines.")
                Toggle("Wrap Text", isOn: $wrapText).toggleStyle(.checkbox)
                    .help("Wrap long lines to fit the window. Copy keeps the original line breaks.")
                Spacer()
            }
            LogTextPane(text: displayed, wrap: wrapText, follow: autoScroll)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(selected == "Server" ? "Latest 256 KB · refreshes every second" : "Recent manager activity")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("Open Log Folder") { NSWorkspace.shared.open(selected == "Server" ? model.engine.data.appendingPathComponent("logs") : model.engine.home) }
            }
        }.padding(20).frame(width: 820, height: 580)
        .task {
            let engine = model.engine
            while !Task.isCancelled {
                let text = await Task.detached(priority: .utility) { engine.logTail() }.value
                guard !Task.isCancelled else { return }
                if currentServerLog != text { currentServerLog = text }
                loading = false
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }
    }
    var filtered: String {
        LogDisplay.readable(selected == "Server" ? currentServerLog : model.activity, filter: filter)
    }
    private var displayed: String {
        if selected == "Server" && loading { return "Loading logs…" }
        if !filtered.isEmpty { return filtered }
        if !filter.isEmpty { return "No matching log lines." }
        return selected == "Server" ? "No server log yet. Start the server to create one." : "No manager activity recorded yet."
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
