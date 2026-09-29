import AppKit
import EnshroudedCore

@MainActor final class StatusMenu: NSObject, NSMenuDelegate {
    private let fleet: FleetModel
    private let showManagement: () -> Void
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var actions: [StatusMenuAction] = []
    private var tracking = false
    private var timer: Timer?

    init(fleet: FleetModel, showManagement: @escaping () -> Void) {
        self.fleet = fleet; self.showManagement = showManagement
        super.init()
        menu.autoenablesItems = false; menu.delegate = self; item.menu = menu
        refreshStatus()
        // Default run-loop mode deliberately pauses status-button changes while
        // AppKit tracks a menu. Models continue monitoring independently.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
    }
    func refreshStatus() {
        guard !tracking else { return }
        item.button?.image = MenuBranding.image(running: fleet.models.contains { $0.state == "RUNNING" }, busy: fleet.models.contains { $0.busy })
        item.button?.title = " Enshrouded · \(fleet.menuValue)"
        item.button?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        item.button?.toolTip = "Enshrouded Manager · \(fleet.selected.build.detail)"
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
    private func open(_ server: Model) {
        fleet.selectedID = server.engine.home.path
        showManagement(); NSApp.activate(ignoringOtherApps: true)
    }
    private func rebuild() {
        menu.removeAllItems(); actions.removeAll()
        let experimental = fleet.selected.build.experimental
        let available = fleet.managerUpdateAvailable
        let managerTitle = experimental ? "Enshrouded Manager · Experimental"
            : "Enshrouded Manager · \(fleet.selected.build.version) · \(fleet.managerUpdateStatus)"
        add(managerTitle, to: menu, enabled: available && !fleet.models.contains(where: \.busy) && !fleet.checkingManagerRelease) { self.fleet.updateManager() }
        if available {
            menu.items.last?.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Manager update available")
        }
        menu.items.last?.toolTip = experimental
            ? "Public manager updates are disabled for experimental builds."
            : available
                ? "Updating the manager will stop all running servers. They will start back up once the update finishes."
                : "Checks for manager updates at launch and every five minutes while the manager is open."
        if !experimental {
            add(fleet.checkingManagerRelease ? "Checking for Manager Updates…" : "Check for Manager Updates", to: menu,
                enabled: !fleet.checkingManagerRelease && !fleet.models.contains(where: \.busy)) { self.fleet.checkManagerUpdates() }
        }
        menu.addItem(.separator())
        let busy = fleet.models.contains { $0.busy }
        if fleet.models.contains(where: { $0.release?.updateAvailable == true }) {
            add("Update Enshrouded Server…", to: menu, enabled: !busy) { self.fleet.updateAllServers() }
            menu.addItem(.separator())
        }
        for server in fleet.models {
            let submenu = NSMenu(); submenu.autoenablesItems = false
            let count = server.stopped ? "0 players" : server.playerCount.map { "\($0) players" } ?? "Players: checking…"
            let row = NSMenuItem(title: "\(server.name) — \(server.label) · \(count)", action: nil, keyEquivalent: "")
            row.submenu = submenu; menu.addItem(row)
            if let address = server.endpoint { add("Join address: \(address) · Copy", to: submenu) { server.copy(address) } }
            else { add("Join address: unavailable", to: submenu) }
            add("Copy Player Password", to: submenu, enabled: !server.settings.password.isEmpty) { server.copy(server.settings.password) }
            add("Copy Admin Password", to: submenu, enabled: !server.settings.adminPassword.isEmpty) { server.copy(server.settings.adminPassword) }
            submenu.addItem(.separator())
            add(server.busy ? server.operationTitle : "Start Server", to: submenu, enabled: server.canEdit) { server.run("start") }
            add("Stop Server (Save & Stop)", to: submenu, enabled: server.state == "RUNNING" && !server.busy) { server.run("stop") }
            add("Start Server at Login", to: submenu, enabled: !server.busy, checked: server.automation.startAtLogin) {
                var value = server.automation; value.startAtLogin.toggle(); server.saveAutomation(value)
            }
            add("Server Management…", to: submenu) { self.open(server) }
        }
        menu.addItem(.separator())
        add("Enshrouded Server Build \(fleet.selected.engine.installedManifest ?? "Unavailable")", to: menu)
        let checking = fleet.models.contains { $0.checkingRelease }
        add(checking ? "Checking for Server Updates…" : "Check for Server Updates", to: menu, enabled: !busy && !checking) { for server in self.fleet.models { server.checkUpdates() } }
        let automatic = fleet.models.allSatisfy { $0.automation.automaticUpdates }
        add("Automatically Update All Enshrouded Servers", to: menu, enabled: !busy, checked: automatic) {
            for server in self.fleet.models { var value = server.automation; value.automaticUpdates = !automatic; server.saveAutomation(value) }
        }
        menu.addItem(.separator())
        add("New Server…", to: menu, enabled: !busy) { self.fleet.showNewServer = true; self.showManagement(); NSApp.activate(ignoringOtherApps: true) }
        menu.addItem(.separator())
        add("Quit Manager (Servers Keep Running)", to: menu, enabled: !busy) { NSApp.terminate(nil) }
    }
}

@MainActor private final class StatusMenuAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func invoke() { action() }
}
