//
//  ChatManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/09.
//

import Combine
import SwiftUI

class ChatManager: ObservableObject {
    // Published properties
    @Published var chats: [ChatModel] {
        didSet {
            saveChats()
        }
    }
    @Published var chatMessages: [String: [MessageData]] = [:]
    @Published var chatHistories: [String: String] = [:]
    @Published var claudeHistories: [String: [ClaudeMessageRequest.Message]] = [:]
    @Published var chatIsLoading: [String: Bool] = [:]
    
    // Singleton instance
    static let shared = ChatManager()
    
    // Private initializer for singleton
    private init() {
        self.chats = Self.loadChats()
        self.chatMessages = Self.loadMessages()
        self.chatHistories = Self.loadHistories()
        self.claudeHistories = Self.loadClaudeHistories()
    }
    
    // MARK: - Chat Management
    
    func createNewChat(modelId: String, modelName: String) -> ChatModel {
        let newChatId = UUID().uuidString
        let newChat = ChatModel(
            id: modelId,
            chatId: newChatId,
            name: modelName,
            title: "New Chat",
            description: "\(modelId)",
            provider: "Provider for \(modelId)",
            lastMessageDate: Date()
        )
        
        DispatchQueue.main.async {
            self.chats.append(newChat)
            self.chatMessages[newChatId] = []
            self.chatHistories[newChatId] = ""
            self.chatIsLoading[newChatId] = false
            self.objectWillChange.send()
            self.saveChats()
        }
        
        return newChat
    }
    
    func updateChatTitle(for chatId: String, title: String) {
        DispatchQueue.main.async {
            if let index = self.chats.firstIndex(where: { $0.chatId == chatId }) {
                self.chats[index].title = title
                self.saveChats()
                self.objectWillChange.send()
            }
        }
    }
    
    func clearAllChats() {
        DispatchQueue.main.async {
            self.chats.removeAll()
            self.chatMessages.removeAll()
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Message Management
    
    func setMessages(for chatId: String, messages: [MessageData]) {
        chatMessages[chatId] = messages
    }
    
    func getMessages(for chatId: String) -> [MessageData] {
        return chatMessages[chatId] ?? []
    }
    
    func setMessagesBatch(for chatId: String, messages: [MessageData]) {
        DispatchQueue.main.async {
            self.chatMessages[chatId] = messages
        }
    }
    
    // MARK: - History Management
    
    func setHistory(for chatId: String, history: String) {
        chatHistories[chatId] = history
    }
    
    func getHistory(for chatId: String) -> String {
        return chatHistories[chatId] ?? ""
    }
    
    func addClaudeHistory(for chatId: String, message: ClaudeMessageRequest.Message) {
        if var messages = claudeHistories[chatId] {
            messages.append(message)
            claudeHistories[chatId] = messages
        } else {
            claudeHistories[chatId] = [message]
        }
    }
    
    func getClaudeHistory(for chatId: String) -> [ClaudeMessageRequest.Message]? {
        return claudeHistories[chatId]
    }
    
    // MARK: - Loading State Management
    
    func setIsLoading(for chatId: String, isLoading: Bool) {
        chatIsLoading[chatId] = isLoading
    }
    
    func getIsLoading(for chatId: String) -> Bool {
        return chatIsLoading[chatId] ?? false
    }
    
    func updateMessagesAndLoading(for chatId: String, messages: [MessageData], isLoading: Bool) {
        DispatchQueue.main.async {
            self.chatMessages[chatId] = messages
            self.chatIsLoading[chatId] = isLoading
        }
    }
    
    // MARK: - Persistence
    
    func saveChats() {
        let chatSnapshots = chats.map(ChatModelSnapshot.init)
        if let encodedChats = try? JSONEncoder().encode(chatSnapshots),
           let encodedMessages = try? JSONEncoder().encode(chatMessages) {
            UserDefaults.standard.set(encodedChats, forKey: "SavedChats")
            UserDefaults.standard.set(encodedMessages, forKey: "SavedMessages")
        }
    }
    
    private static func loadChats() -> [ChatModel] {
        if let savedChats = UserDefaults.standard.object(forKey: "SavedChats") as? Data {
            if let decodedChatSnapshots = try? JSONDecoder().decode([ChatModelSnapshot].self, from: savedChats) {
                return decodedChatSnapshots.map { $0.toChatModel() }
            }
        }
        return []
    }
    
    private static func loadMessages() -> [String: [MessageData]] {
        if let savedMessages = UserDefaults.standard.object(forKey: "SavedMessages") as? Data {
            if let decodedMessages = try? JSONDecoder().decode([String: [MessageData]].self, from: savedMessages) {
                return decodedMessages
            }
        }
        return [:]
    }
    
    func saveHistories() {
        if let encodedHistories = try? JSONEncoder().encode(claudeHistories) {
            UserDefaults.standard.set(encodedHistories, forKey: "SavedHistories")
        }
    }
    
    private static func loadHistories() -> [String: String] {
        if let savedHistories = UserDefaults.standard.object(forKey: "SavedHistories") as? Data {
            if let decodedHistories = try? JSONDecoder().decode([String: String].self, from: savedHistories) {
                return decodedHistories
            }
        }
        return [:]
    }
    
    func saveClaudeHistories() {
        if let encodedHistories = try? JSONEncoder().encode(claudeHistories) {
            UserDefaults.standard.set(encodedHistories, forKey: "SavedClaudeHistories")
        }
    }
    
    private static func loadClaudeHistories() -> [String: [ClaudeMessageRequest.Message]] {
        if let savedHistories = UserDefaults.standard.object(forKey: "SavedClaudeHistories") as? Data {
            if let decodedHistories = try? JSONDecoder().decode([String: [ClaudeMessageRequest.Message]].self, from: savedHistories) {
                return decodedHistories
            }
        }
        return [:]
    }
}
