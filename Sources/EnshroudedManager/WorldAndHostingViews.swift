import SwiftUI
import EnshroudedCore

struct BackupsView: View {
    @ObservedObject var model: Model
    @State private var backupName = ""
    @State private var selectedID: String?
    @State private var pending: WorldBackup?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.stopped ? "Save a copy of your world and server settings." : "Stop the server to create or restore a backup.").font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("Backup name (optional)", text: $backupName)
                Button("Create Backup") { model.backup(backupName); backupName = "" }.disabled(!model.canEdit)
            }
            List(selection: $selectedID) {
                ForEach(model.backups) { backup in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(backup.name)
                        if !backup.hasIntegrityManifest { Text("Legacy backup · no integrity record").font(.caption).foregroundStyle(.secondary) }
                        Text(backup.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4).tag(backup.id)
                }
            }.overlay { if model.backups.isEmpty { Text("No backups yet").foregroundStyle(.secondary) } }
            HStack {
                Button("Open Backups Folder") { NSWorkspace.shared.open(model.engine.backupDirectory) }.disabled(model.backups.isEmpty)
                Spacer()
                Button("Restore Selected…") { pending = model.backups.first { $0.id == selectedID } }
                    .disabled(!model.canEdit || !model.backups.contains { $0.id == selectedID })
            }
        }.padding(20)
        .confirmationDialog("Restore \(pending?.name ?? "backup")?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            if let backup = pending { Button("Restore Backup") { model.restore(backup.id); pending = nil } }
        } message: { Text("This replaces your world and settings, including passwords. A backup of the current state is saved first. The server stays stopped.") }
    }
}
