import AppKit
import SwiftUI

/// Skills live in Settings; selecting one never replaces the main conversation.
struct WorkbenchSkillsLibrary: View {
    @ObservedObject private var store = WorkbenchStore.shared
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var editing: LocalSkill?
    @State private var creating = false
    @State private var deleting: LocalSkill?
    @State private var scrollTarget: String?
    private var threadID: String { store.selectedThreadID ?? "new-thread" }
    private var filtered: [LocalSkill] {
        store.skills.filter { query.isEmpty || "\($0.id) \($0.name) \($0.description) \($0.tags.joined(separator: " "))".localizedStandardContains(query) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                WorkbenchSearchField(placeholder: "Search skills", text: $query)
                if store.isLoadingSkills || store.isImportingSkill { ProgressView().controlSize(.small) }
                Button("Import", action: store.importSkill).disabled(store.isImportingSkill)
                Button { creating = true } label: { Image(systemName: "plus") }
                    .help("Create a skill").accessibilityLabel("Create a skill")
                Button { store.reloadSkills() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Reload skills").accessibilityLabel("Reload skills")
            }.padding(.horizontal, 24).padding(.bottom, 16)
            ScrollViewReader { proxy in
                List {
                    if !store.skillIssues.isEmpty {
                        DisclosureGroup("Some skills need attention") {
                            ForEach(store.skillIssues, id: \.self) { Text($0).font(WorkbenchStyle.caption).textSelection(.enabled) }
                        }.foregroundStyle(.orange)
                    }
                    if filtered.isEmpty {
                        WorkbenchEmptyState(symbol: "sparkles", title: "No matching skills", detail: "Search a skill name or ID, import a SKILL.md file, or create your own instructions.")
                            .listRowSeparator(.hidden)
                    }
                    ForEach(filtered) { skill in
                        DisclosureGroup(isExpanded: Binding(get: { expanded.contains(skill.id) }, set: { value in
                            if value { expanded.insert(skill.id) } else { expanded.remove(skill.id) }
                        })) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(skill.description).font(WorkbenchStyle.caption).foregroundStyle(.secondary)
                                Text(skill.id).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                                if let reason = store.unavailableReason(for: skill) {
                                    Label(reason, systemImage: "exclamationmark.circle").font(WorkbenchStyle.caption).foregroundStyle(.orange)
                                }
                                Toggle(store.selectedThreadID == nil ? "Use in the next chat" : "Use in the current chat", isOn: Binding(
                                    get: { store.thread(threadID).skillIDs.contains(skill.id) },
                                    set: { enabled in store.updateThread(threadID) {
                                        if enabled && !$0.skillIDs.contains(skill.id) { $0.skillIDs.append(skill.id) }
                                        else if !enabled { $0.skillIDs.removeAll { $0 == skill.id } }
                                    } }
                                ))
                                .toggleStyle(WorkbenchSwitchStyle()).disabled(!store.isSkillEnabled(skill) || store.unavailableReason(for: skill) != nil)
                                HStack {
                                    Button("Use in chat") {
                                        store.updateThread(threadID) { if !$0.skillIDs.contains(skill.id) { $0.skillIDs.append(skill.id) } }
                                        WorkbenchWindows.showMain()
                                        WorkbenchWindows.focusComposer()
                                    }.disabled(!store.isSkillEnabled(skill) || store.unavailableReason(for: skill) != nil)
                                    Button("Edit instructions") { editing = skill }
                                    WorkbenchActionMenu("More") {
                                        Button("Reveal file") { store.reveal(skill.url) }
                                        Button("Export skill with references") { store.exportSkill(skill) }
                                    }.fixedSize()
                                    Spacer()
                                    Button("Copy") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(skill.instructions, forType: .string)
                                    }
                                }.controlSize(.small)
                                Text(skill.instructions).font(WorkbenchStyle.body).lineSpacing(4)
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14).background(WorkbenchStyle.canvas, in: RoundedRectangle(cornerRadius: 10))
                                WorkbenchSkillReferences(skill: skill)
                            }.padding(.vertical, 12)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles").font(.system(size: 14)).frame(width: 20).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(skill.name).font(WorkbenchStyle.label)
                                    Text(store.thread(threadID).skillIDs.contains(skill.id) ? "Applied to this chat" :
                                            store.isSkillEnabled(skill) ? "Loads automatically when needed" : "Disabled")
                                        .font(WorkbenchStyle.detail).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("Enable \(skill.name)", isOn: Binding(get: { store.isSkillEnabled(skill) }, set: { store.state.skillEnabled[skill.id] = $0 }))
                                    .toggleStyle(WorkbenchSwitchStyle(showsLabel: false)).labelsHidden()
                            }.padding(.vertical, 7)
                        }
                        .contextMenu {
                            Button("Edit") { editing = skill }
                            Button("Reveal in Finder") { store.reveal(skill.url) }
                            Button("Export with references") { store.exportSkill(skill) }
                            Button("Move to Trash", role: .destructive) { deleting = skill }
                        }
                        .id(skill.id)
                    }
                }.listStyle(.inset).scrollContentBackground(.hidden)
                    .task(id: scrollTarget) {
                        guard let id = scrollTarget else { return }
                        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                        proxy.scrollTo(id, anchor: .center)
                    }
            }
        }
        .onAppear {
            store.reloadSkills()
            if let id = store.requestedSkillID { query = ""; expanded.insert(id); scrollTarget = id; store.requestedSkillID = nil }
        }
        .onChange(of: store.requestedSkillID) { _, id in
            if let id { query = ""; expanded.insert(id); scrollTarget = id; store.requestedSkillID = nil }
        }
        .sheet(item: $editing) { WorkbenchSkillEditor(skill: $0) }
        .sheet(isPresented: $creating) { WorkbenchSkillEditor(skill: nil) }
        .confirmationDialog("Move this skill to Finder Trash?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { skill in
            Button("Move to Trash", role: .destructive) { store.removeSkill(skill); deleting = nil }
        }
        .accessibilityIdentifier("workbench.skills")
    }
}

struct WorkbenchSkillEditor: View {
    let skill: LocalSkill?
    @Environment(\.dismiss) private var dismiss
    @State private var id = ""
    private static let template = """
    ---
    name: My skill
    description: Describe when this skill is useful.
    tags: [custom]
    ---

    Write clear, specific instructions here.
    """
    @State private var source = Self.template
    @State private var error: String?
    @State private var discard = false
    @State private var isSaving = false
    private var changed: Bool {
        if let skill { return source != skill.raw }
        return !id.isEmpty || source != Self.template
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(skill == nil ? "Create a skill" : "Edit \(skill!.name)").font(.title2.weight(.semibold))
                Spacer()
                Text("SKILL.md").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            if skill == nil { TextField("Folder name, e.g. architecture-review", text: $id).textFieldStyle(.roundedBorder) }
            TextEditor(text: $source).font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden).padding(10).background(WorkbenchStyle.canvas)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(WorkbenchStyle.border)).frame(minHeight: 330)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Cancel") { if changed { discard = true } else { dismiss() } }.keyboardShortcut(.cancelAction).disabled(isSaving)
                Spacer()
                Text("Enabled skills can be loaded by the model when needed.").font(.caption).foregroundStyle(.secondary)
                if isSaving { ProgressView().controlSize(.small) }
                Button("Save", action: save).buttonStyle(WorkbenchButtonStyle(prominent: true)).keyboardShortcut("s", modifiers: .command).disabled(isSaving)
            }
        }
        .padding(26).frame(width: 680)
        .onAppear { if let skill { id = skill.id; source = skill.raw } }
        .interactiveDismissDisabled(changed || isSaving)
        .confirmationDialog("Discard your changes?", isPresented: $discard) {
            Button("Discard changes", role: .destructive) { dismiss() }
        }
    }
    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let identifier = id.trimmingCharacters(in: .whitespaces)
                try await WorkbenchStore.shared.saveSkill(id: identifier, source: source)
                WorkbenchStore.shared.requestedSkillID = identifier
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct WorkbenchSkillReferences: View {
    let skill: LocalSkill
    @State private var files: [LocalFileEntry] = []
    @State private var error: String?
    var body: some View {
        Group {
            if let error {
                Text(error).font(WorkbenchStyle.caption).foregroundStyle(.secondary)
            } else if !files.isEmpty {
                DisclosureGroup("Reference files · \(files.count)") {
                    ForEach(files.prefix(100)) { file in
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text").foregroundStyle(.secondary)
                            Text(file.path).font(.system(size: 12, design: .monospaced)).lineLimit(2)
                            Spacer(minLength: 8)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file))
                                .font(WorkbenchStyle.detail).foregroundStyle(.secondary)
                            Button("Reveal") {
                                WorkbenchStore.shared.reveal(skill.url.deletingLastPathComponent().appendingPathComponent(file.path))
                            }.controlSize(.small)
                        }.padding(.vertical, 3)
                    }
                    if files.count > 100 {
                        Button("Show all files in Finder") { WorkbenchStore.shared.reveal(skill.url.deletingLastPathComponent()) }
                    }
                }
            }
        }
        .task(id: skill.raw) {
            let worker = Task.detached(priority: .utility) { try LocalSkillLibrary.references(for: skill) }
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled else { return }
                files = result
                error = nil
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}
