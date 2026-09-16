import AppKit
import SwiftUI

struct HistorySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = AppStore.shared
    @ObservedObject private var chats = ConversationStore.shared
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
                AppSegmentedControl(title: "Show", selection: $scope,
                                          options: Scope.allCases.map { ($0, $0.rawValue) }).frame(width: 210)
                TextField("Search history", text: $query).textFieldStyle(.roundedBorder)
            }.padding(.horizontal, 24).padding(.bottom, 16)
            Divider()
            if filtered.isEmpty {
                EmptyStateView(symbol: scope == .trash ? "trash" : "archivebox",
                    title: query.isEmpty ? (scope == .trash ? "Trash is empty" : "No archived chats") : "No matching chats",
                    detail: query.isEmpty ? "Move a chat here using its menu in the sidebar." : "Try a different name.")
            } else {
                List(filtered, id: \.chatId) { chat in
                    HStack(spacing: 12) {
                        Image(systemName: "bubble.left").foregroundStyle(.secondary).frame(width: 20)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(chat.title).font(DesignTokens.label).lineLimit(1)
                            Text(chat.lastMessageDate.formatted(date: .abbreviated, time: .shortened))
                                .font(DesignTokens.detail).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") { store.restore(chat.chatId) }.controlSize(.small)
                        ActionMenu {
                            Button("Restore and open") {
                                store.restore(chat.chatId); store.selectThread(chat.chatId)
                                dismiss(); AppWindows.showMain()
                            }
                            Divider()
                            ThreadContextMenu(chat: chat)
                        } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize().help("Chat actions")
                    }.padding(.vertical, 7)
                }.listStyle(.inset)
            }
            Divider()
            HStack {
                Text("\(filtered.count) chat\(filtered.count == 1 ? "" : "s")").font(DesignTokens.detail).foregroundStyle(.secondary)
                Spacer()
                if scope == .trash { Text("Deleted only when you choose to remove them permanently.").font(DesignTokens.detail).foregroundStyle(.secondary) }
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 640, height: 500)
        .accessibilityIdentifier("settings.chatHistory")
    }
}
