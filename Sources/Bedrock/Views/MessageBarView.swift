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
    @Environment(\.colorScheme) private var colorScheme
    // MARK: - Properties
    var chatID: String
    @Binding var userInput: String
    @ObservedObject private var settingManager = SettingManager.shared
    @ObservedObject private var workbench = WorkbenchStore.shared
    @ObservedObject private var catalog = WorkbenchModelCatalog.shared
    @ObservedObject var chatManager: ChatManager = ChatManager.shared
    @StateObject var sharedMediaDataSource: SharedMediaDataSource
    @ObservedObject var transcribeManager: TranscribeStreamingManager
    
    // UI state tracking
    @State private var calculatedHeight: CGFloat = 40
    @State private var isImagePickerPresented: Bool = false
    @State private var isLoading: Bool = false
    @State private var isPasting: Bool = false
    @State private var showImagePreview: Bool = false
    @State private var selectedImageIndex: Int? = nil
    @State private var attachments: [ImageAttachment] = []
    @State private var documentAttachments: [DocumentAttachment] = []
    @State private var escapeMonitor: Any?
    @State private var transcriptPrefix = ""
    @State private var previousTranscript = ""
    @State private var attachmentError: String?
    @State private var selectedSlashIndex = 0
    @State private var slashDismissed = false
    
    // Action handlers
    var sendMessage: () async -> Void
    var cancelSending: () -> Void
    var modelId: String
    var backend: Backend? = nil
    var onModelChange: ((ChatModel) -> Void)? = nil
    var modelChangePending = false
    var isPreparingConversation = false
    var supportsQueue = false
    
    var logger = Logger(label: "MessageBarView")
    
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
            
            if showsSlashCommands { slashCommands }
            if !workbench.thread(chatID).skillIDs.isEmpty { selectedSkills }
            if let notice = composerNotice {
                HStack(spacing: 7) {
                    Image(systemName: "info.circle")
                    Text(notice)
                    Spacer(minLength: 0)
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 8)
            }
            VStack(alignment: .leading, spacing: 8) {
                inputArea
                HStack(spacing: 9) {
                    fileUploadButton
                    ModelSelectorDropdown(
                        organizedChatModels: catalog.organized,
                        menuSelection: Binding(get: { .chat(catalog.model(modelId)) }, set: { _ in }),
                        handleSelectionChange: { selection in
                            if case .chat(let model) = selection { onModelChange?(model) }
                        }
                    )
                    .frame(maxWidth: 280, alignment: .leading)
                    Spacer(minLength: 8)
                    if let backend {
                        InferenceConfigDropdown(currentModelId: .constant(modelId), backend: backend)
                    }
                    micButton
                    sendButton
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8).padding(.bottom, 10)
            .modifier(WorkbenchComposerMaterial())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            // Loading indicator
            if isPasting || sharedMediaDataSource.isImporting {
                PasteLoadingView()
            }
        }
        .foregroundColor(Color.text)
        .onExitCommand {
            if isLoading { cancelSending() }
        }
        .sheet(isPresented: $showImagePreview) {
            if let index = selectedImageIndex,
               let source = sharedMediaDataSource.imagePreviewSource(at: index) {
                ImagePreviewModal(
                    source: source,
                    filename: getFileName(for: index),
                    isPresented: $showImagePreview
                )
            }
        }
        .onAppear {
            syncAttachments()
            isLoading = chatManager.getIsLoading(for: chatID)
            setupEscapeKeyHandler()
        }
        .onChange(of: sharedMediaDataSource.images.count) { _, _ in
            syncAttachments()
        }
        .onChange(of: sharedMediaDataSource.documents.count) { _, _ in syncAttachments() }
        .onChange(of: sharedMediaDataSource.textPreviews) { _, _ in syncAttachments() }
        .onChange(of: userInput) { _, _ in selectedSlashIndex = 0; slashDismissed = false }
        .onChange(of: sharedMediaDataSource.importError) { _, error in
            if let error { attachmentError = error }
        }
        .onDisappear {
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
            transcribeManager.stopTranscription()
        }
        .alert("Attachment could not be added", isPresented: Binding(get: { attachmentError != nil }, set: { if !$0 { attachmentError = nil } })) {
            Button("OK") { attachmentError = nil }
        } message: { Text(attachmentError ?? "") }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workbench.composer")
    }
    
    // MARK: - UI Components
    
    private var fileUploadButton: some View {
        Button(action: {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.pdf, .commaSeparatedText, .html, .plainText, .sourceCode, .jpeg, .png, .gif, .tiff, .webP, .heic, .bmp,
                                          UTType(filenameExtension: "doc")!, UTType(filenameExtension: "docx")!,
                                          UTType(filenameExtension: "xls")!, UTType(filenameExtension: "xlsx")!,
                                          UTType(filenameExtension: "md")!]
                + LocalAttachmentProcessor.sourceExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
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
        .frame(width: WorkbenchStyle.controlSize, height: WorkbenchStyle.controlSize)
        .help("Attach images or documents").accessibilityLabel("Attach files")
    }
    
    private var micButton: some View {
        Button(action: {
            Task {
                if transcribeManager.isTranscribing {
                    transcribeManager.stopTranscription()
                } else {
                    transcriptPrefix = userInput
                    previousTranscript = ""
                    transcribeManager.resetTranscript()
                    await transcribeManager.startTranscription()
                }
            }
        }) {
            Image(systemName: transcribeManager.isTranscribing ? "mic.fill" : "mic")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(transcribeManager.isTranscribing ? .red : .primary)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: WorkbenchStyle.controlSize, height: WorkbenchStyle.controlSize)
        // Prevent it from capturing keyboard events
        .focusable(false)
        // Explicitly prevent it from getting keyboard focus
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(transcribeManager.isTranscribing ? "Stop dictation" : "Dictate message")
        .help("Dictate using Amazon Transcribe")
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
            onPaste: nil,
            onPasteDocument: { url in
                handleFileImport([url])
            },
            onPasteLargeText: { text, filename in
                handleLargeTextPaste(text, filename: filename)
            },
            onPastePreparedImage: handlePreparedImagePaste,
            onPasteError: { attachmentError = $0 },
            onComposerCommand: navigateSlashCommands
        )
        .frame(height: max(54, calculatedHeight))
        .onReceive(transcribeManager.$transcript) { newTranscript in
            handleTranscriptUpdate(newTranscript)
        }
    }
    
    private var sendButton: some View {
        let hasDraft = !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !sharedMediaDataSource.isEmpty
        let queues = isLoading && supportsQueue && hasDraft
        let stops = isLoading && !queues
        let enabled = stops || (!isPasting && !sharedMediaDataSource.isImporting && !isPreparingConversation && hasDraft)
        let fill: Color = enabled ? (colorScheme == .dark ? .white : .black) : Color.primary.opacity(0.08)
        let symbol: Color = enabled ? (colorScheme == .dark ? .black : .white) : Color.primary.opacity(0.3)
        return Button(action: {
            if stops {
                cancelSending()
            } else if enabled {
                handleSendMessage()
            }
        }) {
            Image(systemName: stops ? "stop.fill" : "arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(symbol)
                .frame(width: 32, height: 32)
                .background(fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!enabled)
        .onChange(of: chatManager.getIsLoading(for: chatID)) { _, newValue in
            isLoading = newValue
        }
        .accessibilityLabel(stops ? "Stop response" : queues ? "Queue message" : "Send message")
        .accessibilityIdentifier("workbench.send")
        .help(stops ? "Stop response (Esc)" : queues ? "Add to queue · Esc stops the current response" :
                workbench.preferences.sendWithCommandReturn ? "Send (⌘ Return)" : "Send (Return)")
    }
    
    // MARK: - Helper Methods

    private var composerNotice: String? {
        if let error = transcribeManager.errorMessage { return error }
        if modelChangePending { return "\(catalog.model(modelId).name) will be used for your next message." }
        if BedrockModelID.base(modelId).hasPrefix("luma."), settingManager.lumaVideoConfig.outputBucket.isEmpty {
            return "Choose an output S3 bucket in response settings before generating a video."
        }
        if let service = StabilityAIImageService.matching(modelId), sharedMediaDataSource.images.isEmpty {
            return "\(service.displayName) needs a source image. Attach one to get started."
        }
        if modelId.contains("nova-reel") { return "Choose an output S3 bucket in response settings before generating a video." }
        if userInput.localizedStandardContains("attached document") && sharedMediaDataSource.documents.isEmpty {
            return "Attach a document to ground this response."
        }
        if userInput.localizedStandardContains("attached image") && sharedMediaDataSource.images.isEmpty {
            return "Attach an image or screenshot to explore with this prompt."
        }
        return nil
    }
    private struct SlashCommand: Identifiable {
        enum Target { case action(String), skill(String), demo(String) }
        var name: String
        var title: String
        var target: Target
        var id: String { name }
    }
    private var allSlashCommands: [SlashCommand] {
        let actions = [("new", "New chat"), ("skills", "Manage local skills"),
                       ("settings", "Open settings"), ("demos", "Explore demos"), ("clear", "Clear this draft")]
        let reserved = Set(actions.map(\.0))
        let skills = workbench.skills.filter { workbench.isSkillEnabled($0) && workbench.unavailableReason(for: $0) == nil }.map {
            SlashCommand(name: reserved.contains($0.id) ? "skill/" + $0.id : $0.id, title: $0.name, target: .skill($0.id))
        }
        let occupied = reserved.union(skills.map(\.name))
        let demos = workbench.demos.map {
            SlashCommand(name: occupied.contains($0.id) ? "demo/" + $0.id : $0.id, title: $0.title, target: .demo($0.id))
        }
        return actions.map { .init(name: $0.0, title: $0.1, target: .action($0.0)) } + skills + demos
    }
    private var availableSlashCommands: [SlashCommand] {
        allSlashCommands.filter {
            let query = String(userInput.dropFirst()).trimmingCharacters(in: .whitespaces)
            return query.isEmpty || $0.name.localizedStandardContains(query) || $0.title.localizedStandardContains(query)
        }
    }
    private var showsSlashCommands: Bool {
        !slashDismissed && userInput.hasPrefix("/") && !userInput.contains("\n") && !availableSlashCommands.isEmpty
    }
    private var slashCommands: some View {
        let rows = availableSlashCommands
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        Button { activateSlashCommand(item) } label: {
                            HStack(spacing: 12) {
                                Text("/" + item.name).font(.system(size: 11, design: .monospaced))
                                    .frame(width: 170, alignment: .leading).lineLimit(1)
                                Text(item.title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                                Spacer(minLength: 0)
                                if index == selectedSlashIndex { Image(systemName: "return").font(.system(size: 10)).foregroundStyle(.secondary) }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
                            .background(index == selectedSlashIndex ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).id(item.id)
                    }
                }.padding(5)
            }
            .onChange(of: selectedSlashIndex) { _, index in
                if rows.indices.contains(index) { proxy.scrollTo(rows[index].id) }
            }
        }
        .frame(maxHeight: CGFloat(min(6, rows.count)) * 35 + 10)
        .background(WorkbenchStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WorkbenchStyle.border))
        .padding(.horizontal, 12)
    }
    private var selectedSkills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(workbench.thread(chatID).skillIDs, id: \.self) { id in
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text(workbench.skills.first { $0.id == id }?.name ?? id).lineLimit(1)
                        Button {
                            workbench.updateThread(chatID) { $0.skillIDs.removeAll { $0 == id } }
                        } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).frame(width: 18, height: 18) }
                            .buttonStyle(.plain).accessibilityLabel("Remove skill \(id)")
                    }.font(.system(size: 11)).padding(.leading, 9).padding(.trailing, 4).padding(.vertical, 4)
                        .background(WorkbenchStyle.surface, in: Capsule())
                }
            }
        }.padding(.horizontal, 18).padding(.top, 6)
    }
    private func navigateSlashCommands(_ key: ComposerNavigationKey) -> Bool {
        guard showsSlashCommands else { return false }
        let rows = availableSlashCommands
        switch key {
        case .up: selectedSlashIndex = max(0, selectedSlashIndex - 1)
        case .down: selectedSlashIndex = min(rows.count - 1, selectedSlashIndex + 1)
        case .accept:
            if rows.indices.contains(selectedSlashIndex) { activateSlashCommand(rows[selectedSlashIndex]) }
        case .dismiss: slashDismissed = true
        }
        return true
    }
    private func activateSlashCommand(_ command: SlashCommand, remainingText: String = "") {
        userInput = remainingText
        switch command.target {
        case .skill(let id):
            workbench.updateThread(chatID) { if !$0.skillIDs.contains(id) { $0.skillIDs.append(id) } }
            WorkbenchWindows.focusComposer()
        case .demo(let id): workbench.requestedDemoID = id
        case .action(let name):
            switch name {
            case "new": WorkbenchWindows.newThread?()
            case "skills": workbench.showSettings(row: "skills")
            case "demos": workbench.destination = .demos
            case "settings": workbench.showSettings()
            default: break
            }
        }
    }
    private func performSlashCommand() -> Bool {
        let command = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard command.hasPrefix("/") else { return false }
        let parts = command.dropFirst().split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let name = parts.first,
              let match = allSlashCommands.first(where: { $0.name == name }) else { return false }
        if parts.count > 1, case .action = match.target { return false }
        activateSlashCommand(match, remainingText: parts.count > 1 ? String(parts[1]) : "")
        return true
    }
    
    private func handleSendMessage() {
        guard (!isLoading || supportsQueue), !isPasting, !sharedMediaDataSource.isImporting, !isPreparingConversation else { return }
        if performSlashCommand() { return }
        transcribeManager.stopTranscription()
        Task {
            await sendMessage()
            transcribeManager.resetTranscript()
        }
    }
    
    private func setupEscapeKeyHandler() {
        // Create a monitor for local key down events
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, WorkbenchWindows.isMainWindowKey, self.showsSlashCommands,
               let editor = NSApp.keyWindow?.firstResponder as? MyTextView, !editor.hasMarkedText() {
                self.slashDismissed = true
                return nil
            }
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
        sharedMediaDataSource.importFiles(urls)
    }

    private func handlePreparedImagePaste(_ image: PreparedClipboardImage) {
        guard settingManager.allowImagePasting else { return }
        guard sharedMediaDataSource.images.count < 20 else {
            attachmentError = "A message supports up to 20 images."
            return
        }
        if !sharedMediaDataSource.addPreparedImage(image) { attachmentError = "The image preview could not be opened." }
    }
    
    private func handleLargeTextPaste(_ text: String, filename: String) {
        // Treat large text as a document attachment (max 5 documents)
        guard sharedMediaDataSource.documents.count < 5 else {
            attachmentError = "Remove a document before attaching more pasted text. A message supports up to 5 documents."
            return
        }
        guard text.utf8.count <= 4_500_000 else { attachmentError = "Pasted text exceeds the 4.5 MB attachment limit."; return }
        
        // Sanitize the filename to comply with Bedrock API requirements
        let sanitizedName = sanitizeDocumentName(filename)
        
        logger.info("Adding large text as document: \(sanitizedName), size: \(text.count) bytes")
        
        // Use helper method to properly add document with all arrays in sync
        sharedMediaDataSource.addPastedText(text, filename: sanitizedName)
        
        syncAttachments()
    }
    
    private func handleTranscriptUpdate(_ newTranscript: String) {
        guard transcribeManager.isTranscribing, !newTranscript.isEmpty, newTranscript != previousTranscript else { return }
        let previous = transcriptPrefix + (transcriptPrefix.isEmpty || transcriptPrefix.hasSuffix(" ") ? "" : " ") + previousTranscript
        if !previousTranscript.isEmpty, userInput != previous {
            // Preserve manual edits made during dictation before starting the next segment.
            transcriptPrefix = userInput
        }
        userInput = transcriptPrefix + (transcriptPrefix.isEmpty || transcriptPrefix.hasSuffix(" ") ? "" : " ") + newTranscript
        previousTranscript = newTranscript
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
        attachments = sharedMediaDataSource.images.indices.map { i in
            let fileExt = i < sharedMediaDataSource.imageExtensions.count ?
                sharedMediaDataSource.imageExtensions[i] : "jpg"
                
            let filename = i < sharedMediaDataSource.imageFilenames.count ?
                sharedMediaDataSource.imageFilenames[i] : "image\(i+1).\(fileExt)"
                
            return ImageAttachment(
                id: sharedMediaDataSource.imageIDs[i],
                image: sharedMediaDataSource.images[i],
                fileExtension: fileExt,
                filename: filename
            )
        }
        
        documentAttachments = sharedMediaDataSource.documents.indices.map { i in
            let fileExt = i < sharedMediaDataSource.documentExtensions.count ?
                sharedMediaDataSource.documentExtensions[i] : "pdf"
                
            let filename = i < sharedMediaDataSource.documentFilenames.count ?
                sharedMediaDataSource.documentFilenames[i] : "document\(i+1).\(fileExt)"
            
            let textPreview = i < sharedMediaDataSource.textPreviews.count ?
                sharedMediaDataSource.textPreviews[i] : nil
                
            return DocumentAttachment(
                id: sharedMediaDataSource.documentIDs[i],
                data: sharedMediaDataSource.documents[i],
                fileExtension: fileExt,
                filename: filename,
                textPreview: textPreview
            )
        }
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
    
}

// MARK: - Supporting Views
struct PasteLoadingView: View {
    var body: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.7)
            Text("Preparing attachments…")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 34)
        .padding(.bottom, 8)
        .transition(.opacity)
    }
}

struct ImageAttachment: Identifiable {
    var id = UUID()
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
                    .help("Remove all attachments from this draft")
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
            if let text = doc.textPreview {
                WorkbenchPastedTextEditor(filename: doc.filename, initialText: text) { value in
                    sharedMediaDataSource.updatePastedText(id: doc.id, text: value)
                    if let index = documentAttachments.firstIndex(where: { $0.id == doc.id }) {
                        documentAttachments[index] = DocumentAttachment(id: doc.id, data: Data(value.utf8), fileExtension: "txt", filename: doc.filename, textPreview: value)
                    }
                }
            } else {
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
        if sharedMediaDataSource.imageEncodedData.indices.contains(index), let data = sharedMediaDataSource.imageEncodedData[index] {
            do { try data.write(to: fileURL, options: .atomic) }
            catch { logger.info("Failed to save image: \(error.localizedDescription)") }
            return
        }
        
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
                    .help(filename)
                    .accessibilityLabel("Open attachment: \(filename)")
                    
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
                    .help(filename)
                    .accessibilityLabel("Open attachment: \(filename)")
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(WorkbenchStyle.border, lineWidth: 1)
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
                .buttonStyle(PlainButtonStyle())
                .help("Remove \(filename)")
                .accessibilityLabel("Remove attachment: \(filename)"),
                alignment: .topTrailing
            )
            
            Text(filename.count > 10 ? String(filename.prefix(7)) + "..." : filename)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 60)
                .help(filename)
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
                        .font(.system(size: 11))
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
            .help("Inspect and edit pasted text")
            .accessibilityLabel("Edit pasted text")
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
                .help("Remove pasted text")
                .accessibilityLabel("Remove pasted text")
                .opacity(isHovered ? 1 : 0.55),
                alignment: .topTrailing
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            
            // "PASTED" label
            Text("PASTED")
                .font(.system(size: 9, weight: .semibold))
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
