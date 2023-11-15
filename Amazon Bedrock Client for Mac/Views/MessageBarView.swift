//
//  MessageBar.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import Combine

struct MessageBarView: View {
    var channelID: String  // Identifier for the channel
    @Binding var userInput: String
    @Binding var messages: [MessageData]
    @ObservedObject var messageManager: ChannelManager = ChannelManager.shared
    @State private var calculatedHeight: CGFloat = 60  // Add this line

    var sendMessage: () async -> Void
    
    private var isSendButtonDisabled: Bool {
        userInput.isEmpty || messageManager.getIsLoading(for: channelID)
    }
    
    private var sendButtonIcon: String {
        messageManager.getIsLoading(for: channelID) ? "ellipsis.circle" : "paperplane.fill"
    }

    private var sendButtonColor: Color {
        if messageManager.getIsLoading(for: channelID) {
            return Color.secondaryText
        } else {
            return isSendButtonDisabled ? Color.secondaryText : Color.link
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                inputView
            }
            .padding()
            .background(Color.background)
            .frame(minHeight: 70, maxHeight: max(70, calculatedHeight))  // Set the maximum height
        }
        .foregroundColor(Color.text)
    }
    
    private var inputView: some View {
        HStack(alignment: .center, spacing: 0) {
            messageTextView
            sendButton
        }
    }
    
    private var messageTextView: some View {
        FirstResponderTextView(
            text: $userInput,
            isDisabled: .constant(messageManager.getIsLoading(for: channelID)),  // Change here
            calculatedHeight: $calculatedHeight,  // Pass the binding
            onCommit: {
                calculatedHeight = 70
                Task { await sendMessage() }
            }
        )
        .font(.system(size: 16))
        .textFieldStyle(PlainTextFieldStyle())
        .foregroundColor(Color.text)
        // Use GeometryReader to calculate the height
    }
    
    @State private var isLoading: Bool = false  // Add this line
    
    private var sendButton: some View {
        Button(action: { Task { await sendMessage() } }) {
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: sendButtonIcon)
                    .foregroundColor(sendButtonColor)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isSendButtonDisabled)
        .onChange(of: messageManager.getIsLoading(for: channelID)) { newIsLoading in
            self.isLoading = newIsLoading
        }
    }
}

