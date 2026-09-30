import SwiftUI
import EnshroudedCore

/// Embedded in the settings form; shares its draft and Save/Cancel actions.
struct GameplayRulesView: View {
    let rules: [GameplayRule]
    @Binding var values: [String: String]
    let original: [String: String]
    let canEdit: Bool
    private let categories = ["Player Stats", "Survival & Exploration", "Resources & Crafting", "Experience & Progression", "Enemies & Bosses", "World & Wildlife"]

    var body: some View {
        ForEach(categories, id: \.self) { category in
            DisclosureGroup(category) {
                ForEach(rules.filter { $0.category == category }) { rule in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(rule.label)
                            RuleHelp(text: tooltip(rule))
                            Spacer()
                            control(rule).disabled(!canEdit)
                        }
                        Text(rule.explanation ?? "").font(.caption).foregroundStyle(.secondary)
                        if values[rule.key] != original[rule.key] {
                            HStack {
                                Text("Changed from \(friendly(original[rule.key] ?? "", rule: rule))")
                                Button("Undo") { values[rule.key] = original[rule.key] }.buttonStyle(.link).disabled(!canEdit)
                            }.font(.caption).foregroundStyle(.orange)
                        }
                    }.padding(.vertical, 5)
                }
            }.disclosureGroupStyle(FullRowDisclosureStyle())
        }
    }
    @ViewBuilder private func control(_ rule: GameplayRule) -> some View {
        if rule.kind == "bool" {
            Toggle(rule.label, isOn: Binding(get: { values[rule.key] == "true" }, set: { values[rule.key] = $0 ? "true" : "false" })).labelsHidden()
        } else if rule.kind == "choice" {
            Picker(rule.label, selection: binding(rule.key)) {
                ForEach(rule.choices, id: \.self) { Text(friendly($0, rule: rule)).tag($0) }
            }.labelsHidden().frame(maxWidth: 210)
        } else {
            TextField(rule.label, text: binding(rule.key))
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(width: 80)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.5), lineWidth: 1))
            Text(rule.minutes ? "min" : rule.key == "perkUpgradeRecyclingFactor" ? "portion" : "×").foregroundStyle(.secondary)
        }
    }
    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }
    private func friendly(_ value: String, rule: GameplayRule) -> String {
        if rule.key == "curseModifier" { return ["Easy": "Off", "Normal": "Normal", "Hard": "Increased (2× chance)"][value] ?? value }
        let labels = ["true": "On", "false": "Off", "AddBackpackMaterials": "Drop materials only", "Everything": "Drop all backpack items", "NoTombstone": "Keep all items", "VeryEasy": "Very easy", "VeryHard": "Very hard", "KeepProgress": "Keep all progress", "LoseSomeProgress": "Lose some progress", "LoseAllProgress": "Lose all progress"]
        if let label = labels[value] { return label }
        if rule.kind == "choice" { return value }
        return value + (rule.minutes ? " min" : rule.key == "perkUpgradeRecyclingFactor" ? " portion" : "×")
    }
    private func tooltip(_ rule: GameplayRule) -> String {
        var text = rule.explanation ?? rule.label
        if let min = rule.minimum, let max = rule.maximum {
            text += " Allowed range: \(min.formatted())–\(max.formatted())\(rule.minutes ? " minutes" : "")."
            if !rule.minutes && rule.key != "perkUpgradeRecyclingFactor" { text += " 1× is the normal amount; 0.5× is half and 2× is double." }
        }
        return text
    }
}

/// Keep expansion independent of whether the rule controls are editable.
struct FullRowDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).frame(width: 10)
                    configuration.label
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded { configuration.content }
        }
    }
}

private struct RuleHelp: View {
    let text: String
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rule information")
        .accessibilityHint(text)
        .onHover { hovering in showing = hovering }
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                .padding(14).frame(width: 300)
        }
    }
}
