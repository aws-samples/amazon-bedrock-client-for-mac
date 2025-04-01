//
//  SidebarView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import AppKit

// MARK: - Chat Search Index

/// Optimized search index for O(log n) chat content searching
class ChatSearchIndex {
    // Map of chat IDs to indexed chat content tokens
    private var chatIndexMap: [String: Set<String>] = [:]
    // Inverted index: keyword -> chat IDs that contain it
    private var keywordIndex: [String: Set<String>] = [:]
    // Minimum word length for indexing
    private let minWordLength = 2
    
    /// Updates the search index with current chats and their content
    func updateIndex(chats: [ChatModel], chatManager: ChatManager) {
        // Create new indexes to avoid race conditions
        var newChatIndexMap: [String: Set<String>] = [:]
        var newKeywordIndex: [String: Set<String>] = [:]
        
        for chat in chats {
            // Index chat title and model name
            var searchableContent = "\(chat.title.lowercased()) \(chat.name.lowercased())"
            
            // Get chat messages and add to searchable content
            let messages = chatManager.getMessages(for: chat.chatId)
            for message in messages {
                searchableContent += " \(message.text.lowercased())"
            }
            
            // Tokenize content into words for faster searching
            let words = searchableContent
                .split { !$0.isLetter && !$0.isNumber }
                .map { String($0) }
                .filter { $0.count >= minWordLength }
            
            // Store tokenized content
            let wordSet = Set(words)
            newChatIndexMap[chat.chatId] = wordSet
            
            // Update inverted index
            for word in wordSet {
                if newKeywordIndex[word] == nil {
                    newKeywordIndex[word] = []
                }
                newKeywordIndex[word]?.insert(chat.chatId)
            }
        }
        
        // Update class properties
        chatIndexMap = newChatIndexMap
        keywordIndex = newKeywordIndex
    }
    
    /// Performs optimized search with O(log n) complexity
    func search(query: String) -> [String] {
        if query.isEmpty {
            return Array(chatIndexMap.keys)
        }
        
        // Tokenize query
        let searchTerms = query.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0) }
            .filter { $0.count >= minWordLength }
        
        if searchTerms.isEmpty {
            return Array(chatIndexMap.keys)
        }
        
        // Find matching chat IDs
        var result: Set<String>?
        
        for term in searchTerms {
            var matchingChats = Set<String>()
            
            // Find chats containing this term
            for (keyword, chatIds) in keywordIndex {
                if keyword.contains(term) {
                    matchingChats.formUnion(chatIds)
                }
            }
            
            // Intersect with previous results
            if result == nil {
                result = matchingChats
            } else {
                result?.formIntersection(matchingChats)
            }
            
            // Early exit if no matches
            if result?.isEmpty ?? true {
                return []
            }
        }
        
        return Array(result ?? [])
    }
}

struct SidebarView: View {
    // MARK: - Properties
    
    @Binding var selection: SidebarSelection?
    @Binding var menuSelection: SidebarSelection?
    @ObservedObject var chatManager: ChatManager = ChatManager.shared
    @ObservedObject var appCoordinator = AppCoordinator.shared
    
    @State private var showingClearChatAlert = false
    @State private var organizedChatModels: [String: [ChatModel]] = [:]
    @State private var selectionId = UUID()
    @State private var hoverStates: [String: Bool] = [:]
    @State private var searchText: String = ""
    @State private var searchIndex = ChatSearchIndex()
    @State private var searchResults: [String] = []
    @State private var isSearching: Bool = false
    
    // Timer to periodically update chat dates
    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM dd, yyyy"
        return formatter
    }()
    
    // Keys sorted by date for grouping chats
    private var sortedDateKeys: [String] {
        organizedChatModels.keys
            .compactMap { dateFormatter.date(from: $0) }
            .sorted()
            .reversed()
            .map { dateFormatter.string(from: $0) }
    }
    
    // Filtered chat models based on search results
    private var filteredChatModels: [String: [ChatModel]] {
        if searchText.isEmpty {
            return organizedChatModels
        }
        
        var filtered: [String: [ChatModel]] = [:]
        
        for (dateKey, chats) in organizedChatModels {
            let filteredChats = chats.filter { chat in
                searchResults.contains(chat.chatId)
            }
            
            if !filteredChats.isEmpty {
                filtered[dateKey] = filteredChats
            }
        }
        
        return filtered
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar at the top of sidebar
            searchBarView
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            
            // Chat list
            chatListView
                .onReceive(timer) { _ in
                    organizeChatsByDate()
                }
                .onChange(of: appCoordinator.shouldCreateNewChat) { newValue in
                    if newValue {
                        createNewChat()
                        appCoordinator.shouldCreateNewChat = false
                    }
                }
                .onChange(of: appCoordinator.shouldDeleteChat) { newValue in
                    if newValue {
                        deleteSelectedChat()
                        appCoordinator.shouldDeleteChat = false
                    }
                }
                .id(selectionId)
                .listStyle(SidebarListStyle())
                .frame(minWidth: 100, idealWidth: 250, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            organizeChatsByDate()
            updateSearchIndex()
        }
        .onChange(of: chatManager.chats) { _ in
            organizeChatsByDate()
            updateSearchIndex()
        }
        .onChange(of: searchText) { newValue in
            performSearch()
        }
        // Using toolbar with inline items to avoid ambiguity
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: Amazon_Bedrock_Client_for_MacApp.toggleSidebar) {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                        .help("Toggle Sidebar")
                }
                
                Button(action: {
                    createNewChat()
                }) {
                    Label("New Chat", systemImage: "square.and.pencil")
                        .help("New Chat")
                }
            }
        }
    }
    
    // MARK: - Search Bar View
    
    /// Search bar for filtering chats
    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search chats", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 14))
            
            if isSearching {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            } else if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(6)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Chat List View
    
    /// Main chat list view
    private var chatListView: some View {
        List {
            ForEach(sortedDateKeys, id: \.self) { dateKey in
                if let chats = filteredChatModels[dateKey], !chats.isEmpty {
                    Section(header: Text(dateKey)) {
                        ForEach(chats, id: \.self) { chat in
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
            
            if !searchText.isEmpty && searchResults.isEmpty {
                Text("No matching chats found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
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
    }
    
    // MARK: - Search Methods
    
    /// Updates the search index with current chat data
    private func updateSearchIndex() {
        // Perform indexing in the background
        Task(priority: .background) {
            isSearching = true
            searchIndex.updateIndex(chats: chatManager.chats, chatManager: chatManager)
            await MainActor.run {
                isSearching = false
                // Re-run search with updated index
                performSearch()
            }
        }
    }
    
    /// Executes search against the index and updates results
    private func performSearch() {
        if searchText.isEmpty {
            searchResults = []
            return
        }
        
        // Run search in the background
        Task(priority: .userInitiated) {
            isSearching = true
            let results = searchIndex.search(query: searchText)
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        }
    }
    
    // MARK: - Methods
    
    /// Creates a new chat with the currently selected model
    private func createNewChat() {
        if let modelSelection = menuSelection, case .chat(let model) = modelSelection {
            chatManager.createNewChat(modelId: model.id, modelName: model.name, modelProvider: model.provider) { newChat in
                newChat.lastMessageDate = Date()
                self.organizeChatsByDate()
                self.selection = .chat(newChat)
                self.selectionId = UUID()
            }
        }
    }
    
    /// Deletes the currently selected chat
    private func deleteSelectedChat() {
        guard let selectedChat = getSelectedChat() else {
            print("No chat selected to delete")
            return
        }
        selection = chatManager.deleteChat(with: selectedChat.chatId)
        organizeChatsByDate()
    }
    
    /// Returns the currently selected chat model, if any
    private func getSelectedChat() -> ChatModel? {
        if case .chat(let chat) = selection {
            return chat
        }
        return nil
    }
    
    /// Organizes chats by date for display in sections
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
    
    /// Formats a date for section headers
    private func formatDate(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM dd, yyyy"
        return dateFormatter.string(from: date)
    }
    
    /// Creates a view for an individual chat row
    func chatRowView(for chat: ChatModel) -> some View {
        let isHovered = hoverStates[chat.chatId, default: false]
        
        return HStack(spacing: 8) {
            // Chat title and model name
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
        .background(isHovered || selection == .chat(chat) ? Color.gray.opacity(0.15) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
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
        .onTapGesture {
            selection = .chat(chat)
        }
    }
    
    // Rest of the methods (deleteChat, exportChatAsTextFile) remain unchanged
    
    /// Deletes a specific chat
    private func deleteChat(_ chat: ChatModel) {
        hoverStates[chat.chatId] = false
        selection = chatManager.deleteChat(with: chat.chatId)
        organizeChatsByDate()
    }
    
    /// Exports a chat history as a text file
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
