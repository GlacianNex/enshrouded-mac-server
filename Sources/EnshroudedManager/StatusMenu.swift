import AppKit
import EnshroudedCore

@MainActor final class StatusMenu: NSObject, NSMenuDelegate {
    private let fleet: FleetModel
    private let showManagement: () -> Void
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var actions: [StatusMenuAction] = []
    private var liveRows: [() -> Void] = []
    private var tracking = false
    private var timer: Timer?

    init(fleet: FleetModel, showManagement: @escaping () -> Void) {
        self.fleet = fleet; self.showManagement = showManagement
        super.init()
        menu.autoenablesItems = false; menu.delegate = self; item.menu = menu
        refreshStatus()
        // Refresh titles and enabled states in place; never replace hovered rows.
        let statusTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
        RunLoop.main.add(statusTimer, forMode: .common); timer = statusTimer
    }
    func refreshStatus() {
        for update in liveRows { update() }
        item.button?.image = MenuBranding.image(running: fleet.models.contains { $0.state == "RUNNING" }, busy: fleet.models.contains { $0.busy || $0.state == "RECOVERING" })
        item.button?.title = " Enshrouded · \(fleet.menuValue)"
        item.button?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        item.button?.toolTip = "Enshrouded Manager · \(fleet.selected.build.detail)"
        let serverUpdate = fleet.configuredModels.contains { $0.releaseError == nil && $0.release?.updateAvailable == true }
        if fleet.managerUpdateAvailable || serverUpdate, let button = item.button {
            let title = NSMutableAttributedString(string: button.title + " ", attributes: [
                .font: button.font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor
            ])
            let badge = NSTextAttachment()
            badge.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Update available")
            badge.bounds = NSRect(x: 0, y: -3, width: 16, height: 16)
            title.append(NSAttributedString(attachment: badge))
            button.attributedTitle = title
            button.toolTip?.append(fleet.managerUpdateAvailable ? " A manager update is available." : " A server update is available.")
        }
    }
    func menuNeedsUpdate(_ menu: NSMenu) { if !tracking { rebuild() } }
    func menuWillOpen(_ menu: NSMenu) { tracking = true }
    func menuDidClose(_ menu: NSMenu) { tracking = false; refreshStatus() }
    private func add(_ title: String, to menu: NSMenu, enabled: Bool = true, checked: Bool? = nil, action: (() -> Void)? = nil) {
        let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let action {
            let target = StatusMenuAction(action); actions.append(target)
            row.target = target; row.action = #selector(StatusMenuAction.invoke)
        }
        row.isEnabled = enabled && action != nil
        if let checked { row.state = checked ? .on : .off }
        menu.addItem(row)
    }
    private func addLive(to menu: NSMenu, title: @escaping () -> String, enabled: @escaping () -> Bool, checked: (() -> Bool)? = nil, action: @escaping () -> Void) {
        add(title(), to: menu, enabled: enabled(), checked: checked?(), action: action)
        guard let row = menu.items.last else { return }
        liveRows.append { [weak row] in
            row?.title = title()
            row?.isEnabled = enabled()
            if let checked { row?.state = checked() ? .on : .off }
        }
    }
    private func addUpdateCheck(to menu: NSMenu) {
        // A view-backed menu control does not dismiss the menu on click.
        let row = NSMenuItem()
        let button = NSButton(title: "Check for Server Updates", target: nil, action: nil)
        button.isBordered = false
        button.alignment = .left
        button.font = .menuFont(ofSize: 0)
        button.frame = NSRect(x: 18, y: 2, width: 410, height: 23)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 448, height: 27))
        container.addSubview(button)
        row.view = container
        let target = StatusMenuAction { [weak self] in
            guard let self else { return }
            for server in self.fleet.configuredModels where !server.busy { server.checkUpdates() }
            self.refreshStatus()
        }
        actions.append(target)
        button.target = target; button.action = #selector(StatusMenuAction.invoke)
        liveRows.append { [weak self, weak button] in
            guard let self, let button else { return }
            let models = self.fleet.configuredModels
            if let checking = models.first(where: \.checkingRelease) {
                button.title = checking.releaseCheckSummary
                button.isEnabled = false
            } else {
                let failed = models.contains { $0.releaseError != nil }
                let checked = models.contains { $0.releaseCheckedAt != nil }
                let known = models.allSatisfy { $0.release?.installed != nil }
                let available = models.contains { $0.release?.updateAvailable == true }
                button.title = failed ? "Update Check Failed · Retry" : available ? "Server Update Available · Check Again" : checked ? (known ? "Servers Are Up to Date · Check Again" : "Valve Check Complete · Check Again") : "Check for Server Updates"
                button.isEnabled = models.contains { !$0.busy && ["INSTALLED", "RUNNING", "VM_STOPPED"].contains($0.state) }
            }
            button.toolTip = models.compactMap(\.releaseError).first ?? "Checks Valve for a newer server version. No game files are installed."
        }
        menu.addItem(row)
        liveRows.last?()
    }

    func openSelectedManagement() { open(fleet.selected) }
    private func open(_ server: Model) {
        fleet.selectedID = server.engine.home.path
        showManagement(); NSApp.activate(ignoringOtherApps: true)
    }
    private func rebuild() {
        menu.removeAllItems(); actions.removeAll(); liveRows.removeAll()
        let experimental = fleet.selected.build.experimental
        addLive(to: menu, title: { [weak self] in
            guard let self else { return "Enshrouded Manager" }
            return self.fleet.selected.build.experimental ? "Enshrouded Manager · Experimental"
                : "Enshrouded Manager · \(self.fleet.selected.build.version) · \(self.fleet.managerUpdateStatus)"
        }, enabled: { [weak self] in
            guard let self else { return false }
            return self.fleet.managerUpdateAvailable && !self.fleet.models.contains(where: \.busy) && !self.fleet.checkingManagerRelease
        }) { self.fleet.updateManager() }
        if let row = menu.items.last {
            liveRows.append { [weak self, weak row] in
                guard let self, let row else { return }
                row.image = self.fleet.managerUpdateAvailable ? NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Manager update available") : nil
                row.toolTip = self.fleet.selected.build.experimental
                    ? "Public manager updates are disabled for experimental builds."
                    : self.fleet.managerUpdateAvailable
                        ? "Updating the manager will stop all running servers. They will start back up once the update finishes."
                        : "Checks for manager updates at launch and every five minutes while the manager is open."
            }
            liveRows.last?()
        }
        if !experimental {
            addLive(to: menu, title: { [weak self] in self?.fleet.checkingManagerRelease == true ? "Checking for Manager Updates…" : "Check for Manager Updates" },
                enabled: { [weak self] in self?.fleet.checkingManagerRelease == false }) { self.fleet.checkManagerUpdates() }
        }
        menu.addItem(.separator())
        addLive(to: menu, title: { "Update Enshrouded Server…" }, enabled: { [weak self] in
            guard let self else { return false }
            return !self.fleet.models.contains(where: \.busy) && self.fleet.models.contains { $0.releaseError == nil && $0.releaseCheckedAt != nil && $0.release?.updateAvailable == true }
        }) { self.fleet.updateAllServers() }
        menu.addItem(.separator())
        for server in fleet.configuredModels {
            let submenu = NSMenu(); submenu.autoenablesItems = false
            let count = server.stopped ? "0 players" : server.playerCount.map { "\($0) players" } ?? "Players: checking…"
            let row = NSMenuItem(title: "\(server.name) — \(server.label) · \(count)", action: nil, keyEquivalent: "")
            row.submenu = submenu; menu.addItem(row)
            liveRows.append { [weak row] in row?.title = "\(server.name) — \(server.label) · \(server.peerSummary)" }
            if let address = server.endpoint { add("Join address: \(address) · Copy", to: submenu) { server.copy(address) } }
            else { add("Join address: unavailable", to: submenu) }
            add("Copy Player Password", to: submenu, enabled: !server.settings.password.isEmpty) { server.copy(server.settings.password) }
            add("Copy Admin Password", to: submenu, enabled: !server.settings.adminPassword.isEmpty) { server.copy(server.settings.adminPassword) }
            submenu.addItem(.separator())
            addLive(to: submenu, title: { server.busy ? server.operationTitle : "Start Server" }, enabled: { server.canEdit }) { server.run("start") }
            addLive(to: submenu, title: { server.activeAction == "stop" ? "Saving & Stopping…" : "Stop Server (Save & Stop)" }, enabled: { ["RUNNING", "RECOVERING"].contains(server.state) && !server.busy }) { server.run("stop") }
            addLive(to: submenu, title: { "Start Server at Login" }, enabled: { !server.busy || server.activeAction == "stop" }, checked: { server.automation.startAtLogin }) {
                var value = server.automation; value.startAtLogin.toggle(); server.saveAutomation(value)
            }
            addLive(to: submenu, title: { "Delete Server…" }, enabled: { [weak self] in self?.fleet.canChangeProfiles == true && !server.busy }) { self.fleet.deleteServer(server) }
            add("Server Management…", to: submenu) { self.open(server) }
            addLive(to: submenu, title: { "Show Progress…" }, enabled: { server.busy || server.serverProgress != nil || server.setupProgress != nil }) { ServerProgressWindow.show(model: server) }
        }
        menu.addItem(.separator())
        add("Enshrouded Server Build \(fleet.selected.engine.installedManifest ?? "Unavailable")", to: menu)
        addUpdateCheck(to: menu)

        addLive(to: menu, title: { "Automatically Update All Enshrouded Servers" }, enabled: { [weak self] in self?.fleet.canChangeProfiles == true }, checked: { [weak self] in self?.fleet.models.allSatisfy { $0.automation.automaticUpdates } == true }) {
            let automatic = self.fleet.models.allSatisfy { $0.automation.automaticUpdates }
            for server in self.fleet.models { var value = server.automation; value.automaticUpdates = !automatic; server.saveAutomation(value) }
        }
        menu.addItem(.separator())
        addLive(to: menu, title: { "New Server…" }, enabled: { [weak self] in self?.fleet.canChangeProfiles == true }) { EditorWindows.showNew(self.fleet) }
        menu.addItem(.separator())
        addLive(to: menu, title: { "Open Manager at Login" }, enabled: { true }, checked: { [weak self] in self?.fleet.managerAtLogin == true }) {
            self.fleet.setManagerAtLogin(!self.fleet.managerAtLogin)
        }
        addLive(to: menu, title: { "Uninstall Server Files…" }, enabled: { [weak self] in self?.fleet.models.contains(where: \.busy) == false }) { self.fleet.uninstallServerFiles() }
        addLive(to: menu, title: { "Quit Manager (Servers Keep Running)" }, enabled: { [weak self] in self?.fleet.models.contains(where: \.busy) == false }) { NSApp.terminate(nil) }
    }
}

@MainActor private final class StatusMenuAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func invoke() { action() }
}
