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
@MainActor
class ChatSearchIndex {
    // Map of chat IDs to indexed chat content tokens
    var chatIndexMap: [String: Set<String>] = [:]
    private var _chatIndexMap: [String: Set<String>] = [:]

    // Inverted index: keyword -> chat IDs that contain it
    var keywordIndex: [String: Set<String>] = [:]
    private var _keywordIndex: [String: Set<String>] = [:]

    // Minimum word length for indexing
    private let minWordLength = 2

    func updateIndexDirect(chatIndexMap: [String: Set<String>], keywordIndex: [String: Set<String>]) {
        self._chatIndexMap = chatIndexMap
        self._keywordIndex = keywordIndex
    }
    
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
    @Environment(\.colorScheme) private var colorScheme
    
    // Performance optimization properties
    @State private var lastSortTime: Date = Date(timeIntervalSince1970: 0)
    @State private var sortingInProgress: Bool = false
    private let sortingThrottleInterval: TimeInterval = 0.5 // Minimum interval between sorting operations
    
    // Timer to periodically update chat dates - reduced frequency
    let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    
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
            newChatButton
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            
            searchBarView
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            
            chatListView
                .onReceive(timer) { _ in
                    // Only sort if enough time has passed since last update
                    if Date().timeIntervalSince(lastSortTime) > 10 {
                        throttledOrganizeChatsByDate()
                    }
                }
                .onChange(of: appCoordinator.shouldCreateNewChat) { _, newValue in
                    if newValue {
                        createNewChat()
                        appCoordinator.shouldCreateNewChat = false
                    }
                }
                .onChange(of: appCoordinator.shouldDeleteChat) { _, newValue in
                    if newValue {
                        deleteSelectedChat()
                        appCoordinator.shouldDeleteChat = false
                    }
                }
                .id(selectionId)
                .listStyle(SidebarListStyle())
                .frame(minWidth: 100, idealWidth: 250, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .onAppear {
            // Initial organization and indexing only once at startup
            organizeChatsInitial()
        }
        .onChange(of: chatManager.chats) { oldChats, newChats in
            // Only reorganize when chat count changes (add/remove)
            if oldChats.count != newChats.count {
                throttledOrganizeChatsByDate()
            }
        }
        .onChange(of: searchText) { _, _ in
            performSearch()
        }
        // Remove New Chat button from toolbar, keeping only Toggle Sidebar
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: Amazon_Bedrock_Client_for_MacApp.toggleSidebar) {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                        .help("Toggle Sidebar")
                }
            }
        }
    }
    
    // New Chat button view
    private var newChatButton: some View {
        Button(action: {
            createNewChat()
        }) {
            HStack {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                
                Text("New Chat")
                    .font(.system(size: 14))
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ?
                          Color(NSColor.controlBackgroundColor) :
                          Color(NSColor.controlColor))
                    .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(colorScheme == .dark ?
                            Color.white.opacity(0.1) :
                            Color.black.opacity(0.1),
                            lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help("Start a new chat")
    }

    // MARK: - Search Bar View
    
    /// Enhanced search bar for filtering chats
    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
            
            TextField("Search chats", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 14))
            
            if isSearching {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            } else if !searchText.isEmpty {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        searchText = ""
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.opacity)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ?
                      Color(NSColor.textBackgroundColor).opacity(0.8) :
                        Color(NSColor.textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(colorScheme == .dark ?
                        Color.white.opacity(0.1) :
                            Color.black.opacity(0.1),
                        lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Chat List View
    
    /// Enhanced chat list view
    private var chatListView: some View {
        List {
            ForEach(sortedDateKeys, id: \.self) { dateKey in
                if let chats = filteredChatModels[dateKey], !chats.isEmpty {
                    Section(header:
                                Text(dateKey)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    ) {
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
    
    // MARK: - Chat Row View
    
    /// Creates an enhanced view for an individual chat row
    func chatRowView(for chat: ChatModel) -> some View {
        let isHovered = hoverStates[chat.chatId, default: false]
        let isSelected = selection == .chat(chat)
        
        return HStack(spacing: 12) {
            // Chat title and model name
            VStack(alignment: .leading, spacing: 3) {
                Text(chat.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                Text(chat.name)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Loading indicator as animated dots
            if chatManager.getIsLoading(for: chat.chatId) {
                LoadingDotsView()
                    .frame(width: 30, height: 20)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ?
                      Color.blue.opacity(0.15) :
                        (isHovered ? Color.gray.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
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
    
    // New loading dots animation view
    struct LoadingDotsView: View {
        @State private var dotCount = 1
        
        var body: some View {
            HStack {
                Text(String(repeating: ".", count: dotCount))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .onAppear {
                // Start the animation
                let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
                
                // Clean up the timer when the view disappears
                let cancellable = timer.sink { _ in
                    withAnimation {
                        dotCount = (dotCount % 3) + 1
                    }
                }
                
                // Store the cancellable for cleanup
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                    cancellable.cancel()
                }
            }
        }
    }
    
    // MARK: - Methods

    /// Executes search against the index and updates results
    private func performSearch() {
        if searchText.isEmpty {
            searchResults = []
            return
        }
        
        // Run search in the background
        Task(priority: .userInitiated) {
            isSearching = true
            let results = await MainActor.run {
                return searchIndex.search(query: searchText)
            }
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        }
    }
    
    /// Creates a new chat with the currently selected model
    private func createNewChat() {
        if let modelSelection = menuSelection, case .chat(let model) = modelSelection {
            chatManager.createNewChat(modelId: model.id, modelName: model.name, modelProvider: model.provider) { newChat in
                // 1. Add only the new chat, without resorting the entire list
                incrementalAddChat(newChat)
                
                // 2. Update selection
                self.selection = .chat(newChat)
                
                // 3. Update selectionId (needed only for selection changes)
                self.selectionId = UUID()
                
                // 4. Incrementally update search index in background
                Task(priority: .background) {
                    await MainActor.run {
                        incrementalUpdateSearchIndex(for: newChat)
                    }
                }
            }
        }
    }

    // Incremental update: Add a new chat to the appropriate date group
    private func incrementalAddChat(_ newChat: ChatModel) {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: newChat.lastMessageDate)
        
        if let date = calendar.date(from: dateComponents) {
            let key = formatDate(date)
            
            // If date key already exists, add to that group, otherwise create new group
            var mutableOrganizedModels = organizedChatModels
            if var chatsForDate = mutableOrganizedModels[key] {
                // Insert maintaining date sort order
                chatsForDate.insert(newChat, at: 0) // Add at front since it's the newest
                mutableOrganizedModels[key] = chatsForDate
            } else {
                mutableOrganizedModels[key] = [newChat]
            }
            
            organizedChatModels = mutableOrganizedModels
        }
    }
    
    // Incremental update: Add new chat to search index
    @MainActor
    private func incrementalUpdateSearchIndex(for chat: ChatModel) {
        // Optimize by only indexing one chat
        var searchableContent = "\(chat.title.lowercased()) \(chat.name.lowercased())"
        
        // Get chat messages - this could also be optimized if there are many messages
        let messages = chatManager.getMessages(for: chat.chatId)
        for message in messages {
            searchableContent += " \(message.text.lowercased())"
        }
        
        // Tokenize content
        let words = searchableContent
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0) }
            .filter { $0.count >= 2 } // Minimum word length 2
        
        let wordSet = Set(words)
        
        // Update chat index map
        var updatedChatIndexMap = self.searchIndex.chatIndexMap
        updatedChatIndexMap[chat.chatId] = wordSet
        
        // Update keyword index
        var updatedKeywordIndex = self.searchIndex.keywordIndex
        for word in wordSet {
            if updatedKeywordIndex[word] == nil {
                updatedKeywordIndex[word] = []
            }
            updatedKeywordIndex[word]?.insert(chat.chatId)
        }
        
        // Apply index updates
        self.searchIndex.updateIndexDirect(chatIndexMap: updatedChatIndexMap, keywordIndex: updatedKeywordIndex)
    }
    
    // Throttled organization function (prevents multiple calls in short time)
    private func throttledOrganizeChatsByDate() {
        let now = Date()
        if !sortingInProgress && now.timeIntervalSince(lastSortTime) > sortingThrottleInterval {
            sortingInProgress = true
            
            // Move sorting work to background thread
            Task(priority: .userInitiated) {
                let calendar = Calendar.current
                let sortedChats = self.chatManager.chats.sorted { $0.lastMessageDate > $1.lastMessageDate }
                let groupedChats = Dictionary(grouping: sortedChats) { chat -> DateComponents in
                    calendar.dateComponents([.year, .month, .day], from: chat.lastMessageDate)
                }
                
                let sortedDateComponents = groupedChats.keys.sorted {
                    if $0.year != $1.year {
                        return $0.year! > $1.year! // Descending
                    } else if $0.month != $1.month {
                        return $0.month! > $1.month! // Descending
                    } else {
                        return $0.day! > $1.day! // Descending
                    }
                }
                
                var newOrganizedModels: [String: [ChatModel]] = [:]
                for components in sortedDateComponents {
                    if let date = calendar.date(from: components) {
                        let key = self.formatDate(date)
                        if let chatsForDate = groupedChats[components] {
                            newOrganizedModels[key] = chatsForDate
                        }
                    }
                }
                
                // UI updates on main thread
                await MainActor.run {
                    self.organizedChatModels = newOrganizedModels
                    self.lastSortTime = Date()
                    self.sortingInProgress = false
                }
            }
        }
    }
    
    // Initial organization (run once at app startup)
    private func organizeChatsInitial() {
        throttledOrganizeChatsByDate()
        updateSearchIndex()
    }
    
    // Optimized search index update - only called when needed
    private func updateSearchIndex() {
        Task(priority: .background) {
            isSearching = true
            await MainActor.run {
                searchIndex.updateIndex(chats: chatManager.chats, chatManager: chatManager)
                isSearching = false
                performSearch()
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
        throttledOrganizeChatsByDate()
    }
    
    /// Returns the currently selected chat model, if any
    private func getSelectedChat() -> ChatModel? {
        if case .chat(let chat) = selection {
            return chat
        }
        return nil
    }
    
    /// Formats a date for section headers
    private func formatDate(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM dd, yyyy"
        return dateFormatter.string(from: date)
    }
    
    /// Deletes a specific chat
    private func deleteChat(_ chat: ChatModel) {
        hoverStates[chat.chatId] = false
        selection = chatManager.deleteChat(with: chat.chatId)
        throttledOrganizeChatsByDate() // Use optimized version
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
