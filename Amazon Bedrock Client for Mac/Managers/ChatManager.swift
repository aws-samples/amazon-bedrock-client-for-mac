//
//  ChatManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/09.
//

import Combine
import SwiftUI
import CoreData
import Logging

// MARK: - Message Attachments

struct MessageAttachments {
    var imageBase64Strings: [String]?
    var documentBase64Strings: [String]?
    var documentFormats: [String]?
    var documentNames: [String]?
}

// MARK: - Unified Message Structure
struct Message: Codable, Identifiable {
    let id: UUID
    var text: String
    var role: Role
    let timestamp: Date
    let isError: Bool
    
    // Separate fields for different content types
    var thinking: String?
    var thinkingSummary: String?  // Summary of thinking process
    var thinkingSignature: String?
    var imageBase64Strings: [String]?
    var documentBase64Strings: [String]?
    var documentFormats: [String]?
    var documentNames: [String]?
    var pastedTexts: [PastedTextInfo]?  // Pasted text attachments
    
    // Video generation
    var videoUrl: URL?  // Local URL for generated video
    var videoS3Uri: String?  // S3 URI for video reference
    
    // Tool use is a separate concern - not mixed with message text
    var toolUse: ToolUse?
    
    enum Role: String, Codable {
        case user
        case assistant
    }
    
    struct ToolUse: Codable {
        let toolId: String
        let toolName: String
        let inputs: JSONValue
        var result: String?
        var resultTimestamp: Date?
    }
}

// MARK: - Unified Conversation History

/// Unified conversation history structure
struct ConversationHistory: Codable {
    let chatId: String
    let modelId: String
    var messages: [Message]
    var lastUpdated: Date
    var systemPrompt: String?
    
    init(chatId: String, modelId: String, messages: [Message] = [], systemPrompt: String? = nil) {
        self.chatId = chatId
        self.modelId = modelId
        self.messages = messages
        self.lastUpdated = Date()
        self.systemPrompt = systemPrompt
    }
    
    // Improved implementation of addMessage
    mutating func addMessage(_ message: Message) {
        messages.append(message)
        lastUpdated = Date()
    }
    
    // Improved implementation of updateMessage
    mutating func updateMessage(id: UUID,
                              newText: String? = nil,
                              thinking: String? = nil,
                              thinkingSignature: String? = nil,
                              toolResult: String? = nil) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            // Update specific fields only if provided
            if let newText = newText {
                messages[index].text = newText
            }
            
            if let thinking = thinking {
                messages[index].thinking = thinking
            }
            
            if let thinkingSignature = thinkingSignature {
                messages[index].thinkingSignature = thinkingSignature
            }
            
            if let toolResult = toolResult, messages[index].toolUse != nil {
                messages[index].toolUse?.result = toolResult
            }
            
            lastUpdated = Date()
        }
    }
}

@MainActor
class ChatManager: ObservableObject {
    @Published var chats: [ChatModel] = []
    @Published var chatIsLoading: [String: Bool] = [:]
    private var temporaryChats: [String: ChatModel] = [:] // Chats not yet saved to CoreData
    
    var hasChats: Bool {
        return !chats.isEmpty
    }
    
    static let shared = ChatManager()
    @ObservedObject private var settingManager = SettingManager.shared
    
    private let coreDataStack: CoreDataStack
    private let fileManager = FileManager.default
    
    // App version tracking for migrations
    private let currentAppVersion = "2.0.0"
    private let userDefaults = UserDefaults.standard
    private let lastVersionKey = "LastRunAppVersion"
    
    private var logger = Logger(label: "ChatManager")
    
    private init() {
        self.coreDataStack = CoreDataStack(modelName: "ChatModel")
        self.loadChats()
        self.createDirectories()
        
        // Check if we need to run migrations
        checkAndRunMigrations()
        
        // Clean up empty chats on startup
        cleanupEmptyChats()
    }
    
    // MARK: - Migration
    
    private func checkAndRunMigrations() {
        let lastVersion = userDefaults.string(forKey: lastVersionKey) ?? "1.0.0"
        
        if lastVersion.compare(currentAppVersion, options: .numeric) == .orderedAscending {
            logger.info("Running migrations from version \(lastVersion) to \(currentAppVersion)")
            migrateAllHistoriesToUnifiedFormat()
            
            userDefaults.set(currentAppVersion, forKey: lastVersionKey)
        }
    }
    
    private func migrateAllHistoriesToUnifiedFormat() {
        logger.info("Starting history migration to unified format...")
        
        for chat in chats {
            migrateHistoryForChat(chatId: chat.chatId, modelId: chat.id)
        }
        
        logger.info("History migration completed")
    }
    
    private func migrateHistoryForChat(chatId: String, modelId: String, force: Bool = false) {
        logger.info("Migrating history for chat: \(chatId)")
        
        if !force && fileExists(at: getConversationHistoryFileURL(chatId: chatId)) {
            logger.info("Unified history already exists for chat \(chatId), skipping migration")
            return
        }
        
        var conversationHistory = ConversationHistory(
            chatId: chatId,
            modelId: modelId
        )
        
        let systemPrompt = SettingManager.shared.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !systemPrompt.isEmpty {
            conversationHistory.systemPrompt = systemPrompt
        }
        
        let messages = getMessages(for: chatId)
        if messages.isEmpty {
            logger.warning("No legacy messages found for chat \(chatId)")
        }
        
        for message in messages {
            let role = message.user == "User" ? Message.Role.user : Message.Role.assistant
            
            var toolUse: Message.ToolUse? = nil
            if let tool = message.toolUse {
                toolUse = Message.ToolUse(
                    toolId: tool.id,
                    toolName: tool.name,
                    inputs: tool.input,
                    result: message.toolResult,
                    resultTimestamp: message.toolResult != nil ? Date() : nil
                )
            }
            
            let unifiedMessage = Message(
                id: message.id,
                text: message.text,
                role: role,
                timestamp: message.sentTime,
                isError: message.isError,
                thinking: message.thinking,
                thinkingSignature: message.signature,
                imageBase64Strings: message.imageBase64Strings,
                documentBase64Strings: message.documentBase64Strings,
                documentFormats: message.documentFormats,
                documentNames: message.documentNames,
                toolUse: toolUse
            )
            
            conversationHistory.addMessage(unifiedMessage)
        }
        
        saveConversationHistory(conversationHistory, for: chatId)
        logger.info("Successfully migrated history for chat \(chatId) with \(messages.count) messages")
    }

    // MARK: - Chat Management
    
    func createNewChat(modelId: String, modelName: String, modelProvider: String, completion: @escaping (ChatModel) -> Void) {
        let chatModel = ChatModel(
            id: modelId,
            chatId: UUID().uuidString,
            name: modelName,
            title: "New Chat",
            description: modelId,
            provider: modelProvider,
            lastMessageDate: Date()
        )
        
        let chatId = chatModel.chatId
        let modelIdValue = chatModel.id
        
        // Immediately add to UI
        self.chats.append(chatModel)
        self.chatIsLoading[chatId] = false
        self.objectWillChange.send()
        
        // Create empty conversation history
        let history = ConversationHistory(chatId: chatId, modelId: modelIdValue)
        self.saveConversationHistory(history, for: chatId)
        
        // Call completion immediately
        completion(chatModel)
        
        // Save to CoreData in background
        let context = coreDataStack.viewContext
        Task {
            await context.perform { [weak self] in
                guard let self = self else { return }
                
                let newChat = NSEntityDescription.insertNewObject(forEntityName: "ChatEntity", into: context) as! ChatEntity
                newChat.id = chatModel.id
                newChat.chatId = chatModel.chatId
                newChat.name = chatModel.name
                newChat.title = chatModel.title
                newChat.chatDescription = chatModel.description
                newChat.provider = chatModel.provider
                newChat.lastMessageDate = chatModel.lastMessageDate
                newChat.isManuallyRenamed = chatModel.isManuallyRenamed
                
                do {
                    try context.save()
                    Task { @MainActor [weak self] in
                        self?.logger.info("Saved new chat to CoreData: \(chatId)")
                    }
                } catch {
                    Task { @MainActor [weak self] in
                        self?.logger.error("Failed to save new chat to CoreData: \(error)")
                        // Mark as temporary chat if CoreData save fails
                        self?.temporaryChats[chatId] = chatModel
                    }
                }
            }
        }
    }
    
    // MARK: - Empty Chat Cleanup
    
    func cleanupEmptyChats() {
        logger.info("Cleaning up empty chats...")
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            let context = self.coreDataStack.viewContext
            let fetchRequest: NSFetchRequest<ChatEntity> = ChatEntity.fetchRequest()
            
            do {
                let allChats = try context.fetch(fetchRequest)
                var chatsToDelete: [ChatEntity] = []
                
                for chat in allChats {
                    guard let chatId = chat.chatId else { continue }
                    
                    // Skip cleanup for temporary chats (not yet saved to CoreData)
                    if self.temporaryChats[chatId] != nil {
                        continue
                    }
                    
                    // Only delete chats that are older than 5 minutes and have no messages
                    let chatAge = Date().timeIntervalSince(chat.lastMessageDate ?? Date())
                    if chatAge < 300 { // 5 minutes
                        continue
                    }
                    
                    // Check if chat has any messages
                    if let history = self.getConversationHistory(for: chatId) {
                        if history.messages.isEmpty {
                            chatsToDelete.append(chat)
                            self.logger.info("Marking old empty chat for deletion: \(chatId)")
                        }
                    } else {
                        // No history file means empty chat, but only delete if old enough
                        chatsToDelete.append(chat)
                        self.logger.info("Marking old chat with no history for deletion: \(chatId)")
                    }
                }
                
                // Delete empty chats
                for chat in chatsToDelete {
                    context.delete(chat)
                    
                    // Also clean up any associated files
                    if let chatId = chat.chatId {
                        self.cleanupChatFiles(chatId: chatId)
                    }
                }
                
                if !chatsToDelete.isEmpty {
                    try context.save()
                    self.logger.info("Deleted \(chatsToDelete.count) empty chats")
                    self.loadChats()
                }
                
            } catch {
                self.logger.error("Failed to cleanup empty chats: \(error)")
            }
        }
    }
    
    func cleanupTemporaryChats() {
        logger.info("Cleaning up \(temporaryChats.count) temporary chats")
        
        // Remove temporary chats from UI
        let tempChatIds = Set(temporaryChats.keys)
        DispatchQueue.main.async {
            self.chats.removeAll { tempChatIds.contains($0.chatId) }
            self.temporaryChats.removeAll()
            self.objectWillChange.send()
        }
        
        // Clean up any conversation history files for temporary chats
        for chatId in tempChatIds {
            cleanupChatFiles(chatId: chatId)
        }
    }
    
    private func cleanupChatFiles(chatId: String) {
        let filesToDelete = [
            getConversationHistoryFileURL(chatId: chatId)
        ]
        
        for fileURL in filesToDelete {
            if fileExists(at: fileURL) {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    logger.info("Deleted file: \(fileURL.lastPathComponent)")
                } catch {
                    logger.error("Failed to delete file \(fileURL.lastPathComponent): \(error)")
                }
            }
        }
    }
    
    // Save temporary chat to CoreData when first message is added
    private func saveTemporaryChatToCoreData(_ chatModel: ChatModel) {
        let chatId = chatModel.chatId
        
        Task { @MainActor [weak self, chatModel] in
            guard let self = self else { return }
            guard temporaryChats[chatId] != nil else { return }
            
            let context = coreDataStack.viewContext
            await context.perform {
                let newChat = NSEntityDescription.insertNewObject(forEntityName: "ChatEntity", into: context) as! ChatEntity
                newChat.id = chatModel.id
                newChat.chatId = chatModel.chatId
                newChat.name = chatModel.name
                newChat.title = chatModel.title
                newChat.chatDescription = chatModel.description
                newChat.provider = chatModel.provider
                newChat.lastMessageDate = chatModel.lastMessageDate
                newChat.isManuallyRenamed = chatModel.isManuallyRenamed
                
                do {
                    try context.save()
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        // Remove from temporary chats since it's now saved
                        self.temporaryChats.removeValue(forKey: chatId)
                        self.logger.info("Saved temporary chat to CoreData: \(chatId)")
                    }
                } catch {
                    Task { @MainActor [weak self] in
                        self?.logger.error("Failed to save temporary chat to CoreData: \(error)")
                    }
                }
            }
        }
    }
    
    func updateChatTitle(for chatId: String, title: String, isManualRename: Bool = false) {
        let context = coreDataStack.viewContext
        let fetchRequest: NSFetchRequest<ChatEntity> = ChatEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "chatId == %@", chatId)
        
        do {
            let results = try context.fetch(fetchRequest)
            if let chatEntity = results.first {
                chatEntity.title = title
                if isManualRename {
                    chatEntity.isManuallyRenamed = true
                }
                coreDataStack.saveContext()
                
                DispatchQueue.main.async {
                    if let index = self.chats.firstIndex(where: { $0.chatId == chatId }) {
                        self.chats[index].title = title
                        if isManualRename {
                            self.chats[index].isManuallyRenamed = true
                        }
                        self.objectWillChange.send()
                    }
                }
            }
        } catch {
            logger.info("Failed to update chat title: \(error)")
        }
    }
    
    func deleteChat(with chatId: String) -> SidebarSelection {
        // Remove from CoreData
        let context = coreDataStack.viewContext
        let fetchRequest: NSFetchRequest<ChatEntity> = ChatEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "chatId == %@", chatId)
        
        do {
            let results = try context.fetch(fetchRequest)
            if let chatEntity = results.first {
                context.delete(chatEntity)
                try context.save()
            }
        } catch {
            logger.info("Failed to delete chat from CoreData: \(error)")
        }
        
        // Remove from in-memory array
        if let index = chats.firstIndex(where: { $0.chatId == chatId }) {
            chats.remove(at: index)
            objectWillChange.send()
        }
        
        // Delete all associated files
        deleteAllFiles(for: chatId)
        
        // Return the most recent chat or a new chat
        if let mostRecentChat = chats.sorted(by: { $0.lastMessageDate > $1.lastMessageDate }).first {
            return .chat(mostRecentChat)
        } else {
            return .newChat
        }
    }
    
    func clearAllChats() {
        let context = coreDataStack.viewContext
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = ChatEntity.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        
        do {
            try context.execute(deleteRequest)
            coreDataStack.saveContext()
            
            DispatchQueue.main.async {
                self.chats.removeAll()
                self.chatIsLoading.removeAll()
                self.objectWillChange.send()
            }
            
            clearAllFiles()
        } catch {
            logger.info("Failed to clear all chats: \(error)")
        }
    }
    
    func getChatModel(for chatId: String) -> ChatModel? {
        return chats.first { $0.chatId == chatId }
    }
    
    func getIsLoading(for chatId: String) -> Bool {
        return chatIsLoading[chatId] ?? false
    }
    
    func setIsLoading(_ isLoading: Bool, for chatId: String) {
        DispatchQueue.main.async {
            self.chatIsLoading[chatId] = isLoading
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Message Management
    
    func addUserMessage(text: String, chatId: String, attachments: MessageAttachments? = nil) {
        let message = Message(
            id: UUID(),
            text: text,
            role: .user,
            timestamp: Date(),
            isError: false,
            thinking: nil,
            thinkingSignature: nil,
            imageBase64Strings: attachments?.imageBase64Strings,
            documentBase64Strings: attachments?.documentBase64Strings,
            documentFormats: attachments?.documentFormats,
            documentNames: attachments?.documentNames
        )
        
        addMessage(message, to: chatId)
    }
    
    func addAssistantMessage(text: String, chatId: String, thinking: String? = nil) {
        let message = Message(
            id: UUID(),
            text: text,
            role: .assistant,
            timestamp: Date(),
            isError: false,
            thinking: thinking
        )
        
        addMessage(message, to: chatId)
    }
    
    func addAssistantErrorMessage(error: String, chatId: String) {
        let message = Message(
            id: UUID(),
            text: error,
            role: .assistant,
            timestamp: Date(),
            isError: true
        )
        
        addMessage(message, to: chatId)
    }
    
    // The main add message function that handles conversation history updates
    func addMessage(_ message: Message, to chatId: String) {
        // If this is a temporary chat, save it to CoreData now that we have a real message
        if let tempChat = temporaryChats[chatId] {
            saveTemporaryChatToCoreData(tempChat)
        }
        
        var history = getConversationHistory(for: chatId) ?? createNewConversationHistory(for: chatId)
        
        history.addMessage(message)
        saveConversationHistory(history, for: chatId)
        
        // Update UI state
        DispatchQueue.main.async {
            if let index = self.chats.firstIndex(where: { $0.chatId == chatId }) {
                self.chats[index].lastMessageDate = Date()
                self.objectWillChange.send()
            }
        }
    }

    // MARK: - Tool Use Management
    
    func addToolUse(for chatId: String, messageId: UUID, toolName: String, toolId: String, inputs: JSONValue) {
        if var history = getConversationHistory(for: chatId) {
            // Find message and add tool use
            if let index = history.messages.firstIndex(where: { $0.id == messageId }) {
                // Create tool usage structure
                let toolUse = Message.ToolUse(
                    toolId: toolId,
                    toolName: toolName,
                    inputs: inputs
                )
                
                // Update message with tool usage
                history.messages[index].toolUse = toolUse
                
                // Save updated history
                saveConversationHistory(history, for: chatId)
            }
        }
    }
    
    func updateToolResult(for chatId: String, messageId: UUID, result: String) {
        if var history = getConversationHistory(for: chatId) {
            history.updateMessage(id: messageId, toolResult: result)
            saveConversationHistory(history, for: chatId)
        }
    }

    // MARK: - Message Update Methods
    
    func updateMessageText(for chatId: String, messageId: UUID, newText: String) {
        if var history = getConversationHistory(for: chatId) {
            history.updateMessage(id: messageId, newText: newText)
            saveConversationHistory(history, for: chatId)
            
            DispatchQueue.main.async {
                if let chatIndex = self.chats.firstIndex(where: { $0.chatId == chatId }) {
                    self.chats[chatIndex].lastMessageDate = Date()
                    self.objectWillChange.send()
                }
            }
        } else {
            // Fall back to legacy method
            var messages = loadMessagesFromFile(chatId: chatId)
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                var message = messages[index]
                message.text = newText
                messages[index] = message
                
                saveMessagesToFile(chatId: chatId, messages: messages)
                
                DispatchQueue.main.async {
                    if let chatIndex = self.chats.firstIndex(where: { $0.chatId == chatId }) {
                        self.chats[chatIndex].lastMessageDate = Date()
                        self.objectWillChange.send()
                    }
                }
            }
        }
    }
    
    func updateMessageWithToolInfo(for chatId: String, messageId: UUID, newText: String, toolInfo: ToolInfo, toolResult: String? = nil, thinking: String? = nil, thinkingSignature: String? = nil) {
        if var history = getConversationHistory(for: chatId) {
            if let index = history.messages.firstIndex(where: { $0.id == messageId }) {
                // Update message text
                history.messages[index].text = newText
                
                // Update thinking and signature if provided
                if let thinking = thinking {
                    history.messages[index].thinking = thinking
                }
                if let signature = thinkingSignature {
                    history.messages[index].thinkingSignature = signature
                }
                
                // Convert ToolInfo to Message.ToolUse
                let toolUse = Message.ToolUse(
                    toolId: toolInfo.id,
                    toolName: toolInfo.name,
                    inputs: toolInfo.input
                )
                
                // Update tool usage and result
                history.messages[index].toolUse = toolUse
                if let result = toolResult {
                    history.messages[index].toolUse?.result = result
                }
                
                saveConversationHistory(history, for: chatId)
            }
            
            DispatchQueue.main.async {
                if let chatIndex = self.chats.firstIndex(where: { $0.chatId == chatId }) {
                    self.chats[chatIndex].lastMessageDate = Date()
                    self.objectWillChange.send()
                }
            }
        } else {
            // Fall back to legacy method
            var messages = loadMessagesFromFile(chatId: chatId)
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                var message = messages[index]
                message.text = newText
                message.toolUse = toolInfo
                
                // Update thinking and signature if provided
                if let thinking = thinking {
                    message.thinking = thinking
                }
                if let signature = thinkingSignature {
                    message.signature = signature
                }
                
                if let result = toolResult {
                    message.toolResult = result
                }
                
                messages[index] = message
                saveMessagesToFile(chatId: chatId, messages: messages)
                
                DispatchQueue.main.async {
                    if let chatIndex = self.chats.firstIndex(where: { $0.chatId == chatId }) {
                        self.chats[chatIndex].lastMessageDate = Date()
                        self.objectWillChange.send()
                    }
                }
            }
        }
    }
    
    func updateMessageThinking(for chatId: String, messageId: UUID, newThinking: String, signature: String? = nil) {
        if var history = getConversationHistory(for: chatId) {
            history.updateMessage(id: messageId, thinking: newThinking, thinkingSignature: signature)
            saveConversationHistory(history, for: chatId)
        } else {
            // Fall back to legacy method
            var messages = loadMessagesFromFile(chatId: chatId)
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                var message = messages[index]
                message.thinking = newThinking
                if let sig = signature {
                    message.signature = sig
                }
                messages[index] = message
                
                saveMessagesToFile(chatId: chatId, messages: messages)
            }
        }
    }
    
    // MARK: - Get Messages
    
    func getMessages(for chatId: String) -> [MessageData] {
        // First check if we have a unified history
        if let history = getConversationHistory(for: chatId) {
            // Convert from unified format to MessageData
            return history.messages.map { message in
                let user = message.role == .user ? "User" : getChatModel(for: chatId)?.name ?? "Assistant"
                
                // Convert tool usage
                let toolUse: ToolInfo? = message.toolUse.map { usage in
                    return ToolInfo(
                        id: usage.toolId,
                        name: usage.toolName,
                        input: usage.inputs
                    )
                }
                
                return MessageData(
                    id: message.id,
                    text: message.text,
                    thinking: message.thinking,
                    thinkingSummary: message.thinkingSummary,
                    signature: message.thinkingSignature,
                    user: user,
                    isError: message.isError,
                    sentTime: message.timestamp,
                    imageBase64Strings: message.imageBase64Strings,
                    documentBase64Strings: message.documentBase64Strings,
                    documentFormats: message.documentFormats,
                    documentNames: message.documentNames,
                    pastedTexts: message.pastedTexts,
                    toolUse: toolUse,
                    toolResult: message.toolUse?.result,
                    videoUrl: message.videoUrl,
                    videoS3Uri: message.videoS3Uri
                )
            }
        }
        
        // Fall back to legacy format if unified history not found
        return loadMessagesFromFile(chatId: chatId)
    }
    
    // MARK: - Conversation History API (Unified)
    
    /// Gets the unified conversation history for a chat
    func getConversationHistory(for chatId: String) -> ConversationHistory? {
        let fileURL = getConversationHistoryFileURL(chatId: chatId)
        
        do {
            if fileExists(at: fileURL) {
                let data = try Data(contentsOf: fileURL)
                return try JSONDecoder().decode(ConversationHistory.self, from: data)
            }
        } catch {
            logger.info("Failed to load conversation history: \(error)")
        }
        
        return nil
    }
    
    /// Saves the unified conversation history for a chat
    func saveConversationHistory(_ history: ConversationHistory, for chatId: String) {
        let fileURL = getConversationHistoryFileURL(chatId: chatId)
        
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: fileURL)
        } catch {
            logger.info("Failed to save conversation history: \(error)")
        }
    }
    
    /// Creates a new conversation history for a chat
    private func createNewConversationHistory(for chatId: String) -> ConversationHistory {
        guard let chat = getChatModel(for: chatId) else {
            // Default values if chat model can't be found
            return ConversationHistory(chatId: chatId, modelId: "unknown")
        }
        
        // Get system prompt if available
        let systemPrompt = SettingManager.shared.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return ConversationHistory(
            chatId: chatId,
            modelId: chat.id,
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt
        )
    }
    
    // Legacy compatibility support - original methods
    
    func getHistory(for chatId: String) -> String {
        return loadHistoryFromFile(chatId: chatId)
    }
    
    func setHistory(_ history: String, for chatId: String) {
        saveHistoryToFile(chatId: chatId, history: history)
    }
    
    // MARK: - Tool Management
    
    func getToolId(for chatId: String, toolName: String) -> String {
        var toolIds = loadToolIdsFromFile(chatId: chatId)
        
        if let existingId = toolIds[toolName] {
            return existingId
        }
        
        let newId = "tool_\(UUID().uuidString)"
        toolIds[toolName] = newId
        saveToolIdsToFile(chatId: chatId, toolIds: toolIds)
        return newId
    }
    
    func resetToolIds(for chatId: String) {
        saveToolIdsToFile(chatId: chatId, toolIds: [:])
    }
    
    // MARK: - File System Operations
    
    private func loadChats() {
        let context = coreDataStack.viewContext
        let fetchRequest: NSFetchRequest<ChatEntity> = ChatEntity.fetchRequest()
        
        do {
            let results = try context.fetch(fetchRequest)
            DispatchQueue.main.async {
                var uniqueChats = [String: ChatModel]()
                results.forEach { entity in
                    let chatModel = ChatModel(
                        id: entity.id ?? "",
                        chatId: entity.chatId ?? "",
                        name: entity.name ?? "",
                        title: entity.title ?? "",
                        description: entity.chatDescription ?? "",
                        provider: entity.provider ?? "",
                        lastMessageDate: entity.lastMessageDate ?? Date(),
                        isManuallyRenamed: entity.isManuallyRenamed
                    )
                    uniqueChats[chatModel.chatId] = chatModel
                }
                self.chats = Array(uniqueChats.values)
            }
        } catch {
            logger.info("Failed to fetch chats: \(error)")
        }
    }
    
    private func getBaseDirectory() -> URL {
        return URL(fileURLWithPath: settingManager.defaultDirectory)
    }
    
    // File operations that need to be main-actor safe
    @MainActor
    private func createDirectories() {
        let baseURL = getBaseDirectory()
        let messagesURL = baseURL.appendingPathComponent("messages")
        let historyURL = baseURL.appendingPathComponent("history")
        
        do {
            try fileManager.createDirectory(at: messagesURL, withIntermediateDirectories: true, attributes: nil)
            try fileManager.createDirectory(at: historyURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger.info("Failed to create directories: \(error)")
        }
    }

    // MARK: - File URLs
    
    private func getConversationHistoryFileURL(chatId: String) -> URL {
        return getBaseDirectory().appendingPathComponent("history/\(chatId)_unified_history.json")
    }
    
    private func getMessageFileURL(chatId: String) -> URL {
        return getBaseDirectory().appendingPathComponent("messages/\(chatId)_messages.json")
    }
    
    private func getHistoryFileURL(chatId: String) -> URL {
        return getBaseDirectory().appendingPathComponent("history/\(chatId)_history.txt")
    }
    
    private func getToolIdsFileURL(chatId: String) -> URL {
        return getBaseDirectory().appendingPathComponent("history/\(chatId)_tool_ids.json")
    }
    
    // MARK: - Legacy File Operations
    
    private func fileExists(at url: URL) -> Bool {
        return fileManager.fileExists(atPath: url.path)
    }
    
    private func saveMessageInLegacyFormat(_ message: MessageData, for chatId: String) {
        var messages = loadMessagesFromFile(chatId: chatId)
        messages.append(message)
        saveMessagesToFile(chatId: chatId, messages: messages)
    }
    
    private func saveMessagesToFile(chatId: String, messages: [MessageData]) {
        let fileURL = getMessageFileURL(chatId: chatId)
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: fileURL)
        } catch {
            logger.error("Failed to save messages: \(error)")
        }
    }
    
    private func loadMessagesFromFile(chatId: String) -> [MessageData] {
        let fileURL = getMessageFileURL(chatId: chatId)
        
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              !data.isEmpty else {
            return []
        }
        
        // Try the most flexible approach - manual JSON parsing
        do {
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                logger.error("Failed to parse JSON data as array")
                return []
            }
            
            var messages: [MessageData] = []
            
            for json in jsonArray {
                // Extract core fields with fallbacks for different naming conventions
                guard let idString = (json["id"] as? String),
                      let id = UUID(uuidString: idString),
                      let text = json["text"] as? String,
                      let user = json["user"] as? String else {
                    logger.warning("Missing required fields in message data")
                    continue
                }
                
                // Handle timestamp with multiple possible formats
                var sentTime: Date
                if let timeValue = json["sentTime"] as? TimeInterval {
                    sentTime = Date(timeIntervalSince1970: timeValue)
                } else if let timeValue = json["sent_time"] as? TimeInterval {
                    sentTime = Date(timeIntervalSince1970: timeValue)
                } else {
                    // Default to current time if no valid time found
                    sentTime = Date()
                    logger.warning("No valid timestamp found for message, using current time")
                }
                
                // Optional fields with fallbacks
                let isError = (json["isError"] as? Bool) ?? (json["is_error"] as? Bool) ?? false
                let thinking = json["thinking"] as? String
                let thinkingSummary = (json["thinkingSummary"] as? String) ?? (json["thinking_summary"] as? String)
                let signature = json["signature"] as? String
                
                // Image attachments
                var imageBase64Strings: [String]? = nil
                if let images = json["imageBase64Strings"] as? [String] {
                    imageBase64Strings = images
                } else if let images = json["image_base64_strings"] as? [String] {
                    imageBase64Strings = images
                }
                
                // Document attachments
                var documentBase64Strings: [String]? = nil
                if let docs = json["documentBase64Strings"] as? [String] {
                    documentBase64Strings = docs
                } else if let docs = json["document_base64_strings"] as? [String] {
                    documentBase64Strings = docs
                }
                
                var documentFormats: [String]? = nil
                if let formats = json["documentFormats"] as? [String] {
                    documentFormats = formats
                } else if let formats = json["document_formats"] as? [String] {
                    documentFormats = formats
                }
                
                var documentNames: [String]? = nil
                if let names = json["documentNames"] as? [String] {
                    documentNames = names
                } else if let names = json["document_names"] as? [String] {
                    documentNames = names
                }
                
                // Tool usage
                var toolUse: ToolInfo? = nil
                var toolResult: String? = nil
                

                if let toolDict = json["toolUse"] as? [String: Any] {
                    if let toolId = toolDict["id"] as? String,
                       let toolName = toolDict["name"] as? String,
                       let toolInput = toolDict["input"] as? [String: Any] {
                        toolUse = ToolInfo(id: toolId, name: toolName, input: JSONValue.from(toolInput))
                    }
                } else if let toolDict = json["tool_use"] as? [String: Any] {
                    if let toolId = toolDict["id"] as? String,
                       let toolName = toolDict["name"] as? String,
                       let toolInput = toolDict["input"] as? [String: Any] {
                        toolUse = ToolInfo(id: toolId, name: toolName, input: JSONValue.from(toolInput))
                    }
                }
                
                toolResult = (json["toolResult"] as? String) ?? (json["tool_result"] as? String)
                
                // Create message with extracted fields
                let message = MessageData(
                    id: id,
                    text: text,
                    thinking: thinking,
                    thinkingSummary: thinkingSummary,
                    signature: signature,
                    user: user,
                    isError: isError,
                    sentTime: sentTime,
                    imageBase64Strings: imageBase64Strings,
                    documentBase64Strings: documentBase64Strings,
                    documentFormats: documentFormats,
                    documentNames: documentNames,
                    toolUse: toolUse,
                    toolResult: toolResult
                )
                
                messages.append(message)
            }
            
            if !messages.isEmpty {
                logger.info("Successfully loaded \(messages.count) messages using manual JSON parsing")
                return messages
            }
        } catch {
            logger.error("Error during manual JSON parsing: \(error)")
        }
        
        // If we got here, all approaches failed
        logger.error("All attempts to parse message data failed")
        return []
    }
    
    private func saveHistoryToFile(chatId: String, history: String) {
        let fileURL = getHistoryFileURL(chatId: chatId)
        do {
            try history.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Failed to save history: \(error)")
        }
    }
    
    private func loadHistoryFromFile(chatId: String) -> String {
        let fileURL = getHistoryFileURL(chatId: chatId)
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                return try String(contentsOf: fileURL)
            }
        } catch {
            logger.error("Failed to load history: \(error)")
        }
        return ""
    }
    
    private func saveToolIdsToFile(chatId: String, toolIds: [String: String]) {
        let fileURL = getToolIdsFileURL(chatId: chatId)
        do {
            let data = try JSONEncoder().encode(toolIds)
            try data.write(to: fileURL)
        } catch {
            logger.error("Failed to save tool IDs: \(error)")
        }
    }
    
    private func loadToolIdsFromFile(chatId: String) -> [String: String] {
        let fileURL = getToolIdsFileURL(chatId: chatId)
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                return try JSONDecoder().decode([String: String].self, from: data)
            }
        } catch {
            logger.error("Failed to load tool IDs: \(error)")
        }
        return [:]
    }
    
    // MARK: - File Cleanup
    
    private func deleteAllFiles(for chatId: String) {
        let files = [
            getMessageFileURL(chatId: chatId),
            getHistoryFileURL(chatId: chatId),
            getToolIdsFileURL(chatId: chatId),
            getConversationHistoryFileURL(chatId: chatId)
        ]
        
        for fileURL in files {
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
    
    private func clearAllFiles() {
        let documentsURL = getBaseDirectory()
        do {
            let messagesURL = documentsURL.appendingPathComponent("messages")
            let historyURL = documentsURL.appendingPathComponent("history")
            
            if fileManager.fileExists(atPath: messagesURL.path) {
                let messageFiles = try fileManager.contentsOfDirectory(at: messagesURL, includingPropertiesForKeys: nil)
                for fileURL in messageFiles {
                    try fileManager.removeItem(at: fileURL)
                }
            }
            
            if fileManager.fileExists(atPath: historyURL.path) {
                let historyFiles = try fileManager.contentsOfDirectory(at: historyURL, includingPropertiesForKeys: nil)
                for fileURL in historyFiles {
                    try fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
            logger.info("Failed to clear files: \(error)")
        }
    }
}
