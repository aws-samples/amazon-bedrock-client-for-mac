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
    var channelName: String
    var channelDescription: String
    var channelId: String
    
    @ObservedObject var messageManager: ChannelManager = ChannelManager.shared
    @ObservedObject var backendModel: BackendModel

    var body: some View {
        Channel(
            messages: $messages,  // Use a binding here
            backend: backendModel.backend  ,  // Pass the required backend
            modelId: modelId,  // Pass the required modelId
            modelName: modelName,  // Pass the required modelId
            channelId: channelId
        )
        .onChange(of: messages) { newMessages in
            messageManager.setMessages(for: channelId, messages: newMessages)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("# \(channelId)")
        .navigationSubtitle("\(channelDescription)")
        .background(Color.background)  // use the theme background
        .foregroundColor(Color.text)  // use the theme text color
        .textSelection(.enabled)
        .id(channelId)
    }
}
