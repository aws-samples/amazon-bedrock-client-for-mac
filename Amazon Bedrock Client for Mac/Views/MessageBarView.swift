//
//  MessageBarView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

/**
 * Modal view for displaying full-sized image previews.
 * Shows the original image with filename and provides close functionality.
 */
struct ImagePreviewModal: View {
    var image: NSImage
    var filename: String
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 10) {
            // Header with filename and close button
            HStack {
                Text(filename)
                    .font(.headline)
                Spacer()
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            
            // Full-sized image preview
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 800, maxHeight: 600)
                .background(Color.black.opacity(0.05))
                .cornerRadius(8)
            
            Spacer()
            
            // Footer with close button
            Button("Close") {
                isPresented = false
            }
            .keyboardShortcut(.escape, modifiers: [])
            .padding(.bottom)
        }
        .frame(width: 850, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

/**
 * Clickable attachment file view for the message bar.
 * Displays a thumbnail, filename, and file type with delete functionality.
 */
struct AttachmentFileView: View {
    var image: NSImage
    var filename: String
    var fileExtension: String
    var onDelete: () -> Void
    var onClick: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            // Clickable file thumbnail and info
            Button(action: onClick) {
                HStack(spacing: 10) {
                    // Image thumbnail
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .cornerRadius(4)
                        .clipped()
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        )
                    
                    // File metadata
                    VStack(alignment: .leading, spacing: 2) {
                        Text(filename)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        
                        Text("\(fileExtension.uppercased()) image")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.gray.opacity(0.1)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

struct ImageAttachment: Identifiable {
    let id = UUID()
    let image: NSImage
    var fileExtension: String
    var filename: String
}

/**
 * Main message input bar view with image attachment handling.
 * Supports text input, image pasting/uploading, and various interaction modes.
 */
struct MessageBarView: View {
    // MARK: - Properties
    
    // Core identification and data
    var chatID: String
    @Binding var userInput: String
    @ObservedObject private var settingManager = SettingManager.shared
    @ObservedObject var chatManager: ChatManager = ChatManager.shared
    @StateObject var sharedImageDataSource: SharedImageDataSource
    var transcribeManager: TranscribeStreamingManager
    
    // UI state tracking
    @State private var calculatedHeight: CGFloat = 40
    @State private var isImagePickerPresented: Bool = false
    @State private var isLoading: Bool = false
    @State private var isPasting: Bool = false
    @State private var selectedImageIndex: Int? = nil
    @State private var showImagePreview: Bool = false
    @FocusState private var isInputFocused: Bool
    @State private var attachments: [ImageAttachment] = []
    
    // Action handlers
    var sendMessage: () async -> Void
    var cancelSending: () -> Void
    var modelId: String
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Attachment list (shown when images are present)
            if !sharedImageDataSource.images.isEmpty {
                attachmentListView
                    .transition(.opacity)
            }
            
            // Message input bar with buttons
            HStack(alignment: .center, spacing: 2) {
                fileUploadButton
                advancedOptionsButton
                inputArea
                
                HStack(spacing: 4) {
                    micButton
                    sendButton
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            
            // Loading indicator for image processing
            if isPasting {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Processing images...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 34)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPasting)
        .animation(.easeInOut(duration: 0.2), value: sharedImageDataSource.images.count)
        .foregroundColor(Color.text)
        .onExitCommand {
            if isLoading { cancelSending() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
    }
    
    // MARK: - Views
    
    /// Displays the list of attached images with preview capabilities
    private var attachmentListView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Attachments")
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 34)
                .padding(.top, 8)
            
            // 동적 높이를 위한 VStack으로 변경
            VStack(spacing: 6) {
                ForEach(attachments) { attachment in
                    AttachmentFileView(
                        image: attachment.image,
                        filename: attachment.filename,
                        fileExtension: attachment.fileExtension,
                        onDelete: {
                            if let index = attachments.firstIndex(where: { $0.id == attachment.id }) {
                                attachments.remove(at: index)
                                
                                if index < sharedImageDataSource.images.count {
                                    sharedImageDataSource.images.remove(at: index)
                                }
                                if index < sharedImageDataSource.fileExtensions.count {
                                    sharedImageDataSource.fileExtensions.remove(at: index)
                                }
                                if index < sharedImageDataSource.filenames.count {
                                    sharedImageDataSource.filenames.remove(at: index)
                                }
                            }
                        },
                        onClick: {
                            if let index = attachments.firstIndex(where: { $0.id == attachment.id }) {
                                selectedImageIndex = index
                                showImagePreview = true
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showImagePreview) {
            if let index = selectedImageIndex,
               index < sharedImageDataSource.images.count {
                ImagePreviewModal(
                    image: sharedImageDataSource.images[index],
                    filename: getFileName(for: index),
                    isPresented: $showImagePreview
                )
            }
        }
        .onAppear {
            syncAttachments()
        }
        .onChange(of: sharedImageDataSource.images.count) { _ in
            syncAttachments()
        }
    }
    
    /**
     * Separate view component for the advanced options menu.
     * This isolates complex menu structure to avoid compiler type-checking timeouts.
     */
    struct AdvancedOptionsMenu: View {
        @Binding var userInput: String
        @ObservedObject var settingManager: SettingManager
        var modelId: String
        
        var body: some View {
            Menu {
                Text("More Options")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                if modelId.contains("3-7") {
                    Toggle("Enable Thinking", isOn: $settingManager.enableModelThinking)
                        .help("Allow Claude 3.7 to show its thinking process")
                }
                
                Toggle("Allow Image Pasting", isOn: $settingManager.allowImagePasting)
                    .help("Enable or disable image pasting functionality")
                
                // MCP tools section
                if settingManager.mcpEnabled && !MCPManager.shared.toolInfos.isEmpty {
                    Divider()
                    
                    Text("Available Tools").bold()
                    
                    ForEach(MCPManager.shared.toolInfos) { tool in
                        Button {
                            userInput += "\n/tool \(tool.serverName).\(tool.toolName)"
                        } label: {
                            Label(tool.toolName, systemImage: "bolt.fill")
                        }
                        .help(tool.description)
                    }
                }
                
                if !settingManager.systemPrompt.isEmpty {
                    Divider()
                    
                    Button {
                        let alert = NSAlert()
                        alert.messageText = "System Prompt"
                        alert.informativeText = settingManager.systemPrompt
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    } label: {
                        Label("View System Prompt", systemImage: "info.circle")
                    }
                }
            } label: {
                Image(systemName: settingManager.mcpEnabled && !MCPManager.shared.toolInfos.isEmpty
                      ? "plus.circle.fill"
                      : "plus.circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.primary)
            }
            .buttonStyle(PlainButtonStyle())
            .menuIndicator(.hidden)
            .frame(width: 32, height: 32)
        }
    }
    
    /// Advanced options button with contextual menu
    private var advancedOptionsButton: some View {
        AdvancedOptionsMenu(
            userInput: $userInput,
            settingManager: settingManager,
            modelId: modelId
        )
    }
    
    /// File upload button with file picker
    private var fileUploadButton: some View {
        Button(action: {
            isImagePickerPresented = true
        }) {
            Image(systemName: "paperclip")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 32, height: 32)
        .fileImporter(
            isPresented: $isImagePickerPresented,
            allowedContentTypes: [.jpeg, .png, .gif, .tiff, .webP],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                // Limit to 10 images
                let maxToAdd = min(10 - sharedImageDataSource.images.count, urls.count)
                let urlsToProcess = urls.prefix(maxToAdd)
                
                for url in urlsToProcess {
                    if let image = NSImage(contentsOf: url) {
                        sharedImageDataSource.images.append(image)
                        sharedImageDataSource.fileExtensions.append(url.pathExtension)
                        sharedImageDataSource.filenames.append(url.lastPathComponent)
                    }
                }
            case .failure(let error):
                print("Failed to import images: \(error.localizedDescription)")
            }
        }
    }
    
    /// Microphone button for voice transcription
    private var micButton: some View {
        Button(action: {
            Task {
                if transcribeManager.isTranscribing {
                    transcribeManager.stopTranscription()
                } else {
                    await transcribeManager.startTranscription()
                }
            }
        }) {
            Image(systemName: transcribeManager.isTranscribing ? "mic.fill" : "mic")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(transcribeManager.isTranscribing ? .red : .primary)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 28, height: 28)
    }
    
    /// Main text input area with paste handling
    private var inputArea: some View {
        FirstResponderTextView(
            text: $userInput,
            isDisabled: .constant(false),
            calculatedHeight: $calculatedHeight,
            isPasting: $isPasting,
            onCommit: {
                if !userInput.isEmpty || !sharedImageDataSource.images.isEmpty {
                    Task {
                        await sendMessage()
                        transcribeManager.resetTranscript()
                    }
                }
            },
            onPaste: { image in
                if settingManager.allowImagePasting {
                    // Limit to 10 images
                    if sharedImageDataSource.images.count < 10 {
                        if let compressedData = image.compressedData(maxFileSize: 1024 * 1024, maxDimension: 1024, format: ImageFormat.jpeg),
                           let compressedImage = NSImage(data: compressedData) {
                            sharedImageDataSource.images.append(compressedImage)
                            sharedImageDataSource.fileExtensions.append("jpeg")
                            
                            // Create unique timestamp-based filename
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
                            sharedImageDataSource.filenames.append("pasted_image_\(dateFormatter.string(from: Date())).jpeg")
                        } else {
                            sharedImageDataSource.images.append(image)
                            sharedImageDataSource.fileExtensions.append("png")
                            
                            // Create unique timestamp-based filename
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
                            sharedImageDataSource.filenames.append("pasted_image_\(dateFormatter.string(from: Date())).png")
                        }
                    }
                }
            }
        )
        .focused($isInputFocused)
        .frame(minHeight: 40, maxHeight: calculatedHeight)
        .onReceive(transcribeManager.$transcript) { newTranscript in
            guard !newTranscript.isEmpty else { return }
            
            DispatchQueue.main.async {
                // Handle space between words
                if !userInput.isEmpty && !userInput.hasSuffix(" ") {
                    userInput += " "
                }
                
                // Process transcript words
                let words = newTranscript.split(separator: " ")
                if let lastWord = words.last {
                    let previousWords = userInput.split(separator: " ")
                    if let prevWord = previousWords.last,
                       prevWord.lowercased() == lastWord.lowercased() {
                        // Skip duplicate word
                    } else {
                        userInput = newTranscript
                    }
                } else {
                    userInput = newTranscript
                }
                
                // Notify for transcript update
                NotificationCenter.default.post(
                    name: .transcriptUpdated,
                    object: nil
                )
            }
        }
        .onAppear {
            NotificationCenter.default.addObserver(
                forName: .transcriptUpdated,
                object: nil,
                queue: .main
            ) { _ in }
        }
    }
    
    /// Send/Cancel button
    private var sendButton: some View {
        Button(action: {
            if isLoading {
                cancelSending()
            } else if !userInput.isEmpty || !sharedImageDataSource.images.isEmpty {
                Task {
                    await sendMessage()
                    transcribeManager.resetTranscript()
                }
            }
        }) {
            Image(systemName: isLoading ? "stop.fill" : "arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.black)
                        .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(userInput.isEmpty && sharedImageDataSource.images.isEmpty && !isLoading)
        .opacity((userInput.isEmpty && sharedImageDataSource.images.isEmpty && !isLoading) ? 0.6 : 1)
        .onChange(of: chatManager.getIsLoading(for: chatID)) { isLoading = $0 }
    }
    
    // MARK: - Helper Methods
    
    /// Get appropriate filename for the image at the specified index
    private func getFileName(for index: Int) -> String {
        // Use original filename if available
        if index < sharedImageDataSource.filenames.count,
           !sharedImageDataSource.filenames[index].isEmpty {
            return sharedImageDataSource.filenames[index]
        }
        
        // Fallback to extension with timestamp
        let ext = index < sharedImageDataSource.fileExtensions.count ?
            sharedImageDataSource.fileExtensions[index] : "img"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        return "attachment_\(dateFormatter.string(from: Date())).\(ext)"
    }
    
    private func syncAttachments() {
        // 기존 attachments 유지하면서 필요한 항목만 추가/제거
        let currentCount = attachments.count
        let targetCount = sharedImageDataSource.images.count
        
        if currentCount < targetCount {
            // 새 이미지 추가
            for i in currentCount..<targetCount {
                let ext = i < sharedImageDataSource.fileExtensions.count ?
                    sharedImageDataSource.fileExtensions[i] : "img"
                let filename = i < sharedImageDataSource.filenames.count ?
                    sharedImageDataSource.filenames[i] : getFileName(for: i)
                
                attachments.append(ImageAttachment(
                    image: sharedImageDataSource.images[i],
                    fileExtension: ext,
                    filename: filename
                ))
            }
        } else if currentCount > targetCount {
            // 초과 이미지 제거
            attachments = Array(attachments.prefix(targetCount))
        }
    }
}

enum ImageFormat: String, Codable {
    case jpeg
    case png
    case gif
    case webp
}

extension NSImage {
    func compressedData(maxFileSize: Int, maxDimension: CGFloat, format: ImageFormat) -> Data? {
        // Get the best representation of the image
        guard let tiffData = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        // Scale down the image if needed
        let scaledImage: NSBitmapImageRep
        if self.size.width > maxDimension || self.size.height > maxDimension {
            let scale = min(maxDimension / self.size.width, maxDimension / self.size.height)
            let newWidth = self.size.width * scale
            let newHeight = self.size.height * scale
            
            // Create a new bitmap representation for the scaled image
            guard let resizedImage = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(newWidth),
                pixelsHigh: Int(newHeight),
                bitsPerSample: bitmapImage.bitsPerSample,
                samplesPerPixel: bitmapImage.samplesPerPixel,
                hasAlpha: bitmapImage.hasAlpha,
                isPlanar: bitmapImage.isPlanar,
                colorSpaceName: bitmapImage.colorSpaceName,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else {
                return nil
            }
            
            resizedImage.size = NSSize(width: newWidth, height: newHeight)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resizedImage)
            self.draw(in: NSRect(x: 0, y: 0, width: newWidth, height: newHeight), from: .zero, operation: .copy, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            
            scaledImage = resizedImage
        } else {
            scaledImage = bitmapImage
        }
        
        // Compress the image with the specified format
        let properties: [NSBitmapImageRep.PropertyKey: Any]
        switch format {
        case .jpeg:
            properties = [.compressionFactor: 0.8]
            return scaledImage.representation(using: .jpeg, properties: properties)
        case .png:
            properties = [:]
            return scaledImage.representation(using: .png, properties: properties)
        case .gif:
            print("GIF format not directly supported in macOS. Falling back to PNG.")
            properties = [:]
            return scaledImage.representation(using: .png, properties: properties)
        case .webp:
            print("WebP format not directly supported in macOS. Falling back to PNG.")
            properties = [:]
            return scaledImage.representation(using: .png, properties: properties)
        }

    }
}
