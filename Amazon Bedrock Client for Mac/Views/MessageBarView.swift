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
    @State private var calculatedHeight: CGFloat = 60  // Add this line
    @StateObject var sharedImageDataSource: SharedImageDataSource
    
    @State private var showImagePreview = false
    @State private var isImagePickerPresented = false
    
    var sendMessage: () async -> Void
    var modelId: String
    
    private var isSendButtonDisabled: Bool {
        return (userInput.isEmpty && sharedImageDataSource.images.isEmpty) || chatManager.getIsLoading(for: chatID)
    }
    
    private var sendButtonIcon: String {
        chatManager.getIsLoading(for: chatID) ? "ellipsis.circle" : "paperplane.fill"
    }
    
    private var sendButtonColor: Color {
        if chatManager.getIsLoading(for: chatID) {
            return Color.background
        } else {
            return isSendButtonDisabled ? Color.text : Color.text
        }
    }
    
    
    var body: some View {
        VStack(spacing: 0) {
            if !sharedImageDataSource.images.isEmpty {
                imagePreview
                    .transition(.opacity.combined(with: .slide))
                    .animation(.easeInOut, value: sharedImageDataSource.images)
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
        FirstResponderTextView(
            text: $userInput,
            isDisabled: .constant(chatManager.getIsLoading(for: chatID)),  // Change here
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
        .onChange(of: chatManager.getIsLoading(for: chatID)) { newIsLoading in
            self.isLoading = newIsLoading
        }
        .onHover { hover in
            if hover && !isSendButtonDisabled {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
    
    private func isClaude3Model() -> Bool {
        // Implement logic to determine if the model is "claude3" based on `chatID` or another property
        return modelId.contains("claude-3")
    }
    
    // 붙여넣기 처리를 위한 함수
//    private func handlePaste(itemProviders: [NSItemProvider]) {
//        for item in itemProviders {
//            // 이미지 유형 확인 및 처리
//            if item.canLoadObject(ofClass: NSImage.self) {
//                item.loadObject(ofClass: NSImage.self) { (image, error) in
//                    DispatchQueue.main.async {
//                        if let image = image as? NSImage {
//                            // 이미지 처리 로직 (예: 메모리에 임시 저장, 서버 업로드 등)
//                            uploadClipBoardImage(image: image)
//                        }
//                    }
//                }
//            } else if item.hasItemConformingToTypeIdentifier(kUTTypeFileURL as String) {
//                item.loadItem(forTypeIdentifier: kUTTypeFileURL as String, options: nil) { (urlData, error) in
//                    DispatchQueue.main.async {
//                        if let urlData = urlData as? Data, let url = NSURL(dataRepresentation: urlData, relativeTo: nil) as URL? {
//                            // 파일 URL에서 이미지 처리
//                            uploadImage(at: url)
//                        }
//                    }
//                }
//            }
//        }
//    }
//    
//    private func uploadImage(at url: URL) {
//        if let image = NSImage(contentsOf: url) {
//            self.sharedImageDataSource.images.append(image)
//            self.showImagePreview = true // 이미지 미리보기 창을 표시합니다.
//        }
//    }
    
    private func uploadClipBoardImage(image: NSImage) {
        print(image)
    }
    
    private var imageUploadButton: some View {
        Button(action: {
            // 이미지 피커를 열기 위해 isImagePickerPresented를 true로 설정
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

