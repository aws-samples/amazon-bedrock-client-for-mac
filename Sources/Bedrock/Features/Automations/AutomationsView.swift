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
                    .accessibilityIdentifier("automations.new")
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
                                Text("Next \(next.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: automation.timeZone)))")
                                    .font(.caption).help(automation.timeZone.identifier)
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
                                .accessibilityLabel("Options for \(automation.name)")
                                .accessibilityIdentifier("automation.options.\(automation.id)")
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(20).background(DesignTokens.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(DesignTokens.border, lineWidth: 0.5))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("automation.\(automation.id)")
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
                        .accessibilityIdentifier("automation.name")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Model").font(DesignTokens.label)
                        ModelPicker(organizedChatModels: catalog.organized, menuSelection: modelSelection) { _ in }
                        if !automation.modelID.isEmpty {
                            Text("\(catalog.model(automation.modelID).provider) · \(automation.modelID)")
                                .font(DesignTokens.detail).foregroundStyle(.secondary)
                                .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                                .accessibilityIdentifier("automation.modelDetails")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    TextEditor(text: $automation.prompt).font(.system(size: 13)).frame(height: 120).border(DesignTokens.border)
                        .accessibilityLabel("Automation prompt")
                        .accessibilityIdentifier("automation.prompt")
                }
                Section("Schedule") {
                    SelectionField(title: "Repeat", selection: $automation.cadence,
                                       options: AutomationCadence.allCases.map { ($0, $0.title) })
                    if automation.cadence == .interval {
                        Stepper("Every \(automation.intervalMinutes) minutes", value: $automation.intervalMinutes, in: 1...43_200)
                    }
                    else {
                        DatePicker(automation.cadence == .once ? "Run at" : "Local time", selection: $automation.scheduledAt,
                                   displayedComponents: automation.cadence == .once ? [.date, .hourAndMinute] : [.hourAndMinute])
                            .environment(\.timeZone, automation.timeZone)
                    }
                    AutomationScheduleOptions(automation: $automation)
                    Stepper("Stop after \(automation.maximumRuntime) seconds", value: $automation.maximumRuntime, in: 10...3_600, step: 10)
                    Toggle("Enable schedule", isOn: $automation.enabled)
                    Text(automation.formattedNextRun().map { "Next run: \($0)" } ?? "No upcoming run. Choose a future time and at least one day.")
                        .font(DesignTokens.detail).foregroundStyle(.secondary)
                        .accessibilityIdentifier("automation.nextRun")
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
            .formStyle(.grouped).scrollContentBackground(.hidden).toggleStyle(AppSwitchStyle())
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save automation") {
                    do { try AutomationScheduler.shared.save(automation); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
                .buttonStyle(AppButtonStyle(prominent: true)).keyboardShortcut("s", modifiers: .command)
                .accessibilityIdentifier("automation.save")
            }
        }
        .padding(24).frame(width: 620, height: 650)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("automation.editor")
    }

    private var modelSelection: Binding<SidebarSelection?> {
        Binding(
            get: { automation.modelID.isEmpty ? nil : .chat(catalog.model(automation.modelID)) },
            set: { if case .chat(let model) = $0 { automation.modelID = model.id } }
        )
    }
}

private struct AutomationScheduleOptions: View {
    @Binding var automation: AutomationDefinition
    private static let timeZones = [("", "System time zone")] +
        TimeZone.knownTimeZoneIdentifiers.map { ($0, $0.replacingOccurrences(of: "_", with: " ")) }
    private var zone: Binding<String> {
        Binding(get: { automation.timeZoneIdentifier ?? "" }, set: { identifier in
            var calendar = Calendar.current
            calendar.timeZone = automation.timeZone
            let time = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: automation.scheduledAt)
            automation.timeZoneIdentifier = identifier.isEmpty ? nil : identifier
            calendar.timeZone = automation.timeZone
            // Keep the chosen wall-clock time while changing the time zone.
            if let adjusted = calendar.date(from: time) { automation.scheduledAt = adjusted }
        })
    }

    var body: some View {
        SelectionField(title: "Time zone", selection: zone, options: Self.timeZones)
        if automation.cadence != .once {
            VStack(alignment: .leading, spacing: 8) {
                Text("Days").font(DesignTokens.label)
                HStack(spacing: 5) {
                    ForEach(1...7, id: \.self) { day in
                        let selected = automation.weekdays?.contains(day) ?? true
                        Button {
                            var days = automation.weekdays ?? Set(1...7)
                            if selected { days.remove(day) } else { days.insert(day) }
                            automation.weekdays = days.count == 7 ? nil : days
                        } label: {
                            Text(Calendar.current.shortWeekdaySymbols[day - 1])
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity).frame(height: 30)
                                .background(selected ? DesignTokens.selection.opacity(0.14) : DesignTokens.surface,
                                            in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? DesignTokens.selection.opacity(0.5) : DesignTokens.border))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                        .accessibilityValue(selected ? "Selected" : "Not selected")
                    }
                }
            }
        }
        if automation.cadence == .interval {
            Toggle("Run only during active hours", isOn: Binding(
                get: { automation.activeStartMinute != nil },
                set: {
                    automation.activeStartMinute = $0 ? 9 * 60 : nil
                    automation.activeEndMinute = $0 ? 18 * 60 : nil
                }))
            if automation.activeStartMinute != nil {
                HStack {
                    DatePicker("From", selection: time(\.activeStartMinute), displayedComponents: [.hourAndMinute])
                    DatePicker("Until", selection: time(\.activeEndMinute), displayedComponents: [.hourAndMinute])
                }
                .environment(\.timeZone, automation.timeZone)
                Text("An overnight window continues into the following morning. Runs outside the window wait until it opens.")
                    .font(DesignTokens.detail).foregroundStyle(.secondary)
            }
        }
    }

    private func time(_ key: WritableKeyPath<AutomationDefinition, Int?>) -> Binding<Date> {
        Binding(get: {
            var calendar = Calendar.current
            calendar.timeZone = automation.timeZone
            let minute = automation[keyPath: key] ?? 0
            return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        }, set: {
            var calendar = Calendar.current
            calendar.timeZone = automation.timeZone
            automation[keyPath: key] = calendar.component(.hour, from: $0) * 60 + calendar.component(.minute, from: $0)
        })
    }
}
