//
//  Home.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import Combine

struct MainView: View {
    @Environment(\.colorScheme) var colorScheme

    
    @Binding var messages: [MessageData]
    @State var history: String = ""

    var modelId: String
    var modelName: String
    var chatName: String
    var chatDescription: String
    var chatId: String
    
    @ObservedObject var messageManager: ChatManager = ChatManager.shared
    @ObservedObject var backendModel: BackendModel

    var body: some View {
        Chat(
            messages: $messages,  // Use a binding here
            backend: backendModel.backend  ,  // Pass the required backend
            modelId: modelId,  // Pass the required modelId
            modelName: modelName,  // Pass the required modelId
            chatId: chatId
        )
        .onChange(of: messages) { newMessages in
            messageManager.setMessages(for: chatId, messages: newMessages)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
//        .navigationTitle("# \(chatId)")
//        .navigationSubtitle("\(chatDescription)")
        .background(Color.background)  // use the theme background
        .foregroundColor(Color.text)  // use the theme text color
        .textSelection(.enabled)
        .id(chatId)
    }
}
