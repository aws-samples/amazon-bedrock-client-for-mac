//
//  MainContentView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI

struct MainContentView: View {
    @Binding var selection: SidebarSelection?
    @Binding var channelMessages: [ChannelModel: [MessageData]]
    @ObservedObject var backendModel: BackendModel
    
    // Function to get a Binding<[MessageData]> for a specific channel
    func messagesBinding(for channel: ChannelModel) -> Binding<[MessageData]> {
        return Binding(
            get: { self.channelMessages[channel, default: [MessageData]()] },
            set: { self.channelMessages[channel] = $0 }
        )
    }
    
    var body: some View {
        switch selection {
        case .preferences:
            HomeView()
        case .channel(let selectedChannel):
            // Use the custom binding here
            let messages = messagesBinding(for: selectedChannel)
            MainView(messages: messages,
                 modelId: selectedChannel.id,
                 modelName: selectedChannel.name,
                 channelName: selectedChannel.name,
                 channelDescription: selectedChannel.description,
                 channelId: selectedChannel.id,
                 backendModel: backendModel)
            .textSelection(.enabled)
        case .none:
            Text("Select an option")
        }
    }
}

