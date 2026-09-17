import AppKit
import SwiftUI

struct HistorySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = AppStore.shared
    @ObservedObject private var chats = ConversationStore.shared
    @State private var query = ""
    private var filtered: [ChatModel] {
        chats.chats.filter {
            store.thread($0.chatId).archived &&
                (query.isEmpty || "\($0.title) \($0.name)".localizedStandardContains(query))
        }.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Archive").font(.system(size: 21, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            SearchField(placeholder: "Search archived chats", text: $query)
                .padding(.horizontal, 24).padding(.bottom, 16)
            Divider()
            if filtered.isEmpty {
                EmptyStateView(symbol: "archivebox",
                    title: query.isEmpty ? "No archived chats" : "No matching chats",
                    detail: query.isEmpty ? "Archive a chat from its menu or press ⌘D." : "Try a different name.")
            } else {
                ScrollViewReader { proxy in
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
                                Button("Copy conversation") { AppActions.copyThread(chat) }
                                Button("Export Markdown…") { AppActions.exportThread(chat, asJSON: false) }
                                Button("Export JSON…") { AppActions.exportThread(chat, asJSON: true) }
                                Divider()
                                Button("Delete permanently…", role: .destructive) {
                                    AppActions.confirmPermanentDeletion(of: chat)
                                }
                            } label: { Image(systemName: "ellipsis") }
                            .menuStyle(.borderlessButton).fixedSize().help("Chat actions")
                            .accessibilityLabel("Actions for \(chat.title)")
                        }.padding(.vertical, 7)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("archive.chat.\(chat.chatId)")
                            .id(chat.chatId)
                    }.listStyle(.inset)
                        .onChange(of: query) { _, _ in
                            if let firstID = filtered.first?.chatId {
                                // Filtering must not retain a partially scrolled row
                                // when earlier matches are inserted back into the list.
                                proxy.scrollTo(firstID, anchor: .top)
                            }
                        }
                }
            }
            Divider()
            HStack {
                Text("\(filtered.count) chat\(filtered.count == 1 ? "" : "s")").font(DesignTokens.detail).foregroundStyle(.secondary)
                Spacer()
                Text("Kept until you restore or permanently delete them.")
                    .font(DesignTokens.detail).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 640, height: 500)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.chatHistory")
    }
}
