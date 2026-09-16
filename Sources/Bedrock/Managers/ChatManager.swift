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

@MainActor
class ChatManager: ObservableObject {
    @Published var chats: [ChatModel] = []
    @Published var chatIsLoading: [String: Bool] = [:]
    private var temporaryChats: [String: ChatModel] = [:] // Chats not yet saved to CoreData
    private var historyCache: [String: ConversationHistory] = [:]
    private var historyCacheOrder: [String] = []
    private var invalidHistoryPaths: Set<String> = []
    private var conversationFiles = ConversationFileStore()
    @Published var persistenceError: String?
    
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
        // A missing legacy file is not evidence that an old conversation was
        // empty. Keep its index and any older transcript available for recovery.
        guard fileExists(at: getMessageFileURL(chatId: chatId)) else { return }
        
        let messages = getMessages(for: chatId)
        guard !invalidHistoryPaths.contains(getMessageFileURL(chatId: chatId).path),
              !invalidHistoryPaths.contains(getConversationHistoryFileURL(chatId: chatId).path) else { return }
        if messages.isEmpty && !loadHistoryFromFile(chatId: chatId).isEmpty { return }
        let prompt = SettingManager.shared.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let history = ConversationHistory.fromMessages(messages, chatID: chatId, modelID: modelId,
                                                       systemPrompt: prompt.isEmpty ? nil : prompt)
        saveConversationHistory(history, for: chatId)
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
        
        // Persist before notifying consumers; callers can rename/configure a new
        // thread immediately without racing an asynchronous Core Data insertion.
        let context = coreDataStack.viewContext
        let entity = NSEntityDescription.insertNewObject(forEntityName: "ChatEntity", into: context) as! ChatEntity
        entity.id = chatModel.id
        entity.chatId = chatModel.chatId
        entity.name = chatModel.name
        entity.title = chatModel.title
        entity.chatDescription = chatModel.description
        entity.provider = chatModel.provider
        entity.lastMessageDate = chatModel.lastMessageDate
        entity.isManuallyRenamed = chatModel.isManuallyRenamed
        do { try context.save() }
        catch {
            temporaryChats[chatId] = chatModel
            persistenceError = "Could not persist the new thread: \(error.localizedDescription)"
        }
        completion(chatModel)
    }

    @discardableResult
    func changeModel(for chatID: String, to model: ChatModel) -> ChatModel? {
        guard let index = chats.firstIndex(where: { $0.chatId == chatID }), !getIsLoading(for: chatID) else { return nil }
        let previous = chats[index]
        guard previous.id != model.id else { return previous }
        let legacy = getMessages(for: chatID)
        guard !invalidHistoryPaths.contains(getMessageFileURL(chatId: chatID).path),
              !invalidHistoryPaths.contains(getConversationHistoryFileURL(chatId: chatID).path) else { return nil }
        let originalHistory = getConversationHistory(for: chatID) ??
            ConversationHistory.fromMessages(legacy, chatID: chatID, modelID: previous.id)
        var history = originalHistory
        history.switchModel(to: model.id)
        let updated = ChatModel(id: model.id, chatId: chatID, name: model.name, title: previous.title,
                                description: model.description, provider: model.provider,
                                lastMessageDate: previous.lastMessageDate, isManuallyRenamed: previous.isManuallyRenamed)
        let request: NSFetchRequest<ChatEntity> = ChatEntity.fetchRequest()
        request.predicate = NSPredicate(format: "chatId == %@", chatID)
        do {
            guard let entity = try coreDataStack.viewContext.fetch(request).first else {
                throw LocalWorkbenchError.unavailable("This conversation could not be found in local storage.")
            }
            guard saveConversationHistory(history, for: chatID) else { return nil }
            entity.id = model.id
            entity.name = model.name
            entity.provider = model.provider
            entity.chatDescription = model.description
            do { try coreDataStack.viewContext.save() }
            catch {
                entity.id = previous.id; entity.name = previous.name
                entity.provider = previous.provider; entity.chatDescription = previous.description
                saveConversationHistory(originalHistory, for: chatID)
                throw error
            }
            chats[index] = updated
            return updated
        } catch {
            persistenceError = "Could not change the model: \(error.localizedDescription)"
            return nil
        }
    }

    /// Import and branch preparation must finish before the new chat appears.
    /// Encoding large attachment histories happens away from AppKit's event loop.
    func createConversation(modelID: String, modelName: String, provider: String, title: String,
                            messages: [Message], systemPrompt: String?) async throws -> ChatModel {
        let id = UUID().uuidString
        let model = ChatModel(id: modelID, chatId: id, name: modelName, title: title,
                              description: modelID, provider: provider, lastMessageDate: Date(),
                              isManuallyRenamed: true)
        let history = ConversationHistory(chatId: id, modelId: modelID, messages: messages, systemPrompt: systemPrompt)
        let url = getConversationHistoryFileURL(chatId: id)
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            var files = ConversationFileStore()
            return try files.write(history, to: url)
        }
        let saved = try await worker.value
        let context = coreDataStack.viewContext
        let entity = NSEntityDescription.insertNewObject(forEntityName: "ChatEntity", into: context) as! ChatEntity
        entity.id = model.id
        entity.chatId = id
        entity.name = model.name
        entity.title = title
        entity.chatDescription = modelID
        entity.provider = provider
        entity.lastMessageDate = model.lastMessageDate
        entity.isManuallyRenamed = true
        do { try context.save() }
        catch {
            context.delete(entity)
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        cacheHistory(saved, path: url.path)
        chats.append(model)
        chatIsLoading[id] = false
        return model
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
                var candidates: [(chat: ChatEntity, url: URL, modified: Date?, lastMessage: Date?)] = []
                
                for chat in allChats {
                    guard let chatId = chat.chatId, self.canCleanUp(chat) else { continue }
                    let url = self.getConversationHistoryFileURL(chatId: chatId)
                    let legacy = self.getMessageFileURL(chatId: chatId)
                    // An empty auto-created conversation is tiny. Never decode
                    // every large transcript or image payload during startup.
                    guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                          let bytes = values.fileSize, bytes <= 16_384 else { continue }
                    let previousDate = chat.lastMessageDate
                    let loaded = await Task.detached(priority: .utility) {
                        try? ConversationFileStore.read(unifiedURL: url, legacyURL: legacy, chatID: chatId)
                    }.value
                    guard case .unified(let history) = loaded, history.messages.isEmpty else { continue }
                    candidates.append((chat, url, values.contentModificationDate, previousDate))
                }
                var deletedIDs: [String] = []
                for candidate in candidates {
                    let chat = candidate.chat
                    guard let id = chat.chatId, self.canCleanUp(chat),
                          chat.lastMessageDate == candidate.lastMessage,
                          self.getConversationHistoryFileURL(chatId: id) == candidate.url,
                          (try? candidate.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) == candidate.modified,
                          self.cachedMessages(for: id)?.isEmpty != false else { continue }
                    context.delete(chat)
                    deletedIDs.append(id)
                }
                if !deletedIDs.isEmpty {
                    try context.save()
                    for id in deletedIDs { self.cleanupChatFiles(chatId: id) }
                    self.logger.info("Deleted \(deletedIDs.count) empty chats")
                    self.loadChats()
                }
                
            } catch {
                self.logger.error("Failed to cleanup empty chats: \(error)")
            }
        }
    }

    private func canCleanUp(_ chat: ChatEntity) -> Bool {
        guard let id = chat.chatId, !chat.isDeleted, !chat.isManuallyRenamed,
              temporaryChats[id] == nil, chatIsLoading[id] != true,
              Date().timeIntervalSince(chat.lastMessageDate ?? Date()) >= 300 else { return false }
        let store = WorkbenchStore.shared
        if let outboxURL = try? ConversationOutboxFile.url(threadID: id, directory: store.directory),
           FileManager.default.fileExists(atPath: outboxURL.path) { return false }
        if let draftURL = try? ConversationAttachmentDraftFile.url(threadID: id, directory: store.directory),
           FileManager.default.fileExists(atPath: draftURL.path) { return false }
        let metadata = store.thread(id)
        return store.selectedThreadID != id && !metadata.hasUnsentWork &&
            !metadata.archived && metadata.deletedAt == nil && !metadata.isPinned
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
        // ChatManager is main-actor isolated. Deferring this mutation leaves
        // changeModel seeing a completed request as still running.
        guard getIsLoading(for: chatId) != isLoading else { return }
        chatIsLoading[chatId] = isLoading
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
            return Self.messageData(from: history, assistantName: getChatModel(for: chatId)?.name ?? "Assistant")
        }
        return loadMessagesFromFile(chatId: chatId)
    }

    nonisolated private static func messageData(from history: ConversationHistory, assistantName: String) -> [MessageData] {
            history.messages.map { message in
                let user = message.role == .user ? "User" : assistantName
                
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
                    videoS3Uri: message.videoS3Uri,
                    toolUses: message.toolUses,
                    modelID: message.modelID ?? history.modelId
                )
            }
    }

    func cachedMessages(for chatId: String) -> [MessageData]? {
        guard let history = historyCache[getConversationHistoryFileURL(chatId: chatId).path] else { return nil }
        return Self.messageData(from: history, assistantName: getChatModel(for: chatId)?.name ?? "Assistant")
    }

    /// A cold chat never decodes its JSON while the sidebar is handling a click.
    /// Prefer any newer in-memory write that arrived while the disk read ran.
    func loadMessages(for chatId: String) async -> [MessageData] {
        if let cached = cachedMessages(for: chatId) { return cached }
        let unified = getConversationHistoryFileURL(chatId: chatId)
        let legacy = getMessageFileURL(chatId: chatId)
        let worker = Task.detached(priority: .userInitiated) {
            try ConversationFileStore.read(unifiedURL: unified, legacyURL: legacy, chatID: chatId)
        }
        do {
            let loaded = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            guard unified == getConversationHistoryFileURL(chatId: chatId),
                  getChatModel(for: chatId) != nil else { return [] }
            if let latest = cachedMessages(for: chatId) { return latest }
            switch loaded {
            case .unified(let history):
                cacheHistory(history, path: unified.path)
                return Self.messageData(from: history, assistantName: getChatModel(for: chatId)?.name ?? "Assistant")
            case .legacy(let messages): return messages
            }
        } catch is CancellationError {
            return []
        } catch {
            let path = fileExists(at: unified) ? unified.path : legacy.path
            invalidHistoryPaths.insert(path)
            persistenceError = "Could not read this conversation. Its original file has been preserved.\n\(error.localizedDescription)"
            return []
        }
    }

    /// Copy/branch/export cannot treat an unreadable file as an empty thread.
    func conversationSnapshot(for chatID: String) async throws -> ConversationHistory {
        let unified = getConversationHistoryFileURL(chatId: chatID)
        if let cached = historyCache[unified.path] { return cached }
        guard let chat = getChatModel(for: chatID) else {
            throw LocalWorkbenchError.unavailable("This conversation is no longer available.")
        }
        let legacy = getMessageFileURL(chatId: chatID)
        let worker = Task.detached(priority: .userInitiated) {
            try ConversationFileStore.read(unifiedURL: unified, legacyURL: legacy, chatID: chatID)
        }
        let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        guard unified == getConversationHistoryFileURL(chatId: chatID), getChatModel(for: chatID) != nil else {
            throw LocalWorkbenchError.unavailable("The conversation location changed. Please try again.")
        }
        if let latest = historyCache[unified.path] { return latest }
        let history: ConversationHistory
        switch result {
        case .unified(let value): history = value
        case .legacy(let value):
            history = .fromMessages(value, chatID: chatID, modelID: chat.id)
        }
        cacheHistory(history, path: unified.path)
        return history
    }

    func canWriteConversation(_ chatId: String) -> Bool {
        _ = getMessages(for: chatId)
        return !invalidHistoryPaths.contains(getMessageFileURL(chatId: chatId).path) &&
            !invalidHistoryPaths.contains(getConversationHistoryFileURL(chatId: chatId).path)
    }
    
    // MARK: - Conversation History API (Unified)
    
    /// Gets the unified conversation history for a chat
    func getConversationHistory(for chatId: String) -> ConversationHistory? {
        let fileURL = getConversationHistoryFileURL(chatId: chatId)
        if let cached = historyCache[fileURL.path] { return cached }
        
        do {
            if fileExists(at: fileURL) {
                let data = try Data(contentsOf: fileURL)
                let history = try ConversationFileStore.decode(data, chatID: chatId)
                cacheHistory(history, path: fileURL.path)
                return history
            }
        } catch {
            invalidHistoryPaths.insert(fileURL.path)
            persistenceError = "Could not read conversation \(chatId). The original file has been preserved.\n\(error.localizedDescription)"
            logger.info("Failed to load conversation history: \(error)")
        }
        
        return nil
    }
    
    /// Saves the unified conversation history for a chat
    @discardableResult
    func saveConversationHistory(_ history: ConversationHistory, for chatId: String) -> Bool {
        let fileURL = getConversationHistoryFileURL(chatId: chatId)
        guard !invalidHistoryPaths.contains(fileURL.path),
              !invalidHistoryPaths.contains(getMessageFileURL(chatId: chatId).path) else { return false }
        
        do {
            let saved = try conversationFiles.write(history, to: fileURL)
            cacheHistory(saved, path: fileURL.path)
            return true
        } catch {
            persistenceError = "Could not save the conversation. Its original file has been preserved.\n\(error.localizedDescription)"
            logger.info("Failed to save conversation history: \(error)")
            return false
        }
    }

    private func cacheHistory(_ history: ConversationHistory, path: String) {
        historyCache[path] = history
        historyCacheOrder.removeAll { $0 == path }
        historyCacheOrder.append(path)
        while historyCacheOrder.count > 8 {
            historyCache.removeValue(forKey: historyCacheOrder.removeFirst())
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
        guard !invalidHistoryPaths.contains(fileURL.path) else { return }
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save messages: \(error)")
        }
    }
    
    private func loadMessagesFromFile(chatId: String) -> [MessageData] {
        let url = getMessageFileURL(chatId: chatId)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        do { return try LegacyConversationDecoder.decode(Data(contentsOf: url)) }
        catch {
            invalidHistoryPaths.insert(url.path)
            persistenceError = "Could not read legacy conversation \(chatId). Its original file has been preserved.\n\(error.localizedDescription)"
            return []
        }
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
        let historyURL = getConversationHistoryFileURL(chatId: chatId)
        let historyPath = historyURL.path
        historyCache.removeValue(forKey: historyPath)
        historyCacheOrder.removeAll { $0 == historyPath }
        invalidHistoryPaths.remove(historyPath)
        invalidHistoryPaths.remove(getMessageFileURL(chatId: chatId).path)
        conversationFiles.forget(historyURL)
        var files = [
            getMessageFileURL(chatId: chatId),
            getHistoryFileURL(chatId: chatId),
            getToolIdsFileURL(chatId: chatId),
            historyURL,
            ConversationFileStore.backupURL(for: historyURL)
        ]
        if let outboxURL = try? ConversationOutboxFile.url(threadID: chatId, directory: WorkbenchStore.shared.directory) {
            files.append(outboxURL)
        }
        if let draftURL = try? ConversationAttachmentDraftFile.url(threadID: chatId, directory: WorkbenchStore.shared.directory) {
            files.append(draftURL)
        }
        
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
