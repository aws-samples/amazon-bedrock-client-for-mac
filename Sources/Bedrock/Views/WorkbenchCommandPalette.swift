import SwiftUI

struct WorkbenchCommandPalette: View {
    let onNewThread: () -> Void
    let onDemo: (DemoPreset) -> Void
    let onDismiss: () -> Void
    @ObservedObject private var store = WorkbenchStore.shared
    @ObservedObject private var chats = ChatManager.shared
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var contentMatches: [String: ConversationSearchHit] = [:]
    @State private var isSearching = false
    @State private var unreadableCount = 0
    @FocusState private var focused: Bool

    private enum Target {
        case newThread, importThread, setting(String), page(WorkbenchDestination), thread(String), demo(DemoPreset), skill(String)
    }
    private struct Item: Identifiable {
        var id: String
        var title: String
        var detail: String
        var symbol: String
        var target: Target
    }
    private var items: [Item] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [Item] = []
        if text.isEmpty || "new thread chat conversation".localizedStandardContains(text) {
            result.append(.init(id: "new", title: "New thread", detail: "⌘N", symbol: "plus.bubble", target: .newThread))
        }
        if text.isEmpty || "import conversation json".localizedStandardContains(text) {
            result.append(.init(id: "import", title: "Import conversation…", detail: "Local JSON export", symbol: "square.and.arrow.down", target: .importThread))
        }
        for destination in WorkbenchDestination.allCases where destination != .chats {
            let keywords = "\(destination.title) \(destination == .automations ? "schedule cron timer" : "")"
            if text.isEmpty || keywords.localizedStandardContains(text) {
                result.append(.init(id: "page-\(destination.id)", title: destination.title, detail: "Go to page", symbol: destination.symbol, target: .page(destination)))
            }
        }
        if !text.isEmpty {
            for setting in WorkbenchSetting.all where setting.matches(text) {
                result.append(.init(id: "setting-\(setting.id)", title: setting.title, detail: "Settings › \(setting.pane.title)", symbol: setting.pane.symbol, target: .setting(setting.id)))
            }
            for skill in store.skills where "\(skill.name) \(skill.description) \(skill.tags.joined(separator: " "))".localizedStandardContains(text) {
                result.append(.init(id: "skill-\(skill.id)", title: skill.name, detail: "Local skill", symbol: "sparkles", target: .skill(skill.id)))
            }
            for demo in store.demos where "\(demo.title) \(demo.summary) \(demo.category.rawValue)".localizedStandardContains(text) {
                result.append(.init(id: "demo-\(demo.id)", title: demo.title, detail: "Demo › \(demo.category.rawValue)", symbol: demo.category.symbol, target: .demo(demo)))
            }
        }
        let threadResults = chats.chats.filter {
            store.thread($0.chatId).deletedAt == nil &&
            (text.isEmpty || "\($0.title) \($0.name)".localizedStandardContains(text) || contentMatches[$0.chatId] != nil)
        }.sorted {
            let leftTitle = !text.isEmpty && $0.title.localizedStandardContains(text)
            let rightTitle = !text.isEmpty && $1.title.localizedStandardContains(text)
            return leftTitle != rightTitle ? leftTitle : $0.lastMessageDate > $1.lastMessageDate
        }.prefix(text.isEmpty ? 6 : 40)
        for chat in threadResults {
            let detail = contentMatches[chat.chatId]?.snippet ?? chat.name
            result.append(.init(id: "thread-\(chat.chatId)", title: chat.title, detail: detail, symbol: "bubble.left", target: .thread(chat.chatId)))
        }
        return Array(result.prefix(80))
    }

    var body: some View {
        let rows = items
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search threads, settings, demos, skills…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 14)).focused($focused)
                    .onSubmit { activateSelected() }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                Text("esc").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
            }.padding(20)
            Divider()
            if rows.isEmpty {
                WorkbenchEmptyState(symbol: "magnifyingglass", title: isSearching ? "Searching conversations…" : "No results",
                                    detail: "Search message text, a thread topic, a setting, or a skill.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                                Button { activate(item) } label: {
                                    HStack(spacing: 11) {
                                        Image(systemName: item.symbol).font(.system(size: 14)).frame(width: 24).foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.title).font(WorkbenchStyle.label).lineLimit(1)
                                            Text(item.detail).font(WorkbenchStyle.detail).foregroundStyle(.secondary).lineLimit(1)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                        if index == selectedIndex { Image(systemName: "return").font(.system(size: 10)).foregroundStyle(.tertiary) }
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                    .background(index == selectedIndex ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).id(item.id)
                            }
                        }.padding(8)
                    }
                    .onChange(of: selectedIndex) { _, index in
                        if rows.indices.contains(index) { proxy.scrollTo(rows[index].id) }
                    }
                }
            }
            Divider()
            HStack {
                if isSearching {
                    ProgressView().controlSize(.mini)
                    Text("Searching local history…").foregroundStyle(.secondary)
                } else if unreadableCount > 0 {
                    Text("\(unreadableCount) histor\(unreadableCount == 1 ? "y file could" : "y files could") not be read")
                        .foregroundStyle(.secondary).help("The original files were kept. See Data & history in Settings.")
                } else {
                    Text("↑ ↓ to navigate").foregroundStyle(.secondary)
                }
                Spacer()
                Text("↩ to open").foregroundStyle(.secondary)
            }.font(.system(size: 10)).padding(.horizontal, 18).padding(.vertical, 11)
        }
        .frame(width: 620, height: 460)
        .background(WorkbenchStyle.canvas)
        .task {
            await Task.yield()
            focused = true
            AppStateManager.shared.isSearchFieldActive = true
        }
        .onDisappear { AppStateManager.shared.isSearchFieldActive = false }
        .onExitCommand(perform: onDismiss)
        .onChange(of: query) { _, _ in selectedIndex = 0; contentMatches = [:]; unreadableCount = 0 }
        .task(id: query) { await searchContents() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workbench.commandPalette")
    }

    private func move(_ amount: Int) { selectedIndex = min(max(0, selectedIndex + amount), max(0, items.count - 1)) }
    private func activateSelected() {
        guard items.indices.contains(selectedIndex) else { return }
        activate(items[selectedIndex])
    }
    private func activate(_ item: Item) {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let match: ConversationSearchHit?
        if case .thread(let id) = item.target { match = contentMatches[id] } else { match = nil }
        onDismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            switch item.target {
            case .newThread: onNewThread()
            case .importThread: WorkbenchActions.importThread()
            case .setting(let id): store.showSettings(row: id)
            case .page(let page): store.destination = page
            case .thread(let id):
                if let match { store.chatSearchRequest = .init(threadID: id, query: search, messageID: match.messageID) }
                store.selectThread(id)
            case .demo(let demo): onDemo(demo)
            case .skill(let id): store.requestedSkillID = id; store.showSettings(row: "skills")
            }
        }
    }
    private func searchContents() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { isSearching = false; return }
        isSearching = true
        do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
        let root = URL(fileURLWithPath: SettingManager.shared.defaultDirectory).appendingPathComponent("history")
        let inputs = chats.chats.filter { store.thread($0.chatId).deletedAt == nil }
            .sorted { $0.lastMessageDate > $1.lastMessageDate }.map {
            ConversationSearchInput(id: $0.chatId,
                unifiedURL: root.appendingPathComponent("\($0.chatId)_unified_history.json"),
                legacyURL: root.deletingLastPathComponent().appendingPathComponent("messages/\($0.chatId)_messages.json"))
        }
        let task = Task(priority: .userInitiated) {
            await ConversationSearchIndex.shared.search(text, inputs: inputs)
        }
        let matches = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if !Task.isCancelled && query.trimmingCharacters(in: .whitespacesAndNewlines) == text {
            contentMatches = matches.hits
            unreadableCount = matches.unreadableCount
            isSearching = false
        }
    }
}
