import AppKit

@MainActor enum ServerFilePrompts {
    static func deletion(name: String) -> NSAlert {
        let alert = NSAlert(); alert.messageText = "Delete \(name)?"
        alert.informativeText = "Stops this server and deletes its installation and VM. Game data and backups are archived unless you choose to delete them. Other servers and shared downloads are kept."
        let deleteData = NSButton(checkboxWithTitle: "Also delete game data and backups", target: nil, action: nil)
        deleteData.state = .off; deleteData.sizeToFit(); alert.accessoryView = deleteData
        alert.addButton(withTitle: "Delete Server"); alert.addButton(withTitle: "Cancel")
        return alert
    }
    static func clearCache() -> NSAlert {
        let alert = NSAlert(); alert.messageText = "Clear Download Cache?"
        alert.informativeText = "Deletes cached installation downloads and downloaded manager updates. Existing servers, VMs, settings, game data and backups are kept. Future installations download these files again."
        alert.addButton(withTitle: "Clear Cache"); alert.addButton(withTitle: "Cancel")
        return alert
    }
}
