//
//  ChatManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/09.
//

import Combine
import SwiftUI

class ChatManager: ObservableObject {
    // Add a dictionary to track loading states for various chats
    @Published var chats: [ChatModel] {
        didSet {
            saveChats()
        }
    }
    @Published var chatMessages: [String: [MessageData]] = [:]
    @Published var chatHistories: [String: String] = [:]
    @Published var chatIsLoading: [String: Bool] = [:]
    
    // Singleton instance
    static let shared = ChatManager()
    
    private init() {
        self.chats = Self.loadChats()
        self.chatMessages = Self.loadMessages()
    }

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
    
    var selectedModelId: String?  // Holds the currently selected model ID
    
    func createNewChat(modelId: String, modelName: String) -> ChatModel {
        let newChatId = UUID().uuidString
        let newChat = ChatModel(
            id: modelId,
            chatId: newChatId,
            name: modelName,
            title: "New Chat",
            description: "Chat with \(modelId)",
            provider: "Provider for \(modelId)",
            lastMessageDate: Date()
        )
        
        DispatchQueue.main.async {
            self.chats.append(newChat)
            self.chatMessages[newChatId] = []
            self.chatHistories[newChatId] = ""
            self.chatIsLoading[newChatId] = false
            // Trigger the sidebar to update
            self.objectWillChange.send()
            self.saveChats()
        }
        
        return newChat
    }
    
    func updateChatTitle(for chatId: String, title: String) {
        DispatchQueue.main.async {
            // Find the chat by ID and update its title
            if let index = self.chats.firstIndex(where: { $0.chatId == chatId }) {
                self.chats[index].title = title
                self.saveChats()
                self.objectWillChange.send()  // Notify observers of the change
            }
        }
    }
    
    // Other methods to manage chat state
    func setMessages(for chatId: String, messages: [MessageData]) {
        chatMessages[chatId] = messages
    }
    
    func setHistory(for chatId: String, history: String) {
        chatHistories[chatId] = history // Set history for a specific chat
    }
    
    func getHistory(for chatId: String) -> String {
        return chatHistories[chatId] ?? "" // Retrieve history for a specific chat
    }
    
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
    
    func setMessagesBatch(for chatId: String, messages: [MessageData]) {
        DispatchQueue.main.async {
            self.chatMessages[chatId] = messages
        }
    }
}
