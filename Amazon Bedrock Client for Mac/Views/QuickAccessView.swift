//
//  QuickAccessView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Kiro on 2025/09/17.
//

import SwiftUI
import Logging
import UniformTypeIdentifiers

struct QuickAccessView: View {
    @State private var inputText: String = ""
    @State private var calculatedHeight: CGFloat = 40
    @State private var isPasting: Bool = false
    @StateObject private var sharedMediaDataSource = SharedMediaDataSource()
    @State private var attachments: [ImageAttachment] = []
    @State private var documentAttachments: [DocumentAttachment] = []
    @State private var showImagePreview: Bool = false
    @State private var selectedImageIndex: Int? = nil
    
    private let onClose: () -> Void
    private let onHeightChange: (CGFloat) -> Void
    private let logger = Logger(label: "QuickAccessView")
    
    @ViewBuilder
    private var quickAccessBarBackground: some View {
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
    
    init(onClose: @escaping () -> Void, onHeightChange: @escaping (CGFloat) -> Void = { _ in }) {
        self.onClose = onClose
        self.onHeightChange = onHeightChange
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Attachment list (when images or documents are present)
            if (!sharedMediaDataSource.images.isEmpty || !sharedMediaDataSource.documents.isEmpty) {
                QuickAccessAttachmentView(
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
            
            // Message input bar with buttons - identical structure to MessageBarView
            HStack(alignment: .center, spacing: 2) {
                fileUploadButton
                inputArea
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(quickAccessBarBackground)
            
            // Loading indicator
            if isPasting {
                PasteLoadingView()
            }
        }
        .onAppear {
            setupFocus()
            setupEscapeKeyHandler()
            syncAttachments()
        }
        .onChange(of: calculatedHeight) { _, _ in
            updateWindowHeight()
        }
        .onChange(of: sharedMediaDataSource.images.count) { _, _ in
            syncAttachments()
            updateWindowHeight()
        }
        .onChange(of: sharedMediaDataSource.documents.count) { _, _ in
            syncAttachments()
            updateWindowHeight()
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
        .onChange(of: showImagePreview) { _, isShowing in
            // Update state when image preview opens or closes
            QuickAccessWindowManager.shared.setFileUploadInProgress(isShowing)
            
            // Refocus window when preview closes
            if !isShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let window = NSApp.windows.first(where: { $0 is QuickAccessWindow }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
            }
        }
    }
    
    private var fileUploadButton: some View {
        Button(action: {
            // Notify file upload start
            QuickAccessWindowManager.shared.setFileUploadInProgress(true)
            
            let panel = NSOpenPanel()
            var types: [UTType] = [.pdf, .commaSeparatedText, .html, .plainText, .jpeg, .png, .gif, .tiff, .webP]
            if let doc = UTType(filenameExtension: "doc") { types.append(doc) }
            if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
            if let xls = UTType(filenameExtension: "xls") { types.append(xls) }
            if let xlsx = UTType(filenameExtension: "xlsx") { types.append(xlsx) }
            if let md = UTType(filenameExtension: "md") { types.append(md) }
            panel.allowedContentTypes = types
            panel.allowsMultipleSelection = true
            
            panel.begin { response in
                // Notify file upload completion
                QuickAccessWindowManager.shared.setFileUploadInProgress(false)
                
                if response == .OK {
                    handleFileImport(panel.urls)
                }
                
                // Refocus window
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let window = NSApp.windows.first(where: { $0 is QuickAccessWindow }) {
                        window.makeKeyAndOrderFront(nil)
                    }
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
    
    private var inputArea: some View {
        FirstResponderTextView(
            text: $inputText,
            isDisabled: .constant(false),
            calculatedHeight: $calculatedHeight,
            isPasting: $isPasting,
            onCommit: {
                sendMessage()
            },
            onPaste: { image in
                handleImagePaste(image)
            },
            onPasteDocument: { url in
                handleFileImport([url])
            }
        )
        .frame(minHeight: 40, maxHeight: min(calculatedHeight, 200)) // Limit maximum height to 200px
    }
    
    private func setupFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Set focus to text view
            if let window = NSApp.keyWindow,
               let scrollView = findScrollView(in: window.contentView),
               let textView = scrollView.documentView as? NSTextView {
                window.makeFirstResponder(textView)
            }
        }
    }
    
    private func findScrollView(in view: NSView?) -> NSScrollView? {
        guard let view = view else { return nil }
        
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        
        for subview in view.subviews {
            if let found = findScrollView(in: subview) {
                return found
            }
        }
        
        return nil
    }
    
    private func setupEscapeKeyHandler() {
        // Set up ESC key event monitor
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // ESC key
                DispatchQueue.main.async {
                    self.onClose()
                }
                return nil // Consume event
            }
            return event // Pass through other keys
        }
    }
    
    private func handleFileImport(_ urls: [URL]) {
        let maxToAdd = min(10 - (sharedMediaDataSource.images.count + sharedMediaDataSource.documents.count), urls.count)
        let urlsToProcess = urls.prefix(maxToAdd)
        
        for url in urlsToProcess {
            let fileExtension = url.pathExtension.lowercased()
            
            // Handle image files
            if ["jpg", "jpeg", "png", "gif", "tiff", "webp"].contains(fileExtension) {
                if let image = NSImage(contentsOf: url) {
                    logger.info("Adding image: \(url.lastPathComponent)")
                    sharedMediaDataSource.images.append(image)
                    sharedMediaDataSource.fileExtensions.append(fileExtension)
                    sharedMediaDataSource.filenames.append(url.lastPathComponent)
                    sharedMediaDataSource.mediaTypes.append(.image)
                }
            }
            // Handle document files
            else if ["pdf", "csv", "doc", "docx", "xls", "xlsx", "html", "txt", "md"].contains(fileExtension) {
                do {
                    let fileData = try Data(contentsOf: url)
                    let sanitizedName = sanitizeDocumentName(url.lastPathComponent)
                    
                    logger.info("Adding document: \(sanitizedName), size: \(fileData.count) bytes")
                    
                    sharedMediaDataSource.documents.append(fileData)
                    
                    // Document extensions and filenames need to be added at the correct index
                    let docIndex = sharedMediaDataSource.images.count + sharedMediaDataSource.documents.count - 1
                    
                    // Expand arrays if needed
                    while sharedMediaDataSource.fileExtensions.count <= docIndex {
                        sharedMediaDataSource.fileExtensions.append("")
                    }
                    
                    while sharedMediaDataSource.filenames.count <= docIndex {
                        sharedMediaDataSource.filenames.append("")
                    }
                    
                    while sharedMediaDataSource.mediaTypes.count <= docIndex {
                        sharedMediaDataSource.mediaTypes.append(.document)
                    }
                    
                    // Set values at the correct index
                    sharedMediaDataSource.fileExtensions[docIndex] = fileExtension
                    sharedMediaDataSource.filenames[docIndex] = sanitizedName
                    sharedMediaDataSource.mediaTypes[docIndex] = .document
                } catch {
                    logger.info("Error loading document: \(error.localizedDescription)")
                }
            }
        }
        
        // Update attachment list after processing files
        syncAttachments()
    }
    
    private func handleImagePaste(_ image: NSImage) {
        if sharedMediaDataSource.images.count < 10 {
            Task {
                isPasting = true
                let (compressedImage, filename, fileExtension) = await processImageInParallel(image)
                sharedMediaDataSource.images.append(compressedImage)
                sharedMediaDataSource.fileExtensions.append(fileExtension)
                sharedMediaDataSource.filenames.append(filename)
                sharedMediaDataSource.mediaTypes.append(.image)
                isPasting = false
            }
        }
    }
    
    private func processImageInParallel(_ image: NSImage) async -> (NSImage, String, String) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let compressedImage: NSImage
                let fileExtension: String
                
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
    
    private func sanitizeDocumentName(_ name: String) -> String {
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
    
    private func syncAttachments() {
        // Clear current attachments first
        attachments.removeAll()
        documentAttachments.removeAll()
        
        // Sync image attachments
        for i in 0..<sharedMediaDataSource.images.count {
            let fileExt = i < sharedMediaDataSource.fileExtensions.count ?
                sharedMediaDataSource.fileExtensions[i] : "jpg"
                
            let filename = i < sharedMediaDataSource.filenames.count ?
                sharedMediaDataSource.filenames[i] : "image\(i+1).\(fileExt)"
                
            attachments.append(ImageAttachment(
                image: sharedMediaDataSource.images[i],
                fileExtension: fileExt,
                filename: filename
            ))
        }
        
        // Sync document attachments
        for i in 0..<sharedMediaDataSource.documents.count {
            // Calculate correct index for accessing extensions and filenames
            let docIndex = sharedMediaDataSource.images.count + i
            
            let fileExt = docIndex < sharedMediaDataSource.fileExtensions.count ?
                sharedMediaDataSource.fileExtensions[docIndex] : "pdf"
                
            let filename = docIndex < sharedMediaDataSource.filenames.count ?
                sharedMediaDataSource.filenames[docIndex] : "document\(i+1).\(fileExt)"
                
            documentAttachments.append(DocumentAttachment(
                data: sharedMediaDataSource.documents[i],
                fileExtension: fileExt,
                filename: filename
            ))
        }
    }
    
    func removeAttachment(withId id: UUID) {
        if let index = attachments.firstIndex(where: { $0.id == id }) {
            attachments.remove(at: index)
            
            if index < sharedMediaDataSource.images.count {
                sharedMediaDataSource.images.remove(at: index)
            }
            if index < sharedMediaDataSource.fileExtensions.count {
                sharedMediaDataSource.fileExtensions.remove(at: index)
            }
            if index < sharedMediaDataSource.filenames.count {
                sharedMediaDataSource.filenames.remove(at: index)
            }
        }
    }
    
    func removeDocumentAttachment(withId id: UUID) {
        if let index = documentAttachments.firstIndex(where: { $0.id == id }) {
            documentAttachments.remove(at: index)
            
            // Find the corresponding index in the shared data source
            var docIndex = -1
            var count = 0
            
            for (i, type) in sharedMediaDataSource.mediaTypes.enumerated() {
                if type == .document {
                    if count == index {
                        docIndex = i
                        break
                    }
                    count += 1
                }
            }
            
            if docIndex >= 0 {
                sharedMediaDataSource.documents.remove(at: index)
                sharedMediaDataSource.mediaTypes.remove(at: docIndex)
                if docIndex < sharedMediaDataSource.fileExtensions.count {
                    sharedMediaDataSource.fileExtensions.remove(at: docIndex)
                }
                if docIndex < sharedMediaDataSource.filenames.count {
                    sharedMediaDataSource.filenames.remove(at: docIndex)
                }
            }
        }
    }
    
    func removeAllAttachments() {
        attachments.removeAll()
        documentAttachments.removeAll()
        sharedMediaDataSource.images.removeAll()
        sharedMediaDataSource.documents.removeAll()
        sharedMediaDataSource.fileExtensions.removeAll()
        sharedMediaDataSource.filenames.removeAll()
        sharedMediaDataSource.mediaTypes.removeAll()
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
    
    private func updateWindowHeight() {
        let baseHeight: CGFloat = 56 // Base window height
        let attachmentHeight: CGFloat = (!sharedMediaDataSource.images.isEmpty || !sharedMediaDataSource.documents.isEmpty) ? 120 : 0 // Increased height for new design
        let textHeight = max(40, min(calculatedHeight, 200)) // Text height (max 200px)
        let totalHeight = baseHeight + attachmentHeight + (textHeight - 40) // 40 is base text height
        
        onHeightChange(totalHeight)
    }
    
    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !sharedMediaDataSource.images.isEmpty || !sharedMediaDataSource.documents.isEmpty else { return }
        
        let userMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Quick access message: \(userMessage)")
        
        // Prevent duplicate processing
        guard !AppCoordinator.shared.isProcessingQuickAccess else {
            logger.info("Quick access already processing, ignoring")
            onClose()
            return
        }
        
        // Set processing flag immediately to prevent duplicates
        AppCoordinator.shared.isProcessingQuickAccess = true
        
        // Close window
        onClose()
        
        // Activate main app and create new chat
        DispatchQueue.main.async {
            // Activate main app and bring main window to front
            NSApp.activate(ignoringOtherApps: true)
            
            // Find and bring main window to front
            if let mainWindow = NSApp.windows.first(where: { $0.title.isEmpty || $0.title.contains("Amazon Bedrock") }) {
                mainWindow.makeKeyAndOrderFront(nil)
            }
            
            // Set message and attachments only if not already set
            if AppCoordinator.shared.quickAccessMessage == nil {
                AppCoordinator.shared.quickAccessMessage = userMessage
                
                // Pass attachments if available
                if !self.sharedMediaDataSource.images.isEmpty || !self.sharedMediaDataSource.documents.isEmpty {
                    AppCoordinator.shared.quickAccessAttachments = self.sharedMediaDataSource
                }
                
                // Trigger new chat creation after setting message
                AppCoordinator.shared.shouldCreateNewChat = true
            }
        }
    }
}

// MARK: - Quick Access Attachment View
struct QuickAccessAttachmentView: View {
    @Binding var attachments: [ImageAttachment]
    @Binding var documentAttachments: [DocumentAttachment]
    @ObservedObject var sharedMediaDataSource: SharedMediaDataSource
    @Binding var selectedImageIndex: Int?
    @Binding var showImagePreview: Bool
    var onRemoveAttachment: (UUID) -> Void
    var onRemoveDocumentAttachment: (UUID) -> Void
    var onRemoveAllAttachments: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            // Header with count and clear all button
            HStack {
                let totalAttachments = attachments.count + documentAttachments.count
                
                HStack(spacing: 4) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text("\(totalAttachments) file\(totalAttachments == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onRemoveAllAttachments) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                        Text("Clear All")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.1))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            // Attachment grid
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Images
                    ForEach(attachments) { attachment in
                        QuickAccessMediaItem(
                            type: .image(attachment.image),
                            filename: attachment.filename,
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
                        QuickAccessMediaItem(
                            type: .document(document.fileExtension),
                            filename: document.filename,
                            onDelete: {
                                onRemoveDocumentAttachment(document.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 12)
    }
}

// MARK: - Quick Access Media Item
struct QuickAccessMediaItem: View {
    enum MediaType {
        case image(NSImage)
        case document(String)
    }
    
    let type: MediaType
    let filename: String
    let onDelete: () -> Void
    let onClick: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    
    init(type: MediaType, filename: String, onDelete: @escaping () -> Void, onClick: (() -> Void)? = nil) {
        self.type = type
        self.filename = filename
        self.onDelete = onDelete
        self.onClick = onClick
    }
    
    var body: some View {
        VStack(spacing: 6) {
            // Media thumbnail
            ZStack {
                Group {
                    switch type {
                    case .image(let image):
                        Button(action: { onClick?() }) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                    case .document(let ext):
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(documentColor(for: ext))
                                .frame(width: 60, height: 60)
                            
                            VStack(spacing: 2) {
                                Image(systemName: documentIcon(for: ext))
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Text(ext.uppercased())
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                
                // Delete button
                if isHovered {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: onDelete) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                                    .background(
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 18, height: 18)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .offset(x: 6, y: -6)
                        }
                        Spacer()
                    }
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
            
            // Filename
            Text(truncatedFilename)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 60)
        }
        .frame(width: 70)
    }
    
    private var truncatedFilename: String {
        if filename.count > 10 {
            return String(filename.prefix(7)) + "..."
        }
        return filename
    }
    
    private func documentIcon(for extension: String) -> String {
        switch `extension`.lowercased() {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "txt", "md": return "doc.plaintext.fill"
        case "html": return "globe"
        default: return "doc.fill"
        }
    }
    
    private func documentColor(for extension: String) -> Color {
        switch `extension`.lowercased() {
        case "pdf": return Color.red
        case "doc", "docx": return Color.blue
        case "xls", "xlsx", "csv": return Color.green
        case "txt", "md": return Color.gray
        case "html": return Color.orange
        default: return Color.gray
        }
    }
}