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
    // MARK: - State
    @State private var inputText: String = ""
    @State private var calculatedHeight: CGFloat = 40
    @State private var isPasting: Bool = false
    @StateObject private var sharedMediaDataSource = SharedMediaDataSource()
    @State private var attachments: [ImageAttachment] = []
    @State private var documentAttachments: [DocumentAttachment] = []
    @State private var showImagePreview: Bool = false
    @State private var selectedImageIndex: Int? = nil
    @State private var showDocumentPreview: Bool = false
    @State private var selectedDocumentIndex: Int? = nil
    @ObservedObject private var settingManager = SettingManager.shared

    // MARK: - Properties
    private let onClose: () -> Void
    private let onHeightChange: (CGFloat) -> Void
    private let logger = Logger(label: "QuickAccessView")

    private var hasAttachments: Bool {
        !sharedMediaDataSource.images.isEmpty || !sharedMediaDataSource.documents.isEmpty
    }

    private var totalAttachmentCount: Int {
        attachments.count + documentAttachments.count
    }

    // MARK: - Init
    init(onClose: @escaping () -> Void, onHeightChange: @escaping (CGFloat) -> Void = { _ in }) {
        self.onClose = onClose
        self.onHeightChange = onHeightChange
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            mainContainer
        }
        .onAppear {
            setupFocus()
            setupEscapeKeyHandler()
            syncAttachments()
        }
        .onChange(of: calculatedHeight) { _, _ in updateWindowHeight() }
        .onChange(of: sharedMediaDataSource.images.count) { _, _ in
            syncAttachments()
            updateWindowHeight()
        }
        .onChange(of: sharedMediaDataSource.documents.count) { _, _ in
            syncAttachments()
            updateWindowHeight()
        }
        .sheet(isPresented: $showImagePreview) {
            if let index = selectedImageIndex, index < sharedMediaDataSource.images.count {
                ImagePreviewModal(
                    image: sharedMediaDataSource.images[index],
                    filename: getFileName(for: index),
                    isPresented: $showImagePreview
                )
            }
        }
        .sheet(isPresented: $showDocumentPreview) {
            if let index = selectedDocumentIndex, index < documentAttachments.count {
                let doc = documentAttachments[index]
                DocumentPreviewModal(
                    documentData: doc.data,
                    filename: doc.filename,
                    fileExtension: doc.fileExtension,
                    isPresented: $showDocumentPreview
                )
            }
        }
        .onChange(of: showImagePreview) { _, isShowing in
            QuickAccessWindowManager.shared.setFileUploadInProgress(isShowing)
            if !isShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let window = NSApp.windows.first(where: { $0 is QuickAccessWindow }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
            }
        }
        .onChange(of: showDocumentPreview) { _, isShowing in
            QuickAccessWindowManager.shared.setFileUploadInProgress(isShowing)
            if !isShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let window = NSApp.windows.first(where: { $0 is QuickAccessWindow }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
            }
        }
    }

    // MARK: - Main Container
    @ViewBuilder
    private var mainContainer: some View {
        VStack(spacing: 0) {
            // Input row
            HStack(alignment: .center, spacing: 6) {
                optionsMenuButton
                attachButton
                textInputArea
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, hasAttachments ? 6 : 10)

            // Attachments row (if any)
            if hasAttachments {
                attachmentsRow
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }

            // Loading indicator
            if isPasting {
                loadingIndicator
            }
        }
        .background(containerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Container Background
    @ViewBuilder
    private var containerBackground: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        } else {
            Color(NSColor.windowBackgroundColor)
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        }
    }

    // MARK: - Options Menu Button (placeholder for future options)
    private var optionsMenuButton: some View {
        EmptyView()
            .frame(width: 0, height: 0)
    }

    // MARK: - Attach Button
    private var attachButton: some View {
        Button(action: openFilePicker) {
            Image(systemName: "paperclip")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
    }

    // MARK: - Text Input Area
    private var textInputArea: some View {
        FirstResponderTextView(
            text: $inputText,
            isDisabled: .constant(false),
            calculatedHeight: $calculatedHeight,
            isPasting: $isPasting,
            allowImagePasting: settingManager.allowImagePasting,
            treatLargeTextAsFile: settingManager.treatLargeTextAsFile,
            onCommit: sendMessage,
            onPaste: handleImagePaste,
            onPasteDocument: { url in handleFileImport([url]) },
            onPasteLargeText: handleLargeTextPaste
        )
        .frame(minHeight: 36, maxHeight: max(36, min(calculatedHeight, 180)))
    }

    // MARK: - Attachments Row
    private var attachmentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentChip(
                        image: attachment.image,
                        name: attachment.filename,
                        onRemove: { removeAttachment(withId: attachment.id) },
                        onTap: {
                            if let idx = attachments.firstIndex(where: { $0.id == attachment.id }) {
                                selectedImageIndex = idx
                                showImagePreview = true
                            }
                        }
                    )
                }

                ForEach(Array(documentAttachments.enumerated()), id: \.element.id) { index, doc in
                    if let preview = doc.textPreview {
                        PastedTextChip(
                            preview: preview,
                            onRemove: { removeDocumentAttachment(withId: doc.id) },
                            onTap: {
                                selectedDocumentIndex = index
                                showDocumentPreview = true
                            }
                        )
                    } else {
                        DocumentChip(
                            name: doc.filename,
                            ext: doc.fileExtension,
                            onRemove: { removeDocumentAttachment(withId: doc.id) },
                            onTap: {
                                selectedDocumentIndex = index
                                showDocumentPreview = true
                            }
                        )
                    }
                }

                if totalAttachmentCount > 1 {
                    clearAllButton
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Clear All Button
    private var clearAllButton: some View {
        Button(action: removeAllAttachments) {
            Text("Clear")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading Indicator
    private var loadingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.6)
            Text("Processing...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 8)
    }


    // MARK: - Actions
    private func openFilePicker() {
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
            QuickAccessWindowManager.shared.setFileUploadInProgress(false)
            if response == .OK {
                handleFileImport(panel.urls)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.windows.first(where: { $0 is QuickAccessWindow }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    private func handleFileImport(_ urls: [URL]) {
        // Bedrock API limits: max 20 images, max 5 documents per request
        let maxImages = 20
        let maxDocuments = 5

        for url in urls {
            let ext = url.pathExtension.lowercased()

            if ["jpg", "jpeg", "png", "gif", "tiff", "webp"].contains(ext) {
                guard sharedMediaDataSource.images.count < maxImages else { continue }
                if let image = NSImage(contentsOf: url) {
                    sharedMediaDataSource.addImage(image, fileExtension: ext, filename: url.lastPathComponent)
                }
            } else if ["pdf", "csv", "doc", "docx", "xls", "xlsx", "html", "txt", "md"].contains(ext) {
                guard sharedMediaDataSource.documents.count < maxDocuments else { continue }
                if let fileData = try? Data(contentsOf: url) {
                    let sanitizedName = sanitizeDocumentName(url.lastPathComponent)
                    sharedMediaDataSource.addDocument(fileData, fileExtension: ext, filename: sanitizedName)
                }
            }
        }
        syncAttachments()
    }

    private func handleImagePaste(_ image: NSImage) {
        guard sharedMediaDataSource.images.count < 20 else { return }
        Task {
            isPasting = true
            let (compressedImage, filename, ext) = await processImageInParallel(image)
            sharedMediaDataSource.addImage(compressedImage, fileExtension: ext, filename: filename)
            syncAttachments()
            isPasting = false
        }
    }
    
    private func handleLargeTextPaste(_ text: String, _ filename: String) {
        // Max 5 documents per request
        guard sharedMediaDataSource.documents.count < 5 else { return }
        
        let sanitizedName = sanitizeDocumentName(filename)
        logger.info("Adding large text as document: \(sanitizedName), size: \(text.count) bytes")
        sharedMediaDataSource.addPastedText(text, filename: sanitizedName)
        syncAttachments()
    }

    private func processImageInParallel(_ image: NSImage) async -> (NSImage, String, String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let compressedImage: NSImage
                let ext: String

                if let data = image.compressedData(maxFileSize: 1024 * 1024, maxDimension: 1024, format: NSBitmapImageRep.FileType.jpeg),
                   let processed = NSImage(data: data) {
                    compressedImage = processed
                    ext = "jpeg"
                } else {
                    compressedImage = image
                    ext = "png"
                }

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd_HHmmss"
                let filename = "pasted_image_\(formatter.string(from: Date())).\(ext)"
                continuation.resume(returning: (compressedImage, filename, ext))
            }
        }
    }

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
              !sharedMediaDataSource.images.isEmpty ||
              !sharedMediaDataSource.documents.isEmpty else { return }

        let userMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !AppCoordinator.shared.isProcessingQuickAccess else {
            onClose()
            return
        }

        AppCoordinator.shared.isProcessingQuickAccess = true
        onClose()

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let mainWindow = NSApp.windows.first(where: { $0.title.isEmpty || $0.title.contains("Amazon Bedrock") }) {
                mainWindow.makeKeyAndOrderFront(nil)
            }

            if AppCoordinator.shared.quickAccessMessage == nil {
                AppCoordinator.shared.quickAccessMessage = userMessage
                if !self.sharedMediaDataSource.images.isEmpty || !self.sharedMediaDataSource.documents.isEmpty {
                    AppCoordinator.shared.quickAccessAttachments = self.sharedMediaDataSource
                }
                AppCoordinator.shared.shouldCreateNewChat = true
            }
        }
    }


    // MARK: - Helpers
    private func setupFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let window = NSApp.keyWindow,
               let scrollView = findScrollView(in: window.contentView),
               let textView = scrollView.documentView as? NSTextView {
                window.makeFirstResponder(textView)
            }
        }
    }

    private func findScrollView(in view: NSView?) -> NSScrollView? {
        guard let view = view else { return nil }
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) { return found }
        }
        return nil
    }

    private func setupEscapeKeyHandler() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // ESC key
                // If a sheet/modal is open, let it handle ESC first
                if self.showImagePreview || self.showDocumentPreview {
                    return event // Let the sheet handle ESC
                }
                
                // Check if any modal/sheet is open
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
                
                DispatchQueue.main.async { self.onClose() }
                return nil
            }
            return event
        }
    }

    private func sanitizeDocumentName(_ name: String) -> String {
        let nameWithoutExt: String
        if let lastDotIndex = name.lastIndex(of: ".") {
            nameWithoutExt = String(name[..<lastDotIndex])
        } else {
            nameWithoutExt = name
        }

        var result = ""
        var lastCharWasSpace = false

        for scalar in nameWithoutExt.unicodeScalars {
            if (scalar.value >= 65 && scalar.value <= 90) ||
               (scalar.value >= 97 && scalar.value <= 122) ||
               (scalar.value >= 48 && scalar.value <= 57) {
                result.append(Character(scalar))
                lastCharWasSpace = false
            } else if CharacterSet.whitespaces.contains(scalar) {
                if !lastCharWasSpace {
                    result.append(" ")
                    lastCharWasSpace = true
                }
            } else if scalar == "-" || scalar == "(" || scalar == ")" || scalar == "[" || scalar == "]" {
                result.append(Character(scalar))
                lastCharWasSpace = false
            } else if !lastCharWasSpace {
                result.append(" ")
                lastCharWasSpace = true
            }
        }

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            return "Document-\(formatter.string(from: Date()))"
        }
        return trimmed
    }

    private func syncAttachments() {
        attachments.removeAll()
        documentAttachments.removeAll()

        // Sync images (using separate image arrays)
        for i in 0..<sharedMediaDataSource.images.count {
            let ext = i < sharedMediaDataSource.imageExtensions.count ? sharedMediaDataSource.imageExtensions[i] : "jpg"
            let name = i < sharedMediaDataSource.imageFilenames.count ? sharedMediaDataSource.imageFilenames[i] : "image\(i+1).\(ext)"
            attachments.append(ImageAttachment(image: sharedMediaDataSource.images[i], fileExtension: ext, filename: name))
        }

        // Sync documents (using separate document arrays)
        for i in 0..<sharedMediaDataSource.documents.count {
            let ext = i < sharedMediaDataSource.documentExtensions.count ? sharedMediaDataSource.documentExtensions[i] : "pdf"
            let name = i < sharedMediaDataSource.documentFilenames.count ? sharedMediaDataSource.documentFilenames[i] : "document\(i+1).\(ext)"
            let preview = i < sharedMediaDataSource.textPreviews.count ? sharedMediaDataSource.textPreviews[i] : nil
            documentAttachments.append(DocumentAttachment(data: sharedMediaDataSource.documents[i], fileExtension: ext, filename: name, textPreview: preview))
        }
    }

    func removeAttachment(withId id: UUID) {
        if let index = attachments.firstIndex(where: { $0.id == id }) {
            attachments.remove(at: index)
            sharedMediaDataSource.removeImage(at: index)
            updateWindowHeight()
        }
    }

    func removeDocumentAttachment(withId id: UUID) {
        if let index = documentAttachments.firstIndex(where: { $0.id == id }) {
            documentAttachments.remove(at: index)
            sharedMediaDataSource.removeDocument(at: index)
            updateWindowHeight()
        }
    }

    func removeAllAttachments() {
        attachments.removeAll()
        documentAttachments.removeAll()
        sharedMediaDataSource.clear()
        // Reset to default height
        calculatedHeight = 40
        updateWindowHeight()
    }

    func getFileName(for index: Int) -> String {
        if index < sharedMediaDataSource.imageFilenames.count, !sharedMediaDataSource.imageFilenames[index].isEmpty {
            return sharedMediaDataSource.imageFilenames[index]
        }
        let ext = index < sharedMediaDataSource.imageExtensions.count ? sharedMediaDataSource.imageExtensions[index] : "img"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "attachment_\(formatter.string(from: Date())).\(ext)"
    }

    private func updateWindowHeight() {
        let baseHeight: CGFloat = 56
        let attachmentHeight: CGFloat = hasAttachments ? 44 : 0
        let textHeight = max(36, min(calculatedHeight, 180))
        let extraTextHeight = max(0, textHeight - 36)  // Ensure non-negative
        let totalHeight = baseHeight + attachmentHeight + extraTextHeight
        onHeightChange(totalHeight)
    }
}


// MARK: - Attachment Chip (Image)
struct AttachmentChip: View {
    let image: NSImage
    let name: String
    let onRemove: () -> Void
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var displayName: String {
        let nameOnly = name.contains(".") ? String(name[..<name.lastIndex(of: ".")!]) : name
        return nameOnly.count > 10 ? String(nameOnly.prefix(8)) + "…" : nameOnly
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onTap) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)

            Text(displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 16, height: 16)
            .background(Circle().fill(Color.primary.opacity(0.08)))
        }
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
        )
    }
}

// MARK: - Document Chip
struct DocumentChip: View {
    let name: String
    let ext: String
    let onRemove: () -> Void
    var onTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var displayName: String {
        let nameOnly = name.contains(".") ? String(name[..<name.lastIndex(of: ".")!]) : name
        return nameOnly.count > 10 ? String(nameOnly.prefix(8)) + "…" : nameOnly
    }

    private var iconName: String {
        switch ext.lowercased() {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "txt", "md": return "doc.plaintext.fill"
        case "html": return "globe"
        default: return "doc.fill"
        }
    }

    private var iconColor: Color {
        switch ext.lowercased() {
        case "pdf": return .red
        case "doc", "docx": return .blue
        case "xls", "xlsx", "csv": return .green
        case "txt", "md": return .gray
        case "html": return .orange
        default: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { onTap?() }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(iconColor.opacity(0.85))
                        .frame(width: 24, height: 24)
                    Image(systemName: iconName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)

            Text(displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 16, height: 16)
            .background(Circle().fill(Color.primary.opacity(0.08)))
        }
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
        )
    }
}

// MARK: - Pasted Text Chip (Claude Desktop style)
struct PastedTextChip: View {
    let preview: String
    let onRemove: () -> Void
    var onTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var displayPreview: String {
        // First truncate to avoid processing large text
        let truncated = String(preview.prefix(120))
        // Clean up newlines without regex
        let cleaned = truncated
            .split(separator: "\n", omittingEmptySubsequences: false)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleaned.count > 80 {
            return String(cleaned.prefix(77)) + "..."
        }
        return cleaned
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Button(action: { onTap?() }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayPreview)
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 200, alignment: .leading)
                    
                    Text("PASTED")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                        )
                }
                .padding(10)
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Circle().fill(Color.primary.opacity(0.08)).frame(width: 20, height: 20))
            .padding(.top, 4)
            .padding(.trailing, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}
