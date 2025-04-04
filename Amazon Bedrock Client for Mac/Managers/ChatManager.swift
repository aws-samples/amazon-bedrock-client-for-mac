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

// MARK: - Unified Conversation History

/// Unified conversation history structure
struct ConversationHistory: Codable {
    struct Message: Codable, Identifiable {
        let id: UUID
        var text: String
        var thinking: String?
        var thinkingSignature: String?
        let role: String
        let timestamp: Date
        let isError: Bool
        var imageBase64Strings: [String]?
        var documentBase64Strings: [String]?
        var documentFormats: [String]?
        var documentNames: [String]?
        var toolUsage: ToolUsage?
        
        struct ToolUsage: Codable {
            let toolId: String
            let toolName: String
            let inputs: JSONValue
            var result: String?
        }
    }
    
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
    
    mutating func addMessage(_ message: Message) {
        if message.role == "user" {
            while let lastMessage = messages.last, lastMessage.role == "user" {
                messages.removeLast()
            }
        }
        
        messages.append(message)
        lastUpdated = Date()
    }
    
    mutating func updateMessage(id: UUID, newText: String? = nil, thinking: String? = nil, thinkingSignature: String? = nil, toolResult: String? = nil) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            var message = messages[index]
            
            if let newText = newText {
                message.text = newText
            }
            
            if let thinking = thinking {
                message.thinking = thinking
            }
            
            if let thinkingSignature = thinkingSignature {
                message.thinkingSignature = thinkingSignature
            }
            
            if let toolResult = toolResult, message.toolUsage != nil {
                message.toolUsage?.result = toolResult
            }
            
            messages[index] = message
            lastUpdated = Date()
        }
    }
}

class ChatManager: ObservableObject {
    @Published var chats: [ChatModel] = []
    @Published var chatIsLoading: [String: Bool] = [:]
    
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
    
    private func migrateHistoryForChat(chatId: String, modelId: String) {
        logger.info("Migrating history for chat: \(chatId)")
        
        if fileExists(at: getConversationHistoryFileURL(chatId: chatId)) {
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
        for message in messages {
            let role = message.user == "User" ? "user" : "assistant"
            
            var toolUsage: ConversationHistory.Message.ToolUsage? = nil
            if let tool = message.toolUse {
                toolUsage = ConversationHistory.Message.ToolUsage(
                    toolId: tool.id,
                    toolName: tool.name,
                    inputs: tool.input,  // Already a JSONValue type
                    result: message.toolResult
                )
            }
            
            // Create message with all available fields, handling potential nil values
            let unifiedMessage = ConversationHistory.Message(
                id: message.id,
                text: message.text,
                thinking: message.thinking,
                thinkingSignature: message.signature,
                role: role,
                timestamp: message.sentTime,
                isError: message.isError,
                imageBase64Strings: message.imageBase64Strings,
                documentBase64Strings: message.documentBase64Strings,
                documentFormats: message.documentFormats,
                documentNames: message.documentNames,
                toolUsage: toolUsage
            )
            
            conversationHistory.addMessage(unifiedMessage)
        }
        
        saveConversationHistory(conversationHistory, for: chatId)
        logger.info("Successfully migrated history for chat \(chatId)")
    }
    
    // MARK: - Chat Management
    
    func createNewChat(modelId: String, modelName: String, modelProvider: String, completion: @escaping (ChatModel) -> Void) {
        let context = coreDataStack.viewContext
        context.perform {
            let newChat = NSEntityDescription.insertNewObject(forEntityName: "ChatEntity", into: context) as! ChatEntity
            newChat.id = modelId
            newChat.chatId = UUID().uuidString
            newChat.name = modelName
            newChat.title = "New Chat"
            newChat.chatDescription = modelId
            newChat.provider = modelProvider
            newChat.lastMessageDate = Date()
            
            do {
                try context.save()
                
                let chatModel = ChatModel(
                    id: newChat.id ?? "",
                    chatId: newChat.chatId ?? "",
                    name: newChat.name ?? "",
                    title: newChat.title ?? "",
                    description: newChat.chatDescription ?? "",
                    provider: newChat.provider ?? "",
                    lastMessageDate: newChat.lastMessageDate ?? Date()
                )
                
                // Create empty conversation history for this chat
                let history = ConversationHistory(chatId: chatModel.chatId, modelId: chatModel.id)
                self.saveConversationHistory(history, for: chatModel.chatId)
                
                DispatchQueue.main.async {
                    self.chats.append(chatModel)
                    self.chatIsLoading[chatModel.chatId] = false
                    self.objectWillChange.send()
                    completion(chatModel)
                }
            } catch {
                self.logger.info("Failed to save context: \(error)")
                completion(ChatModel(id: "", chatId: "", name: "", title: "", description: "", provider: "", lastMessageDate: Date()))
            }
        }
    }
    
    func updateChatTitle(for chatId: String, title: String) {
        let context = coreDataStack.viewContext
        let fetchRequest: NSFetchRequest<ChatEntity> = ChatEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "chatId == %@", chatId)
        
        do {
            let results = try context.fetch(fetchRequest)
            if let chatEntity = results.first {
                chatEntity.title = title
                coreDataStack.saveContext()
                
                DispatchQueue.main.async {
                    if let index = self.chats.firstIndex(where: { $0.chatId == chatId }) {
                        self.chats[index].title = title
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
    
    // MARK: - Messages API
    
    func getMessages(for chatId: String) -> [MessageData] {
        // First check if we have a unified history
        if let history = getConversationHistory(for: chatId) {
            // Convert from unified format to MessageData
            return history.messages.map { message in
                let user = message.role == "user" ? "User" : getChatModel(for: chatId)?.name ?? "Assistant"
                
                // Convert tool usage
                let toolUse: ToolInfo? = message.toolUsage.map { usage in
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
                    user: user,
                    isError: message.isError,
                    sentTime: message.timestamp,
                    imageBase64Strings: message.imageBase64Strings,
                    documentBase64Strings: message.documentBase64Strings,
                    documentFormats: message.documentFormats,
                    documentNames: message.documentNames,
                    toolUse: toolUse,
                    toolResult: message.toolUsage?.result
                )
            }
        }
        
        // Fall back to legacy format if unified history not found
        return loadMessagesFromFile(chatId: chatId)
    }
    
    func addMessage(_ message: MessageData, for chatId: String) {
        // Get existing conversation history or create new one
        var history = getConversationHistory(for: chatId) ?? createNewConversationHistory(for: chatId)
        
        // Add message to history
        let role = message.user == "User" ? "user" : "assistant"
        
        // Process tool usage data
        var toolUsage: ConversationHistory.Message.ToolUsage? = nil
        if let tool = message.toolUse {
            toolUsage = ConversationHistory.Message.ToolUsage(
                toolId: tool.id,
                toolName: tool.name,
                inputs: tool.input,
                result: message.toolResult
            )
        }
        
        let unifiedMessage = ConversationHistory.Message(
            id: message.id,
            text: message.text,
            thinking: message.thinking,
            role: role,
            timestamp: message.sentTime,
            isError: message.isError,
            imageBase64Strings: message.imageBase64Strings,
            documentBase64Strings: message.documentBase64Strings,
            documentFormats: message.documentFormats,
            documentNames: message.documentNames,
            toolUsage: toolUsage
        )
        
        history.addMessage(unifiedMessage)
        
        // Save updated history
        saveConversationHistory(history, for: chatId)
        
        // For backward compatibility, also save in the legacy format
        saveMessageInLegacyFormat(message, for: chatId)
        
        // Update last message date for chat model
        DispatchQueue.main.async {
            if let index = self.chats.firstIndex(where: { $0.chatId == chatId }) {
                self.chats[index].lastMessageDate = Date()
                self.objectWillChange.send()
            }
        }
    }
    
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
    
    func updateMessageWithToolInfo(for chatId: String, messageId: UUID, newText: String, toolInfo: ToolInfo, toolResult: String? = nil) {
        if var history = getConversationHistory(for: chatId) {
            history.updateMessage(id: messageId, newText: newText, toolResult: toolResult)
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
                message.toolUse = toolInfo
                
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
    
    func updateMessageThinking(for chatId: String, messageId: UUID, newThinking: String) {
        if var history = getConversationHistory(for: chatId) {
            history.updateMessage(id: messageId, thinking: newThinking)
            saveConversationHistory(history, for: chatId)
        } else {
            // Fall back to legacy method
            var messages = loadMessagesFromFile(chatId: chatId)
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                var message = messages[index]
                message.thinking = newThinking
                messages[index] = message
                
                saveMessagesToFile(chatId: chatId, messages: messages)
            }
        }
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
                        lastMessageDate: entity.lastMessageDate ?? Date()
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
