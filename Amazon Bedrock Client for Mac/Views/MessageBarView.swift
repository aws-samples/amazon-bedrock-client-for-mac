//
//  MessageBarView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers
import Logging

/**
 * Main message input bar view with image attachment handling.
 * Supports text input, image pasting/uploading, and various interaction modes.
 */
struct MessageBarView: View {
    // MARK: - Properties
    var chatID: String
    @Binding var userInput: String
    @ObservedObject private var settingManager = SettingManager.shared
    @ObservedObject private var mcpManager = MCPManager.shared
    @ObservedObject var chatManager: ChatManager = ChatManager.shared
    @StateObject var sharedMediaDataSource: SharedMediaDataSource
    var transcribeManager: TranscribeStreamingManager
    
    // UI state tracking
    @State private var calculatedHeight: CGFloat = 40
    @State private var isImagePickerPresented: Bool = false
    @State private var isLoading: Bool = false
    @State private var isPasting: Bool = false
    @State private var showImagePreview: Bool = false
    @State private var selectedImageIndex: Int? = nil
    @FocusState private var isInputFocused: Bool
    @State private var attachments: [ImageAttachment] = []
    @State private var documentAttachments: [DocumentAttachment] = []
    
    // Action handlers
    var sendMessage: () async -> Void
    var cancelSending: () -> Void
    var modelId: String
    
    var logger = Logger(label: "MessageBarView")
    
    // MARK: - Liquid Glass Background (Messages App Style - macOS 26+ only)
    @ViewBuilder
    private var messageBarBackground: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
    }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Attachment list (when images or documents are present)
            if (!sharedMediaDataSource.images.isEmpty || !sharedMediaDataSource.documents.isEmpty) {
                AttachmentListView(
                    attachments: $attachments,
                    documentAttachments: $documentAttachments,
                    sharedMediaDataSource: sharedMediaDataSource,
                    selectedImageIndex: $selectedImageIndex,
                    showImagePreview: $showImagePreview,
                    onRemoveAttachment: removeAttachment,
                    onRemoveDocumentAttachment: removeDocumentAttachment,
                    onRemoveAllAttachments: removeAllAttachments
                )
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(messageBarBackground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            // Loading indicator
            if isPasting {
                PasteLoadingView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPasting)
        .animation(.easeInOut(duration: 0.2), value: sharedMediaDataSource.images.count)
        .foregroundColor(Color.text)
        .onExitCommand {
            if isLoading { cancelSending() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
        .sheet(isPresented: $showImagePreview) {
            if let index = selectedImageIndex,
               index < sharedMediaDataSource.images.count {
                ImagePreviewModal(
                    image: sharedMediaDataSource.images[index],
                    filename: getFileName(for: index),
                    isPresented: $showImagePreview
                )
            }
        }
        .onAppear {
            syncAttachments()
        }
        .onChange(of: sharedMediaDataSource.images.count) { _, _ in
            syncAttachments()
        }
    }
    
    // MARK: - UI Components
    
    private var advancedOptionsButton: some View {
        AdvancedOptionsMenu(
            userInput: $userInput,
            settingManager: settingManager,
            modelId: modelId
        )
    }
    
    private var fileUploadButton: some View {
        Button(action: {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.pdf, .commaSeparatedText, .html, .plainText, .jpeg, .png, .gif, .tiff, .webP,
                                          UTType(filenameExtension: "doc")!, UTType(filenameExtension: "docx")!,
                                          UTType(filenameExtension: "xls")!, UTType(filenameExtension: "xlsx")!,
                                          UTType(filenameExtension: "md")!].compactMap { $0 }
            panel.allowsMultipleSelection = true
            
            panel.begin { response in
                if response == .OK {
                    handleFileImport(panel.urls)
                }
            }
        }) {
            Image(systemName: "paperclip")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 32, height: 32)
    }
    
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
        // Prevent it from capturing keyboard events
        .focusable(false)
        // Explicitly prevent it from getting keyboard focus
        .accessibilityAddTraits(.isButton)
    }
    
    private var inputArea: some View {
        FirstResponderTextView(
            text: $userInput,
            isDisabled: .constant(false),
            calculatedHeight: $calculatedHeight,
            isPasting: $isPasting,
            allowImagePasting: settingManager.allowImagePasting,
            treatLargeTextAsFile: settingManager.treatLargeTextAsFile,
            onCommit: {
                handleSendMessage()
            },
            onPaste: { image in
                handleImagePaste(image)
            },
            onPasteDocument: { url in
                handleFileImport([url])
            },
            onPasteLargeText: { text, filename in
                handleLargeTextPaste(text, filename: filename)
            }
        )
        .focused($isInputFocused)
        .frame(minHeight: 40, maxHeight: calculatedHeight)
        .onReceive(transcribeManager.$transcript) { newTranscript in
            handleTranscriptUpdate(newTranscript)
        }
        .onAppear {
            setupEscapeKeyHandler()
            setupTranscriptObserver()
        }
    }
    
    private var sendButton: some View {
        Button(action: {
            if isLoading {
                cancelSending()
            } else if !userInput.isEmpty || !sharedMediaDataSource.images.isEmpty || !sharedMediaDataSource.documents.isEmpty {
                handleSendMessage()
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
        .disabled(userInput.isEmpty && sharedMediaDataSource.images.isEmpty && sharedMediaDataSource.documents.isEmpty && !isLoading)
        .opacity((userInput.isEmpty && sharedMediaDataSource.images.isEmpty && sharedMediaDataSource.documents.isEmpty && !isLoading) ? 0.6 : 1)
        .onChange(of: chatManager.getIsLoading(for: chatID)) { _, newValue in
            isLoading = newValue
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleSendMessage() {
        Task {
            await sendMessage()
            transcribeManager.resetTranscript()
        }
    }
    
    private func setupEscapeKeyHandler() {
        // Create a monitor for local key down events
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 && self.isLoading { // ESC key
                // Check if any modal/sheet is open
                // SwiftUI sheets open as separate windows, so check if key window is a sheet
                // or if any window has sheets attached
                if let keyWindow = NSApp.keyWindow {
                    // Check if current key window is a sheet (has a parent)
                    if keyWindow.sheetParent != nil {
                        return event // Let the sheet handle ESC
                    }
                    // Check if any window has sheets
                    if keyWindow.sheets.count > 0 {
                        return event // Let the sheet handle ESC
                    }
                }
                
                DispatchQueue.main.async {
                    self.cancelSending()
                }
                return nil // Consume the event
            }
            return event // Pass other events through
        }
    }
    
    private func handleFileImport(_ urls: [URL]) {
        // Bedrock API limits: max 20 images, max 5 documents per request
        let maxImages = 20
        let maxDocuments = 5
        
        for url in urls {
            let fileExtension = url.pathExtension.lowercased()
            
            // Handle image files (max 20)
            if ["jpg", "jpeg", "png", "gif", "tiff", "webp"].contains(fileExtension) {
                guard sharedMediaDataSource.images.count < maxImages else {
                    logger.info("Maximum images (\(maxImages)) reached, skipping: \(url.lastPathComponent)")
                    continue
                }
                if let image = NSImage(contentsOf: url) {
                    logger.info("Adding image: \(url.lastPathComponent)")
                    sharedMediaDataSource.addImage(image, fileExtension: fileExtension, filename: url.lastPathComponent)
                }
            }
            // Handle document files (max 5)
            else if ["pdf", "csv", "doc", "docx", "xls", "xlsx", "html", "txt", "md"].contains(fileExtension) {
                guard sharedMediaDataSource.documents.count < maxDocuments else {
                    logger.info("Maximum documents (\(maxDocuments)) reached, skipping: \(url.lastPathComponent)")
                    continue
                }
                do {
                    let fileData = try Data(contentsOf: url)
                    let sanitizedName = sanitizeDocumentName(url.lastPathComponent)
                    
                    logger.info("Adding document: \(sanitizedName), size: \(fileData.count) bytes")
                    sharedMediaDataSource.addDocument(fileData, fileExtension: fileExtension, filename: sanitizedName)
                } catch {
                    logger.info("Error loading document: \(error.localizedDescription)")
                }
            }
        }
        
        // Update attachment list after processing files
        syncAttachments()
    }

    
    private func handleImagePaste(_ image: NSImage) {
        if settingManager.allowImagePasting {
            if sharedMediaDataSource.images.count < 10 {
                Task {
                    isPasting = true
                    let (compressedImage, filename, fileExtension) = await processImageInParallel(image)
                    sharedMediaDataSource.addImage(compressedImage, fileExtension: fileExtension, filename: filename)
                    syncAttachments()
                    isPasting = false
                }
            }
        }
    }
    
    private func handleLargeTextPaste(_ text: String, filename: String) {
        // Treat large text as a document attachment (max 5 documents)
        guard sharedMediaDataSource.documents.count < 5 else {
            logger.info("Maximum documents (5) reached, cannot add pasted text")
            return
        }
        
        // Sanitize the filename to comply with Bedrock API requirements
        let sanitizedName = sanitizeDocumentName(filename)
        
        logger.info("Adding large text as document: \(sanitizedName), size: \(text.count) bytes")
        
        // Use helper method to properly add document with all arrays in sync
        sharedMediaDataSource.addPastedText(text, filename: sanitizedName)
        
        syncAttachments()
    }
    
    private func handleTranscriptUpdate(_ newTranscript: String) {
        guard !newTranscript.isEmpty else { return }
        
        DispatchQueue.main.async {
            if !userInput.isEmpty && !userInput.hasSuffix(" ") {
                userInput += " "
            }
            
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
            
            NotificationCenter.default.post(
                name: .transcriptUpdated,
                object: nil
            )
        }
    }
    
    /// Sanitizes document name to comply with Bedrock restrictions
    /// - Only allows alphanumeric characters, single spaces, hyphens, parentheses, and square brackets
    func sanitizeDocumentName(_ name: String) -> String {
        // First, remove the file extension if present
        let nameWithoutExtension: String
        if let lastDotIndex = name.lastIndex(of: ".") {
            nameWithoutExtension = String(name[..<lastDotIndex])
        } else {
            nameWithoutExtension = name
        }
        
        var result = ""
        var lastCharWasSpace = false
        
        // Process each character
        for scalar in nameWithoutExtension.unicodeScalars {
            // Allow only English alphanumeric characters (a-z, A-Z, 0-9)
            if (scalar.value >= 65 && scalar.value <= 90) ||    // A-Z
               (scalar.value >= 97 && scalar.value <= 122) ||   // a-z
               (scalar.value >= 48 && scalar.value <= 57) {     // 0-9
                result.append(Character(scalar))
                lastCharWasSpace = false
            }
            // Allow single spaces (no consecutive spaces)
            else if CharacterSet.whitespaces.contains(scalar) {
                if !lastCharWasSpace {
                    result.append(" ")
                    lastCharWasSpace = true
                }
            }
            // Allow specific permitted symbols
            else if scalar == "-" || scalar == "(" || scalar == ")" || scalar == "[" || scalar == "]" {
                result.append(Character(scalar))
                lastCharWasSpace = false
            }
            // For any other character, replace with a space if we don't already have one
            else if !lastCharWasSpace {
                result.append(" ")
                lastCharWasSpace = true
            }
        }
        
        // Trim any leading/trailing spaces
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If the result is empty, provide a default name
        if trimmed.isEmpty {
            // Use current timestamp to create a unique default name
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
            return "Document-\(dateFormatter.string(from: Date()))"
        }
        
        return trimmed
    }

    
    private func setupTranscriptObserver() {
        NotificationCenter.default.addObserver(
            forName: .transcriptUpdated,
            object: nil,
            queue: .main
        ) { _ in }
    }
    
    func getFileName(for index: Int) -> String {
        if index < sharedMediaDataSource.filenames.count,
           !sharedMediaDataSource.filenames[index].isEmpty {
            return sharedMediaDataSource.filenames[index]
        }
        
        let ext = index < sharedMediaDataSource.fileExtensions.count ?
        sharedMediaDataSource.fileExtensions[index] : "img"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        return "attachment_\(dateFormatter.string(from: Date())).\(ext)"
    }
    
    private func syncAttachments() {
        // Debug info
        logger.info("Starting syncAttachments")
        logger.info("Images: \(sharedMediaDataSource.images.count), Documents: \(sharedMediaDataSource.documents.count)")
        logger.info("MediaTypes: \(sharedMediaDataSource.mediaTypes.count), Extensions: \(sharedMediaDataSource.fileExtensions.count)")
        
        // Clear current attachments first
        attachments.removeAll()
        documentAttachments.removeAll()
        
        // Sync image attachments (using separate image arrays)
        for i in 0..<sharedMediaDataSource.images.count {
            let fileExt = i < sharedMediaDataSource.imageExtensions.count ?
                sharedMediaDataSource.imageExtensions[i] : "jpg"
                
            let filename = i < sharedMediaDataSource.imageFilenames.count ?
                sharedMediaDataSource.imageFilenames[i] : "image\(i+1).\(fileExt)"
                
            logger.info("Adding image attachment: \(filename) with ext \(fileExt)")
            
            attachments.append(ImageAttachment(
                image: sharedMediaDataSource.images[i],
                fileExtension: fileExt,
                filename: filename
            ))
        }
        
        // Sync document attachments (using separate document arrays)
        for i in 0..<sharedMediaDataSource.documents.count {
            let fileExt = i < sharedMediaDataSource.documentExtensions.count ?
                sharedMediaDataSource.documentExtensions[i] : "pdf"
                
            let filename = i < sharedMediaDataSource.documentFilenames.count ?
                sharedMediaDataSource.documentFilenames[i] : "document\(i+1).\(fileExt)"
            
            let textPreview = i < sharedMediaDataSource.textPreviews.count ?
                sharedMediaDataSource.textPreviews[i] : nil
                
            logger.info("Adding document attachment: \(filename) with ext \(fileExt)")
            
            documentAttachments.append(DocumentAttachment(
                data: sharedMediaDataSource.documents[i],
                fileExtension: fileExt,
                filename: filename,
                textPreview: textPreview
            ))
        }
        
        logger.info("After sync: Image attachments: \(attachments.count), Document attachments: \(documentAttachments.count)")
    }
    
    func removeAttachment(withId id: UUID) {
        if let index = attachments.firstIndex(where: { $0.id == id }) {
            attachments.remove(at: index)
            sharedMediaDataSource.removeImage(at: index)
        }
    }
    
    func removeDocumentAttachment(withId id: UUID) {
        if let index = documentAttachments.firstIndex(where: { $0.id == id }) {
            documentAttachments.remove(at: index)
            sharedMediaDataSource.removeDocument(at: index)
        }
    }
    
    func removeAllAttachments() {
        withAnimation {
            attachments.removeAll()
            documentAttachments.removeAll()
            sharedMediaDataSource.clear()
        }
    }
    
    private func processImageInParallel(_ image: NSImage) async -> (NSImage, String, String) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let compressedImage: NSImage
                let fileExtension: String
                
                // 여기서 NSBitmapImageRep.FileType을 사용하도록 변경
                if let compressedData = image.compressedData(maxFileSize: 1024 * 1024, maxDimension: 1024, format: NSBitmapImageRep.FileType.jpeg),
                   let processedImage = NSImage(data: compressedData) {
                    compressedImage = processedImage
                    fileExtension = "jpeg"
                } else {
                    compressedImage = image
                    fileExtension = "png"
                }
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
                let filename = "pasted_image_\(dateFormatter.string(from: Date())).\(fileExtension)"
                
                continuation.resume(returning: (compressedImage, filename, fileExtension))
            }
        }
    }
}

// MARK: - Supporting Views
struct PasteLoadingView: View {
    var body: some View {
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

struct AdvancedOptionsMenu: View {
    @Binding var userInput: String
    @ObservedObject var settingManager: SettingManager
    @ObservedObject var mcpManager: MCPManager = MCPManager.shared
    var modelId: String
    
    // Check if current model supports reasoning/thinking
    private var supportsThinking: Bool {
        let id = modelId.lowercased()
        // Claude 3.7, Claude 4 series, and DeepSeek R1 support thinking
        return id.contains("claude-3-7") || id.contains("claude-sonnet-4") || id.contains("claude-haiku-4") || id.contains("claude-opus-4") || id.contains("deepseek") && id.contains("r1")
    }
    
    // Check if model has always-on reasoning that can't be toggled
    private var hasAlwaysOnThinking: Bool {
        let id = modelId.lowercased()
        // DeepSeek R1 has always-on thinking
        return id.contains("deepseek") && id.contains("r1")
    }
    
    // Check if thinking toggle should be shown
    private var shouldShowThinkingToggle: Bool {
        return supportsThinking && !hasAlwaysOnThinking
    }
    
    // Check if current model supports streaming tool use
    private var supportsStreamingTools: Bool {
        let id = modelId.lowercased()
        return (
            // Claude models (3 and 4 series)
            (id.contains("claude-3") && !id.contains("haiku")) ||
            id.contains("claude-sonnet-4") ||
            id.contains("claude-opus-4") ||
            
            // Amazon Nova models
            (id.contains("amazon") && (
                id.contains("nova-pro") ||
                id.contains("nova-lite") ||
                id.contains("nova-micro") ||
                id.contains("nova-premier")
            )) ||
            
            // Cohere Command-R models
            (id.contains("cohere") && id.contains("command-r")) ||
            
            // AI21 Jamba models (except Instruct)
            (id.contains("ai21") && id.contains("jamba") && !id.contains("instruct")) ||
            
            // OpenAI GPT-OSS models
            (id.contains("openai") && id.contains("gpt-oss"))
        )
    }

    // Check if MCP tools should be available and shown
    private var shouldShowMCPTools: Bool {
        return mcpManager.mcpEnabled && !mcpManager.toolInfos.isEmpty && supportsStreamingTools
    }
    
    var body: some View {
        Menu {
            Text("More Options")
                .font(.headline)
                .foregroundColor(.secondary)
            
            // Show thinking toggle for models that support configurable reasoning
            if shouldShowThinkingToggle {
                Toggle("Enable Thinking", isOn: $settingManager.enableModelThinking)
                    .help("Allow the model to show its thinking process")
            }
            
            // For models with always-on thinking, show an informative option
            if hasAlwaysOnThinking {
                Text("Thinking: Always On")
                    .foregroundColor(.secondary)
                    .help("This model always includes its thinking process")
            }
            
            Toggle("Allow Image Pasting", isOn: $settingManager.allowImagePasting)
                .help("Enable or disable image pasting functionality")
            
            // MCP tools section - only show if model supports streaming tool use
            if shouldShowMCPTools {
                Divider()
                
                Text("Available Tools").bold()
                
                ForEach(MCPManager.shared.toolInfos) { tool in
                    Button {
                    } label: {
                        Label(tool.toolName, systemImage: "bolt.fill")
                    }
                    .help(tool.description)
                }
            }
            

        } label: {
            Image(systemName: shouldShowMCPTools
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

struct ImageAttachment: Identifiable {
    let id = UUID()
    let image: NSImage
    var fileExtension: String
    var filename: String
}

struct AttachmentListView: View {
    @Binding var attachments: [ImageAttachment]
    @Binding var documentAttachments: [DocumentAttachment]
    @ObservedObject var sharedMediaDataSource: SharedMediaDataSource
    @Binding var selectedImageIndex: Int?
    @Binding var showImagePreview: Bool
    var onRemoveAttachment: (UUID) -> Void
    var onRemoveDocumentAttachment: (UUID) -> Void
    var onRemoveAllAttachments: () -> Void
    
    @State private var selectedDocumentIndex: Int? = nil
    @State private var documentToPreview: DocumentAttachment? = nil  // Use for sheet(item:)
    
    var logger = Logger(label: "AttachmentListView")
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                let totalAttachments = attachments.count + documentAttachments.count
                
                Text("Attachments (\(totalAttachments))")
                    .font(.system(size: 13, weight: .medium))
                
                Spacer()
                
                if totalAttachments > 1 {
                    Button(action: onRemoveAllAttachments) {
                        Text("Clear all")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 8)
            
            // Combined attachment list (images + documents)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Images
                    ForEach(attachments) { attachment in
                        MediaAttachmentView(
                            attachmentType: .image(attachment.image),
                            filename: attachment.filename,
                            fileExtension: attachment.fileExtension,
                            onDelete: {
                                onRemoveAttachment(attachment.id)
                            },
                            onClick: {
                                if let index = attachments.firstIndex(where: { $0.id == attachment.id }) {
                                    selectedImageIndex = index
                                    showImagePreview = true
                                }
                            }
                        )
                    }
                    
                    // Documents
                    ForEach(documentAttachments) { document in
                        if let preview = document.textPreview {
                            PastedTextAttachmentView(
                                preview: preview,
                                onDelete: {
                                    onRemoveDocumentAttachment(document.id)
                                },
                                onClick: {
                                    // Use sheet(item:) pattern - set the document directly
                                    documentToPreview = document
                                }
                            )
                        } else {
                            MediaAttachmentView(
                                attachmentType: .document(document.fileExtension),
                                filename: document.filename,
                                fileExtension: document.fileExtension,
                                onDelete: {
                                    onRemoveDocumentAttachment(document.id)
                                },
                                onClick: {
                                    // Use sheet(item:) pattern - set the document directly
                                    documentToPreview = document
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 8)
            }
            .frame(height: 90)
            .contextMenu {
                Button(action: onRemoveAllAttachments) {
                    Label("Delete All Attachments", systemImage: "trash")
                }
                
                if !attachments.isEmpty {
                    Button(action: {
                        saveAllImages()
                    }) {
                        Label("Save All Images", systemImage: "folder")
                    }
                }
            }
        }
        .sheet(item: $documentToPreview) { doc in
            DocumentPreviewModal(
                documentData: doc.data,
                filename: doc.filename,
                fileExtension: doc.fileExtension,
                isPresented: Binding(
                    get: { documentToPreview != nil },
                    set: { if !$0 { documentToPreview = nil } }
                )
            )
        }
    }
    
    private func saveAllImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Folder"
        panel.message = "Choose a folder to save all images"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    for (index, image) in sharedMediaDataSource.images.enumerated() {
                        saveImage(image, at: index, to: url)
                    }
                }
            }
        }
    }
    
    private func saveImage(_ image: NSImage, at index: Int, to folderURL: URL) {
        let filename = getFilename(for: index)
        let fileURL = folderURL.appendingPathComponent(filename)
        
        if let tiffData = image.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData) {
            let fileExtension = index < sharedMediaDataSource.fileExtensions.count ?
            sharedMediaDataSource.fileExtensions[index] : "jpg"
            
            let imageData: Data?
            switch fileExtension.lowercased() {
            case "jpg", "jpeg":
                imageData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
            default:
                imageData = bitmapImage.representation(using: .png, properties: [:])
            }
            
            if let data = imageData {
                do {
                    try data.write(to: fileURL)
                } catch {
                    logger.info("Failed to save image: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func getFilename(for index: Int) -> String {
        if index < sharedMediaDataSource.filenames.count,
           !sharedMediaDataSource.filenames[index].isEmpty {
            return sharedMediaDataSource.filenames[index]
        }
        
        let ext = index < sharedMediaDataSource.fileExtensions.count ?
        sharedMediaDataSource.fileExtensions[index] : "img"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        return "attachment_\(dateFormatter.string(from: Date())).\(ext)"
    }
}

struct MediaAttachmentView: View {
    enum AttachmentType {
        case image(NSImage)
        case document(String) // Document extension
    }
    
    var attachmentType: AttachmentType
    var filename: String
    var fileExtension: String
    var onDelete: () -> Void
    var onClick: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail or icon
            Group {
                switch attachmentType {
                case .image(let image):
                    Button(action: { onClick?() }) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .cornerRadius(6)
                            .clipped()
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                case .document(let ext):
                    Button(action: { onClick?() }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(documentColor(for: ext).opacity(0.15))
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: documentIcon(for: ext))
                                .font(.system(size: 24))
                                .foregroundColor(documentColor(for: ext))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
            .overlay(
                Button(action: onDelete) {
                    ZStack {
                        Circle()
                            .fill(colorScheme == .dark ?
                                  Color(white: 0.2).opacity(0.8) :
                                  Color.white.opacity(0.9))
                            .frame(width: 20, height: 20)
                            .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                }
                .buttonStyle(PlainButtonStyle()),
                alignment: .topTrailing
            )
            
            Text(filename.count > 10 ? String(filename.prefix(7)) + "..." : filename)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 60)
        }
        .frame(width: 70, height: 80)
    }
    
    // Get icon based on file extension
    private func documentIcon(for extension: String) -> String {
        switch fileExtension.lowercased() {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "txt", "md": return "doc.plaintext.fill"
        case "html": return "globe"
        default: return "doc.fill"
        }
    }
    
    // Get color based on file extension
    private func documentColor(for extension: String) -> Color {
        switch fileExtension.lowercased() {
        case "pdf": return .red
        case "doc", "docx": return .blue
        case "xls", "xlsx", "csv": return .green
        case "txt", "md": return .gray
        case "html": return .orange
        default: return .gray
        }
    }
}

// MARK: - Pasted Text Attachment View (Claude Desktop style)
struct PastedTextAttachmentView: View {
    let preview: String
    var onDelete: () -> Void
    var onClick: (() -> Void)? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    
    private var displayPreview: String {
        // First truncate to avoid processing large text
        let truncated = String(preview.prefix(100))
        // Clean up newlines without regex
        let cleaned = truncated
            .split(separator: "\n", omittingEmptySubsequences: false)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleaned.count > 60 {
            return String(cleaned.prefix(57)) + "..."
        }
        return cleaned
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Text preview area
            Button(action: { onClick?() }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayPreview)
                        .font(.system(size: 10))
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(width: 80, height: 50, alignment: .topLeading)
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .overlay(
                Button(action: onDelete) {
                    ZStack {
                        Circle()
                            .fill(colorScheme == .dark ?
                                  Color(white: 0.2).opacity(0.8) :
                                  Color.white.opacity(0.9))
                            .frame(width: 20, height: 20)
                            .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    .contentShape(Rectangle().size(width: 28, height: 28))
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(isHovered ? 1 : 0),
                alignment: .topTrailing
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            
            // "PASTED" label
            Text("PASTED")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.secondary.opacity(0.4), lineWidth: 0.5)
                )
        }
        .frame(width: 92, height: 80)
    }
}
