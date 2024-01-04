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
    //    @Binding var chatMessages: [ChatModel: [MessageData]]
    @ObservedObject var backendModel: BackendModel
    @ObservedObject var chatManager: ChatManager = ChatManager.shared

    var organizedChatModels: [String: [ChatModel]]
    
    // Function to get a Binding<[MessageData]> for a specific chat
    private func messagesBinding(for chatId: String) -> Binding<[MessageData]> {
        Binding(
            get: { self.chatManager.chatMessages[chatId] ?? [] },
            set: { self.chatManager.chatMessages[chatId] = $0 }
        )
    }
    
    var body: some View {
        switch selection {
        case .newChat:
            HomeView(selection: $selection, menuSelection: $menuSelection)
        case .chat(let selectedChat):
            // Use the custom binding here
            let messagesBinding = messagesBinding(for: selectedChat.chatId)
            let messages = messagesBinding.wrappedValue  // 실제 메시지 배열을 가져옵니다.
            
            Chat(
                messages: messagesBinding,  // Use a binding here
                backend: backendModel.backend,  // Pass the required backend
                modelId: selectedChat.id,  // Pass the required modelId
                modelName: selectedChat.name,  // Pass the required modelName
                chatId: selectedChat.chatId
            )
            .textSelection(.enabled)
            .onChange(of: messages.count) { _ in  // 메시지 배열의 길이 변경 감지
                chatManager.setMessages(for: selectedChat.chatId, messages: messages)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.background)  // use the theme background
            .foregroundColor(Color.text)  // use the theme text color
            .id(selectedChat.chatId)
        case .none:
            Text("Select an option")
        }
    }
}
