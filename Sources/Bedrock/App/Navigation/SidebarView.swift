import AppKit
import SwiftUI

struct SidebarView: View {
    var onNew: () -> Void
    @ObservedObject private var store = AppStore.shared
    @ObservedObject private var chats = ConversationStore.shared
    @ObservedObject private var settings = PreferencesStore.shared
    @State private var referenceDate = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var visibleChats: [ChatModel] {
        chats.chats.filter { !store.thread($0.chatId).archived }
    }
    private var selectedItem: String {
        store.destination == .chats ? store.selectedThreadID.map { "thread:\($0)" } ?? "new" : "page:\(store.destination.rawValue)"
    }
    private var selection: Binding<String?> {
        Binding(get: { selectedItem }, set: { value in
            guard let value, value != selectedItem else { return }
            if value == "new" { onNew() }
            else if value.hasPrefix("thread:") { store.selectThread(String(value.dropFirst(7))) }
            else if value.hasPrefix("page:"), let destination = NavigationDestination(rawValue: String(value.dropFirst(5))) { store.destination = destination }
        })
    }
    var body: some View {
        let visible = visibleChats
        let pinned = visible.filter { store.thread($0.chatId).isPinned }.sorted {
            (store.thread($0.chatId).pinnedAt ?? .distantPast) < (store.thread($1.chatId).pinnedAt ?? .distantPast)
        }
        let recent = visible.filter { !store.thread($0.chatId).isPinned }
        let groups = ConversationDateGroup.group(recent, date: \.lastMessageDate, now: referenceDate)
        VStack(spacing: 0) {
            HStack {
                Text("Bedrock").font(.system(size: 16, weight: .semibold)).tracking(-0.3).lineLimit(1)
                Spacer()
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
            navigationRow("New chat", symbol: "plus.bubble", selected: selectedItem == "new", action: onNew)
                .padding(.horizontal, 10).padding(.bottom, 8)
            List(selection: selection) {
                sectionHeader("Library", id: "library")
                if store.preferences.isSidebarSectionExpanded("library") {
                    ForEach([NavigationDestination.demos, .automations, .activity]) { destination in
                        navigationRow(destination.title, symbol: destination.symbol,
                                      selected: store.destination == destination) {
                            store.destination = destination
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .selectionDisabled()
                    }
                }
                if !pinned.isEmpty {
                    sectionHeader("Pinned", id: "pinned")
                    if store.preferences.isSidebarSectionExpanded("pinned") {
                        ForEach(pinned, id: \.chatId) { chat in
                            SidebarThreadRow(chat: chat).tag("thread:\(chat.chatId)")
                                .listRowInsets(EdgeInsets())
                        }
                    }
                }
                sectionHeader("Chats", id: "chats")
                if store.preferences.isSidebarSectionExpanded("chats") {
                    ForEach(groups) { group in
                        Text(group.title)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                            .padding(.leading, 16)
                            .padding(.top, group.id == groups.first?.id ? 0 : 10)
                            .listRowInsets(EdgeInsets())
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("sidebar.date.\(group.title)")
                            .selectionDisabled()
                        ForEach(group.items, id: \.chatId) { chat in
                            SidebarThreadRow(chat: chat).tag("thread:\(chat.chatId)")
                                .listRowInsets(EdgeInsets())
                        }
                    }
                    if visible.isEmpty { Text("No conversations yet").font(DesignTokens.caption).foregroundStyle(.secondary) }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(SidebarScrollChrome())
            .font(DesignTokens.body)
            .symbolRenderingMode(.monochrome)
            // Keep each row's content height explicit. Header spacing belongs
            // inside its view; native sidebar row insets also add space below.
            .environment(\.defaultMinListRowHeight, 0)
            Divider().padding(.horizontal, 14)
            Button { store.showSettings(row: "profile") } label: {
                HStack(spacing: 10) {
                    Image(systemName: "network").font(.system(size: 14)).frame(width: 20).foregroundStyle(.primary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(settings.selectedProfile).font(DesignTokens.caption).lineLimit(1)
                        Text(settings.selectedRegion.rawValue).font(DesignTokens.detail).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(.primary)
                }.contentShape(Rectangle()).padding(.horizontal, 18).padding(.vertical, 13)
            }.buttonStyle(.plain).accessibilityLabel("AWS connection and settings")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workbench.sidebar")
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in referenceDate = Date() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in referenceDate = Date() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in referenceDate = Date() }
    }

    // These are ordinary, non-selectable rows rather than outline sections.
    // AppKit must not maintain a second disclosure state beside the persisted
    // preference, or the visible rows and the relaunch state can disagree.
    private func sectionHeader(_ title: String, id: String) -> some View {
        let expanded = store.preferences.isSidebarSectionExpanded(id)
        return Button {
            // Keep large chat lists immediate; animate only the small library.
            withAnimation(id == "library" && !reduceMotion ? .easeInOut(duration: 0.16) : nil) {
                store.preferences.setSidebarSection(id, expanded: !expanded)
            }
        } label: {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("sidebar.\(id).toggle")
        .padding(.top, id == "library" ? 0 : 12)
        .listRowInsets(EdgeInsets())
        .selectionDisabled()
    }

    private func navigationRow(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(width: 17)
                Text(title).font(DesignTokens.body).lineLimit(1)
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

struct SidebarThreadRow: View {
    @ObservedObject var chat: ChatModel
    @ObservedObject private var draftIndicator: DraftIndicator
    @ObservedObject private var chats = ConversationStore.shared
    @ObservedObject private var store = AppStore.shared

    init(chat: ChatModel) {
        self.chat = chat
        self.draftIndicator = AppStore.shared.draftIndicator(for: chat.chatId)
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(chat.title == "New Chat" ? "New chat" : chat.title).lineLimit(1).font(DesignTokens.body)
            Spacer(minLength: 1)
            if chats.getIsLoading(for: chat.chatId) { ProgressView().controlSize(.mini) }
            else if store.thread(chat.chatId).isPinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.tertiary) }
            else if draftIndicator.hasText || store.thread(chat.chatId).hasDraftAttachments == true {
                Image(systemName: "pencil").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: store.preferences.compactSidebar ? 26 : 32)
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .help("\(chat.name) · \(chat.lastMessageDate.formatted(date: .abbreviated, time: .shortened))")
        .contextMenu { ThreadContextMenu(chat: chat) }
        .accessibilityIdentifier("thread.\(chat.chatId)")
    }
}

struct ThreadContextMenu: View {
    @ObservedObject var chat: ChatModel
    @ObservedObject private var store = AppStore.shared
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
                    if !title.isEmpty { ConversationStore.shared.updateChatTitle(for: chat.chatId, title: title, isManualRename: true) }
                }
            }
            Button(store.thread(chat.chatId).isPinned ? "Unpin" : "Pin thread") { store.togglePin(chat.chatId) }
            Button("Branch conversation") { AppActions.fork(chat) }
                .disabled(ConversationStore.shared.getIsLoading(for: chat.chatId))
            if let parentID = store.thread(chat.chatId).parentThreadID,
               ConversationStore.shared.getChatModel(for: parentID) != nil {
                Button("Open original conversation") { store.selectThread(parentID) }
            }
            Divider()
            Button("Copy conversation") { AppActions.copyThread(chat) }
            Button("Export Markdown…") { AppActions.exportThread(chat, asJSON: false) }
            Button("Export JSON…") { AppActions.exportThread(chat, asJSON: true) }
            Divider()
            if store.thread(chat.chatId).archived {
                Button("Restore") { store.restore(chat.chatId) }
                Button("Delete permanently…", role: .destructive) {
                    AppActions.confirmPermanentDeletion(of: chat)
                }
            } else {
                Button("Archive") { store.archive(chat.chatId) }
            }
        }
    }
}
