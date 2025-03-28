//
//  SidebarView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import AppKit

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 10)
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @Binding var menuSelection: SidebarSelection?
    @ObservedObject var chatManager: ChatManager = ChatManager.shared
    @ObservedObject var appCoordinator = AppCoordinator.shared

    @State private var showingClearChatAlert = false
    @State private var organizedChatModels: [String: [ChatModel]] = [:]
    @State private var selectionId = UUID()
    @State private var hoverStates: [String: Bool] = [:]
    
    @State var buttonHover = false
    
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM dd, yyyy"
        return formatter
    }()
    
    private var sortedDateKeys: [String] {
        organizedChatModels.keys
            .compactMap { dateFormatter.date(from: $0) }
            .sorted()
            .reversed()
            .map { dateFormatter.string(from: $0) }
    }
    
    var body: some View {
        List {
            newChatSection
            ForEach(sortedDateKeys, id: \.self) { dateKey in
                Section(header: Text(dateKey)) {
                    ForEach(organizedChatModels[dateKey] ?? [], id: \.self) { chat in
                        chatRowView(for: chat)
                            .contextMenu {
                                Button("Delete Chat", action: {
                                    deleteChat(chat)
                                })
                                Button("Export Chat as Text", action: {
                                    exportChatAsTextFile(chat)
                                })
                            }
                    }
                }
            }
        }
        .contextMenu {
            Button("Delete All Chats", action: {
                showingClearChatAlert = true
            })
        }
        .alert(isPresented: $showingClearChatAlert) {
            Alert(
                title: Text("Delete all messages"),
                message: Text("This will delete all chat histories"),
                primaryButton: .destructive(Text("Delete")) {
                    chatManager.clearAllChats()
                },
                secondaryButton: .cancel()
            )
        }
        .onReceive(timer) { _ in
            organizeChatsByDate()
        }
        .onChange(of: appCoordinator.shouldCreateNewChat, perform: { newValue in
            if newValue {
                createNewChat()
                appCoordinator.shouldCreateNewChat = false
            }
        })
        .onChange(of: appCoordinator.shouldDeleteChat) { newValue in
            if newValue {
                deleteSelectedChat()
                appCoordinator.shouldDeleteChat = false
            }
        }
        .id(selectionId)
        .listStyle(SidebarListStyle())
        .frame(minWidth: 100, idealWidth: 150, maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: organizeChatsByDate)
        .onChange(of: chatManager.chats, perform: { _ in
            organizeChatsByDate()
        })
    }
    
    var newChatSection: some View {
        Button(action: {
            createNewChat()
            // 임의로 0.5초 후 buttonHover 해제 (기존 로직)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.buttonHover = false
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .semibold))
                Text("New Chat")
                    .font(.system(size: 16, weight: .medium))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(buttonHover ? Color.gray.opacity(0.15) : Color.clear)
            .cornerRadius(8)
            // 살짝 확대되는 애니메이션
            .scaleEffect(buttonHover ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: buttonHover)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover in
            buttonHover = hover
            if hover {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
    
    private func createNewChat() {
        if let modelSelection = menuSelection, case .chat(let model) = modelSelection {
            chatManager.createNewChat(modelId: model.id, modelName: model.name) { newChat in
                newChat.lastMessageDate = Date()
                self.organizeChatsByDate()
                self.selection = .chat(newChat)
                self.selectionId = UUID()
            }
        }
    }
    
    private func deleteSelectedChat() {
        guard let selectedChat = getSelectedChat() else {
            print("No chat selected to delete")
            return
        }
        selection = chatManager.deleteChat(with: selectedChat.chatId)
        organizeChatsByDate()
    }
    
    private func getSelectedChat() -> ChatModel? {
        if case .chat(let chat) = selection {
            return chat
        }
        return nil
    }
    
    func organizeChatsByDate() {
        let calendar = Calendar.current
        let sortedChats = chatManager.chats.sorted { $0.lastMessageDate > $1.lastMessageDate }
        let groupedChats = Dictionary(grouping: sortedChats) { chat -> DateComponents in
            calendar.dateComponents([.year, .month, .day], from: chat.lastMessageDate)
        }
        
        let sortedDateComponents = groupedChats.keys.sorted {
            if $0.year != $1.year {
                return $0.year! < $1.year!
            } else if $0.month != $1.month {
                return $0.month! < $1.month!
            } else {
                return $0.day! < $1.day!
            }
        }
        
        organizedChatModels = [:]
        for components in sortedDateComponents {
            if let date = calendar.date(from: components) {
                let key = formatDate(date)
                if let chatsForDate = groupedChats[components] {
                    organizedChatModels[key] = chatsForDate
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM dd, yyyy"
        return dateFormatter.string(from: date)
    }
    
    func chatRowView(for chat: ChatModel) -> some View {
        let isHovered = hoverStates[chat.chatId, default: false]

        return HStack(spacing: 8) {
            // Main text content (now using chat.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(chat.name)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Loading indicator
            if chatManager.getIsLoading(for: chat.chatId) {
                Text("…")
                    .font(.headline)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        // Background color when hovered or selected
        .background(isHovered || selection == .chat(chat) ? Color.gray.opacity(0.15) : Color.clear)
        .cornerRadius(8)
        // Slight scale up on hover
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .contentShape(Rectangle())
        // Update cursor and hover states on hover
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.2)) {
                hoverStates[chat.chatId] = hover
            }
            if hover {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        // Select chat on tap
        .onTapGesture {
            selection = .chat(chat)
        }
    }

    
    private func getIcon(for chat: ChatModel) -> Image {
        switch chat.id {
        case let id where id.contains("anthropic"):
            return Image("anthropic")
        case let id where id.contains("meta"):
            return Image("meta")
        case let id where id.contains("cohere"):
            return Image("cohere")
        case let id where id.contains("mistral"):
            return Image("mistral")
        case let id where id.contains("ai21"):
            return Image("AI21")
        case let id where id.contains("amazon"):
            return Image("amazon")
        case let id where id.contains("stability"):
            return Image("stability ai")
        case let id where id.contains("deepseek"):
            return Image("deepseek")
        default:
            return Image("bedrock")
        }
    }
    
    private func deleteChat(_ chat: ChatModel) {
        hoverStates[chat.chatId] = false
        selection = chatManager.deleteChat(with: chat.chatId)
        organizeChatsByDate()
    }
    
    private func exportChatAsTextFile(_ chat: ChatModel) {
        let chatMessages = chatManager.getMessages(for: chat.chatId)
        let fileContents = chatMessages.map { "\($0.sentTime): \($0.user): \($0.text)" }.joined(separator: "\n")
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.text]
        savePanel.nameFieldStringValue = "\(chat.title).txt"
        
        savePanel.begin { response in
            if response == .OK {
                guard let url = savePanel.url else { return }
                do {
                    try fileContents.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Failed to save chat history: \(error)")
                }
            }
        }
    }
}
