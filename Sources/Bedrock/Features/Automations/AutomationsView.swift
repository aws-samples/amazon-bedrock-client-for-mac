import SwiftUI

struct AutomationsView: View {
    @ObservedObject private var store = AppStore.shared
    @ObservedObject private var runner = AutomationScheduler.shared
    @State private var editing: AutomationDefinition?
    @State private var deleting: AutomationDefinition?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "A little help, on schedule", subtitle: "Repeat useful prompts while Bedrock is open on this Mac. Missed runs are skipped after sleep; completed work stays in your threads.")
                HStack {
                    Toggle("Schedules enabled", isOn: Binding(get: { store.preferences.automationsEnabled }, set: { store.preferences.automationsEnabled = $0 }))
                        .toggleStyle(AppSwitchStyle()).fixedSize()
                    Spacer()
                    Button("New automation", systemImage: "plus") {
                        editing = AutomationDefinition(name: "", prompt: "", modelID: ModelCatalog.shared.defaultModel?.id ?? "")
                    }
                }
                if store.state.automations.isEmpty {
                    EmptyStateView(symbol: "clock.arrow.2.circlepath", title: "Put a useful prompt on repeat", detail: "Create a writing exercise or a repeatable Bedrock demo. New automations start paused.")
                }
                ForEach(store.state.automations) { automation in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 13) {
                            Image(systemName: "clock").font(.system(size: 19, weight: .light)).foregroundStyle(DesignTokens.accent).padding(.top, 3)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(automation.name).font(.system(size: 15, weight: .semibold))
                                Text(automation.prompt).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Toggle("Enabled", isOn: Binding(get: { automation.enabled }, set: { runner.setEnabled(automation.id, enabled: $0) }))
                                .toggleStyle(AppSwitchStyle(showsLabel: false)).labelsHidden().help("Enable \(automation.name)")
                        }
                        HStack(spacing: 14) {
                            Text(automation.cadence.title).font(.caption)
                            if let next = automation.nextRunAt, automation.enabled {
                                Text("Next \(next.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                            } else { Text("Paused").font(.caption) }
                            Spacer()
                            if let thread = runner.running[automation.id] {
                                ProgressView().controlSize(.small)
                                Button("View run") { store.selectThread(thread) }
                                Button("Stop", role: .destructive) { runner.stop(automation.id) }
                            } else {
                                if let thread = automation.lastThreadID {
                                    Button(automation.lastStatus?.title ?? "Last run") { store.selectThread(thread) }.buttonStyle(.link)
                                }
                                Button("Run now", systemImage: "play") { runner.runNow(automation) }
                            }
                            ActionMenu {
                                Button("Edit") { editing = automation }
                                Button("Duplicate") {
                                    var copy = automation; copy.id = UUID(); copy.name += " copy"; copy.enabled = false
                                    copy.lastRunAt = nil; copy.lastThreadID = nil; copy.lastStatus = nil; copy.nextRunAt = nil
                                    editing = copy
                                }
                                Divider()
                                Button("Delete", role: .destructive) { deleting = automation }
                            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(20).background(DesignTokens.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(DesignTokens.border, lineWidth: 0.5))
                }
            }
            .padding(32).frame(maxWidth: 1050).frame(maxWidth: .infinity)
        }
        .sheet(item: $editing) { AutomationEditor(automation: $0) }
        .confirmationDialog("Delete this schedule? Completed threads will remain.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { item in
            Button("Delete \(item.name)", role: .destructive) { store.state.automations.removeAll { $0.id == item.id }; deleting = nil }
        }
        .accessibilityIdentifier("workbench.automations")
    }
}

struct AutomationEditor: View {
    @State var automation: AutomationDefinition
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = AppStore.shared
    @ObservedObject private var catalog = ModelCatalog.shared
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Configure automation").font(.title2.weight(.semibold))
            Form {
                Section {
                    TextField("Name", text: $automation.name)
                    SelectionField(title: "Model", selection: $automation.modelID,
                        options: (catalog.models.contains(where: { $0.id == automation.modelID }) ? [] :
                            [(automation.modelID, automation.modelID.isEmpty ? "Choose a model" : automation.modelID)]) +
                            catalog.models.map { ($0.id, $0.name) })
                    TextEditor(text: $automation.prompt).font(.system(size: 13)).frame(height: 120).border(DesignTokens.border)
                }
                Section("Schedule") {
                    SelectionField(title: "Repeat", selection: $automation.cadence,
                                       options: AutomationCadence.allCases.map { ($0, $0.title) })
                    if automation.cadence == .interval { Stepper("Every \(automation.intervalMinutes) minutes", value: $automation.intervalMinutes, in: 1...43_200) }
                    else {
                        DatePicker(automation.cadence == .once ? "Run at" : "Local time", selection: $automation.scheduledAt,
                                   displayedComponents: automation.cadence == .once ? [.date, .hourAndMinute] : [.hourAndMinute])
                    }
                    Stepper("Stop after \(automation.maximumRuntime) seconds", value: $automation.maximumRuntime, in: 10...3_600, step: 10)
                    Toggle("Enable schedule", isOn: $automation.enabled)
                }
                DisclosureGroup("Skills (\(automation.skillIDs.count))") {
                    ForEach(store.skills) { skill in
                        Toggle(skill.name, isOn: Binding(get: { automation.skillIDs.contains(skill.id) }, set: { value in
                            if value { automation.skillIDs.append(skill.id) } else { automation.skillIDs.removeAll { $0 == skill.id } }
                        })).disabled(!store.isSkillEnabled(skill) || store.unavailableReason(for: skill) != nil)
                    }
                }
                DisclosureGroup("Working directory") {
                    TextField("Path", text: Binding(get: { automation.workingDirectory ?? "" },
                                                   set: { automation.workingDirectory = $0.isEmpty ? nil : $0 }),
                              prompt: Text(store.preferences.workingDirectory ?? "~"))
                    Text("Optional starting folder for relative paths and shell commands.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped).scrollContentBackground(.hidden)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save automation") {
                    do { try AutomationScheduler.shared.save(automation); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
                .buttonStyle(AppButtonStyle(prominent: true)).keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(24).frame(width: 620, height: 650)
    }
}
