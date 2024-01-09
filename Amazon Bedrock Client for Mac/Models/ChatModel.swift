//
//  ChatModel.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import Foundation
import AWSBedrock

class ChatModel: ObservableObject, Identifiable, Equatable, Hashable {
    var id: String
    let chatId: String
    var name: String
    @Published var title: String
    var description: String
    let provider: String
    @Published var lastMessageDate: Date
    
    init(id: String, chatId: String, name: String, title: String, description: String, provider: String, lastMessageDate: Date) {
        self.id = id
        self.chatId = chatId
        self.name = name
        self.title = title
        self.description = description
        self.provider = provider
        self.lastMessageDate = lastMessageDate
    }
    
    static func == (lhs: ChatModel, rhs: ChatModel) -> Bool {
        return lhs.id == rhs.id && lhs.chatId == rhs.chatId
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(chatId)
    }
    
    static func fromSummary(_ summary: BedrockClientTypes.FoundationModelSummary) -> ChatModel {
        return ChatModel(
            id: summary.modelId ?? "",
            chatId: UUID().uuidString,
            name: summary.modelName ?? "",
            title: "New Chat",
            description: "\(summary.providerName ?? "") \(summary.modelName ?? "") (\(summary.modelId ?? ""))",
            provider: summary.providerName ?? "",
            lastMessageDate: Date()
        )
    }
}
