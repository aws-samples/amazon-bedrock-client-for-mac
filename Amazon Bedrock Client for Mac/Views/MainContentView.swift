//
//  MainContentView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI

struct MainContentView: View {
    @Binding var selection: SidebarSelection?
    @Binding var menuSelection: SidebarSelection?
    @Binding var chatMessages: [ChatModel: [MessageData]]
    @ObservedObject var backendModel: BackendModel
    
    var organizedChatModels: [String: [ChatModel]]
    
    // Function to get a Binding<[MessageData]> for a specific chat
    func messagesBinding(for chat: ChatModel) -> Binding<[MessageData]> {
        return Binding(
            get: { self.chatMessages[chat, default: [MessageData]()] },
            set: { self.chatMessages[chat] = $0 }
        )
    }
    
    var body: some View {
        switch selection {
        case .newChat:
            HomeView(selection:$selection, menuSelection:$menuSelection)
        case .chat(let selectedChat):
            // Use the custom binding here
            let messages = messagesBinding(for: selectedChat)
            MainView(messages: messages,
                     modelId: selectedChat.id,
                     modelName: selectedChat.name,
                     chatName: selectedChat.title,
                     chatDescription: selectedChat.description,
                     chatId: selectedChat.chatId,
                     backendModel: backendModel)
            .textSelection(.enabled)
        case .none:
            Text("Select an option")
        }
    }
}

