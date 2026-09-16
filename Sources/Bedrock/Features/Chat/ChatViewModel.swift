//
//  ChatViewModel.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 6/28/24.
//

import SwiftUI
import Combine
import AWSBedrockRuntime
import Logging
import Smithy

// MARK: - Required Type Definitions for Bedrock API integration

enum MessageRole: String, Codable {
    case user = "user"
    case assistant = "assistant"
}

enum MessageContent: Codable {
    case text(String)
    case image(ImageContent)
    case document(DocumentContent)
    case thinking(ThinkingContent)
    case toolresult(ToolResultContent)
    case tooluse(ToolUseContent)
    
    // For encoding/decoding
    private enum CodingKeys: String, CodingKey {
        case type, text, image, document, thinking, toolresult, tooluse
    }
    
    struct ImageContent: Codable {
        let format: ImageFormat
        let base64Data: String
    }
    
    struct DocumentContent: Codable {
        let format: DocumentFormat
        let base64Data: String
        let name: String
    }
    
    struct ThinkingContent: Codable {
        let text: String
        let signature: String
    }
    
    struct ToolResultContent: Codable {
        let toolUseId: String
        let result: String
        let status: String
    }
    
    struct ToolUseContent: Codable {
        let toolUseId: String
        let name: String
        let input: JSONValue
    }
    
    enum DocumentFormat: String, Codable {
        case pdf = "pdf"
        case csv = "csv"
        case doc = "doc"
        case docx = "docx"
        case xls = "xls"
        case xlsx = "xlsx"
        case html = "html"
        case txt = "txt"
        case md = "md"
        
        static func fromExtension(_ ext: String) -> DocumentFormat {
            let lowercased = ext.lowercased()
            switch lowercased {
            case "pdf": return .pdf
            case "csv": return .csv
            case "doc": return .doc
            case "docx": return .docx
            case "xls": return .xls
            case "xlsx": return .xlsx
            case "html": return .html
            case "txt": return .txt
            case "md": return .md
            default: return .pdf // Default to PDF if unsupported
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let imageContent):
            try container.encode("image", forKey: .type)
            try container.encode(imageContent, forKey: .image)
        case .document(let documentContent):
            try container.encode("document", forKey: .type)
            try container.encode(documentContent, forKey: .document)
        case .thinking(let thinkingContent):
            try container.encode("thinking", forKey: .type)
            try container.encode(thinkingContent, forKey: .thinking)
        case .toolresult(let toolResultContent):
            try container.encode("toolresult", forKey: .type)
            try container.encode(toolResultContent, forKey: .toolresult)
        case .tooluse(let toolUseContent):
            try container.encode("tooluse", forKey: .type)
            try container.encode(toolUseContent, forKey: .tooluse)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image":
            let imageContent = try container.decode(ImageContent.self, forKey: .image)
            self = .image(imageContent)
        case "document":
            let documentContent = try container.decode(DocumentContent.self, forKey: .document)
            self = .document(documentContent)
        case "thinking":
            let thinkingContent = try container.decode(ThinkingContent.self, forKey: .thinking)
            self = .thinking(thinkingContent)
        case "toolresult":
            let toolResultContent = try container.decode(ToolResultContent.self, forKey: .toolresult)
            self = .toolresult(toolResultContent)
        case "tooluse":
            let toolUseContent = try container.decode(ToolUseContent.self, forKey: .tooluse)
            self = .tooluse(toolUseContent)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown content type: \(type)"
            )
        }
    }
}

struct BedrockMessage: Codable {
    let role: MessageRole
    var content: [MessageContent]
}

struct ToolUseError: Error {
    let message: String
}

// New struct for tool results in a modal
struct ToolResultInfo: Identifiable {
    let id: UUID = UUID()
    let toolUseId: String
    let toolName: String
    let input: JSONValue
    let result: String
    let status: String
    let timestamp: Date = Date()
}

@MainActor
final class StreamingMessageState: ObservableObject {
    @Published private(set) var message: MessageData?

    func update(_ value: MessageData?) {
        if message != value { message = value }
    }
}

@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Properties
    let chatId: String
    let chatManager: ConversationStore
    let sharedMediaDataSource: AttachmentStore
    @ObservedObject private var settingManager = PreferencesStore.shared
    @ObservedObject private var mcpManager = MCPClientManager.shared
    
    @ObservedObject var backendModel: BedrockConnection
    @Published var chatModel: ChatModel
    @Published private(set) var pendingModel: ChatModel?
    @Published var messages: [MessageData] = []
    @Published private(set) var isLoadingHistory = false
    private var initialLoadTask: Task<Void, Never>?
    let streamingMessage = StreamingMessageState()

    /// Checkpoints and search include the live reply without publishing a new
    /// chat array for every token and rebuilding the surrounding controls.
    var messagesIncludingStream: [MessageData] {
        guard let live = streamingMessage.message,
              let index = messages.firstIndex(where: { $0.id == live.id }) else { return messages }
        var snapshot = messages
        snapshot[index] = live
        return snapshot
    }
    @Published var userInput: String = ""
    @Published var isMessageBarDisabled: Bool = false
    @Published var isSending: Bool = false
    @Published var isStreamingEnabled: Bool = false
    @Published var selectedPlaceholder: String
    @Published var emptyText: String = ""
    @Published var availableTools: [MCPToolInfo] = []
    
    // New properties for tool results modal
    @Published var toolResults: [ToolResultInfo] = []
    @Published var isToolResultModalVisible: Bool = false
    @Published var selectedToolResult: ToolResultInfo?
    @Published var activeRunID: UUID?
    var nextAutomationID: UUID?
    @Published var contextNotice: String?
    @Published private(set) var outbox = ConversationOutbox()
    @Published private(set) var isUpdatingQueue = false
    private var canWriteOutbox = true
    private var outboxOperation: Task<Bool, Never>?
    private var queuedOperationCount = 0
    private var queueDrainTask: Task<Void, Never>?
    private var resumeQueueAfterStop = false
    private var attachmentsRestored = false
    private var canWriteAttachmentDraft = true
    private var attachmentDraftDirty = false
    private var attachmentRevision: UInt64 = 0
    private var attachmentSaveCount = 0
    private var attachmentSaveTask: Task<Void, Never>?
    private let attachmentWriter = ConversationAttachmentDraftWriter()
    private var isClosingSession = false
    var isSavingLocalWork: Bool { isUpdatingQueue || attachmentDraftDirty || attachmentSaveCount > 0 }
    
    private var logger = Logger(label: "ChatViewModel")
    private var cancellables: Set<AnyCancellable> = []
    private var messageTask: Task<Void, Never>?
    private var backgroundShutdownTask: Task<Void, Never>?
    private var didSetupBindings = false
    
    // Track current message ID being streamed to fix duplicate issue
    @Published private(set) var currentStreamingMessageId: UUID?
    
    // Thinking summary generation state
    private var lastThinkingSummaryLength: Int = 0
    private var thinkingSummaryCallCount: Int = 0
    private var thinkingSummaryTask: Task<Void, Never>?
    private var thinkingCompleted: Bool = false
    
    // Usage handler for displaying token usage information
    var usageHandler: ((String) -> Void)?
    
    // Format usage information for display
    private func formatUsageString(_ usage: UsageInfo) -> String {
        var parts: [String] = []
        
        if let input = usage.inputTokens {
            parts.append("Input: \(input)")
        }
        
        if let output = usage.outputTokens {
            parts.append("Output: \(output)")
        }
        
        if let cacheRead = usage.cacheReadInputTokens, cacheRead > 0 {
            parts.append("Cache Read: \(cacheRead)")
        }
        
        if let cacheWrite = usage.cacheCreationInputTokens, cacheWrite > 0 {
            parts.append("Cache Write: \(cacheWrite)")
        }
        
        return parts.joined(separator: " • ")
    }
    
    // MARK: - Initialization
    
    init(chatId: String, backendModel: BedrockConnection, chatManager: ConversationStore = .shared, sharedMediaDataSource: AttachmentStore) {
        self.chatId = chatId
        self.backendModel = backendModel
        self.chatManager = chatManager
        self.sharedMediaDataSource = sharedMediaDataSource
        
        // Try to get existing chat model, or create a temporary one if not found
        if let model = chatManager.getChatModel(for: chatId) {
            self.chatModel = model
            self.selectedPlaceholder = ""
            setupStreamingEnabled()
            setupBindings()
        } else {
            // Create a temporary model and load asynchronously
            logger.warning("Chat model not found for id: \(chatId), will attempt to load or create")
            self.chatModel = ChatModel(
                id: chatId,
                chatId: chatId,
                name: "Loading...",
                title: "Loading...",
                description: "",
                provider: "bedrock",
                lastMessageDate: Date()
            )
            self.selectedPlaceholder = ""
            
            // Try to load the model asynchronously
            Task {
                await loadChatModel()
            }
        }
        self.userInput = AppStore.shared.thread(chatId).draft
    }
    
    // MARK: - Setup Methods
    
    private func setupStreamingEnabled() {
        self.isStreamingEnabled = isTextGenerationModel(chatModel.id)
    }
    
    private func setupBindings() {
        guard !didSetupBindings else { return }
        didSetupBindings = true
        sharedMediaDataSource.onAttachmentsChanged = { [weak self] in self?.attachmentDraftChanged() }
        chatManager.$chats
            .map { [weak self] chats in
                chats.first { $0.chatId == self?.chatId }
            }
            .compactMap { $0 }
            .sink { [weak self] model in
                guard let self, self.chatModel !== model else { return }
                self.chatModel = model
            }
            .store(in: &cancellables)
        $userInput.dropFirst().sink { [weak self] text in
            guard let self else { return }
            AppStore.shared.updateDraft(self.chatId, text: text)
        }.store(in: &cancellables)
        
        $chatModel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] model in
                guard let self = self else { return }
                self.isStreamingEnabled = self.isTextGenerationModel(model.id)
            }
            .store(in: &cancellables)
    }
    
    private func loadChatModel() async {
        // Try to find existing model for up to 10 attempts
        for attempt in 0..<10 {
            if let model = chatManager.getChatModel(for: chatId) {
                await MainActor.run {
                    self.chatModel = model
                    setupStreamingEnabled()
                    setupBindings()
                }
                logger.info("Successfully loaded chat model for id: \(chatId) after \(attempt + 1) attempts")
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        // If still not found, create a new chat
        logger.warning("Chat model still not found for id: \(chatId) after 10 attempts, creating new chat")
        
        await MainActor.run {
            // Use default values since we can't access BedrockConnection properties directly
            chatManager.createNewChat(
                modelId: "claude-3-5-sonnet-20241022-v2:0", // Default model
                modelName: "Claude 3.5 Sonnet",
                modelProvider: "anthropic"
            ) { [weak self] newModel in
                guard let self = self else { return }
                
                // Update the chat ID if it was changed during creation
                if newModel.id != self.chatId {
                    logger.info("Chat ID changed from \(self.chatId) to \(newModel.id)")
                }
                
                self.chatModel = newModel
                self.setupStreamingEnabled()
                self.setupBindings()
                logger.info("Successfully created new chat model with id: \(newModel.id)")
            }
        }
    }
    
    // MARK: - Public Methods
    
    func loadInitialData() {
        guard initialLoadTask == nil else { return }
        if let cached = chatManager.cachedMessages(for: chatId), cached.isEmpty,
           let url = try? ConversationOutboxFile.url(threadID: chatId, directory: AppStore.shared.directory),
           let draftURL = try? ConversationAttachmentDraftFile.url(threadID: chatId, directory: AppStore.shared.directory),
           !FileManager.default.fileExists(atPath: url.path), !FileManager.default.fileExists(atPath: draftURL.path) {
            attachmentsRestored = true
            finishInitialLoad(cached)
            if !sharedMediaDataSource.isEmpty { attachmentDraftChanged() }
            return
        }
        isLoadingHistory = true
        initialLoadTask = Task { [weak self] in
            guard let self else { return }
            let loaded = await chatManager.loadMessages(for: chatId)
            // The full history is available immediately. Prewarming nearby
            // Markdown is a cache optimization, never a visible page boundary.
            async let markdown: Void = MarkdownPreparation.prewarm(ConversationTranscript.prewarmingTexts(in: loaded))
            async let queue: Void = loadOutbox(sentMessageIDs: Set(loaded.map(\.id)))
            async let attachments: Void = loadAttachmentDraft()
            _ = await (markdown, queue, attachments)
            guard !Task.isCancelled else { return }
            finishInitialLoad(loaded)
            initialLoadTask = nil
            if let next = pendingModel { switchModel(to: next) }
        }
    }

    private func finishInitialLoad(_ loaded: [MessageData]) {
        var loadedMessages = loaded
        
        // Mark tool result messages with "ToolResult" user so they are hidden in UI
        // Tool result messages have: user == "User", toolUse != nil, toolResult != nil
        for i in 0..<loadedMessages.count {
            if loadedMessages[i].user == "User" &&
               ((loadedMessages[i].toolUse != nil && loadedMessages[i].toolResult != nil) || loadedMessages[i].toolUses != nil) {
                loadedMessages[i].user = "ToolResult"
            }
        }
        
        messages = loadedMessages
        isLoadingHistory = false
        let store = AppStore.shared
        if store.state.threads[chatId] == nil,
           let prompt = chatManager.getConversationHistory(for: chatId)?.systemPrompt,
           !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt != settingManager.systemPrompt {
            store.updateThread(chatId) { $0.systemPrompt = prompt }
        }
    }

    func discardSession(stopProcesses: Bool = true) {
        isClosingSession = true
        initialLoadTask?.cancel()
        initialLoadTask = nil
        cancelSending(stopProcesses: stopProcesses)
        queueDrainTask?.cancel()
        attachmentSaveTask?.cancel()
    }

    func retainSession() { isClosingSession = false }

    /// Called before graceful quit or removing a session from the cache.
    /// The application continues processing UI events while these writes finish.
    func flushLocalWork(stopRun: Bool = false) async -> Bool {
        if stopRun {
            isClosingSession = true
            queueDrainTask?.cancel()
            cancelSending()
            await messageTask?.value
            await backgroundShutdownTask?.value
        }
        await initialLoadTask?.value
        await sharedMediaDataSource.waitForImports()
        _ = await outboxOperation?.value
        attachmentSaveTask?.cancel()
        return await persistAttachmentDraft()
    }

    private func loadAttachmentDraft() async {
        guard !attachmentsRestored else { return }
        do {
            let url = try ConversationAttachmentDraftFile.url(threadID: chatId, directory: AppStore.shared.directory)
            let value = try await Task.detached(priority: .userInitiated) { try ConversationAttachmentDraftFile.read(url) }.value
            if !value.isEmpty { try await sharedMediaDataSource.restoreAttachmentDraft(value) }
            attachmentsRestored = true
            AppStore.shared.updateThread(chatId) { $0.hasDraftAttachments = !sharedMediaDataSource.isEmpty }
        } catch {
            attachmentsRestored = true
            canWriteAttachmentDraft = false
            AppStore.shared.errorMessage = "Could not restore unsent attachments. The original draft file was kept.\n\(error.localizedDescription)"
        }
    }

    private func attachmentDraftChanged() {
        guard attachmentsRestored else { return }
        attachmentRevision &+= 1
        attachmentDraftDirty = true
        AppStore.shared.updateThread(chatId) { $0.hasDraftAttachments = !sharedMediaDataSource.isEmpty }
        attachmentSaveTask?.cancel()
        attachmentSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(180)) }
            catch { return }
            guard let self else { return }
            _ = await persistAttachmentDraft()
        }
    }

    private func persistAttachmentDraft() async -> Bool {
        guard attachmentDraftDirty else { return true }
        guard canWriteAttachmentDraft else {
            AppStore.shared.errorMessage = "The original attachment draft could not be opened. Your current attachments remain in this window."
            return false
        }
        let revision = attachmentRevision
        attachmentSaveCount += 1
        defer { attachmentSaveCount -= 1 }
        do {
            let value = try sharedMediaDataSource.attachmentDraft()
            let url = try ConversationAttachmentDraftFile.url(threadID: chatId, directory: AppStore.shared.directory)
            try await attachmentWriter.write(value, to: url, revision: revision)
            if attachmentRevision == revision { attachmentDraftDirty = false }
            return true
        } catch {
            AppStore.shared.errorMessage = "Could not save unsent attachments. They remain in this window.\n\(error.localizedDescription)"
            return false
        }
    }

    func submitDraft() async {
        if isSending { await enqueueCurrentPrompt() }
        else { sendMessage() }
    }

    private func loadOutbox(sentMessageIDs: Set<UUID>) async {
        do {
            let url = try ConversationOutboxFile.url(threadID: chatId, directory: AppStore.shared.directory)
            var value = try await Task.detached(priority: .userInitiated) { try ConversationOutboxFile.read(url) }.value
            value.recover(sentMessageIDs: sentMessageIDs)
            outbox = value
        } catch {
            canWriteOutbox = false
            AppStore.shared.errorMessage = "Could not restore queued messages. The original queue file was kept.\n\(error.localizedDescription)"
        }
    }

    private func enqueueCurrentPrompt() async {
        guard !isUpdatingQueue, !sharedMediaDataSource.isImporting,
              !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !sharedMediaDataSource.isEmpty else { return }
        let text = userInput
        let imageIDs = Set(sharedMediaDataSource.imageIDs)
        let documentIDs = Set(sharedMediaDataSource.documentIDs)
        let prompt = QueuedPrompt(message: createUserMessage(), modelID: pendingModel?.id ?? chatModel.id)
        let saved = await updateOutbox { try $0.append(prompt) }
        if saved {
            if userInput == text { userInput = "" }
            sharedMediaDataSource.remove(imageIDs: imageIDs, documentIDs: documentIDs)
            drainQueue()
        }
    }

    func removeQueuedPrompt(_ id: UUID) async {
        _ = await updateOutbox { $0.queued.removeAll { $0.id == id } }
    }

    func editQueuedPrompt(_ id: UUID, text: String) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                (outbox.queued.first(where: { $0.id == id })?.attachmentCount ?? 0) > 0 else {
            throw LocalOperationError.invalid("Write a message or keep an attachment.")
        }
        guard await updateOutbox({ value in
            guard let index = value.queued.firstIndex(where: { $0.id == id }) else {
                throw LocalOperationError.invalid("This queued message has already been sent or removed.")
            }
            value.queued[index].message.text = text
        }) else { throw LocalOperationError.invalid("The queued message could not be saved. Your original message was kept.") }
    }

    func setQueuePaused(_ paused: Bool) async {
        if await updateOutbox({ $0.pauseReason = paused ? "Queue paused. Your messages are saved on this Mac." : nil }) {
            if !paused { drainQueue() }
        }
    }

    func sendQueuedPromptNow(_ id: UUID) async {
        guard outbox.queued.contains(where: { $0.id == id }) else { return }
        if await updateOutbox({ $0.moveToFront(id); $0.pauseReason = nil }) {
            if isSending {
                resumeQueueAfterStop = true
                cancelSending()
            } else { drainQueue() }
        }
    }

    /// Serialize complete mutations, including their UI state commit. A request
    /// finishing at the same time as an enqueue cannot overwrite that enqueue.
    private func updateOutbox(_ change: @escaping @MainActor (inout ConversationOutbox) throws -> Void) async -> Bool {
        guard canWriteOutbox else {
            AppStore.shared.errorMessage = "The saved queue needs recovery before it can be changed. Its file was preserved."
            return false
        }
        let previous = outboxOperation
        queuedOperationCount += 1
        isUpdatingQueue = true
        let operation = Task { [weak self] in
            _ = await previous?.value
            guard let self else { return false }
            defer {
                queuedOperationCount -= 1
                isUpdatingQueue = queuedOperationCount > 0
                if !isUpdatingQueue { outboxOperation = nil }
            }
            do {
                var next = outbox
                try change(&next)
                let url = try ConversationOutboxFile.url(threadID: chatId, directory: AppStore.shared.directory)
                let snapshot = next
                try await Task.detached(priority: .userInitiated) { try ConversationOutboxFile.write(snapshot, to: url) }.value
                outbox = next
                AppStore.shared.updateThread(chatId) { $0.hasQueuedMessages = !next.queued.isEmpty || next.inFlight != nil }
                return true
            } catch {
                outbox.pauseReason = "The queue could not be saved. Try resuming after checking local storage."
                AppStore.shared.errorMessage = error.localizedDescription
                return false
            }
        }
        outboxOperation = operation
        return await operation.value
    }

    private func drainQueue() {
        guard !isClosingSession, !isSending, !isLoadingHistory, !isUpdatingQueue, queueDrainTask == nil,
              outbox.pauseReason == nil, outbox.inFlight == nil, !outbox.queued.isEmpty,
              AppStore.shared.thread(chatId).deletedAt == nil else { return }
        queueDrainTask = Task { [weak self] in
            guard let self else { return }
            defer { queueDrainTask = nil }
            guard !Task.isCancelled, let prompt = outbox.queued.first else { return }
            let draftModel = pendingModel ?? chatModel
            switchModel(to: ModelCatalog.shared.model(prompt.modelID))
            guard chatModel.id == prompt.modelID, pendingModel == nil else {
                _ = await updateOutbox { $0.pauseReason = "Choose an available model before resuming this queue." }
                return
            }
            guard await updateOutbox({ value in
                guard value.queued.first?.id == prompt.id else { throw LocalOperationError.invalid("The next queued message changed.") }
                value.queued.removeFirst()
                value.inFlight = prompt
            }) else { return }
            if sendPreparedMessage(prompt.message) {
                // Keep the user's composer selection for their next draft.
                if draftModel.id != chatModel.id { pendingModel = draftModel }
            } else {
                _ = await updateOutbox {
                    $0.inFlight = nil
                    $0.queued.insert(prompt, at: 0)
                    $0.pauseReason = "This message needs attention. Check its model or attachments, then resume."
                }
                switchModel(to: draftModel)
            }
        }
    }

    private func finishQueuedRun(_ outcome: RunStatus) async {
        let resume = resumeQueueAfterStop
        resumeQueueAfterStop = false
        guard outbox.inFlight != nil || !outbox.queued.isEmpty || isUpdatingQueue else { return }
        _ = await updateOutbox {
            $0.inFlight = nil
            if outcome != .completed && !resume {
                $0.pauseReason = outcome == .cancelled ? "Response stopped. Resume to send the remaining messages." :
                    "The last response failed. Review the error, then resume the queue."
            }
        }
    }
    
    func sendMessage() {
        // Allow sending if there's text, images, or documents
        guard !isSending, !isLoadingHistory, !sharedMediaDataSource.isImporting, !AppStore.shared.isRelocating,
                !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !sharedMediaDataSource.isEmpty else { return }
        let message = createUserMessage()
        if sendPreparedMessage(message) {
            userInput = ""
            sharedMediaDataSource.clear()
        }
    }

    func continueResponse() {
        guard AppStore.shared.state.runs.first(where: { $0.threadID == chatId })?.canContinueResponse == true else { return }
        // A follow-up has its own immutable prompt. Preserve the unrelated
        // draft and attachments already present in the composer.
        _ = sendPreparedMessage(MessageData(
            text: "Continue the previous response from where it stopped. Do not repeat content already provided.",
            user: "User", sentTime: Date()
        ))
    }

    /// Queue/retry requests have their own immutable attachments. Starting one
    /// must not clear a different draft the user is composing in this thread.
    @discardableResult
    func sendPreparedMessage(_ message: MessageData) -> Bool {
        guard ValidationMode.permitsInference(
            modelID: pendingModel?.id ?? chatModel.id,
            runtimeEndpoint: backendModel.backend.runtimeEndpoint
        ) else {
            AppStore.shared.errorMessage = "AWS requests are disabled in this isolated UI test run."
            return false
        }
        guard !isClosingSession, !isSending, !isLoadingHistory, !AppStore.shared.isRelocating else { return false }
        if let next = pendingModel {
            switchModel(to: next)
            // A storage failure must not silently send with a different model
            // from the one still selected in the composer.
            guard pendingModel == nil else { return false }
        }
        guard chatManager.canWriteConversation(chatId) else {
            AppStore.shared.errorMessage = chatManager.persistenceError
            return false
        }
        do {
            _ = try AppStore.shared.effectiveSystemPrompt(for: chatId)
            try validateDemoInputs(message)
            try validateImageInputs(message.imageBase64Strings?.count ?? 0)
            if BedrockModelID.base(chatModel.id).hasPrefix("luma.") {
                let config = settingManager.lumaVideoConfig
                _ = try config.request(prompt: message.text)
                let validation = NovaReelService.validateS3Uri(config.outputBucket)
                guard validation.isValid else { throw LocalOperationError.invalid("Choose an output S3 bucket in response settings before generating a video.") }
                guard (message.imageBase64Strings?.count ?? 0) <= 2 else { throw LocalOperationError.invalid("Attach at most two video keyframes: the start image and the end image.") }
            }
            if backendModel.backend.isMantleResponsesModel(chatModel.id) &&
                (message.imageBase64Strings?.isEmpty == false || message.documentBase64Strings?.isEmpty == false) {
                throw LocalOperationError.invalid("This model currently accepts text only in this app. Choose a vision/document model or remove the attachments.")
            }
            if message.documentBase64Strings?.isEmpty == false && !backendModel.backend.isDocumentChatSupported(chatModel.id) {
                throw LocalOperationError.invalid("This model does not accept document attachments. Choose a document-capable model.")
            }
            if message.imageBase64Strings?.isEmpty == false &&
                !backendModel.backend.isVisionSupported(chatModel.id) &&
                !backendModel.backend.isImageGenerationModel(chatModel.id) {
                throw LocalOperationError.invalid("This model does not accept images. Choose a vision model to send these attachments.")
            }
        } catch {
            AppStore.shared.errorMessage = error.localizedDescription
            return false
        }
        isSending = true
        var prepared = message
        prepared.modelID = chatModel.id
        let previousShutdown = backgroundShutdownTask
        messageTask = Task {
            // A queued follow-up must not start a process while the previous
            // turn's Stop action is still collecting and cancelling its jobs.
            await previousShutdown?.value
            await sendMessageAsync(prepared)
        }
        return true
    }

    private func validateDemoInputs(_ message: MessageData) throws {
        let store = AppStore.shared
        if store.thread(chatId).demoID == "project-review" {
            guard store.preferences.enabledTools.contains(.readFile),
                  store.preferences.enabledTools.contains(.listFiles) else {
                throw LocalOperationError.invalid("Enable Read files and List files in Settings → Tools & MCP before running this demo.")
            }
        }
        guard messages.isEmpty else { return }
        switch store.thread(chatId).demoID {
        case "document" where message.documentBase64Strings?.isEmpty != false:
            throw LocalOperationError.invalid("Attach a document before running this demo. Your prompt is ready in the message bar.")
        case "vision" where message.imageBase64Strings?.isEmpty != false:
            throw LocalOperationError.invalid("Attach an image or screenshot before running this demo.")
        default: break
        }
    }

    private func validateImageInputs(_ count: Int) throws {
        if let service = StabilityAIImageService.matching(chatModel.id) {
            let required = service == .styleTransfer || service == .erase ? 2 : 1
            guard count >= required else {
                let detail = service == .styleTransfer ? "Attach the source image first and the style reference second." :
                    service.requiresMask ? "Attach the source image first and the mask second." : "Attach a source image, or choose an image creation model."
                throw LocalOperationError.invalid("\(service.displayName) needs \(required == 1 ? "an image" : "two images"). \(detail)")
            }
            let config = settingManager.stabilityAIServicesConfig
            if service == .outpaint && [config.outpaintLeft, config.outpaintRight, config.outpaintUp, config.outpaintDown].allSatisfy({ $0 == 0 }) {
                throw LocalOperationError.invalid("Set at least one extension direction in response settings before outpainting.")
            }
            if [.searchReplace, .searchRecolor].contains(service) && config.searchPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw LocalOperationError.invalid("Describe the object to change in response settings before using \(service.displayName).")
            }
        } else if chatModel.id.contains("stability.") && settingManager.stabilityAIConfig.taskType == StabilityAITaskType.imageToImage.rawValue {
            guard chatModel.id.contains("sd3") else {
                throw LocalOperationError.invalid("This model creates images from text. Choose Text to Image in response settings, or select SD3.5 Large to edit an image.")
            }
            guard count > 0 else { throw LocalOperationError.invalid("Attach a source image before using Image to Image.") }
        }
    }
    
    func sendMessage(_ message: String) {
        guard !isSending, !message.isEmpty else { return }
        
        // Set the message and send it
        userInput = message
        sendMessage()
    }
    
    func cancelSending() { cancelSending(stopProcesses: true) }

    private func cancelSending(stopProcesses: Bool) {
        if stopProcesses {
            let owner = chatId
            let previousShutdown = backgroundShutdownTask
            backgroundShutdownTask = Task {
                await previousShutdown?.value
                await BackgroundProcessRegistry.shared.stopAll(owner: owner)
            }
        }
        messageTask?.cancel()
        thinkingSummaryTask?.cancel()
        ToolApprovalCenter.shared.cancel(threadID: chatId)
    }

    /// A running response finishes with the model that started it. The composer
    /// can already select the next model without losing this session or its draft.
    func switchModel(to model: ChatModel) {
        if isSending || isLoadingHistory {
            pendingModel = model.id == chatModel.id ? nil : model
            return
        }
        let previousID = chatModel.id
        guard previousID != model.id else {
            pendingModel = nil
            return
        }
        guard let updated = chatManager.changeModel(for: chatId, to: model) else {
            pendingModel = model
            AppStore.shared.errorMessage = chatManager.persistenceError ??
                "Could not switch to \(model.name). Your draft is saved. Try selecting the model again."
            return
        }
        if messages.contains(where: { $0.modelID == nil }) {
            messages = messages.map { message in
                var message = message
                if message.modelID == nil { message.modelID = previousID }
                return message
            }
        }
        chatModel = updated
        pendingModel = nil
        contextNotice = nil
    }

    func showToolResultDetails(_ toolResult: ToolResultInfo) {
        selectedToolResult = toolResult
        isToolResultModalVisible = true
    }

    func waitUntilReady() async {
        await initialLoadTask?.value
        await AppStore.shared.waitForSkills()
    }

    func branchAndSend(prompt: Message, text: String? = nil) async throws {
        guard !isSending, !isLoadingHistory else { throw LocalOperationError.invalid("Wait for this response to finish or stop it first.") }
        let history = try await chatManager.conversationSnapshot(for: chatId)
        let prefix = try ConversationEditing.messages(in: history, before: prompt.id)
        let model = pendingModel ?? chatModel
        let branch = try await AppActions.branch(chatModel, messages: prefix,
                                                      originalSystemPrompt: history.systemPrompt, model: model, select: false)
        let session = ChatSessionPool.shared.session(chatID: branch.chatId, backend: backendModel)
        await session.waitUntilReady()
        let outgoing = MessageData(text: text ?? prompt.text, user: "User", sentTime: Date(),
                                   imageBase64Strings: prompt.imageBase64Strings,
                                   documentBase64Strings: prompt.documentBase64Strings,
                                   documentFormats: prompt.documentFormats, documentNames: prompt.documentNames,
                                   pastedTexts: prompt.pastedTexts, modelID: model.id)
        AppStore.shared.selectThread(branch.chatId)
        if !session.sendPreparedMessage(outgoing) {
            session.userInput = outgoing.text
            try await session.sharedMediaDataSource.restore(outgoing,
                imagesDirectory: URL(fileURLWithPath: settingManager.defaultDirectory).appendingPathComponent("generated_images"))
        }
        AppWindows.focusComposer()
    }
    
    // MARK: - Private Message Handling Methods
    
    private func sendMessageAsync(_ preparedMessage: MessageData) async {
        chatManager.setIsLoading(true, for: chatId)
        isMessageBarDisabled = true
        defer {
            commitStreamingMessage()
            isSending = false
            isMessageBarDisabled = false
            currentStreamingMessageId = nil
            chatManager.setIsLoading(false, for: chatId)
            if let next = pendingModel { switchModel(to: next) }
            drainQueue()
        }

        let tempInput = preparedMessage.text
        if AppStore.shared.preferences.automaticTitles {
            Task { await updateChatTitle(with: tempInput) }
        } else if messages.isEmpty && !chatModel.isManuallyRenamed {
            let title = tempInput.trimmingCharacters(in: .whitespacesAndNewlines)
            chatManager.updateChatTitle(for: chatId, title: title.isEmpty ? "Attachment analysis" : String(title.prefix(70)))
        }
        let runID = AppStore.shared.beginRun(threadID: chatId, modelID: chatModel.id, title: tempInput, automationID: nextAutomationID)
        nextAutomationID = nil
        activeRunID = runID
        var outcome: RunStatus = .completed
        var failure: String?
        var userMessage = preparedMessage
        if userMessage.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userMessage.text = userMessage.imageBase64Strings?.isEmpty != false ? "Please analyze the attached document." : "Please analyze the attached image."
        }
        addMessage(userMessage)
        
        let attachedImages = userMessage.imageBase64Strings ?? []
        
        do {
            await AppStore.shared.waitForSkills()
            try Task.checkCancellation()
            if backendModel.backend.isImageGenerationModel(chatModel.id) {
                try await handleImageGenerationModel(userMessage, attachedImages: attachedImages)
            } else if backendModel.backend.isEmbeddingModel(chatModel.id) {
                try await handleEmbeddingModel(userMessage)
            } else if backendModel.backend.isMantleResponsesModel(chatModel.id) {
                // OpenAI frontier models (GPT-5.5/5.4) are served only via the bedrock-mantle Responses API
                try await handleMantleResponsesModel(userMessage)
            } else {
                // The backend emits the same events for a full response and a
                // streamed response, so tool execution works with either setting.
                try await handleTextLLMWithConverseStream(userMessage)
            }
        } catch let error {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                outcome = .cancelled
            } else if let nsError = error as NSError?,
               nsError.localizedDescription.contains("ValidationException") &&
                nsError.localizedDescription.contains("maxLength: 512") {
                outcome = .failed
                failure = error.localizedDescription
                let errorMessage = MessageData(
                    id: UUID(),
                    text: "Error: Your prompt is too long. Titan Image Generator has a 512 character limit for prompts. Please try again with a shorter prompt.",
                    user: "System",
                    isError: true,
                    sentTime: Date()
                )
                addMessage(errorMessage)
            } else {
                outcome = .failed
                failure = error.localizedDescription
                await handleModelError(error)
            }
        }
        commitStreamingMessage()
        if Task.isCancelled { outcome = .cancelled }
        await saveFromUIMessages()
        AppStore.shared.finishRun(runID, status: outcome, error: failure)
        await finishQueuedRun(outcome)
        if outcome == .completed || outcome == .failed {
            await NotificationService.shared.post(title: outcome == .completed ? "Response ready" : "Bedrock request failed",
                                                     body: chatModel.title, threadID: chatId)
        }
    }
    
    private func createUserMessage() -> MessageData {
        // Process images
        let imageBase64Strings = sharedMediaDataSource.images.enumerated().compactMap { index, image -> String? in
            if sharedMediaDataSource.imageEncodedData.indices.contains(index),
               let data = sharedMediaDataSource.imageEncodedData[index] { return data.base64EncodedString() }
            guard index < sharedMediaDataSource.fileExtensions.count else {
                logger.error("Missing extension for image at index \(index)")
                return nil
            }
            
            let fileExtension = sharedMediaDataSource.fileExtensions[index]
            let result = base64EncodeImage(image, withExtension: fileExtension)
            return result.base64String
        }
        
        // Process documents with improved error handling
        // Pasted text (has textPreview) is sent as text block, not document block
        // This avoids Bedrock's 5 document limit in conversation history
        var documentBase64Strings: [String] = []
        var documentFormats: [String] = []
        var documentNames: [String] = []
        var pastedTextInfos: [PastedTextInfo] = []  // For UI display
        var pastedTextContents: [String] = []  // For text block in API
        
        for (index, docData) in sharedMediaDataSource.documents.enumerated() {
            // Check if this is pasted text (has textPreview)
            let isPastedText = index < sharedMediaDataSource.textPreviews.count &&
                               sharedMediaDataSource.textPreviews[index] != nil
            
            if isPastedText {
                // Convert pasted text to string and add to text contents
                if let textContent = String(data: docData, encoding: .utf8) {
                    let filename = index < sharedMediaDataSource.documentFilenames.count ?
                        sharedMediaDataSource.documentFilenames[index] : "pasted_text.txt"
                    pastedTextContents.append("[\(filename)]\n\(textContent)")
                    pastedTextInfos.append(PastedTextInfo(filename: filename, content: textContent))
                    logger.info("Added pasted text as text block: \(filename) (\(docData.count) bytes)")
                }
                continue  // Skip adding to document arrays
            }
            
            // Regular document processing
            guard index < sharedMediaDataSource.documentExtensions.count,
                  index < sharedMediaDataSource.documentFilenames.count else {
                logger.error("Missing extension or filename for document at index \(index)")
                continue
            }
            
            let fileExt = sharedMediaDataSource.documentExtensions[index]
            let filename = sharedMediaDataSource.documentFilenames[index]
            
            // Validate file extension is supported
            let supportedExtensions = ["pdf", "csv", "doc", "docx", "xls", "xlsx", "html", "txt", "md"]
            guard supportedExtensions.contains(fileExt.lowercased()) else {
                logger.error("Unsupported document format: \(fileExt)")
                continue
            }
            
            // Validate document data is not empty
            guard !docData.isEmpty else {
                logger.error("Empty document data for \(filename)")
                continue
            }
            
            let base64String = docData.base64EncodedString()
            documentBase64Strings.append(base64String)
            documentFormats.append(fileExt)
            documentNames.append(filename)
            
            logger.info("Added document: \(filename) (\(fileExt), \(docData.count) bytes)")
        }
        
        // Determine the text to send
        // Bedrock API requires a text block when sending images or documents
        // Include pasted text contents in the text block (not as documents)
        var textToSend: String
        
        // Start with user input or default prompt
        if userInput.isEmpty {
            if !documentBase64Strings.isEmpty && !imageBase64Strings.isEmpty {
                textToSend = "Please analyze these documents and images."
            } else if !documentBase64Strings.isEmpty {
                textToSend = "Please analyze this document."
            } else if !imageBase64Strings.isEmpty {
                textToSend = "Please analyze this image."
            } else if !pastedTextContents.isEmpty {
                textToSend = "Please analyze this text."
            } else {
                textToSend = userInput
            }
        } else {
            textToSend = userInput
        }
        
        // Store original text for UI display (pasted texts shown separately as chips)
        // The pasted text content will be appended when converting to Bedrock message format
        return MessageData(
            id: UUID(),
            text: textToSend,  // Original user input only, not including pasted text
            user: "User",
            isError: false,
            sentTime: Date(),
            imageBase64Strings: imageBase64Strings.isEmpty ? nil : imageBase64Strings,
            documentBase64Strings: documentBase64Strings.isEmpty ? nil : documentBase64Strings,
            documentFormats: documentFormats.isEmpty ? nil : documentFormats,
            documentNames: documentNames.isEmpty ? nil : documentNames,
            pastedTexts: pastedTextInfos.isEmpty ? nil : pastedTextInfos,
            modelID: chatModel.id
        )
    }
    
    // MARK: - Tool Conversion and Processing
    
    private func convertMCPToolsToBedrockFormat(_ tools: [MCPToolInfo]) throws -> AWSBedrockRuntime.BedrockRuntimeClientTypes.ToolConfiguration {
        let bedrockTools: [AWSBedrockRuntime.BedrockRuntimeClientTypes.Tool] = try tools.map { info in
            // Preserve nested objects, arrays, enums, descriptions and $defs.
            // Reconstructing only property types makes valid MCP tools unusable.
            let data = try JSONEncoder().encode(info.tool.inputSchema)
            guard let schema = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LocalOperationError.invalid("The input schema for MCP tool \(info.toolName) must be a JSON object.")
            }
            let document = try Smithy.Document.make(from: schema)
            let description = "\(info.tool.description ?? info.toolName)\nMCP server: \(info.serverName). Original tool name: \(info.toolName)."
            return .toolspec(.init(description: description,
                                   inputSchema: .json(document), name: info.invocationName))
        }
        return .init(toolChoice: .auto(.init()), tools: bedrockTools)
    }

    // MARK: - handleTextLLMWithConverseStream
    
    private func handleTextLLMWithConverseStream(_ userMessage: MessageData) async throws {
        // Create message content from user message
        var messageContents: [MessageContent] = []
        
        // Build full text including pasted texts for API transmission
        var fullText = userMessage.text
        if let pastedTexts = userMessage.pastedTexts, !pastedTexts.isEmpty {
            for pastedText in pastedTexts {
                if !fullText.isEmpty {
                    fullText += "\n\n---\n\n"
                }
                fullText += "[\(pastedText.filename)]:\n\(pastedText.content)"
            }
            logger.debug("[API] Added \(pastedTexts.count) pasted text(s) to message")
        }
        
        // Always include a text prompt as required when sending documents/images/pasted texts
        var textToSend = fullText
        if textToSend.isEmpty {
            if userMessage.documentBase64Strings?.isEmpty == false {
                textToSend = "Please analyze this document."
            } else if userMessage.imageBase64Strings?.isEmpty == false {
                textToSend = "Please analyze this image."
            } else if userMessage.pastedTexts?.isEmpty == false {
                textToSend = "Please analyze this text."
            }
        }
        messageContents.append(.text(textToSend))
        
        // Add images if present
        if let imageBase64Strings = userMessage.imageBase64Strings, !imageBase64Strings.isEmpty {
            for base64String in imageBase64Strings {
                let format = ImageFormat.detectFromBase64(base64String)
                messageContents.append(.image(MessageContent.ImageContent(
                    format: format,
                    base64Data: base64String
                )))
            }
        }
        
        // Add documents if present
        if let documentBase64Strings = userMessage.documentBase64Strings,
           let documentFormats = userMessage.documentFormats,
           let documentNames = userMessage.documentNames,
           !documentBase64Strings.isEmpty {
            
            for (index, base64String) in documentBase64Strings.enumerated() {
                guard index < documentFormats.count && index < documentNames.count else {
                    continue
                }
                
                let fileExt = documentFormats[index].lowercased()
                let fileName = documentNames[index]
                
                let docFormat = MessageContent.DocumentFormat.fromExtension(fileExt)
                messageContents.append(.document(MessageContent.DocumentContent(
                    format: docFormat,
                    base64Data: base64String,
                    name: fileName
                )))
            }
        }

        // Save current messages first, then get conversation history
        // This ensures the new user message (with pastedTexts) is included
        await saveFromUIMessages()
        let conversationHistory = try await getConversationHistory()
        
        // Get tool configurations if MCP is enabled
        var toolConfig: AWSBedrockRuntime.BedrockRuntimeClientTypes.ToolConfiguration? = nil
        
        // Check if any MCP server is actually connected (subprocess running)
        let hasConnectedServer = mcpManager.connectionStatus.values.contains(.connected)
        
        if mcpManager.mcpEnabled &&
            !mcpManager.toolInfos.isEmpty &&
            hasConnectedServer &&
            backendModel.backend.isStreamingToolUseSupported(chatModel.id) {
            let toolCount = mcpManager.toolInfos.count
            let connectedCount = mcpManager.connectionStatus.values.filter { $0 == .connected }.count
            logger.info("MCP enabled with \(toolCount) tools from \(connectedCount) connected server(s) for model \(chatModel.id).")
            toolConfig = try convertMCPToolsToBedrockFormat(mcpManager.toolInfos)
            // MCP connection notification is sent from MCPClientManager when server connects
        } else if mcpManager.mcpEnabled && !mcpManager.toolInfos.isEmpty && !hasConnectedServer {
            logger.info("MCP enabled but no servers connected yet.")
        } else if mcpManager.mcpEnabled && hasConnectedServer && !backendModel.backend.isStreamingToolUseSupported(chatModel.id) {
            logger.info("MCP enabled, but model \(chatModel.id) does not support streaming tool use. Tools disabled.")
        }
        if backendModel.backend.isStreamingToolUseSupported(chatModel.id) {
            let localTools = LocalToolExecutor.specifications(threadID: chatId)
            if !localTools.isEmpty {
                let existing = toolConfig?.tools ?? []
                toolConfig = .init(toolChoice: .auto(.init()), tools: existing + localTools)
            }
        }
        let availableToolNames = (toolConfig?.tools ?? []).compactMap { tool -> String? in
            guard case .toolspec(let specification) = tool else { return nil }
            return specification.name
        }
        let systemPrompt = try AppStore.shared.effectiveSystemPrompt(for: chatId, availableToolNames: availableToolNames)
        
        // Reset tool tracker for new conversation
        
        let maxTurns = settingManager.maxToolUseTurns
        let turn_count = 0
        
        // Get Bedrock messages in AWS SDK format
        let bedrockMessages = try conversationHistory.map { try convertToBedrockMessage($0, modelId: chatModel.id) }
        
        // Convert to system prompt format used by AWS SDK
        let systemContentBlock: [AWSBedrockRuntime.BedrockRuntimeClientTypes.SystemContentBlock]? =
        systemPrompt.isEmpty ? nil : [.text(systemPrompt)]
        
        logger.info("Starting converseStream request with model ID: \(chatModel.id)")
        
        // Start the tool cycling process
        try await processToolCycles(bedrockMessages: bedrockMessages, systemContentBlock: systemContentBlock, toolConfig: toolConfig, turnCount: turn_count, maxTurns: maxTurns)
    }
    
    // Drain each response before executing tools. The accumulator belongs to this
    // response, so simultaneous threads and multiple tool blocks cannot collide.
    private func processToolCycles(
        bedrockMessages: [AWSBedrockRuntime.BedrockRuntimeClientTypes.Message],
        systemContentBlock: [AWSBedrockRuntime.BedrockRuntimeClientTypes.SystemContentBlock]?,
        toolConfig: AWSBedrockRuntime.BedrockRuntimeClientTypes.ToolConfiguration?,
        turnCount: Int,
        maxTurns: Int
    ) async throws {
        var history = bedrockMessages
        for cycle in turnCount..<max(1, maxTurns) {
            try Task.checkCancellation()
            let messageID = UUID()
            currentStreamingMessageId = messageID
            var text = ""
            var thinking = ""
            var signature = ""
            var tools = ToolStreamAccumulator()
            var lastDisplayUpdate = Date.distantPast
            var lastCheckpoint = Date()
            var didCommitResponse = false
            defer {
                // Stop and transport errors must retain the final buffered
                // characters even when they arrived between display updates.
                if !didCommitResponse {
                    displayStream(id: messageID, text: text, thinking: thinking, signature: signature)
                    commitStreamingMessage()
                }
            }
            let runID = activeRunID
            let stream = try await backendModel.backend.converseStream(
                withId: chatModel.id, messages: history, systemContent: systemContentBlock,
                toolConfig: toolConfig,
                usageHandler: { @Sendable [weak self] usage in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.usageHandler?(self.formatUsageString(usage))
                        if let runID { AppStore.shared.recordUsage(usage, runID: runID) }
                    }
                }
            )
            for try await chunk in stream {
                try Task.checkCancellation()
                if case .messagestop(let event) = chunk, let runID {
                    AppStore.shared.updateRun(runID) { $0.stopReason = event.stopReason?.rawValue }
                }
                if case .contentblockstart(let event) = chunk,
                   let index = event.contentBlockIndex, case .tooluse(let tool)? = event.start,
                   let id = tool.toolUseId, let name = tool.name {
                    try tools.begin(index: index, id: id, name: name)
                }
                if case .contentblockdelta(let event) = chunk,
                   let index = event.contentBlockIndex, case .tooluse(let delta)? = event.delta,
                   let json = delta.input {
                    try tools.append(index: index, json: json)
                }
                if case .contentblockstop(let event) = chunk, let index = event.contentBlockIndex {
                    try tools.complete(index: index)
                }
                if let delta = extractTextFromChunk(chunk) { text += delta }
                let reasoning = extractThinkingFromChunk(chunk)
                if let delta = reasoning.text { thinking += delta }
                if let delta = reasoning.signature { signature += delta }
                let displayInterval = text.utf8.count > 24_000 ? 0.12 : 0.08
                if (!text.isEmpty || !thinking.isEmpty) && Date().timeIntervalSince(lastDisplayUpdate) >= displayInterval {
                    displayStream(id: messageID, text: text, thinking: thinking, signature: signature)
                    lastDisplayUpdate = Date()
                }
                if Date().timeIntervalSince(lastCheckpoint) >= 2 {
                    await saveFromUIMessages()
                    lastCheckpoint = Date()
                }
            }
            displayStream(id: messageID, text: text, thinking: thinking, signature: signature)
            commitStreamingMessage()
            didCommitResponse = true
            let calls = try tools.finish()
            if calls.isEmpty {
                if AppStore.shared.preferences.thinkingSummaries && !thinking.isEmpty {
                    thinkingSummaryTask = Task { [weak self] in
                        await self?.generateThinkingSummary(for: messageID, thinking: thinking)
                    }
                }
                await saveFromUIMessages()
                currentStreamingMessageId = nil
                return
            }

            var assistantContents: [MessageContent] = []
            if !thinking.isEmpty && !signature.isEmpty {
                assistantContents.append(.thinking(.init(text: thinking, signature: signature)))
            }
            if !text.isEmpty { assistantContents.append(.text(text)) }
            var storedCalls: [Message.ToolUse] = try calls.map { call in
                let input = try JSONDecoder().decode(JSONValue.self, from: Data(call.inputJSON.utf8))
                assistantContents.append(.tooluse(.init(toolUseId: call.id, name: call.name, input: input)))
                let info = mcpManager.toolInfo(named: call.name)
                return Message.ToolUse(toolId: call.id, toolName: call.name, inputs: input,
                                       displayName: info?.toolName, serverName: info?.serverName)
            }
            if let index = messages.firstIndex(where: { $0.id == messageID }) {
                messages[index].toolUses = storedCalls
            }
            var resultContents: [MessageContent] = []
            for index in storedCalls.indices {
                let call = storedCalls[index]
                let started = Date()
                let result: SendableToolResult
                if Task.isCancelled {
                    // Keep every tool use paired with a result in persisted
                    // history, including tools that Stop prevented from starting.
                    result = .init(status: "error", text: "Tool stopped before execution.", error: "Cancelled")
                } else {
                    result = await executeSendableMCPTool(id: call.toolId, name: call.toolName, input: call.inputs.asDictionary ?? [:])
                    if let runID { AppStore.shared.updateRun(runID) { $0.toolCalls += 1 } }
                }
                storedCalls[index].result = result.text
                storedCalls[index].status = result.status
                storedCalls[index].resultTimestamp = Date()
                storedCalls[index].elapsedSeconds = Date().timeIntervalSince(started)
                toolResults.append(.init(toolUseId: call.toolId, toolName: call.toolName, input: call.inputs, result: result.text, status: result.status))
                resultContents.append(.toolresult(.init(toolUseId: call.toolId, result: result.text, status: result.status)))
                if let messageIndex = messages.firstIndex(where: { $0.id == messageID }) { messages[messageIndex].toolUses = storedCalls }
            }
            messages.append(MessageData(text: "", user: "ToolResult", sentTime: Date(), toolUses: storedCalls, modelID: chatModel.id))
            await saveFromUIMessages()
            try Task.checkCancellation()
            history.append(try convertToBedrockMessage(.init(role: .assistant, content: assistantContents), modelId: chatModel.id))
            history.append(try convertToBedrockMessage(.init(role: .user, content: resultContents), modelId: chatModel.id))
            if cycle + 1 >= max(1, maxTurns) {
                throw LocalOperationError.invalid("Stopped after \(maxTurns) tool turns. The results are saved. Send a follow-up to continue or change the limit in Tools & MCP.")
            }
        }
    }

    private func displayStream(id: UUID, text: String, thinking: String, signature: String) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            var message = streamingMessage.message?.id == id ? streamingMessage.message! : messages[index]
            message.text = text
            message.thinking = thinking.isEmpty ? nil : thinking
            message.signature = signature.isEmpty ? nil : signature
            streamingMessage.update(message)
        } else {
            let message = MessageData(id: id, text: text, thinking: thinking.isEmpty ? nil : thinking,
                                      signature: signature.isEmpty ? nil : signature, user: chatModel.name, sentTime: Date(),
                                      modelID: chatModel.id)
            streamingMessage.update(message)
            messages.append(message)
        }
        if let activeRunID, !text.isEmpty || !thinking.isEmpty {
            if AppStore.shared.state.runs.first(where: { $0.id == activeRunID })?.firstTokenAt == nil {
                AppStore.shared.updateRun(activeRunID) { $0.firstTokenAt = Date() }
            }
        }
    }

    private func commitStreamingMessage() {
        guard let live = streamingMessage.message else { return }
        if let index = messages.firstIndex(where: { $0.id == live.id }), messages[index] != live {
            messages[index] = live
        }
        streamingMessage.update(nil)
    }

    // Sendable tool result struct
    struct SendableToolResult: Sendable {
        let status: String
        let text: String
        let error: String?
    }
    
    // Fixed Sendable MCP tool execution
    private func executeSendableMCPTool(id: String, name: String, input: [String: Any]) async -> SendableToolResult {
        let jsonInput = JSONValue.from(input)
        guard await LocalToolExecutor.authorize(name: name, input: jsonInput, threadID: chatId) else {
            return .init(status: "error", text: Task.isCancelled ? "Tool stopped." : "The user declined this tool call.", error: "Tool was not authorized")
        }
        if let kind = BuiltInTool(rawValue: name) {
            return await LocalToolExecutor.execute(kind: kind, input: jsonInput, threadID: chatId, modelID: chatModel.id)
        }
        guard mcpManager.mcpEnabled, mcpManager.toolInfo(named: name) != nil else {
            return .init(status: "error", text: "This MCP tool is no longer available.", error: "Tool unavailable")
        }
        let result = await mcpManager.executeBedrockTool(id: id, name: name, input: input)
        let status = result["status"] as? String ?? "error"
        let text = MCPToolOutput.text(result)
        return SendableToolResult(status: status,
            text: LocalFileTools.bounded(text, limit: AppStore.shared.preferences.validToolOutputLimit),
            error: status == "error" ? result["error"] as? String ?? text : nil)
    }

    private func appendThinkingToMessage(_ thinking: String, messageId: UUID, shouldCreateNewMessage: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            var currentThinking: String = ""
            
            if shouldCreateNewMessage {
                let newMessage = MessageData(
                    id: messageId,
                    text: "",
                    thinking: thinking,
                    user: self.chatModel.name,
                    isError: false,
                    sentTime: Date()
                )
                self.messages.append(newMessage)
                currentThinking = thinking
            } else {
                if let index = self.messages.firstIndex(where: { $0.id == messageId }) {
                    self.messages[index].thinking = (self.messages[index].thinking ?? "") + thinking
                    currentThinking = self.messages[index].thinking ?? ""
                }
            }
            
            self.objectWillChange.send()

            // Progressive threshold: first summary at 500 chars, then every 2000 chars
            let thinkingLength = currentThinking.count
            let threshold = self.thinkingSummaryCallCount == 0 ? 500 : 2000
            if thinkingLength - self.lastThinkingSummaryLength >= threshold {
                self.lastThinkingSummaryLength = thinkingLength
                self.triggerThinkingSummary(for: messageId, thinking: currentThinking)
            }
        }
    }

    /// Trigger thinking summary generation with debounce (cancels previous in-flight request)
    private func triggerThinkingSummary(for messageId: UUID, thinking: String) {
        guard AppStore.shared.preferences.thinkingSummaries, !thinkingCompleted else { return }

        thinkingSummaryTask?.cancel()
        thinkingSummaryTask = Task { [weak self] in
            guard let self = self, !self.thinkingCompleted else { return }
            self.thinkingSummaryCallCount += 1
            await self.generateThinkingSummary(for: messageId, thinking: thinking)
        }
    }
    
    /// Stop thinking summary generation (called when text starts streaming)
    private func stopThinkingSummaryGeneration() {
        thinkingCompleted = true
        thinkingSummaryTask?.cancel()
        thinkingSummaryTask = nil
    }
    
    private func updateMessageText(messageId: UUID, newText: String) {
        // Update UI
        if let index = self.messages.firstIndex(where: { $0.id == messageId }) {
            self.messages[index].text = newText
        }
        
        // Update storage
        chatManager.updateMessageText(
            for: chatId,
            messageId: messageId,
            newText: newText
        )
    }
    
    private func updateMessageVideoUrl(messageId: UUID, videoUrl: URL, s3Uri: String) {
        if let index = self.messages.firstIndex(where: { $0.id == messageId }) {
            var updatedMessage = self.messages[index]
            updatedMessage.videoUrl = videoUrl
            updatedMessage.videoS3Uri = s3Uri
            self.messages[index] = updatedMessage
            logger.info("Updated message \(messageId) with video URL: \(videoUrl.path)")
        }
    }

    private func updateMessageThinking(messageId: UUID, newThinking: String, signature: String? = nil) {
        // Update UI
        if let index = self.messages.firstIndex(where: { $0.id == messageId }) {
            self.messages[index].thinking = newThinking
            if let sig = signature {
                self.messages[index].signature = sig
            }
        }
        
        // Update storage
        chatManager.updateMessageThinking(
            for: chatId,
            messageId: messageId,
            newThinking: newThinking,
            signature: signature
        )
    }

    private func updateMessageWithToolInfo(messageId: UUID, newText: String? = nil, toolInfo: ToolInfo?, toolResult: String? = nil) {
        // Update UI
        if let index = self.messages.firstIndex(where: { $0.id == messageId }) {
            // Only update text if provided and not nil
            if let text = newText {
                self.messages[index].text = text
            }
            self.messages[index].toolUse = toolInfo
            self.messages[index].toolResult = toolResult
        }
        
        // Update storage with thinking/signature preserved
        if let index = self.messages.firstIndex(where: { $0.id == messageId }) {
            let currentText = self.messages[index].text
            let currentThinking = self.messages[index].thinking
            let currentSignature = self.messages[index].signature
            
            chatManager.updateMessageWithToolInfo(
                for: chatId,
                messageId: messageId,
                newText: currentText, // Always use current text to preserve original response
                toolInfo: toolInfo!,
                toolResult: toolResult,
                thinking: currentThinking,
                thinkingSignature: currentSignature
            )
        }
    }
    
    // MARK: - Conversation History Management
    
    /// Gets conversation history
    private func getConversationHistory() async throws -> [BedrockMessage] {
        // Build conversation history from local storage
        if let history = chatManager.getConversationHistory(for: chatId) {
            return try boundedHistory(convertConversationHistoryToBedrockMessages(history))
        }
        
        // Migrate from legacy formats if needed
        if chatManager.getMessages(for: chatId).count > 0 {
            return try boundedHistory(await migrateAndGetConversationHistory())
        }
        
        // No history exists
        return []
    }

    private func boundedHistory(_ history: [BedrockMessage]) throws -> [BedrockMessage] {
        let sizes = history.map { message in
            let startsTurn = message.role == .user && !message.content.contains {
                if case .toolresult = $0 { return true }
                return false
            }
            let count = message.content.reduce(0) { total, content in
                switch content {
                case .text(let text): return total + text.count
                case .thinking(let value): return total + value.text.count
                case .toolresult(let value): return total + value.result.count
                case .tooluse(let value): return total + ((try? JSONEncoder().encode(value.input).count) ?? 1_000)
                case .image: return total + 4_000
                case .document(let value): return total + min(value.base64Data.count, 100_000)
                }
            }
            return ContextMessageSize(startsUserTurn: startsTurn, characters: count)
        }
        let systemSize = try AppStore.shared.effectiveSystemPrompt(for: chatId).count
        let selection = try ContextBudget.select(sizes, budget: AppStore.shared.preferences.validContextBudget - systemSize)
        contextNotice = selection.notice
        AppStore.shared.updateThread(chatId) { $0.contextNotice = selection.notice }
        return Array(history.dropFirst(selection.startIndex))
    }
    
    /// Migrates from legacy formats and returns conversation history
    private func migrateAndGetConversationHistory() async -> [BedrockMessage] {
        let legacy = chatManager.getMessages(for: chatId)
        let history = ConversationHistory.fromMessages(legacy, chatID: chatId, modelID: chatModel.id,
                                                       systemPrompt: settingManager.systemPrompt)
        chatManager.saveConversationHistory(history, for: chatId)
        return convertConversationHistoryToBedrockMessages(history)
    }

    /// Persist the same message fields for legacy and current conversations.
    private func saveFromUIMessages() async {
        let previous = chatManager.getConversationHistory(for: chatId)
        let history = ConversationHistory.fromMessages(messagesIncludingStream, chatID: chatId, modelID: chatModel.id,
                                                       systemPrompt: previous?.systemPrompt)
        chatManager.saveConversationHistory(history, for: chatId)
    }

    /// Converts a ConversationHistory to Bedrock messages
    private func convertConversationHistoryToBedrockMessages(_ history: ConversationHistory) -> [BedrockMessage] {
        var bedrockMessages: [BedrockMessage] = []
        
        let backend = backendModel.backend
        let isResponses = backend.isMantleResponsesModel(chatModel.id)
        let hasMCPTools = mcpManager.mcpEnabled && !mcpManager.toolInfos.isEmpty &&
            mcpManager.connectionStatus.values.contains(.connected)
        let hasLocalTools = !LocalToolExecutor.specifications(threadID: chatId).isEmpty
        let replay = ConversationReplay.prepare(
            history, targetModelID: chatModel.id,
            supportsReasoning: !isResponses && !isOpenAIModel(chatModel.id) && backend.isReasoningSupported(chatModel.id),
            supportsTools: !isResponses && backend.isStreamingToolUseSupported(chatModel.id) && (hasMCPTools || hasLocalTools),
            supportsImages: !isResponses && backend.isVisionSupported(chatModel.id),
            supportsDocuments: !isResponses && backend.isDocumentChatSupported(chatModel.id),
            foundationID: { BedrockCapabilityRegistry.shared.foundationID($0, region: backend.region) }
        )
        for message in replay.messages where !message.isError {
            let role: MessageRole = message.role == .user ? .user : .assistant
            
            var contents: [MessageContent] = []
            
            // Add thinking content if present for assistant messages
            // Skip thinking content for OpenAI models as they don't support signature field
            // IMPORTANT: Only include thinking block if we have a valid signature from the API
            // Using a fake/generated signature will cause "Invalid signature in thinking block" error
            if role == .assistant,
               let thinking = message.thinking, !thinking.isEmpty,
               let signature = message.thinkingSignature, !signature.isEmpty,
               !isOpenAIModel(chatModel.id) {
                contents.append(.thinking(.init(text: thinking, signature: signature)))
            }
            
            // Add documents FIRST (before text) to support prompt caching
            // AWS Bedrock requires cache points to follow text blocks, not document/image blocks
            if let documentBase64Strings = message.documentBase64Strings,
               let documentFormats = message.documentFormats,
               let documentNames = message.documentNames {
                
                for i in 0..<min(documentBase64Strings.count, min(documentFormats.count, documentNames.count)) {
                    let format = MessageContent.DocumentFormat.fromExtension(documentFormats[i])
                    contents.append(.document(MessageContent.DocumentContent(
                        format: format,
                        base64Data: documentBase64Strings[i],
                        name: documentNames[i]
                    )))
                }
            }
            
            // Add images SECOND (before text) to support prompt caching
            if let imageBase64Strings = message.imageBase64Strings {
                for base64String in imageBase64Strings {
                    let format = ImageFormat.detectFromBase64(base64String)
                    contents.append(.image(MessageContent.ImageContent(
                        format: format,
                        base64Data: base64String
                    )))
                }
            }
            
            // Handle tool results specially - they should ONLY contain toolresult, no text
            if role == .user, let toolUses = message.toolUses, !toolUses.isEmpty {
                contents = toolUses.map { tool in
                    .toolresult(.init(toolUseId: tool.toolId, result: tool.result ?? "Tool did not complete.", status: tool.status ?? (tool.result == nil ? "error" : "success")))
                }
            } else if role == .user, let toolUse = message.toolUse, let result = toolUse.result {
                // Tool result message - only add toolresult content
                contents.append(.toolresult(.init(
                    toolUseId: toolUse.toolId,
                    result: result,
                    status: toolUse.status ?? "success"
                )))
            } else {
                // Regular message - add text content AFTER documents/images
                // Include pasted texts in the text block for API transmission
                var fullText = message.text
                if let pastedTexts = message.pastedTexts, !pastedTexts.isEmpty {
                    for pastedText in pastedTexts {
                        if !fullText.isEmpty {
                            fullText += "\n\n---\n\n"
                        }
                        fullText += "[\(pastedText.filename)]:\n\(pastedText.content)"
                    }
                }
                if !fullText.isEmpty {
                    contents.append(.text(fullText))
                }
                
                // Handle Tool Use for assistant messages
                if role == .assistant, let toolUses = message.toolUses {
                    contents += toolUses.map { .tooluse(.init(toolUseId: $0.toolId, name: $0.toolName, input: $0.inputs)) }
                } else if role == .assistant, let toolUse = message.toolUse {
                    contents.append(.tooluse(.init(
                        toolUseId: toolUse.toolId,
                        name: toolUse.toolName,
                        input: toolUse.inputs
                    )))
                }
            }
            
            if !contents.isEmpty {
                func hasToolProtocol(_ content: [MessageContent]) -> Bool {
                    content.contains { if case .tooluse = $0 { return true }; if case .toolresult = $0 { return true }; return false }
                }
                if let last = bedrockMessages.last, last.role == role,
                   !hasToolProtocol(last.content), !hasToolProtocol(contents) {
                    bedrockMessages[bedrockMessages.count - 1].content += contents
                } else {
                    bedrockMessages.append(BedrockMessage(role: role, content: contents))
                }
            }
        }
        
        return bedrockMessages
    }
    
    // MARK: - Utility Functions
    
    // Extracts text content from a streaming chunk
    private func extractTextFromChunk(_ chunk: BedrockRuntimeClientTypes.ConverseStreamOutput) -> String? {
        if case .contentblockdelta(let deltaEvent) = chunk,
           let delta = deltaEvent.delta {
            if case .text(let textChunk) = delta {
                return textChunk
            }
        }
        return nil
    }
    
    // Extracts thinking content from a streaming chunk
    private func extractThinkingFromChunk(_ chunk: BedrockRuntimeClientTypes.ConverseStreamOutput) -> (text: String?, signature: String?) {
        var text: String? = nil
        var signature: String? = nil
        
        if case .contentblockdelta(let deltaEvent) = chunk,
           let delta = deltaEvent.delta,
           case .reasoningcontent(let reasoningChunk) = delta {
            
            switch reasoningChunk {
            case .text(let textContent):
                text = textContent
            case .signature(let signatureContent):
                signature = signatureContent
            case .redactedcontent, .sdkUnknown:
                break
            }
        }
        
        return (text, signature)
    }
    
    /// Converts a BedrockMessage to AWS SDK format
    private func convertToBedrockMessage(_ message: BedrockMessage, modelId: String = "") throws -> AWSBedrockRuntime.BedrockRuntimeClientTypes.Message {
        var contentBlocks: [AWSBedrockRuntime.BedrockRuntimeClientTypes.ContentBlock] = []
        
        // Process all content blocks in their original order (no reordering!)
        for content in message.content {
            switch content {
            case .text(let text):
                contentBlocks.append(.text(text))
                
            case .thinking(let thinkingContent):
                // Skip reasoning content for user messages
                // Also skip for DeepSeek models due to a server-side validation error
                // Also skip for OpenAI models that don't support signature field
                if message.role == .user || isDeepSeekModel(modelId) || isOpenAIModel(modelId) {
                    continue
                }
                
                // Add thinking content as a reasoning block
                let reasoningTextBlock = AWSBedrockRuntime.BedrockRuntimeClientTypes.ReasoningTextBlock(
                    signature: thinkingContent.signature,
                    text: thinkingContent.text
                )
                contentBlocks.append(.reasoningcontent(.reasoningtext(reasoningTextBlock)))
                
            case .image(let imageContent):
                // Convert to AWS image format
                let awsFormat: AWSBedrockRuntime.BedrockRuntimeClientTypes.ImageFormat
                switch imageContent.format {
                case .jpeg: awsFormat = .jpeg
                case .png: awsFormat = .png
                case .gif: awsFormat = .gif
                case .webp: awsFormat = .png // Fall back to PNG for WebP
                }
                
                guard let imageData = Data(base64Encoded: imageContent.base64Data) else {
                    logger.error("Failed to decode image base64 string")
                    throw NSError(domain: "ChatViewModel", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to decode base64 image to data"])
                }
                
                contentBlocks.append(.image(AWSBedrockRuntime.BedrockRuntimeClientTypes.ImageBlock(
                    format: awsFormat,
                    source: .bytes(imageData)
                )))
                
            case .document(let documentContent):
                // Convert to AWS document format
                let docFormat: AWSBedrockRuntime.BedrockRuntimeClientTypes.DocumentFormat
                
                switch documentContent.format {
                case .pdf: docFormat = .pdf
                case .csv: docFormat = .csv
                case .doc: docFormat = .doc
                case .docx: docFormat = .docx
                case .xls: docFormat = .xls
                case .xlsx: docFormat = .xlsx
                case .html: docFormat = .html
                case .txt: docFormat = .txt
                case .md: docFormat = .md
                }
                
                guard let documentData = Data(base64Encoded: documentContent.base64Data) else {
                    logger.error("Failed to decode document base64 string")
                    throw NSError(domain: "ChatViewModel", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to decode base64 document to data"])
                }
                
                contentBlocks.append(.document(AWSBedrockRuntime.BedrockRuntimeClientTypes.DocumentBlock(
                    format: docFormat,
                    name: documentContent.name,
                    source: .bytes(documentData)
                )))
                
            case .toolresult(let toolResultContent):
                // Convert to AWS tool result format
                let toolResultBlock = AWSBedrockRuntime.BedrockRuntimeClientTypes.ToolResultBlock(
                    content: [.text(toolResultContent.result)],
                    status: toolResultContent.status == "success" ? .success : .error,
                    toolUseId: toolResultContent.toolUseId
                )
                
                contentBlocks.append(.toolresult(toolResultBlock))
                
            case .tooluse(let toolUseContent):
                // Convert to AWS tool use format
                do {
                    // Convert JSONValue input to Smithy Document
                    let swiftInputObject = toolUseContent.input.asAny
                    let inputDocument = try Smithy.Document.make(from: swiftInputObject)
                    
                    let toolUseBlock = AWSBedrockRuntime.BedrockRuntimeClientTypes.ToolUseBlock(
                        input: inputDocument,
                        name: toolUseContent.name,
                        toolUseId: toolUseContent.toolUseId
                    )
                    
                    contentBlocks.append(.tooluse(toolUseBlock))
                    logger.debug("Successfully converted toolUse block for '\(toolUseContent.name)' with input: \(inputDocument)")
                    
                } catch {
                    logger.error("Failed to convert tool use input (\(toolUseContent.input)) to Smithy Document: \(error). Skipping this toolUse block in the request.")
                }
            }
        }
        
        // IMPORTANT: Do NOT reorder content blocks!
        // The order must be preserved to maintain proper tool_use/tool_result pairing
        // Removing all the previous reordering logic that was causing ValidationException
        
        return AWSBedrockRuntime.BedrockRuntimeClientTypes.Message(
            content: contentBlocks,
            role: convertToAWSRole(message.role)
        )
    }
    
    /// Converts MessageRole to AWS SDK role
    private func convertToAWSRole(_ role: MessageRole) -> AWSBedrockRuntime.BedrockRuntimeClientTypes.ConversationRole {
        switch role {
        case .user: return .user
        case .assistant: return .assistant
        }
    }
    
    // MARK: - Image Generation Model Handling
    
    /// Determines if the model ID represents a text generation model that can support streaming
    private func isTextGenerationModel(_ modelId: String) -> Bool {
        let id = modelId.lowercased()
        
        // Special case: check for non-text generation models first
        if id.contains("embed") ||
            id.contains("image") ||
            id.contains("video") ||
            id.contains("stable-") ||
            id.contains("-canvas") ||
            id.contains("titan-embed") ||
            id.contains("titan-e1t") {
            return false
        } else {
            // Text generation models - be more specific with nova to exclude nova-canvas
            let isNova = id.contains("nova") && !id.contains("canvas")
            
            return id.contains("mistral") ||
            id.contains("claude") ||
            id.contains("llama") ||
            isNova ||
            id.contains("titan") ||
            id.contains("deepseek") ||
            id.contains("command") ||
            id.contains("jurassic") ||
            id.contains("jamba") ||
            id.contains("openai")
        }
    }
    
    private func isDeepSeekModel(_ modelId: String) -> Bool {
        return modelId.lowercased().contains("deepseek")
    }
    
    private func isOpenAIModel(_ modelId: String) -> Bool {
        BedrockCapabilityRegistry.shared.foundationID(modelId, region: backendModel.backend.region).hasPrefix("openai.")
    }
    
    // MARK: - Mantle Responses API (OpenAI GPT-5.5/5.4)

    /// Handles OpenAI frontier models served via the bedrock-mantle Responses API.
    /// Text-only at launch: tool use and attachments are not wired through this path.
    private func handleMantleResponsesModel(_ userMessage: MessageData) async throws {
        // Persist the new user message, then rebuild history for the API
        await saveFromUIMessages()
        let conversationHistory = try await getConversationHistory()

        var input: [[String: Any]] = []

        // System prompt maps to the "developer" role in the Responses API
        let systemPrompt = try AppStore.shared.effectiveSystemPrompt(for: chatId, availableToolNames: [])
        if !systemPrompt.isEmpty {
            input.append(["role": "developer", "content": systemPrompt])
        }

        for message in conversationHistory {
            // Flatten text content; images/documents/tool blocks are not supported on this path
            let text = message.content.compactMap { content -> String? in
                if case .text(let textContent) = content { return textContent }
                return nil
            }.joined(separator: "\n\n")

            guard !text.isEmpty else { continue }
            input.append([
                "role": message.role == .user ? "user" : "assistant",
                "content": text
            ])
        }

        let messageId = UUID()
        currentStreamingMessageId = messageId
        var streamedText = ""
        var lastDisplayUpdate = Date.distantPast
        var lastCheckpoint = Date()
        var didCommitResponse = false
        let runID = activeRunID
        defer {
            if !didCommitResponse {
                displayStream(id: messageId, text: streamedText, thinking: "", signature: "")
                commitStreamingMessage()
            }
        }

        let backend = await MainActor.run { backendModel.backend }

        let stream = await backend.mantleResponsesStream(
            modelId: chatModel.id,
            input: input
        )

        for try await event in stream {
            try Task.checkCancellation()
            switch event {
            case .text(let text):
                streamedText += text
            case .finished(let reason, let usage, let fallbackText):
                if streamedText.isEmpty { streamedText = fallbackText }
                if let runID { AppStore.shared.updateRun(runID) { $0.stopReason = reason } }
                if let usage {
                    usageHandler?(formatUsageString(usage))
                    if let runID { AppStore.shared.recordUsage(usage, runID: runID) }
                }
            }
            let displayInterval = streamedText.utf8.count > 24_000 ? 0.12 : 0.08
            if Date().timeIntervalSince(lastDisplayUpdate) >= displayInterval {
                displayStream(id: messageId, text: streamedText, thinking: "", signature: "")
                lastDisplayUpdate = Date()
            }
            if Date().timeIntervalSince(lastCheckpoint) >= 2 {
                await saveFromUIMessages()
                lastCheckpoint = Date()
            }
        }

        let assistantText = streamedText.trimmingCharacters(in: .whitespacesAndNewlines)
        displayStream(id: messageId, text: assistantText.isEmpty ? "(No response)" : assistantText, thinking: "", signature: "")
        commitStreamingMessage()
        didCommitResponse = true

        await saveFromUIMessages()
        currentStreamingMessageId = nil
    }

    /// Handles image generation models that don't use converseStream
    private func handleImageGenerationModel(_ userMessage: MessageData, attachedImages: [String] = []) async throws {
        let modelId = chatModel.id
        
        if BedrockModelID.base(modelId).hasPrefix("luma.") {
            try await invokeLumaVideo(prompt: userMessage.text, inputImages: attachedImages)
        } else if modelId.contains("nova-reel") {
            try await invokeNovaReelModel(prompt: userMessage.text, inputImages: attachedImages)
        } else if modelId.contains("titan-image") {
            try await invokeTitanImageModel(prompt: userMessage.text)
        } else if modelId.contains("nova-canvas") {
            try await invokeNovaCanvasModel(prompt: userMessage.text, inputImages: attachedImages)
        } else if modelId.contains("stable") || modelId.contains("sd3") {
            try await invokeStableDiffusionModel(prompt: userMessage.text, inputImages: attachedImages)
        } else {
            throw NSError(domain: "ChatViewModel", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported image generation model: \(modelId)"
            ])
        }
    }
    
    private func invokeLumaVideo(prompt: String, inputImages: [String]) async throws {
        let backend = backendModel.backend
        let config = settingManager.lumaVideoConfig
        let service = VideoGenerationService(bedrockRuntimeClient: backend.bedrockRuntimeClient,
                                             credentialResolver: backend.awsCredentialIdentityResolver, region: backend.region)
        let path = NovaReelService.generateS3OutputPath(bucket: config.outputBucket)
        let arn = try await service.startLumaVideoGeneration(modelID: chatModel.id,
                                                            request: config.request(prompt: prompt, images: inputImages),
                                                            s3OutputUri: path)
        let invocationID = NovaReelService.extractInvocationId(from: arn) ?? ""
        let videoURI = "\(path)\(invocationID)/output.mp4"
        let messageID = UUID()
        addMessage(MessageData(id: messageID, text: "Generating your video…\n\nOutput: `\(videoURI)`",
                               user: chatModel.name, isError: false, sentTime: Date()))
        do {
            for _ in 0..<180 {
                try Task.checkCancellation()
                let job = try await service.getJobStatus(invocationArn: arn)
                switch job.jobStatus {
                case .completed:
                    let local = try? await service.downloadVideoFromS3(s3Uri: videoURI)
                    if let local { updateMessageVideoUrl(messageId: messageID, videoUrl: local, s3Uri: videoURI) }
                    updateMessageText(messageId: messageID, newText: local == nil ? "Your video is ready in S3.\n\n`\(videoURI)`" : "")
                    return
                case .failed:
                    throw LocalOperationError.invalid(job.failureMessage ?? "Video generation failed.")
                case .inProgress:
                    try await Task.sleep(for: .seconds(5))
                }
            }
            throw LocalOperationError.invalid("Video generation is still running. Check the job in Bedrock or the output S3 location.")
        } catch {
            updateMessageText(messageId: messageID,
                              newText: Task.isCancelled ? "Stopped waiting for the video. The AWS job may still finish.\n\nOutput: `\(videoURI)`" :
                                "Video job: `\(arn)`\n\nOutput: `\(videoURI)`")
            throw error
        }
    }

    /// Invokes Nova Reel video generation model (async - saves to S3)
    private func invokeNovaReelModel(prompt: String, inputImages: [String] = []) async throws {
        let backend = await MainActor.run { backendModel.backend }
        let savedConfig = settingManager.novaReelConfig
        
        // Set loading state for sidebar indicator
        await MainActor.run {
            chatManager.setIsLoading(true, for: chatId)
        }
        
        // Validate S3 bucket
        guard !savedConfig.s3OutputBucket.isEmpty else {
            throw NSError(
                domain: "NovaReel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "S3 output bucket is required. Please configure it in the Nova Reel settings."]
            )
        }
        
        let validation = NovaReelService.validateS3Uri(savedConfig.s3OutputBucket)
        guard validation.isValid else {
            throw NSError(
                domain: "NovaReel",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: validation.message ?? "Invalid S3 URI"]
            )
        }
        
        let taskType = NovaReelTaskType(rawValue: savedConfig.taskType) ?? .textToVideo
        let videoService = VideoGenerationService(
            bedrockRuntimeClient: backend.bedrockRuntimeClient,
            credentialResolver: backend.awsCredentialIdentityResolver,
            region: backend.region
        )
        
        // Generate unique S3 output path
        let s3OutputPath = NovaReelService.generateS3OutputPath(bucket: savedConfig.s3OutputBucket)
        
        let invocationArn: String
        let durationSeconds: Int
        
        switch taskType {
        case .textToVideo:
            durationSeconds = 6
            invocationArn = try await videoService.startTextToVideo(
                prompt: prompt,
                firstFrameImage: inputImages.first,
                imageFormat: "png",
                seed: savedConfig.seed,
                s3OutputUri: s3OutputPath
            )
            
        case .multiShotAutomated:
            durationSeconds = savedConfig.durationSeconds
            invocationArn = try await videoService.startMultiShotAutomated(
                prompt: prompt,
                durationSeconds: durationSeconds,
                seed: savedConfig.seed,
                s3OutputUri: s3OutputPath
            )
            
        case .multiShotManual:
            let shots = savedConfig.shots.isEmpty ? [prompt] : savedConfig.shots
            durationSeconds = shots.count * 6
            invocationArn = try await videoService.startMultiShotManual(
                shots: shots,
                seed: savedConfig.seed,
                s3OutputUri: s3OutputPath
            )
        }
        
        // Create initial response message
        let estimatedTime = NovaReelService.estimatedTime(durationSeconds: durationSeconds)
        // Nova Reel creates: {s3OutputPath}{invocationId}/output.mp4 (s3OutputPath has trailing slash)
        let invocationId = NovaReelService.extractInvocationId(from: invocationArn) ?? "unknown"
        let videoUri = "\(s3OutputPath)\(invocationId)/output.mp4"
        let messageId = UUID()
        let initialText = """
        **Video Generation Started**
        
        **Task:** \(taskType.displayName)
        **Duration:** \(durationSeconds) seconds
        **Estimated Time:** \(estimatedTime)
        **Output:** `\(videoUri)`
        
        **Job ARN:**
        `\(invocationArn)`
        
        Status: Generating video... Please wait.
        """
        
        let assistantMessage = MessageData(
            id: messageId,
            text: initialText,
            user: chatModel.name,
            isError: false,
            sentTime: Date()
        )
        addMessage(assistantMessage)
        
        // Start polling for completion
        Task {
            await pollVideoGenerationStatus(
                videoService: videoService,
                invocationArn: invocationArn,
                s3OutputPath: s3OutputPath,
                messageId: messageId,
                taskType: taskType,
                durationSeconds: durationSeconds
            )
        }
    }
    
    /// Poll video generation status and update message when complete
    private func pollVideoGenerationStatus(
        videoService: VideoGenerationService,
        invocationArn: String,
        s3OutputPath: String,
        messageId: UUID,
        taskType: NovaReelTaskType,
        durationSeconds: Int
    ) async {
        let maxAttempts = 200  // ~17 minutes max (5s intervals)
        var attempts = 0
        
        while attempts < maxAttempts {
            attempts += 1
            
            do {
                let jobInfo = try await videoService.getJobStatus(invocationArn: invocationArn)
                
                // Nova Reel creates: {s3OutputPath}{invocationId}/output.mp4 (s3OutputPath has trailing slash)
                let invocationId = NovaReelService.extractInvocationId(from: invocationArn) ?? "unknown"
                let videoUri = "\(s3OutputPath)\(invocationId)/output.mp4"
                
                switch jobInfo.jobStatus {
                case .completed:
                    // Try to download video from S3
                    var localVideoUrl: URL?
                    do {
                        localVideoUrl = try await videoService.downloadVideoFromS3(s3Uri: videoUri)
                    } catch {
                        logger.warning("Failed to download video: \(error.localizedDescription)")
                    }
                    
                    // If video downloaded successfully, clear text (video player will show)
                    let completedText: String
                    if localVideoUrl != nil {
                        completedText = ""
                    } else {
                        completedText = """
                        **Video Generation Complete**
                        
                        **Task:** \(taskType.displayName)
                        **Duration:** \(durationSeconds) seconds
                        **Output:** `\(videoUri)`
                        
                        Status: Complete - Video is ready in S3.
                        """
                    }
                    
                    await MainActor.run {
                        // Set video URL first, then update text
                        if let videoUrl = localVideoUrl {
                            updateMessageVideoUrl(messageId: messageId, videoUrl: videoUrl, s3Uri: videoUri)
                        }
                        updateMessageText(messageId: messageId, newText: completedText)
                        chatManager.setIsLoading(false, for: chatId)
                    }
                    await saveFromUIMessages()
                    return
                    
                case .failed:
                    let failedText = """
                    **Video Generation Failed**
                    
                    **Task:** \(taskType.displayName)
                    **Output:** `\(videoUri)`
                    
                    **Job ARN:**
                    `\(invocationArn)`
                    
                    Status: Failed - \(jobInfo.failureMessage ?? "Unknown error")
                    """
                    
                    await MainActor.run {
                        updateMessageText(messageId: messageId, newText: failedText)
                        chatManager.setIsLoading(false, for: chatId)
                    }
                    await saveFromUIMessages()
                    return
                    
                case .inProgress:
                    // Update progress message periodically
                    if attempts % 6 == 0 {  // Every 30 seconds
                        let elapsed = attempts * 5
                        let progressText = """
                        **Video Generation In Progress**
                        
                        **Task:** \(taskType.displayName)
                        **Duration:** \(durationSeconds) seconds
                        **Output:** `\(videoUri)`
                        
                        **Job ARN:**
                        `\(invocationArn)`
                        
                        Status: Generating... (\(elapsed)s elapsed)
                        """
                        
                        await MainActor.run {
                            updateMessageText(messageId: messageId, newText: progressText)
                        }
                    }
                }
            } catch {
                // Log error but continue polling
                print("Error polling video status: \(error.localizedDescription)")
            }
            
            // Wait 5 seconds before next poll
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
        
        // Timeout
        let invocationId = NovaReelService.extractInvocationId(from: invocationArn) ?? "unknown"
        let videoUri = "\(s3OutputPath)\(invocationId)/output.mp4"
        let timeoutText = """
        **Video Generation Timeout**
        
        **Task:** \(taskType.displayName)
        **Duration:** \(durationSeconds) seconds
        **Output:** `\(videoUri)`
        
        **Job ARN:**
        `\(invocationArn)`
        
        Status: Timeout - Check the AWS Console for current status.
        """
        
        await MainActor.run {
            updateMessageText(messageId: messageId, newText: timeoutText)
            chatManager.setIsLoading(false, for: chatId)
        }
        await saveFromUIMessages()
    }
    
    /// Handles embedding models by directly parsing JSON responses
    private func handleEmbeddingModel(_ userMessage: MessageData) async throws {
        // Capture backend locally to avoid data races
        let backend = await MainActor.run { backendModel.backend }
        
        // Invoke embedding model to get raw data response
        let responseData = try await backend.invokeEmbeddingModel(
            withId: chatModel.id,
            text: userMessage.text
        )
        
        let modelId = chatModel.id.lowercased()
        var responseText = ""
        
        // Parse JSON data directly
        if let json = try? JSONSerialization.jsonObject(with: responseData, options: []) {
            if modelId.contains("titan-embed") || modelId.contains("titan-e1t") {
                if let jsonDict = json as? [String: Any],
                   let embedding = jsonDict["embedding"] as? [Double] {
                    responseText = embedding.map { "\($0)" }.joined(separator: ",")
                } else {
                    responseText = "Failed to extract Titan embedding data"
                }
            } else if modelId.contains("cohere") {
                if let jsonDict = json as? [String: Any],
                   let embeddings = jsonDict["embeddings"] as? [[Double]],
                   let firstEmbedding = embeddings.first {
                    responseText = firstEmbedding.map { "\($0)" }.joined(separator: ",")
                } else {
                    responseText = "Failed to extract Cohere embedding data"
                }
            } else {
                if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    responseText = jsonString
                } else {
                    responseText = "Unknown embedding format"
                }
            }
        } else {
            responseText = String(data: responseData, encoding: .utf8) ?? "Unable to decode response"
        }
        
        // Create response message
        let assistantMessage = MessageData(
            id: UUID(),
            text: responseText,
            user: chatModel.name,
            isError: false,
            sentTime: Date()
        )
        
        // Add message to chat
        addMessage(assistantMessage)
        
        // Save conversation history from UI messages
        await saveFromUIMessages()
    }
    
    /// Invokes Titan Image model
    private func invokeTitanImageModel(prompt: String) async throws {
        let backend = await MainActor.run { backendModel.backend }
        let data = try await backend.invokeImageModel(
            withId: chatModel.id,
            prompt: prompt,
            modelType: .titanImage
        )
        
        try processImageModelResponse(data)
    }
    
    /// Invokes Nova Canvas image model with full feature support
    /// Supports: TEXT_IMAGE, COLOR_GUIDED_GENERATION, IMAGE_VARIATION, INPAINTING, OUTPAINTING, BACKGROUND_REMOVAL
    private func invokeNovaCanvasModel(prompt: String, inputImages: [String] = []) async throws {
        let backend = await MainActor.run { backendModel.backend }
        
        // Get saved config from settings
        let savedConfig = settingManager.novaCanvasConfig
        let configuredTaskType = NovaCanvasTaskType(rawValue: savedConfig.taskType) ?? .textToImage
        
        // Parse the prompt to detect task type override and extract parameters
        let (parsedTaskType, cleanPrompt, parameters) = NovaCanvasService.parsePrompt(prompt)
        
        // Use parsed task type if prompt contains explicit commands, otherwise use configured
        let taskType = parsedTaskType != .textToImage ? parsedTaskType : configuredTaskType
        
        // Extract negative prompt if present (format: "prompt --no negative terms")
        let (finalPrompt, negativePrompt) = NovaCanvasService.extractNegativePrompt(from: cleanPrompt)
        
        // Use saved negative prompt if user didn't specify one
        let effectiveNegativePrompt = negativePrompt ?? (savedConfig.negativePrompt.isEmpty ? nil : savedConfig.negativePrompt)
        
        // Validate requirements for tasks that need input images
        if taskType.requiresInputImage && inputImages.isEmpty {
            throw NSError(
                domain: "NovaCanvas",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "This task requires an input image. Please attach an image to use \(taskType.displayName)."]
            )
        }
        
        // Extract colors if present in parameters
        let colors = parameters["colors"] as? [String] ?? []
        
        // Get mask prompt from user input or saved config
        let userMaskPrompt = extractMaskPrompt(from: prompt)
        let effectiveMaskPrompt = userMaskPrompt ?? (savedConfig.maskPrompt.isEmpty ? nil : savedConfig.maskPrompt)
        
        // Build config from saved settings
        let config = NovaCanvasImageGenerationConfig(
            width: savedConfig.width,
            height: savedConfig.height,
            quality: savedConfig.quality,
            cfgScale: savedConfig.cfgScale,
            seed: savedConfig.seed,  // 0 = random, otherwise fixed seed
            numberOfImages: savedConfig.numberOfImages
        )
        
        // Build request based on task type
        var request: NovaCanvasRequest
        if taskType == .textToImage {
            // Use style for text-to-image
            let style = NovaCanvasStyle(rawValue: savedConfig.style)
            request = .textToImage(
                prompt: finalPrompt,
                negativePrompt: effectiveNegativePrompt,
                style: style,
                conditionImage: inputImages.first,
                config: config
            )
        } else {
            request = NovaCanvasService.buildRequest(
                taskType: taskType,
                prompt: finalPrompt,
                negativePrompt: effectiveNegativePrompt,
                inputImages: inputImages,
                maskPrompt: effectiveMaskPrompt,
                colors: colors,
                config: config
            )
        }
        
        // Invoke Nova Canvas
        let data = try await backend.invokeNovaCanvas(request: request)
        
        try processImageModelResponse(data)
    }
    
    /// Extract mask prompt from user input (format: "[mask: description]")
    private func extractMaskPrompt(from prompt: String) -> String? {
        let pattern = "\\[mask:\\s*([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
              let range = Range(match.range(at: 1), in: prompt) else {
            return nil
        }
        return String(prompt[range]).trimmingCharacters(in: .whitespaces)
    }
    
    /// Get attached images from current context as base64 strings
    private func getAttachedImagesBase64() async -> [String] {
        var base64Images: [String] = []
        
        for (index, image) in sharedMediaDataSource.images.enumerated() {
            if sharedMediaDataSource.imageEncodedData.indices.contains(index),
               let data = sharedMediaDataSource.imageEncodedData[index] {
                base64Images.append(data.base64EncodedString())
                continue
            }
            let fileExtension = index < sharedMediaDataSource.imageExtensions.count ?
                sharedMediaDataSource.imageExtensions[index] : "jpg"
            
            let result = base64EncodeImage(image, withExtension: fileExtension)
            if let base64 = result.base64String {
                base64Images.append(base64)
            }
        }
        
        return base64Images
    }
    
    /// Invokes Stability AI image models (Stable Image Ultra, SD3 Large, Stable Image Core)
    /// Also handles Stability AI Image Services (Upscale, Edit, Control)
    /// Note: Only SD3 Large supports image-to-image mode. Ultra and Core are text-to-image only.
    private func invokeStableDiffusionModel(prompt: String, inputImages: [String] = []) async throws {
        let backend = await MainActor.run { backendModel.backend }
        let modelId = chatModel.id
        
        // Check if this is a Stability AI Image Service
        if let service = StabilityAIImageService.matching(modelId) {
            try await invokeStabilityAIImageService(service: service, prompt: prompt, inputImages: inputImages)
            return
        }
        
        // Get saved config to check task type
        let savedConfig = settingManager.stabilityAIConfig
        let taskType = StabilityAITaskType(rawValue: savedConfig.taskType) ?? .textToImage
        
        // Check if model supports image-to-image
        // Only SD3 Large (sd3-5-large) supports image-to-image mode
        // Stable Image Ultra and Core do NOT support image-to-image
        let supportsImageToImage = modelId.contains("sd3-5-large") || modelId.contains("sd3-large")
        
        // Determine if we should use image-to-image mode
        let useImageToImage = taskType == .imageToImage && !inputImages.isEmpty && supportsImageToImage
        
        // Warn user if they selected image-to-image but model doesn't support it
        if taskType == .imageToImage && !inputImages.isEmpty && !supportsImageToImage {
            // Fall back to text-to-image with a warning in the response
            let modelName = modelId.contains("ultra") ? "Stable Image Ultra" :
                           modelId.contains("core") ? "Stable Image Core" : "this model"
            throw NSError(
                domain: "StabilityAI",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "\(modelName) does not support image-to-image mode. Please use SD3 Large for image-to-image, or switch to Text to Image mode."]
            )
        }
        
        if useImageToImage {
            // Validate that we have an input image for image-to-image
            guard let inputImage = inputImages.first else {
                throw NSError(
                    domain: "StabilityAI",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Image-to-image mode requires an input image. Please attach an image."]
                )
            }
            
            // Use ImageGenerationService for image-to-image
            let imageService = ImageGenerationService(bedrockRuntimeClient: backend.bedrockRuntimeClient, region: backend.region)
            let data = try await imageService.invokeStabilityAIImageToImage(
                modelId: modelId,
                prompt: prompt,
                inputImage: inputImage
            )
            try processImageModelResponse(data)
        } else {
            // Text-to-image mode
            let data = try await backend.invokeImageModel(
                withId: modelId,
                prompt: prompt,
                modelType: .stableDiffusion
            )
            try processImageModelResponse(data)
        }
    }
    
    /// Invokes Stability AI Image Services (Upscale, Edit, Control)
    private func invokeStabilityAIImageService(service: StabilityAIImageService, prompt: String, inputImages: [String]) async throws {
        let backend = await MainActor.run { backendModel.backend }
        
        // Validate input image requirement
        if service.requiresImage && inputImages.isEmpty {
            throw NSError(
                domain: "StabilityAI",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "\(service.displayName) requires an input image. Please attach an image."]
            )
        }
        
        // For style transfer, we need two images
        var styleImage: String? = nil
        if service == .styleTransfer {
            if inputImages.count < 2 {
                throw NSError(
                    domain: "StabilityAI",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Style Transfer requires two images: init_image (first) and style_image (second). Please attach both images."]
                )
            }
            styleImage = inputImages[1]
        }
        
        let imageService = ImageGenerationService(bedrockRuntimeClient: backend.bedrockRuntimeClient, region: backend.region)
        let data = try await imageService.invokeStabilityAIService(
            service: service,
            modelID: chatModel.id,
            prompt: prompt,
            inputImage: inputImages.first ?? "",
            maskImage: service.requiresMask && inputImages.count > 1 ? inputImages[1] : nil,
            styleImage: styleImage
        )
        
        try processImageModelResponse(data)
    }
    
    /// Process and display image data from image generation models
    /// Uses efficient file-based storage to avoid bloating conversation history
    private func processImageModelResponse(_ data: Data) throws {
        // Save image to file storage and get reference ID (img_xxx format)
        // This avoids storing large base64 strings in conversation history JSON
        let imageReference = ImageStore.shared.saveImage(data)
        
        // Use the file reference directly in imageBase64Strings
        // The image preview worker resolves these local file references.
        // This prevents double-saving in convertImagesToReferences (it skips img_ prefixed strings)
        let imageMessage = MessageData(
            id: UUID(),
            text: "",  // No markdown needed - image is in imageBase64Strings
            user: chatModel.name,
            isError: false,
            sentTime: Date(),
            imageBase64Strings: [imageReference]  // Use file reference directly
        )
        addMessage(imageMessage)
        
        // Update history with reference (not full base64)
        var history = chatManager.getHistory(for: chatId)
        history += "\nAssistant: [Generated Image: \(imageReference)]\n"
        chatManager.setHistory(history, for: chatId)
    }
    
    // MARK: - Basic Message Operations
    
    func addMessage(_ incoming: MessageData) {
        var message = incoming
        if message.modelID == nil { message.modelID = chatModel.id }
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
        let converted = ConversationHistory.fromMessages([message], chatID: chatId, modelID: chatModel.id)
        if let stored = converted.messages.first { chatManager.addMessage(stored, to: chatId) }
    }

    /// Convert base64 image strings to file references for efficient storage
    /// This prevents conversation history JSON from becoming too large
    private func convertImagesToReferences(_ base64Strings: [String]?) -> [String]? {
        guard let strings = base64Strings, !strings.isEmpty else { return nil }
        
        return strings.map { base64 in
            // Skip if already a file reference
            if ImageStore.isFileReference(base64) {
                return base64
            }
            
            // Convert base64 to file and return reference
            guard let data = Data(base64Encoded: base64) else {
                return base64  // Keep original if decode fails
            }
            
            return ImageStore.shared.saveImage(data)
        }
    }
    
    private func handleModelError(_ error: Error) async {
        logger.error("Error invoking the model: \(error)")

        // Errors we raise ourselves (e.g. a Mantle model that isn't served in this region)
        // already carry a user-facing message — show it instead of dumping the NSError.
        let nsError = error as NSError
        let text: String
        if let message = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
            text = message
        } else {
            text = "Error invoking the model: \(error)"
        }

        let errorMessage = MessageData(
            id: UUID(),
            text: text,
            user: "System",
            isError: true,
            sentTime: Date()
        )
        addMessage(errorMessage)
    }
    
    /// Encodes an image to Base64.
    func base64EncodeImage(_ image: NSImage, withExtension fileExtension: String) -> (base64String: String?, mediaType: String?) {
        guard let tiffRepresentation = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else {
            return (nil, nil)
        }
        
        let imageData: Data?
        let mediaType: String
        
        switch fileExtension.lowercased() {
        case "jpg", "jpeg":
            imageData = bitmapImage.representation(using: .jpeg, properties: [:])
            mediaType = "image/jpeg"
        case "png":
            imageData = bitmapImage.representation(using: .png, properties: [:])
            mediaType = "image/png"
        case "webp":
            imageData = nil
            mediaType = "image/webp"
        case "gif":
            imageData = nil
            mediaType = "image/gif"
        default:
            return (nil, nil)
        }
        
        guard let data = imageData else {
            return (nil, nil)
        }
        
        return (data.base64EncodedString(), mediaType)
    }
    
    /// Updates the chat title with a summary of the input.
    func updateChatTitle(with input: String) async {
        // Skip auto title generation if chat was manually renamed
        if chatModel.isManuallyRenamed {
            return
        }
        let summaryPrompt = """
        Summarize user input <input>\(input)</input> as short as possible. Just in few words without punctuation. It should not be more than 5 words. Do as best as you can. please do summary this without punctuation:
        """
        
        // Create message for converseStream
        let userMsg = BedrockMessage(
            role: .user,
            content: [.text(summaryPrompt)]
        )
        
        // Select model for title generation with fallback
        let preferredModelId = "global.anthropic.claude-haiku-4-5-20251001-v1:0"
        let fallbackModelId = "us.amazon.nova-pro-v1:0"
        
        // Check if preferred model is available, otherwise use fallback
        let availableModelIds = PreferencesStore.shared.availableModels.map { $0.id }
        let titleModelId = availableModelIds.contains(preferredModelId) ? preferredModelId : fallbackModelId
        
        do {
            // Convert to AWS SDK format
            let awsMessage = try convertToBedrockMessage(userMsg)
            
            // Use converseStream API to get the title
            var title = ""
            
            let systemContentBlocks: [BedrockRuntimeClientTypes.SystemContentBlock]? = nil
            let backend = await MainActor.run { backendModel.backend }
            
            for try await chunk in try await backend.converseStream(
                withId: titleModelId,
                messages: [awsMessage],
                systemContent: systemContentBlocks,
                inferenceConfig: nil,
                usageHandler: { @Sendable usage in
                    // Title generation usage info
                    print("Title generation usage - Input: \(usage.inputTokens ?? 0), Output: \(usage.outputTokens ?? 0)")
                }
            ) {
                if let textChunk = extractTextFromChunk(chunk) {
                    title += textChunk
                }
            }
            
            // Update chat title with the generated summary
            if !title.isEmpty {
                chatManager.updateChatTitle(
                    for: chatModel.chatId,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        } catch {
            logger.error("Error updating chat title: \(error)")
        }
    }
    
    // MARK: - Thinking Summary Generation
    
    /// Generate a brief summary of the thinking process using a lightweight model
    private func generateThinkingSummary(for messageId: UUID, thinking: String) async {
        guard !thinkingCompleted, !Task.isCancelled else { return }

        // Use tail-focused truncation: keep beginning for context + recent content for current direction
        let truncatedThinking: String
        if thinking.count > 2000 {
            let head = String(thinking.prefix(500))
            let tail = String(thinking.suffix(1500))
            truncatedThinking = head + "\n...\n" + tail
        } else {
            truncatedThinking = thinking
        }

        let summaryPrompt = """
        What is this AI currently working through? Describe in one short sentence (under 15 words). Focus on the latest reasoning step, not the full history. No quotes or prefixes.

        <thinking>
        \(truncatedThinking)
        </thinking>
        """
        
        // Create message for converseStream
        let userMsg = BedrockMessage(
            role: .user,
            content: [.text(summaryPrompt)]
        )
        
        // Select model for summary generation with fallback
        let preferredModelId = "global.anthropic.claude-haiku-4-5-20251001-v1:0"
        let fallbackModelId = "us.amazon.nova-pro-v1:0"
        
        // Check if preferred model is available, otherwise use fallback
        let availableModelIds = await MainActor.run { PreferencesStore.shared.availableModels.map { $0.id } }
        let summaryModelId = availableModelIds.contains(preferredModelId) ? preferredModelId : fallbackModelId
        
        do {
            // Convert to AWS SDK format
            let awsMessage = try convertToBedrockMessage(userMsg)
            
            // Use converseStream API to get the summary
            var summary = ""
            
            let systemContentBlocks: [BedrockRuntimeClientTypes.SystemContentBlock]? = nil
            let backend = await MainActor.run { backendModel.backend }
            
            for try await chunk in try await backend.converseStream(
                withId: summaryModelId,
                messages: [awsMessage],
                systemContent: systemContentBlocks,
                inferenceConfig: BedrockRuntimeClientTypes.InferenceConfiguration(
                    maxTokens: 80,
                    temperature: 0.2
                ),
                usageHandler: { @Sendable _ in }
            ) {
                guard !Task.isCancelled, !thinkingCompleted else { break }
                if let textChunk = extractTextFromChunk(chunk) {
                    summary += textChunk
                }
            }

            // Update message with thinking summary (only if not cancelled/completed)
            if !summary.isEmpty && !thinkingCompleted && !Task.isCancelled {
                let cleanedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run { [weak self] in
                    guard let self = self, !self.thinkingCompleted else { return }
                    if let index = self.messages.firstIndex(where: { $0.id == messageId }) {
                        self.messages[index].thinkingSummary = cleanedSummary
                        self.objectWillChange.send()
                    }
                }
                logger.info("Generated thinking summary: \(cleanedSummary)")
            }
        } catch {
            logger.error("Error generating thinking summary: \(error)")
        }
    }
    
    // MARK: - Non-Streaming Text LLM Handling
    
    private func handleTextLLMWithNonStreaming(_ userMessage: MessageData) async throws {
        // BedrockService normalizes Converse responses into the same event stream. Tool
        // cycles, skills, usage and history therefore share the exact same path.
        try await handleTextLLMWithConverseStream(userMessage)
    }
}
