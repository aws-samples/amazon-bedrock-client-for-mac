//
//  ChatModelSnapshot.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2024/01/04.
//

import Foundation

struct ChatModelSnapshot: Codable {
    let id: String
    let chatId: String
    let name: String
    var title: String
    let description: String
    let provider: String
    let lastMessageDate: Date

    init(from chatModel: ChatModel) {
        id = chatModel.id
        chatId = chatModel.chatId
        name = chatModel.name
        title = chatModel.title
        description = chatModel.description
        provider = chatModel.provider
        lastMessageDate = chatModel.lastMessageDate
    }

    func toChatModel() -> ChatModel {
        return ChatModel(id: id, chatId: chatId, name: name, title: title, description: description, provider: provider, lastMessageDate: lastMessageDate)
    }
}
