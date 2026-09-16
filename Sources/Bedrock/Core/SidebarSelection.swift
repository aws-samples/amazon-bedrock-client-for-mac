//
//  SidebarSelection.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import Foundation

enum SidebarSelection: Hashable, Identifiable {
    var id: String {
        switch self {
        case .newChat:
            return "newChat"
        case .chat(let chat):
            return chat.chatId // Make sure to use `chatId` if it is the unique identifier
        }
    }
    
    case newChat
    case chat(ChatModel)
}
