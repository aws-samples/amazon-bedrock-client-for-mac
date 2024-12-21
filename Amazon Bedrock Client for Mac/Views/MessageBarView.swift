//
//  MessageBarView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

/// A view that displays a resizable image with rounded corners and a shadow effect.
struct ImageViewer: View {
    var image: NSImage
    
    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: 100, height: 100)
            .cornerRadius(12)
            .shadow(radius: 7)
    }
}

/// Main user interface for managing text input and image uploads for messaging.
struct MessageBarView: View {
    var chatID: String
    @Binding var userInput: String
    @ObservedObject var chatManager: ChatManager = ChatManager.shared
    @StateObject var sharedImageDataSource: SharedImageDataSource
    
    @State private var calculatedHeight: CGFloat = 40
    @State private var isImagePickerPresented: Bool = false
    @State private var isLoading: Bool = false
    
    var sendMessage: () async -> Void
    var cancelSending: () -> Void
    var modelId: String
    
    var body: some View {
        VStack {
            if !sharedImageDataSource.images.isEmpty {
                imagePreview
            }
            
            HStack(alignment: .bottom) {
                fileUploadButton
                    .padding(.bottom, 4)
                Spacer()
                inputArea
                    .background(RoundedRectangle(cornerRadius: 30).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    .padding(.top, 4)
                Spacer()
                sendButton
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .foregroundColor(Color.text)
        .onExitCommand(perform: {
            if isLoading {
                cancelSending()
            }
        })
        //        .animation(.default, value: calculatedHeight)
    }
    
    private var imagePreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(sharedImageDataSource.images.indices, id: \.self) { index in
                    ImageViewer(image: sharedImageDataSource.images[index])
                        .overlay(deleteButton(at: index), alignment: .topTrailing)
                }
            }
            .padding(.horizontal)
            .frame(height: 110)
        }
    }
    
    private func deleteButton(at index: Int) -> some View {
        Button(action: {
            sharedImageDataSource.images.remove(at: index)
        }) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.gray)
                .background(Color.white)
                .clipShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .padding(2)
    }
    
    private var inputArea: some View {
        FirstResponderTextView(
            text: $userInput,
            isDisabled: .constant(false),
            calculatedHeight: $calculatedHeight,
            onCommit: {             if !userInput.isEmpty {
                Task { await sendMessage() }
            } },
            onPaste: { image in
                if let compressedData = image.compressedData(maxFileSize: 1024 * 1024, format: .jpeg),
                   let compressedImage = NSImage(data: compressedData) {
                    sharedImageDataSource.images.append(compressedImage)
                    sharedImageDataSource.fileExtensions.append("jpeg")
                } else {
                    sharedImageDataSource.images.append(image)
                    sharedImageDataSource.fileExtensions.append("png")
                }
            }
        )
        .frame(minHeight: 40, maxHeight: calculatedHeight)
        .padding(.horizontal, 12)
    }
    
    private var fileUploadButton: some View {
        Button(action: {
            isImagePickerPresented = true
        }) {
            Image(systemName: "paperclip")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color.text)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .fileImporter(isPresented: $isImagePickerPresented, allowedContentTypes: [.jpeg, .png], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                urls.forEach { url in
                    if let image = NSImage(contentsOf: url) {
                        self.sharedImageDataSource.images.append(image)
                        
                        // Extract and append file extension
                        let fileExtension = url.pathExtension
                        self.sharedImageDataSource.fileExtensions.append(fileExtension)
                    }
                }
            case .failure(let error):
                print("Failed to import images: \(error.localizedDescription)")
            }
        }
    }
    
    private var sendButton: some View {
        Button(action: {
            if isLoading {
                cancelSending()
            } else {
                Task { await sendMessage() }
            }
        }) {
            Image(systemName: isLoading ? "stop.fill" : "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color.background)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 32, height: 32)
        .background(Color.text)
        .clipShape(Circle())
        .disabled(userInput.isEmpty && !isLoading)
        .onChange(of: chatManager.getIsLoading(for: chatID)) { isLoading = $0 }
    }
    
    /// Determines if the user's device or server model corresponds to "claude-3".
    private func isClaude3Model() -> Bool {
        return modelId.contains("claude-3")
    }
}

extension NSImage {
    func compressedData(maxFileSize: Int, format: NSBitmapImageRep.FileType = .jpeg) -> Data? {
        guard let tiffRepresentation = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        
        var compressionFactor: CGFloat = 1.0
        var compressedData: Data?
        
        while compressionFactor > 0.0 {
            let properties: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: compressionFactor]
            compressedData = bitmapImage.representation(using: format, properties: properties)
            
            if let data = compressedData, data.count <= maxFileSize {
                return data
            }
            compressionFactor -= 0.1
        }
        
        return compressedData
    }
}
