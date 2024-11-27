//
//  ChatManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/09.
//

import Combine
import SwiftUI
import CoreData

class ChatManager: ObservableObject {
    @Published var chats: [ChatModel] = []
    @Published var chatIsLoading: [String: Bool] = [:]
    
    var hasChats: Bool {
        return !chats.isEmpty
    }
    
    static let shared = ChatManager()
    @StateObject private var settingManager = SettingManager.shared
    
    private let coreDataStack: CoreDataStack
    private let fileManager = FileManager.default
    
    private init() {
        self.coreDataStack = CoreDataStack(modelName: "ChatModel")
        self.loadChats()
        self.createDirectories()
    }
    
    // MARK: - Chat Management
    
    func createNewChat(modelId: String, modelName: String, completion: @escaping (ChatModel) -> Void) {
        let context = coreDataStack.viewContext
        context.perform {
            let newChat = NSEntityDescription.insertNewObject(forEntityName: "ChatEntity", into: context) as! ChatEntity
            newChat.id = modelId
            newChat.chatId = UUID().uuidString
            newChat.name = modelName
            newChat.title = "New Chat"
            newChat.chatDescription = modelId
            newChat.provider = "Provider for \(modelId)"
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
                
                DispatchQueue.main.async {
                    self.chats.append(chatModel)
                    self.chatIsLoading[chatModel.chatId] = false
                    self.objectWillChange.send()
                    completion(chatModel)
                }
            } catch {
                print("Failed to save context: \(error)")
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
            print("Failed to update chat title: \(error)")
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
            print("Failed to delete chat from CoreData: \(error)")
        }
        
        // Remove from in-memory array
        if let index = chats.firstIndex(where: { $0.chatId == chatId }) {
            chats.remove(at: index)
        }
        
        // Delete associated files
        deleteMessagesFile(for: chatId)
        deleteHistoryFile(for: chatId)
        deleteClaudeHistoryFile(for: chatId)
        
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
            
            clearAllMessageAndHistoryFiles()
        } catch {
            print("Failed to clear all chats: \(error)")
        }
    }
    
    // MARK: - Persistence
    
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
            print("Failed to fetch chats: \(error)")
        }
    }
    
    
    // MARK: - File Management
    
    private func getBaseDirectory() -> URL {
        let tempDir = URL(fileURLWithPath: settingManager.defaultDirectory)
        return tempDir
    }
    
    private func createDirectories() {
        let baseURL = getBaseDirectory()
        let messagesURL = baseURL.appendingPathComponent("messages")
        let historyURL = baseURL.appendingPathComponent("history")
        
        do {
            try fileManager.createDirectory(at: messagesURL, withIntermediateDirectories: true, attributes: nil)
            try fileManager.createDirectory(at: historyURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create directories: \(error)")
        }
    }
    
    private func getMessageFileURL(chatId: String) -> URL {
        return getBaseDirectory().appendingPathComponent("messages/\(chatId)_messages.json")
    }
    
    private func getHistoryFileURL(chatId: String) -> URL {
        return getBaseDirectory().appendingPathComponent("history/\(chatId)_history.txt")
    }
    
    private func getClaudeHistoryFileURL(chatId: String) -> URL {
        return getBaseDirectory().appendingPathComponent("history/\(chatId)_claude_history.json")
    }
    
    private func saveMessagesToFile(chatId: String, messages: [MessageData]) {
        let fileURL = getMessageFileURL(chatId: chatId)
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save messages: \(error)")
        }
    }
    
    private func loadMessagesFromFile(chatId: String) -> [MessageData] {
        let fileURL = getMessageFileURL(chatId: chatId)
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([MessageData].self, from: data)
        } catch {
            print("Failed to load messages: \(error)")
            return []
        }
    }
    
    private func saveHistoryToFile(chatId: String, history: String) {
        let fileURL = getHistoryFileURL(chatId: chatId)
        do {
            try history.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save history: \(error)")
        }
    }
    
    private func loadHistoryFromFile(chatId: String) -> String {
        let fileURL = getHistoryFileURL(chatId: chatId)
        do {
            return try String(contentsOf: fileURL)
        } catch {
            print("Failed to load history: \(error)")
            return ""
        }
    }
    
    private func saveClaudeHistoryToFile(chatId: String, history: [ClaudeMessageRequest.Message]) {
        let fileURL = getClaudeHistoryFileURL(chatId: chatId)
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save Claude history: \(error)")
        }
    }
    
    private func loadClaudeHistoryFromFile(chatId: String) -> [ClaudeMessageRequest.Message] {
        let fileURL = getClaudeHistoryFileURL(chatId: chatId)
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([ClaudeMessageRequest.Message].self, from: data)
        } catch {
            print("Failed to load Claude history: \(error)")
            return []
        }
    }
    
    private func clearAllMessageAndHistoryFiles() {
        let documentsURL = getBaseDirectory()
        do {
            let messagesURL = documentsURL.appendingPathComponent("messages")
            let historyURL = documentsURL.appendingPathComponent("history")
            
            let messageFiles = try fileManager.contentsOfDirectory(at: messagesURL, includingPropertiesForKeys: nil)
            for fileURL in messageFiles {
                try fileManager.removeItem(at: fileURL)
            }
            
            let historyFiles = try fileManager.contentsOfDirectory(at: historyURL, includingPropertiesForKeys: nil)
            for fileURL in historyFiles {
                try fileManager.removeItem(at: fileURL)
            }
        } catch {
            print("Failed to clear message and history files: \(error)")
        }
    }
}

extension ChatManager {
    func getMessages(for chatId: String) -> [MessageData] {
        return loadMessagesFromFile(chatId: chatId)
    }
    
    func addMessage(_ message: MessageData, for chatId: String) {
        var messages = getMessages(for: chatId)
        messages.append(message)
        saveMessagesToFile(chatId: chatId, messages: messages)
        
        DispatchQueue.main.async {
            if let index = self.chats.firstIndex(where: { $0.chatId == chatId }) {
                self.chats[index].lastMessageDate = Date()
                self.objectWillChange.send()
            }
        }
    }
}

extension ChatManager {
    func getHistory(for chatId: String) -> String {
        return loadHistoryFromFile(chatId: chatId)
    }
    
    func setHistory(_ history: String, for chatId: String) {
        saveHistoryToFile(chatId: chatId, history: history)
    }
    
    func getClaudeHistory(for chatId: String) -> [ClaudeMessageRequest.Message] {
        return loadClaudeHistoryFromFile(chatId: chatId)
    }
    
    func addClaudeHistory(_ message: ClaudeMessageRequest.Message, for chatId: String) {
        var history = getClaudeHistory(for: chatId)
        
        // If the new message is from the "user", check previous messages
        if message.role == "user" {
            // Remove all "user" messages after the last "assistant" message
            while let lastMessage = history.last, lastMessage.role == "user" {
                history.removeLast()
            }
        }
        
        // Add the new message
        history.append(message)
        
        // Save the modified history
        saveClaudeHistoryToFile(chatId: chatId, history: history)
    }
    
    func cleanupClaudeHistory(for chatId: String) {
        var history = getClaudeHistory(for: chatId)
        var cleanedHistory: [ClaudeMessageRequest.Message] = []
        var lastRole: String?
        
        for message in history {
            if message.role != lastRole {
                cleanedHistory.append(message)
                lastRole = message.role
            } else if message.role == "user" {
                // If the same role appears consecutively, replace only the "user" message with the latest one
                cleanedHistory[cleanedHistory.count - 1] = message
            }
        }
        
        saveClaudeHistoryToFile(chatId: chatId, history: cleanedHistory)
    }
}

extension ChatManager {
    func getChatModel(for chatId: String) -> ChatModel? {
        return chats.first { $0.chatId == chatId }
    }
    
    private func deleteMessagesFile(for chatId: String) {
        let fileURL = getMessageFileURL(chatId: chatId)
        try? fileManager.removeItem(at: fileURL)
    }
    
    private func deleteHistoryFile(for chatId: String) {
        let fileURL = getHistoryFileURL(chatId: chatId)
        try? fileManager.removeItem(at: fileURL)
    }
    
    private func deleteClaudeHistoryFile(for chatId: String) {
        let fileURL = getClaudeHistoryFileURL(chatId: chatId)
        try? fileManager.removeItem(at: fileURL)
    }
}

extension ChatManager {
    func getIsLoading(for chatId: String) -> Bool {
        return chatIsLoading[chatId] ?? false
    }
    
    func setIsLoading(_ isLoading: Bool, for chatId: String) {
        DispatchQueue.main.async {
            self.chatIsLoading[chatId] = isLoading
            self.objectWillChange.send()
        }
    }
}
