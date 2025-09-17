//
//  SidebarView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import AppKit

// MARK: - Chat Search Index

/// Optimized search index for O(log n) chat content searching with relevance scoring
@MainActor
class ChatSearchIndex: ObservableObject {
    static let shared = ChatSearchIndex()
    
    // Map of chat IDs to indexed chat content tokens
    var chatIndexMap: [String: Set<String>] = [:]
    private var _chatIndexMap: [String: Set<String>] = [:]

    // Inverted index: keyword -> chat IDs that contain it
    var keywordIndex: [String: Set<String>] = [:]
    private var _keywordIndex: [String: Set<String>] = [:]
    
    // Chat metadata for relevance scoring
    var chatMetadata: [String: ChatMetadata] = [:]
    
    // Track indexed chats to avoid reindexing
    var indexedChatIds: Set<String> = []
    var lastIndexUpdate: Date = Date.distantPast
    
    // Minimum word length for indexing (1 to catch single character searches like "응")
    private let minWordLength = 1
    
    private init() {} // Singleton pattern
    
    struct ChatMetadata {
        let title: String
        let modelName: String
        let messageCount: Int
        let lastMessageDate: Date
        let totalTextLength: Int
    }

    func updateIndexDirect(chatIndexMap: [String: Set<String>], keywordIndex: [String: Set<String>]) {
        self.chatIndexMap = chatIndexMap
        self.keywordIndex = keywordIndex
    }
    
    /// Updates the search index with current chats and their content - optimized to avoid unnecessary reindexing
    func updateIndex(chats: [ChatModel], chatManager: ChatManager) {
        let currentChatIds = Set(chats.map { $0.chatId })
        
        // Force update if we have no indexed chats or if chats have changed significantly
        let needsUpdate = indexedChatIds.isEmpty || 
                         currentChatIds != indexedChatIds || 
                         Date().timeIntervalSince(lastIndexUpdate) > 300 // 5 minutes
        
        if !needsUpdate {
            return // Skip reindexing if nothing changed
        }
        
        // For simplicity and reliability, do a full reindex when there are changes
        var newChatIndexMap: [String: Set<String>] = [:]
        var newKeywordIndex: [String: Set<String>] = [:]
        var newChatMetadata: [String: ChatMetadata] = [:]
        
        // Index all current chats
        for chat in chats {
            indexSingleChat(chat, chatManager: chatManager, 
                          chatIndexMap: &newChatIndexMap, 
                          keywordIndex: &newKeywordIndex, 
                          chatMetadata: &newChatMetadata)
        }
        
        // Update class properties
        chatIndexMap = newChatIndexMap
        keywordIndex = newKeywordIndex
        chatMetadata = newChatMetadata
        indexedChatIds = currentChatIds
        lastIndexUpdate = Date()
    }
    
    /// Index a single chat - extracted for reuse
    private func indexSingleChat(_ chat: ChatModel, 
                               chatManager: ChatManager,
                               chatIndexMap: inout [String: Set<String>],
                               keywordIndex: inout [String: Set<String>],
                               chatMetadata: inout [String: ChatMetadata]) {
        // Get chat messages
        let messages = chatManager.getMessages(for: chat.chatId)
        
        // Index chat title and model name with higher weight
        var searchableContent = "\(chat.title.lowercased()) \(chat.name.lowercased())"
        var totalTextLength = searchableContent.count
        
        // Add message content
        for message in messages {
            let messageText = message.text.lowercased()
            searchableContent += " \(messageText)"
            totalTextLength += messageText.count
        }
        
        // Tokenize content into words for faster searching
        let words = searchableContent
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0) }
            .filter { $0.count >= minWordLength }
        
        // Store tokenized content
        let wordSet = Set(words)
        chatIndexMap[chat.chatId] = wordSet
        
        // Store metadata for relevance scoring
        chatMetadata[chat.chatId] = ChatMetadata(
            title: chat.title,
            modelName: chat.name,
            messageCount: messages.count,
            lastMessageDate: chat.lastMessageDate,
            totalTextLength: totalTextLength
        )
        
        // Update inverted index
        for word in wordSet {
            if keywordIndex[word] == nil {
                keywordIndex[word] = []
            }
            keywordIndex[word]?.insert(chat.chatId)
        }
    }
    
    /// Performs optimized search with relevance scoring
    func search(query: String) -> [String] {
        if query.isEmpty {
            // Return all chats sorted by last message date
            return chatMetadata.keys.sorted { chatId1, chatId2 in
                let date1 = chatMetadata[chatId1]?.lastMessageDate ?? Date.distantPast
                let date2 = chatMetadata[chatId2]?.lastMessageDate ?? Date.distantPast
                return date1 > date2
            }
        }
        
        // Normalize query for better matching
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Calculate relevance scores for each chat
        var chatScores: [String: Double] = [:]
        
        for (chatId, words) in chatIndexMap {
            guard let metadata = chatMetadata[chatId] else { continue }
            
            var score = 0.0
            
            // Check title match (highest priority)
            let titleLower = metadata.title.lowercased()
            if titleLower.contains(normalizedQuery) {
                score += 100.0
            }
            
            // Check model name match
            let modelLower = metadata.modelName.lowercased()
            if modelLower.contains(normalizedQuery) {
                score += 50.0
            }
            
            // Check word matches in content
            for word in words {
                if word.contains(normalizedQuery) {
                    if word == normalizedQuery {
                        score += 20.0 // Exact match
                    } else if word.hasPrefix(normalizedQuery) {
                        score += 10.0 // Prefix match
                    } else {
                        score += 5.0 // Contains match
                    }
                }
            }
            
            // Add recency bonus if there's any match
            if score > 0 {
                let daysSinceLastMessage = Date().timeIntervalSince(metadata.lastMessageDate) / (24 * 60 * 60)
                let recencyBonus = max(0, 5.0 - daysSinceLastMessage * 0.1)
                score += recencyBonus
                
                chatScores[chatId] = score
            }
        }
        
        // Sort by relevance score (highest first)
        return chatScores.keys.sorted { chatId1, chatId2 in
            let score1 = chatScores[chatId1] ?? 0
            let score2 = chatScores[chatId2] ?? 0
            return score1 > score2
        }
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
    @State private var searchIndex = ChatSearchIndex.shared
    @State private var searchResults: [String] = []
    @State private var isSearching: Bool = false
    @State private var searchDebounceTimer: Timer?
    @State private var renamingChatId: String? = nil
    @State private var renameText: String = ""
    @FocusState private var renamingTextfieldFocused: Bool
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
        // Create a mapping of display keys to actual dates for proper sorting
        var keyToDateMap: [String: Date] = [:]
        
        for key in organizedChatModels.keys {
            // Try to parse the key back to a date
            if let date = dateFormatter.date(from: key) {
                keyToDateMap[key] = date
            } else {
                // Handle special cases like "Today" and "Yesterday"
                let calendar = Calendar.current
                if key == "Today" {
                    keyToDateMap[key] = calendar.startOfDay(for: Date())
                } else if key == "Yesterday" {
                    if let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) {
                        keyToDateMap[key] = calendar.startOfDay(for: yesterday)
                    }
                }
            }
        }
        
        // Sort by actual dates (most recent first)
        return keyToDateMap.keys.sorted { key1, key2 in
            let date1 = keyToDateMap[key1] ?? Date.distantPast
            let date2 = keyToDateMap[key2] ?? Date.distantPast
            return date1 > date2
        }
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
            // Initial organization only - search index will be built lazily when first search is performed
            organizeChatsInitial()
        }
        .onChange(of: chatManager.chats) { oldChats, newChats in
            // Only reorganize when chat count changes (add/remove)
            if oldChats.count != newChats.count {
                throttledOrganizeChatsByDate()
                // Update search index only when chats actually change
                updateSearchIndexIfNeeded()
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
                                    Button("Rename Chat", action: {
                                        startRenaming(chat)
                                    })
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
        let isRenaming = renamingChatId == chat.chatId
        
        return HStack(spacing: 12) {
            // Chat title and model name
            VStack(alignment: .leading, spacing: 3) {
                if isRenaming {
                    TextField("Chat title", text: $renameText)
                        .font(.system(size: 13, weight: .medium))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($renamingTextfieldFocused)
                        .onSubmit {
                            finishRenaming(chat)
                        }
                        .onExitCommand {
                            cancelRenaming()
                        }
                        .onChange(of: renamingTextfieldFocused) { _, newValue in
                            if (!newValue) {
                                finishRenaming(chat)
                            }
                        }
                } else {
                    Text(chat.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                
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
            if !isRenaming {
                withAnimation(.easeInOut(duration: 0.2)) {
                    hoverStates[chat.chatId] = hover
                }
                if hover {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
        }
        .onTapGesture {
            if !isRenaming {
                selection = .chat(chat)
            }
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

    /// Executes search against the index and updates results with debouncing
    private func performSearch() {
        // Cancel previous timer
        searchDebounceTimer?.invalidate()
        
        // Update search index lazily only when search is actually used
        if searchText.isEmpty {
            searchResults = []
            return
        }
        
        // Ensure search index is up to date before searching (lazy initialization)
        if searchIndex.indexedChatIds.isEmpty && !chatManager.chats.isEmpty {
            updateSearchIndexIfNeeded()
        }
        
        // Set new timer for debounced search (faster than chat search - 0.2s)
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
            executeSearch()
        }
    }
    
    private func executeSearch() {
        if searchText.isEmpty {
            searchResults = []
            return
        }
        
        // Run search in the background with higher priority for sidebar
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
                
                // 4. Mark that search index needs update for this new chat
                Task(priority: .background) {
                    await MainActor.run {
                        // Reset indexed chat IDs to force reindex when search is used
                        searchIndex.indexedChatIds.remove(newChat.chatId)
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
    
    // Incremental update: Add new chat to search index - removed as it's now handled by lazy loading
    // The search index will be updated when actually needed during search
    
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
        // Don't update search index here - it will be updated lazily when needed
    }
    
    // Optimized search index update - only called when needed and chats have changed
    private func updateSearchIndexIfNeeded() {
        // Only update if we have chats and index is empty or outdated
        guard !chatManager.chats.isEmpty else { return }
        
        Task(priority: .background) {
            // Run indexing in background thread to avoid blocking UI
            await Task.detached(priority: .background) {
                await MainActor.run {
                    searchIndex.updateIndex(chats: chatManager.chats, chatManager: chatManager)
                }
            }.value
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
        let calendar = Calendar.current
        
        // Check if date is today
        if calendar.isDateInToday(date) {
            return "Today"
        }
        
        // Check if date is yesterday
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        
        // For all other dates, use the standard format
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
    
    /// Starts renaming a chat
    private func startRenaming(_ chat: ChatModel) {
        renamingChatId = chat.chatId
        renameText = chat.title
        renamingTextfieldFocused = true
    }
    
    /// Finishes renaming a chat and saves the new title
    private func finishRenaming(_ chat: ChatModel) {
        let trimmedTitle = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Only update if the title actually changed and is not empty
        if !trimmedTitle.isEmpty && trimmedTitle != chat.title {
            chatManager.updateChatTitle(for: chat.chatId, title: trimmedTitle, isManualRename: true)
        }
        
        // Reset renaming state
        renamingChatId = nil
        renameText = ""
        renamingTextfieldFocused = false
    }
    
    /// Cancels renaming a chat without saving changes
    private func cancelRenaming() {
        renamingChatId = nil
        renameText = ""
        renamingTextfieldFocused = false
    }
}
