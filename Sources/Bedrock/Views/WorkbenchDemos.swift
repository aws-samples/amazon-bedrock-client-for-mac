import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkbenchDemoLibrary: View {
    var onUse: (DemoPreset) -> Void
    @ObservedObject private var store = WorkbenchStore.shared
    @State private var query = ""
    @State private var category: DemoCategory?
    @State private var editing: DemoPreset?
    @State private var deleting: DemoPreset?
    private var filtered: [DemoPreset] {
        store.demos.filter {
            (category == nil || $0.category == category) &&
            (query.isEmpty || "\($0.title) \($0.summary) \($0.prompt)".localizedStandardContains(query))
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WorkbenchPageHeader(title: "Start with a possibility", subtitle: "Editable prompts for your next Bedrock demo. Choose one, make it yours, then send.")
                HStack {
                    TextField("Search demos", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                    Spacer()
                    Button("Import", systemImage: "square.and.arrow.down", action: importDemo)
                    Button("New demo", systemImage: "plus") {
                        editing = DemoPreset(id: UUID().uuidString, title: "", summary: "", category: .text, prompt: "")
                    }
                }
                WorkbenchMenuField(title: "Category", selection: $category,
                    options: [(nil, "All categories")] + DemoCategory.allCases.map { (Optional($0), $0.rawValue) }).frame(width: 210)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 15)], spacing: 15) {
                    ForEach(filtered) { demo in card(demo) }
                }
                if filtered.isEmpty { WorkbenchEmptyState(symbol: "magnifyingglass", title: "No matching demos", detail: "Try another search or create a prompt of your own.") }
            }
            .padding(32).frame(maxWidth: 1120).frame(maxWidth: .infinity)
        }
        .sheet(item: $editing) { demo in WorkbenchDemoEditor(demo: demo) }
        .confirmationDialog("Delete this demo?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { demo in
            Button("Delete \(demo.title)", role: .destructive) { store.state.customDemos.removeAll { $0.id == demo.id }; deleting = nil }
        }
        .accessibilityIdentifier("workbench.demos")
    }
    private func card(_ demo: DemoPreset) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: demo.category.symbol).font(.system(size: 20, weight: .light)).foregroundStyle(WorkbenchStyle.accent)
                Spacer()
                WorkbenchActionMenu {
                    Button("Duplicate") {
                        var copy = demo
                        copy.id = UUID().uuidString; copy.title += " copy"; copy.isBuiltIn = false
                        editing = copy
                    }
                    if !demo.isBuiltIn { Button("Edit") { editing = demo } }
                    Button("Export…") { WorkbenchActions.exportDemo(demo) }
                    if !demo.isBuiltIn {
                        Divider()
                        Button("Delete", role: .destructive) { deleting = demo }
                    }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).fixedSize()
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(demo.title).font(.system(size: 15, weight: .semibold))
                Text(demo.summary).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            HStack {
                Text(demo.category.rawValue).font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button("Use prompt", systemImage: "arrow.up.right") { onUse(demo) }
                    .buttonStyle(.borderless).font(.system(size: 11, weight: .medium))
            }
        }
        .padding(20)
        .background(WorkbenchStyle.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WorkbenchStyle.border, lineWidth: 0.5))
    }
    private func importDemo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_000_000 else { throw LocalWorkbenchError.tooLarge(1_000_000) }
                var demo = try JSONDecoder().decode(DemoPreset.self, from: Data(contentsOf: url))
                guard !demo.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !demo.prompt.isEmpty else { throw LocalWorkbenchError.invalid("The demo needs a title and prompt.") }
                demo.id = UUID().uuidString
                demo.isBuiltIn = false
                editing = demo
            } catch { store.errorMessage = "Could not import demo: \(error.localizedDescription)" }
        }
    }
}

struct WorkbenchDemoEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var demo: DemoPreset
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit demo").font(.title2.weight(.semibold))
            Form {
                TextField("Title", text: $demo.title)
                TextField("Description", text: $demo.summary)
                WorkbenchMenuField(title: "Category", selection: $demo.category,
                                   options: DemoCategory.allCases.map { ($0, $0.rawValue) })
                Text("Use {{variable}} in a prompt for a required field.").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $demo.prompt).font(.system(size: 13)).frame(minHeight: 190).border(WorkbenchStyle.border)
                DisclosureGroup("System instructions") { TextEditor(text: $demo.systemPrompt).font(.system(size: 12)).frame(height: 90) }
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save demo") { WorkbenchStore.shared.saveDemo(demo); dismiss() }
                    .buttonStyle(WorkbenchButtonStyle(prominent: true)).keyboardShortcut("s", modifiers: .command)
                    .disabled(demo.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || demo.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(26).frame(width: 580)
    }
}

struct WorkbenchDemoVariablesSheet: View {
    let demo: DemoPreset
    var onUse: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(demo.title).font(.title2.weight(.semibold))
            Text(demo.summary).foregroundStyle(.secondary)
            ForEach(demo.variables, id: \.self) { key in
                TextField(key.capitalized, text: Binding(get: { values[key] ?? "" }, set: { values[key] = $0 }))
                    .textFieldStyle(.roundedBorder).onSubmit(use)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Prepare prompt", action: use).buttonStyle(WorkbenchButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(26).frame(width: 480)
    }
    private func use() {
        do { onUse(try demo.renderedPrompt(values: values)) }
        catch { self.error = error.localizedDescription }
    }
}

struct WorkbenchComparisonSheet: View {
    let models: [ChatModel]
    let backend: BackendModel
    @Environment(\.dismiss) private var dismiss
    @State private var first = ""
    @State private var second = ""
    @State private var prompt = DemoPreset.builtIns.first { $0.id == "compare" }!.prompt
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("One prompt. Two perspectives.").font(.title2.weight(.semibold))
            Text("Run two independent Bedrock requests and keep their responses side by side. Each request uses your AWS account.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                modelPicker("First model", selection: $first)
                modelPicker("Second model", selection: $second)
            }
            TextEditor(text: $prompt).font(.system(size: 13)).frame(height: 180).border(WorkbenchStyle.border)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Run comparison", systemImage: "play.fill", action: run)
                    .buttonStyle(WorkbenchButtonStyle(prominent: true))
                    .disabled(first.isEmpty || second.isEmpty || first == second || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(26).frame(width: 660)
        .onAppear {
            first = WorkbenchModelCatalog.shared.defaultModel?.id ?? models.first?.id ?? ""
            second = models.first { $0.id != first && $0.provider != models.first { $0.id == first }?.provider }?.id
                ?? models.first { $0.id != first }?.id ?? ""
        }
    }
    private func modelPicker(_ label: String, selection: Binding<String>) -> some View {
        WorkbenchMenuField(title: label, selection: selection,
                           options: [("", "Choose a model")] + models.map { ($0.id, $0.name) })
        .frame(maxWidth: .infinity)
    }
    private func run() {
        guard let a = models.first(where: { $0.id == first }), let b = models.first(where: { $0.id == second }) else { return }
        let firstChat = WorkbenchActions.newThread(model: a, draft: prompt)
        let secondChat = WorkbenchActions.newThread(model: b, draft: prompt, select: false)
        WorkbenchStore.shared.companionThreadID = secondChat.chatId
        let firstSession = ChatSessionPool.shared.session(chatID: firstChat.chatId, backend: backend)
        let secondSession = ChatSessionPool.shared.session(chatID: secondChat.chatId, backend: backend)
        Task {
            await firstSession.waitUntilReady()
            await secondSession.waitUntilReady()
            firstSession.sendMessage()
            secondSession.sendMessage()
        }
        dismiss()
    }
}
