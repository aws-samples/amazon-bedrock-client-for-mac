import AppKit
import SwiftUI

struct SkillPicker: View {
    let threadID: String
    @ObservedObject private var store = AppStore.shared
    private var selected: [String] { store.thread(threadID).skillIDs }
    var body: some View {
        ActionMenu {
            if store.skills.isEmpty { Text("No local skills installed") }
            ForEach(store.skills) { skill in
                Toggle(isOn: Binding(
                    get: { selected.contains(skill.id) },
                    set: { on in store.updateThread(threadID) {
                        if on && !$0.skillIDs.contains(skill.id) { $0.skillIDs.append(skill.id) }
                        else if !on { $0.skillIDs.removeAll { $0 == skill.id } }
                    }}
                )) { Text(skill.name) }
                .disabled(!store.isSkillEnabled(skill) || store.unavailableReason(for: skill) != nil)
            }
            Divider()
            Button("Manage skills…") { store.showSettings(row: "skills") }
        } label: {
            Label(selected.isEmpty ? "Skills" : "\(selected.count) skill\(selected.count == 1 ? "" : "s")", systemImage: "sparkles")
                .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("workbench.skillPicker")
    }
}
