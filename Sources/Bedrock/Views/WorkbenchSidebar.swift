import AppKit
import SwiftUI

struct WorkbenchSidebar: View {
    var onNew: () -> Void
    @ObservedObject private var store = WorkbenchStore.shared
    @ObservedObject private var chats = ChatManager.shared
    @ObservedObject private var settings = SettingManager.shared
    private var visibleChats: [ChatModel] {
        chats.chats.filter { !store.thread($0.chatId).archived && store.thread($0.chatId).deletedAt == nil }
            .sorted {
                let a = store.thread($0.chatId), b = store.thread($1.chatId)
                if let ap = a.pinnedAt, let bp = b.pinnedAt { return ap < bp }
                if a.isPinned != b.isPinned { return a.isPinned }
                return $0.lastMessageDate > $1.lastMessageDate
            }
    }
    private var selectedItem: String {
        store.destination == .chats ? store.selectedThreadID.map { "thread:\($0)" } ?? "new" : "page:\(store.destination.rawValue)"
    }
    private var selection: Binding<String?> {
        Binding(get: { selectedItem }, set: { value in
            guard let value, value != selectedItem else { return }
            if value == "new" { onNew() }
            else if value.hasPrefix("thread:") { store.selectThread(String(value.dropFirst(7))) }
            else if value.hasPrefix("page:"), let destination = WorkbenchDestination(rawValue: String(value.dropFirst(5))) { store.destination = destination }
        })
    }
    var body: some View {
        let visible = visibleChats
        let pinned = visible.filter { store.thread($0.chatId).isPinned }
        let recent = visible.filter { !store.thread($0.chatId).isPinned }
        VStack(spacing: 0) {
            HStack {
                Text("Bedrock").font(.system(size: 16, weight: .semibold)).tracking(-0.3).lineLimit(1)
                Spacer()
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
            VStack(spacing: 2) {
                navigationRow("New chat", symbol: "plus.bubble", selected: selectedItem == "new", action: onNew)
                    .padding(.bottom, 12)
                ForEach([WorkbenchDestination.demos, .automations, .activity]) { destination in
                    navigationRow(destination.title, symbol: destination.symbol,
                                  selected: store.destination == destination) {
                        store.destination = destination
                    }
                }
            }
            .padding(.horizontal, 10).padding(.bottom, 10)
            List(selection: selection) {
                if !pinned.isEmpty {
                    Section("Pinned") {
                        ForEach(pinned, id: \.chatId) { chat in
                            WorkbenchThreadRow(chat: chat).tag("thread:\(chat.chatId)")
                        }
                    }
                }
                Section("Chats") {
                    ForEach(recent, id: \.chatId) { chat in
                        WorkbenchThreadRow(chat: chat).tag("thread:\(chat.chatId)")
                    }
                    if visible.isEmpty { Text("No conversations yet").font(WorkbenchStyle.caption).foregroundStyle(.secondary) }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(WorkbenchSidebarScrollChrome())
            .font(WorkbenchStyle.body)
            .symbolRenderingMode(.monochrome)
            .environment(\.defaultMinListRowHeight, store.preferences.compactSidebar ? 26 : 32)
            Divider().padding(.horizontal, 14)
            Button { store.showSettings(row: "profile") } label: {
                HStack(spacing: 10) {
                    Image(systemName: "network").font(.system(size: 14)).frame(width: 20).foregroundStyle(.primary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(settings.selectedProfile).font(WorkbenchStyle.caption).lineLimit(1)
                        Text(settings.selectedRegion.rawValue).font(WorkbenchStyle.detail).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(.primary)
                }.contentShape(Rectangle()).padding(.horizontal, 18).padding(.vertical, 13)
            }.buttonStyle(.plain).accessibilityLabel("AWS connection and settings")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workbench.sidebar")
    }

    private func navigationRow(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(width: 17)
                Text(title).font(WorkbenchStyle.body).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(height: store.preferences.compactSidebar ? 30 : 34)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .background(selected ? Color.primary.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct WorkbenchThreadRow: View {
    @ObservedObject var chat: ChatModel
    @ObservedObject private var draftIndicator: WorkbenchDraftIndicator
    @ObservedObject private var chats = ChatManager.shared
    @ObservedObject private var store = WorkbenchStore.shared

    init(chat: ChatModel) {
        self.chat = chat
        self.draftIndicator = WorkbenchStore.shared.draftIndicator(for: chat.chatId)
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(chat.title == "New Chat" ? "New chat" : chat.title).lineLimit(1).font(WorkbenchStyle.body)
            Spacer(minLength: 1)
            if chats.getIsLoading(for: chat.chatId) { ProgressView().controlSize(.mini) }
            else if store.thread(chat.chatId).isPinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.tertiary) }
            else if draftIndicator.hasText || store.thread(chat.chatId).hasDraftAttachments == true {
                Image(systemName: "pencil").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .help("\(chat.name) · \(chat.lastMessageDate.formatted(date: .abbreviated, time: .shortened))")
        .contextMenu { WorkbenchThreadMenu(chat: chat) }
        .accessibilityIdentifier("thread.\(chat.chatId)")
    }
}

struct WorkbenchThreadMenu: View {
    @ObservedObject var chat: ChatModel
    @ObservedObject private var store = WorkbenchStore.shared
    @State private var rename = ""
    @State private var showRename = false
    var body: some View {
        Group {
            Button("Rename…") {
                let alert = NSAlert()
                alert.messageText = "Rename thread"
                let field = NSTextField(string: chat.title)
                field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
                alert.accessoryView = field
                alert.addButton(withTitle: "Rename")
                alert.addButton(withTitle: "Cancel")
                alert.window.initialFirstResponder = field
                if alert.runModal() == .alertFirstButtonReturn {
                    let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty { ChatManager.shared.updateChatTitle(for: chat.chatId, title: title, isManualRename: true) }
                }
            }
            Button(store.thread(chat.chatId).isPinned ? "Unpin" : "Pin thread") { store.togglePin(chat.chatId) }
            Button("Branch conversation") { WorkbenchActions.fork(chat) }
                .disabled(ChatManager.shared.getIsLoading(for: chat.chatId))
            if let parentID = store.thread(chat.chatId).parentThreadID,
               ChatManager.shared.getChatModel(for: parentID) != nil {
                Button("Open original conversation") { store.selectThread(parentID) }
            }
            Divider()
            Button("Copy conversation") { WorkbenchActions.copyThread(chat) }
            Button("Export Markdown…") { WorkbenchActions.exportThread(chat, asJSON: false) }
            Button("Export JSON…") { WorkbenchActions.exportThread(chat, asJSON: true) }
            Divider()
            Button(store.thread(chat.chatId).archived ? "Unarchive" : "Archive") { store.archive(chat.chatId, archived: !store.thread(chat.chatId).archived) }
            if store.thread(chat.chatId).deletedAt != nil {
                Button("Restore from trash") { store.restore(chat.chatId) }
                Button("Delete permanently…", role: .destructive) {
                    let alert = NSAlert()
                    alert.messageText = "Permanently delete “\(chat.title)”?"
                    alert.informativeText = "This removes this conversation's local history. It cannot be undone."
                    alert.addButton(withTitle: "Delete")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn { store.deletePermanently(chat.chatId) }
                }
            } else {
                Button("Move to trash", role: .destructive) { store.trash(chat.chatId) }
            }
        }
    }
}

/// Archived and deleted chats share one management surface in Settings.
struct WorkbenchHistorySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = WorkbenchStore.shared
    @ObservedObject private var chats = ChatManager.shared
    @State private var scope: Scope = .archived
    @State private var query = ""
    private enum Scope: String, CaseIterable { case archived = "Archived", trash = "Trash" }
    private var filtered: [ChatModel] {
        chats.chats.filter {
            let metadata = store.thread($0.chatId)
            let included = scope == .trash ? metadata.deletedAt != nil : metadata.archived && metadata.deletedAt == nil
            return included && (query.isEmpty || "\($0.title) \($0.name)".localizedStandardContains(query))
        }.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chat history").font(.system(size: 21, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            HStack(spacing: 16) {
                WorkbenchSegmentedControl(title: "Show", selection: $scope,
                                          options: Scope.allCases.map { ($0, $0.rawValue) }).frame(width: 210)
                TextField("Search history", text: $query).textFieldStyle(.roundedBorder)
            }.padding(.horizontal, 24).padding(.bottom, 16)
            Divider()
            if filtered.isEmpty {
                WorkbenchEmptyState(symbol: scope == .trash ? "trash" : "archivebox",
                    title: query.isEmpty ? (scope == .trash ? "Trash is empty" : "No archived chats") : "No matching chats",
                    detail: query.isEmpty ? "Move a chat here using its menu in the sidebar." : "Try a different name.")
            } else {
                List(filtered, id: \.chatId) { chat in
                    HStack(spacing: 12) {
                        Image(systemName: "bubble.left").foregroundStyle(.secondary).frame(width: 20)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(chat.title).font(WorkbenchStyle.label).lineLimit(1)
                            Text(chat.lastMessageDate.formatted(date: .abbreviated, time: .shortened))
                                .font(WorkbenchStyle.detail).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") { store.restore(chat.chatId) }.controlSize(.small)
                        WorkbenchActionMenu {
                            Button("Restore and open") {
                                store.restore(chat.chatId); store.selectThread(chat.chatId)
                                dismiss(); WorkbenchWindows.showMain()
                            }
                            Divider()
                            WorkbenchThreadMenu(chat: chat)
                        } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize().help("Chat actions")
                    }.padding(.vertical, 7)
                }.listStyle(.inset)
            }
            Divider()
            HStack {
                Text("\(filtered.count) chat\(filtered.count == 1 ? "" : "s")").font(WorkbenchStyle.detail).foregroundStyle(.secondary)
                Spacer()
                if scope == .trash { Text("Deleted only when you choose to remove them permanently.").font(WorkbenchStyle.detail).foregroundStyle(.secondary) }
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 640, height: 500)
        .accessibilityIdentifier("settings.chatHistory")
    }
}
