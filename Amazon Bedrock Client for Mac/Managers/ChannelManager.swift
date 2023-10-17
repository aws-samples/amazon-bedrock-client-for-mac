//
//  ChannelManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/09.
//

import Combine
import SwiftUI

class ChannelManager: ObservableObject {
    // Add a dictionary to track loading states for various channels
    @Published var channelMessages: [String: [MessageData]] = [:]
    @Published var channelHistories: [String: String] = [:] // New dictionary to store histories
    @Published var channelIsLoading: [String: Bool] = [:]  // New dictionary for isLoading statuses
    @Published var channelLoadingStates: [String: Bool] = [:]
    
    // Singleton instance
    static let shared = ChannelManager()
    
    private init() {}
    
    // Other methods to manage channel state
    func setMessages(for channelId: String, messages: [MessageData]) {
        channelMessages[channelId] = messages
    }
    
    func setHistory(for channelId: String, history: String) {
        channelHistories[channelId] = history // Set history for a specific channel
    }
    
    func getHistory(for channelId: String) -> String {
        return channelHistories[channelId] ?? "" // Retrieve history for a specific channel
    }
    
    func setIsLoading(for channelId: String, isLoading: Bool) {
        channelIsLoading[channelId] = isLoading
    }

    func getIsLoading(for channelId: String) -> Bool {
        return channelIsLoading[channelId] ?? false
    }
    
    func updateMessagesAndLoading(for channelId: String, messages: [MessageData], isLoading: Bool) {
        DispatchQueue.main.async {
            self.channelMessages[channelId] = messages
            self.channelIsLoading[channelId] = isLoading
        }
    }
    
    func setMessagesBatch(for channelId: String, messages: [MessageData]) {
        DispatchQueue.main.async {
            self.channelMessages[channelId] = messages
        }
    }
}
