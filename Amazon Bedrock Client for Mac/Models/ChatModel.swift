//
//  ChatModel.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import Foundation
import AWSBedrock

class ChatModel: ObservableObject, Identifiable, Equatable, Hashable, @unchecked Sendable {
    var id: String
    var chatId: String
    var name: String
    @Published var title: String
    var description: String
    let provider: String
    @Published var lastMessageDate: Date
    var isManuallyRenamed: Bool = false // Track if user manually renamed this chat
    
    init(id: String, chatId: String, name: String, title: String, description: String, provider: String, lastMessageDate: Date, isManuallyRenamed: Bool = false) {
        self.id = id
        self.chatId = chatId
        self.name = name
        self.title = title
        self.description = description
        self.provider = provider
        self.lastMessageDate = lastMessageDate
        self.isManuallyRenamed = isManuallyRenamed
    }
    
    static func == (lhs: ChatModel, rhs: ChatModel) -> Bool {
        lhs.chatId == rhs.chatId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(chatId)
    }
    
    static func fromSummary(_ summary: BedrockClientTypes.FoundationModelSummary) -> ChatModel {
        ChatModel(
            id: summary.modelId ?? "",
            chatId: UUID().uuidString,
            name: summary.modelName ?? "",
            title: "New Chat",
            description: "\(summary.providerName ?? "") \(summary.modelName ?? "") (\(summary.modelId ?? ""))",
            provider: summary.providerName ?? "",
            lastMessageDate: Date()
        )
    }
    
    static func fromInferenceProfile(_ profileSummary: BedrockClientTypes.InferenceProfileSummary) -> ChatModel {
        return ChatModel(
            id: profileSummary.inferenceProfileId ?? "Unknown Id",  // Provide default if nil
            chatId: UUID().uuidString,  // Generate unique chatId
            name: profileSummary.inferenceProfileName ?? "Unknown Profile",  // Provide default if nil
            title: "Inference Profile: \(profileSummary.inferenceProfileName ?? "Unknown")",  // Provide default if nil
            description: profileSummary.description ?? "No description available",  // Provide default if nil
            provider: profileSummary.type?.rawValue ?? "Unknown Type",  // Use rawValue or default if nil
            lastMessageDate: profileSummary.updatedAt ?? Date()  // Use current date as default
        )
    }
}
