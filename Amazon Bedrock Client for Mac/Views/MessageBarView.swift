//
//  MessageBar.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import Combine

struct MessageBarView: View {
    var chatID: String  // Identifier for the chat
    @Binding var userInput: String
    @Binding var messages: [MessageData]
    @ObservedObject var messageManager: ChatManager = ChatManager.shared
    @State private var calculatedHeight: CGFloat = 60  // Add this line

    var sendMessage: () async -> Void
    
    private var isSendButtonDisabled: Bool {
        userInput.isEmpty || messageManager.getIsLoading(for: chatID)
    }
    
    private var sendButtonIcon: String {
        messageManager.getIsLoading(for: chatID) ? "ellipsis.circle" : "paperplane.fill"
    }

    private var sendButtonColor: Color {
        if messageManager.getIsLoading(for: chatID) {
            return Color.background
        } else {
            return isSendButtonDisabled ? Color.secondaryText : Color.text
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
            isDisabled: .constant(messageManager.getIsLoading(for: chatID)),  // Change here
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
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.background)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 25, height: 25)
        .background(sendButtonColor)
        .cornerRadius(5)
//        .shadow(radius: 2)
        .disabled(isSendButtonDisabled)
        .onChange(of: messageManager.getIsLoading(for: chatID)) { newIsLoading in
            self.isLoading = newIsLoading
        }
    }

}

