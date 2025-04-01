//
//  ChatViewModel.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 6/28/24.
//

import SwiftUI
import Combine
import AWSBedrockRuntime

// MARK: - Required Type Definitions for Bedrock API integration

/// Bedrock message role
enum MessageRole: String, Codable {
    case user = "user"
    case assistant = "assistant"
}

/// Message content structure for Bedrock API
enum MessageContent: Codable {
    case text(String)
    case image(ImageContent)
    
    // For encoding/decoding
    private enum CodingKeys: String, CodingKey {
        case type, text, image
    }
    
    struct ImageContent: Codable {
        let format: ImageFormat
        let base64Data: String
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
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown content type: \(type)"
            )
        }
    }
}

/// Unified message structure for Bedrock API
struct BedrockMessage: Codable {
    let role: MessageRole
    var content: [MessageContent]
}

/// Tool usage error type definition
struct ToolUseError: Error {
    let message: String
}

class ChatViewModel: ObservableObject {
    let chatId: String
    let chatManager: ChatManager
    let sharedImageDataSource: SharedImageDataSource
    @ObservedObject private var settingManager = SettingManager.shared
    
    @ObservedObject var backendModel: BackendModel
    @Published var chatModel: ChatModel
    @Published var messages: [MessageData] = []
    @Published var userInput: String = ""
    @Published var isMessageBarDisabled: Bool = false
    @Published var isSending: Bool = false
    @Published var isStreamingEnabled: Bool = false
    @Published var selectedPlaceholder: String
    @Published var emptyText: String = ""
    
    private var cancellables: Set<AnyCancellable> = []
    private var messageTask: Task<Void, Never>?
    
    init(chatId: String, backendModel: BackendModel, chatManager: ChatManager = .shared, sharedImageDataSource: SharedImageDataSource) {
        self.chatId = chatId
        self.backendModel = backendModel
        self.chatManager = chatManager
        self.sharedImageDataSource = sharedImageDataSource
        
        guard let model = chatManager.getChatModel(for: chatId) else {
            fatalError("Chat model not found for id: \(chatId)")
        }
        self.chatModel = model
        
        self.selectedPlaceholder = ""
        
        setupStreamingEnabled()
        
        // Setup bindings after all properties are initialized
        setupBindings()
    }
    
    @MainActor
    private func loadChatModel() async {
        // Wait for chat model to be ready
        for _ in 0..<10 { // Try up to 10 times
            if let model = chatManager.getChatModel(for: chatId) {
                self.chatModel = model
                setupStreamingEnabled()
                setupBindings()
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // Wait 0.1 second
        }
        // Chat model not found
        print("Error: Chat model not found for id: \(chatId)")
    }
    
    private func setupStreamingEnabled() {
        // Enable streaming for all text generation models
        self.isStreamingEnabled = isTextGenerationModel(chatModel.id)
    }
    
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
            id.contains("jamba")
        }
    }
    
    private func setupBindings() {
        chatManager.$chats
            .map { [weak self] chats in
                chats.first { $0.chatId == self?.chatId }
            }
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .assign(to: \.chatModel, on: self)
            .store(in: &cancellables)
        
        // Update streaming status when chat model changes
        $chatModel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] model in
                guard let self = self else { return }
                self.isStreamingEnabled = self.isTextGenerationModel(model.id)
            }
            .store(in: &cancellables)
    }
    
    func loadInitialData() {
        messages = chatManager.getMessages(for: chatId)
    }
    
    func sendMessage() {
        guard !userInput.isEmpty else { return }
        
        messageTask?.cancel()
        messageTask = Task { await sendMessageAsync() }
    }
    
    private func sendMessageAsync() async {
        await MainActor.run {
            chatManager.setIsLoading(true, for: chatId)
            isMessageBarDisabled = true
        }
        
        let tempInput = userInput
        Task {
            await updateChatTitle(with: tempInput)
        }
        
        let userMessage = createUserMessage()
        addMessage(userMessage)
        
        await MainActor.run {
            userInput = ""
            sharedImageDataSource.images.removeAll()
            sharedImageDataSource.fileExtensions.removeAll()
        }
        
        do {
            // Determine model type and choose appropriate handling
            if backendModel.backend.isImageGenerationModel(chatModel.id) {
                // Use existing image generation methods
                try await handleImageGenerationModel(userMessage)
            } else {
                // Use unified converseStream for all text LLMs
                try await handleTextLLMWithConverseStream(userMessage)
            }
        } catch let error as ToolUseError {
            let errorMessage = MessageData(
                id: UUID(),
                text: "Tool Use Error: \(error.message)",
                user: "System",
                isError: true,
                sentTime: Date()
            )
            await addMessage(errorMessage)
        } catch let error {
            // 일반 오류 처리
            if let nsError = error as NSError?,
               nsError.localizedDescription.contains("ValidationException") &&
                nsError.localizedDescription.contains("maxLength: 512") {
                let errorMessage = MessageData(
                    id: UUID(),
                    text: "Error: Your prompt is too long. Titan Image Generator has a 512 character limit for prompts. Please try again with a shorter prompt.",
                    user: "System",
                    isError: true,
                    sentTime: Date()
                )
                await addMessage(errorMessage)
            } else {
                await handleModelError(error)
            }
        }
        
        await MainActor.run {
            isMessageBarDisabled = false
            chatManager.setIsLoading(false, for: chatId)
        }
    }
    
    func cancelSending() {
        messageTask?.cancel()
        chatManager.setIsLoading(false, for: chatId)
    }
    
    private func createUserMessage() -> MessageData {
        let imageBase64Strings = sharedImageDataSource.images.enumerated().compactMap { index, image in
            let fileExtension = sharedImageDataSource.fileExtensions.indices.contains(index)
            ? sharedImageDataSource.fileExtensions[index]
            : ""
            let (base64String, _) = base64EncodeImage(image, withExtension: fileExtension)
            
            if let base64String = base64String {
                print("Image at index \(index) encoded successfully: \(base64String.prefix(30))...")
            } else {
                print("Failed to encode image at index \(index)")
            }
            
            return base64String
        }
        
        let userMessage = MessageData(id: UUID(), text: userInput, user: "User", isError: false, sentTime: Date(), imageBase64Strings: imageBase64Strings)
        return userMessage
    }
    
    // MARK: - Unified Text LLM Handler with converseStream
    
    /// Handles all text-based LLM models using converseStream API
    private func handleTextLLMWithConverseStream(_ userMessage: MessageData) async throws {
        // Create message content from user message
        var messageContents: [MessageContent] = []
        
        // Add text content
        if !userMessage.text.isEmpty {
            messageContents.append(.text(userMessage.text))
        }
        
        // Add images if present
        if let imageBase64Strings = userMessage.imageBase64Strings, !imageBase64Strings.isEmpty {
            for (index, base64String) in imageBase64Strings.enumerated() {
                let fileExtension = sharedImageDataSource.fileExtensions.indices.contains(index)
                    ? sharedImageDataSource.fileExtensions[index].lowercased()
                    : "jpeg"
                
                // Map file extension to image format
                let format: ImageFormat
                switch fileExtension {
                case "jpg", "jpeg": format = .jpeg
                case "png": format = .png
                case "gif": format = .gif
                case "webp": format = .webp
                default: format = .jpeg
                }
                
                // Create image content
                messageContents.append(.image(MessageContent.ImageContent(
                    format: format,
                    base64Data: base64String
                )))
            }
        }
        
        // Create user message
        let userMsg = BedrockMessage(
            role: .user,
            content: messageContents
        )
        
        // Get conversation history
        var conversationHistory = await getConversationHistory()
        
        // Note: There are conversation history duplication issue for last user message.
        // conversationHistory.append(userMsg)
        
        // Save updated history
        await saveConversationHistory(conversationHistory)
        
        // Get system prompt
        let systemPrompt = SettingManager.shared.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Get Bedrock messages in AWS SDK format
        let bedrockMessages = try conversationHistory.map { try convertToBedrockMessage($0) }

        // Invoke the model stream
        var streamedText = ""
        var thinking: String? = nil
        var isFirstChunk = true
        
        // Convert to system prompt format used by AWS SDK
        let systemContentBlock: [AWSBedrockRuntime.BedrockRuntimeClientTypes.SystemContentBlock]? =
            systemPrompt.isEmpty ? nil : [.text(systemPrompt)]

        for try await chunk in try await backendModel.backend.converseStream(
            withId: chatModel.id,
            messages: bedrockMessages,
            systemContent: systemContentBlock,
            inferenceConfig: nil
        ) {
            // Process each chunk from the stream
            if let textChunk = extractTextFromChunk(chunk) {
                streamedText += textChunk
                appendTextToMessage(textChunk, shouldCreateNewMessage: isFirstChunk)
                isFirstChunk = false
            }
            
            if let thinkingChunk = extractThinkingFromChunk(chunk) {
                thinking = (thinking ?? "") + thinkingChunk
                appendTextToMessage("", thinking: thinkingChunk, shouldCreateNewMessage: isFirstChunk)
                isFirstChunk = false
            }
        }
        
        // Create assistant message when streaming is complete
        let assistantText = streamedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistantMessage = MessageData(
            id: UUID(),
            text: assistantText,
            thinking: thinking,
            user: chatModel.name,
            isError: false,
            sentTime: Date()
        )
        
        // Only save to history if we haven't already streamed it
        if isFirstChunk {
            addMessage(assistantMessage)
        } else {
            // Update the already streamed message in chat history
            chatManager.addMessage(assistantMessage, for: chatId)
        }
        
        // Create assistant message for conversation history
        let assistantMsg = BedrockMessage(
            role: .assistant,
            content: [.text(assistantText)]
        )
        
        // Add assistant response to history and save
        conversationHistory.append(assistantMsg)
        await saveConversationHistory(conversationHistory)
    }
    
    /// Extracts text content from a streaming chunk
    private func extractTextFromChunk(_ chunk: BedrockRuntimeClientTypes.ConverseStreamOutput) -> String? {
        if case .contentblockdelta(let deltaEvent) = chunk,
           let delta = deltaEvent.delta {
            if case .text(let textChunk) = delta {
                return textChunk
            }
        }
        return nil
    }

    /// Extracts thinking content from a streaming chunk
    private func extractThinkingFromChunk(_ chunk: BedrockRuntimeClientTypes.ConverseStreamOutput) -> String? {
        if case .contentblockdelta(let deltaEvent) = chunk,
           let delta = deltaEvent.delta {
            if case .reasoningcontent(let reasoningChunk) = delta,
               case .text(let textContent) = reasoningChunk {
                return textContent
            }
        }
        return nil
    }

    /// Gets conversation history
    private func getConversationHistory() async -> [BedrockMessage] {
        // Build conversation history from local storage
        if let history = chatManager.getConversationHistory(for: chatId) {
            return convertConversationHistoryToBedrockMessages(history)
        }
        
        // Migrate from legacy formats if needed
        if chatManager.getMessages(for: chatId).count > 0 {
            return await migrateAndGetConversationHistory()
        }
        
        // No history exists
        return []
    }
    
    /// Migrates from legacy formats and returns conversation history
    private func migrateAndGetConversationHistory() async -> [BedrockMessage] {
        // Get messages and convert to unified format
        let messages = chatManager.getMessages(for: chatId)
        
        var bedrockMessages: [BedrockMessage] = []
        
        for message in messages {
            let role: MessageRole = message.user == "User" ? .user : .assistant
            
            var contents: [MessageContent] = []
            
            // Add text content
            if !message.text.isEmpty {
                contents.append(.text(message.text))
            }
            
            // Add images if present
            if let imageBase64Strings = message.imageBase64Strings {
                for base64String in imageBase64Strings {
                    contents.append(.image(MessageContent.ImageContent(
                        format: .jpeg,
                        base64Data: base64String
                    )))
                }
            }
            
            let bedrockMessage = BedrockMessage(role: role, content: contents)
            bedrockMessages.append(bedrockMessage)
        }
        
        // Save newly converted history
        await saveConversationHistory(bedrockMessages)
        
        return bedrockMessages
    }
    
    /// Saves conversation history
    private func saveConversationHistory(_ history: [BedrockMessage]) async {
        // Convert to ConversationHistory format
        var conversationHistory = ConversationHistory(
            chatId: chatId,
            modelId: chatModel.id,
            messages: []
        )
        
        // Add all messages
        for message in history {
            let role = message.role == .user ? "user" : "assistant"
            let text = message.content.compactMap { content -> String? in
                if case let .text(text) = content {
                    return text
                }
                return nil
            }.joined()
            
            // Extract images
            var imageBase64Strings: [String]? = nil
            for content in message.content {
                if case let .image(imageContent) = content {
                    if imageBase64Strings == nil {
                        imageBase64Strings = []
                    }
                    imageBase64Strings?.append(imageContent.base64Data)
                }
            }
            
            let unifiedMessage = ConversationHistory.Message(
                id: UUID(),
                text: text,
                role: role,
                timestamp: Date(),
                isError: false,
                imageBase64Strings: imageBase64Strings
            )
            
            conversationHistory.addMessage(unifiedMessage)
        }
        
        // Save the history
        chatManager.saveConversationHistory(conversationHistory, for: chatId)
    }
    
    /// Converts a ConversationHistory to Bedrock messages
    private func convertConversationHistoryToBedrockMessages(_ history: ConversationHistory) -> [BedrockMessage] {
        return history.messages.map { message in
            let role: MessageRole = message.role == "user" ? .user : .assistant
            
            var contents: [MessageContent] = []
            
            // Add text content
            if !message.text.isEmpty {
                contents.append(.text(message.text))
            }
            
            // Add images if present
            if let imageBase64Strings = message.imageBase64Strings {
                for base64String in imageBase64Strings {
                    contents.append(.image(MessageContent.ImageContent(
                        format: .jpeg,
                        base64Data: base64String
                    )))
                }
            }
            
            return BedrockMessage(role: role, content: contents)
        }
    }
    
    /// Converts a BedrockMessage to AWS SDK format
    private func convertToBedrockMessage(_ message: BedrockMessage) throws -> AWSBedrockRuntime.BedrockRuntimeClientTypes.Message {
        // Convert content blocks
        var contentBlocks: [AWSBedrockRuntime.BedrockRuntimeClientTypes.ContentBlock] = []
        
        for content in message.content {
            switch content {
            case .text(let text):
                contentBlocks.append(.text(text))
                
            case .image(let imageContent):
                // Convert to AWS image format
                let awsFormat: AWSBedrockRuntime.BedrockRuntimeClientTypes.ImageFormat
                switch imageContent.format {
                    case .jpeg: awsFormat = .jpeg
                    case .png: awsFormat = .png
                    case .gif: awsFormat = .gif
                    case .webp: awsFormat = .webp
                }

                guard let imageData = Data(base64Encoded: imageContent.base64Data) else {
                    throw NSError(domain: "ChatViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode base64 string to Data"])
                }

                contentBlocks.append(.image(AWSBedrockRuntime.BedrockRuntimeClientTypes.ImageBlock(
                    format: awsFormat,
                    source: .bytes(imageData)
                )))
            }
        }
        
        // SDK 문서와 일치하는 Message 생성
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
    
    /// Handles image generation models that don't use converseStream
    private func handleImageGenerationModel(_ userMessage: MessageData) async throws {
        let modelId = chatModel.id
        
        if modelId.contains("titanImage") {
            try await invokeTitanImageModel(prompt: userMessage.text)
        } else if modelId.contains("novaCanvas") {
            try await invokeNovaCanvasModel(prompt: userMessage.text)
        } else if modelId.contains("stable") || modelId.contains("sd3") {
            try await invokeStableDiffusionModel(prompt: userMessage.text)
        } else {
            throw NSError(domain: "ChatViewModel", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported image generation model: \(modelId)"
            ])
        }
    }
    
    /// Invokes Titan Image model
    private func invokeTitanImageModel(prompt: String) async throws {
        let data = try await backendModel.backend.invokeImageModel(
            withId: chatModel.id,
            prompt: prompt,
            modelType: .titanImage
        )
        
        try processImageModelResponse(data)
    }
    
    /// Invokes Nova Canvas image model
    private func invokeNovaCanvasModel(prompt: String) async throws {
        let data = try await backendModel.backend.invokeImageModel(
            withId: chatModel.id,
            prompt: prompt,
            modelType: .novaCanvas
        )
        
        try processImageModelResponse(data)
    }
    
    /// Invokes Stable Diffusion image model
    private func invokeStableDiffusionModel(prompt: String) async throws {
        let data = try await backendModel.backend.invokeImageModel(
            withId: chatModel.id,
            prompt: prompt,
            modelType: .stableDiffusion
        )
        
        try processImageModelResponse(data)
    }
    
    /// Process and save image data from image generation models
    private func processImageModelResponse(_ data: Data) throws {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let timestamp = formatter.string(from: now)
        let fileName = "\(timestamp).png"
        let tempDir = URL(fileURLWithPath: settingManager.defaultDirectory)
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        try data.write(to: fileURL)
        
        if let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            let markdownImage = "![](http://localhost:8080/\(encoded))"
            let imageMessage = MessageData(
                id: UUID(),
                text: markdownImage,
                user: chatModel.name,
                isError: false,
                sentTime: Date()
            )
            messages.append(imageMessage)
            chatManager.addMessage(imageMessage, for: chatId)
            
            // Update history
            var history = chatManager.getHistory(for: chatId)
            history += "\nAssistant: [Generated Image]\n"
            chatManager.setHistory(history, for: chatId)
        } else {
            throw NSError(
                domain: "ImageEncodingError",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode image filename"]
            )
        }
    }
    
    @MainActor
    private func addMessage(_ message: MessageData) {
        messages.append(message)
        chatManager.addMessage(message, for: chatId)
    }
    
    private func handleModelError(_ error: Error) async {
        print("Error invoking the model: \(error)")
        let errorMessage = MessageData(
            id: UUID(),
            text: "Error invoking the model: \(error)",
            user: "System",
            isError: true,
            sentTime: Date()
        )
        addMessage(errorMessage)
    }
    
    /// Append the text to the last message, or create a new one.
    private func appendTextToMessage(_ text: String, thinking: String? = nil, shouldCreateNewMessage: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if shouldCreateNewMessage {
                self.messages.append(MessageData(
                    id: UUID(),
                    text: text,
                    thinking: thinking,
                    user: self.chatModel.name,
                    isError: false,
                    sentTime: Date()
                ))
            } else {
                if var lastMessage = self.messages.last {
                    lastMessage.text += text
                    if let thinking = thinking {
                        lastMessage.thinking = (lastMessage.thinking ?? "") + thinking
                    }
                    self.messages[self.messages.count - 1] = lastMessage
                }
            }
            self.objectWillChange.send()
        }
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
        let summaryPrompt = """
        Summarize user input <input>\(input)</input> as short as possible. Just in few words without punctuation. It should not be more than 5 words. It will be book title. Do as best as you can. If you don't know how to do summarize, please give me just 'Friendly Chat', but please do summary this without punctuation:
        """
        
        // Create message for converseStream
        let userMsg = BedrockMessage(
            role: .user,
            content: [.text(summaryPrompt)]
        )
        
        // Use Claude-3 Haiku for title generation
        let haikuModelId = "anthropic.claude-3-haiku-20240307-v1:0"
        
        do {
            // Convert to AWS SDK format
            let awsMessage = try convertToBedrockMessage(userMsg)

            // Use converseStream API to get the title
            var title = ""
            
            let systemContentBlocks: [BedrockRuntimeClientTypes.SystemContentBlock]? = nil

            for try await chunk in try await backendModel.backend.converseStream(
                withId: haikuModelId,
                messages: [awsMessage],
                systemContent: systemContentBlocks,
                inferenceConfig: nil
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
            print("Error updating chat title: \(error)")
        }
    }
}
