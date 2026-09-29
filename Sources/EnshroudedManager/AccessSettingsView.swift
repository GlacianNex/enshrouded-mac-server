import SwiftUI
import EnshroudedCore

struct AccessSettingsView: View {
    @ObservedObject var model: Model
    @State private var roles: [AccessRole] = []
    @State private var bans: [SavedBan] = []
    @State private var removedBans = Set<Int>()
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    let labels = ["canKickBan": "Kick & ban", "canAccessInventories": "Access base storage", "canEditWorld": "Edit open world", "canEditBase": "Build & edit bases", "canExtendBase": "Manage Flame Altars"]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Roles & Saved Bans").font(.title2.bold())
            Text("The join password determines player permissions. Stop the server to edit roles. Kick or ban players in Enshrouded’s Social tab.").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach($roles) { $role in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Role name", text: $role.name)
                                SecureField("Role password (8+ characters)", text: $role.password)
                                ForEach(AccessRole.keys, id: \.self) { key in Toggle(labels[key] ?? key, isOn: Binding(get: { role.permissions[key] ?? false }, set: { role.permissions[key] = $0 })) }
                                Stepper("Reserved slots: \(role.reservedSlots)", value: $role.reservedSlots, in: 0...16)
                                Button("Remove Role") { roles.removeAll { $0.id == role.id } }
                            }.padding(8)
                        }
                    }
                    Button("Add Role") { roles.append(AccessRole()) }
                    Divider(); Text("Saved Bans").font(.headline)
                    if bans.isEmpty { Text("No saved bans.").foregroundStyle(.secondary) }
                    ForEach(bans) { ban in
                        Toggle("Unban \(ban.displayName)\(ban.characterName.isEmpty ? "" : " · " + ban.characterName)", isOn: Binding(get: { removedBans.contains(ban.id) }, set: { if $0 { removedBans.insert(ban.id) } else { removedBans.remove(ban.id) } }))
                    }
                }.disabled(!model.canEdit)
            }
            if let error { Text(error).foregroundStyle(.orange).font(.caption) }
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Save Roles & Bans") { let draft = roles, removed = removedBans; model.operation("Save roles and bans") { try $0.saveAccess(draft, removingBans: removed) }; dismiss() }.disabled(!model.canEdit || roles.isEmpty) }
        }.padding(22).frame(width: 610, height: 680).onAppear {
            do { roles = try model.engine.accessRoles(); bans = try model.engine.savedBans() } catch { self.error = error.localizedDescription }
        }
    }
}
