//
//  MessageBarView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers


struct ImageViewer: View {
    var image: NSImage
    
    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: 300, height: 300)
            .cornerRadius(12)
            .shadow(radius: 7)
    }
}

struct MessageBarView: View {
    var chatID: String  // Identifier for the chat
    @Binding var userInput: String
    @Binding var messages: [MessageData]
    @ObservedObject var chatManager: ChatManager = ChatManager.shared
    @State private var calculatedHeight: CGFloat = 60
    @StateObject var sharedImageDataSource: SharedImageDataSource
    
    @State private var showImagePreview = false
    @State private var isImagePickerPresented = false
    @State private var isLoading: Bool = false
    
    var sendMessage: () async -> Void
    var cancelSending: () -> Void
    var modelId: String
    
    private var isSendButtonDisabled: Bool {
        userInput.isEmpty && sharedImageDataSource.images.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if !sharedImageDataSource.images.isEmpty {
                imagePreview
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                inputView
            }
            .padding()
            .background(Color.background)
            .frame(minHeight: 70, maxHeight: max(70, calculatedHeight))  // Set the maximum height
        }
        .foregroundColor(Color.text)
        .onExitCommand(perform: {
            if isLoading {
                cancelSending()
            }
        })
    }
    
    private var inputView: some View {
        HStack(alignment: .center, spacing: 10) {
            if isClaude3Model() {
                imageUploadButton
            }
            messageTextView
            sendButton
        }
    }
    
    private var imagePreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(sharedImageDataSource.images.indices, id: \.self) { index in
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: sharedImageDataSource.images[index])
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                            )
                        
                        // Delete button
                        Button(action: {
                            self.sharedImageDataSource.images.remove(at: index)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .background(Color.white)
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(2)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 5)
        }
        .frame(height: 110)
        .padding(.bottom, 10)
    }
    
    private var messageTextView: some View {
        VStack {
            FirstResponderTextView(
                text: $userInput,
                isDisabled: .constant(chatManager.getIsLoading(for: chatID)),  // Change here
                calculatedHeight: $calculatedHeight,  // Pass the binding
                onCommit: {
                    calculatedHeight = 70
                    Task { await sendMessage() }
                },
                onPaste: { image in
                    self.sharedImageDataSource.images.append(image)
                    self.showImagePreview = true
                }
            )
            .font(.system(size: 16))
            .textFieldStyle(PlainTextFieldStyle())
            .foregroundColor(Color.text)
            // Use GeometryReader to calculate the height
        }
    }
    
    // Send Button
    private var sendButton: some View {
        Button(action: {
            if isLoading {
                cancelSending()
            } else {
                Task { await sendMessage() }
            }
        }) {
            Image(systemName: isLoading ? "stop.fill" : "arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.background)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 25, height: 25)
        .background(Color.text)
        .clipShape(isLoading ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 5, style: .continuous)))
        .onChange(of: chatManager.getIsLoading(for: chatID)) { newIsLoading in
            self.isLoading = newIsLoading // Update isLoading when chatManager's loading state changes
        }
    }
    
    private func isClaude3Model() -> Bool {
        // Implement logic to determine if the model is "claude3" based on `chatID` or another property
        return modelId.contains("claude-3")
    }
    
    private var imageUploadButton: some View {
        Button(action: {
            isImagePickerPresented = true
        }) {
            Image(systemName: "photo")
                .font(.system(size: 15))
                .foregroundColor(Color.text)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 25, height: 25)
        .cornerRadius(5)
        .onHover { hover in
            if hover {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .fileImporter(isPresented: $isImagePickerPresented, allowedContentTypes: [
            UTType.jpeg,
            UTType.png,
            UTType.webP,
            UTType.gif
        ], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    if let image = NSImage(contentsOf: url) {
                        self.sharedImageDataSource.images.append(image)
                        
                        // Extract and append file extension
                        let fileExtension = url.pathExtension
                        self.sharedImageDataSource.fileExtensions.append(fileExtension)
                    }
                }
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }
}
