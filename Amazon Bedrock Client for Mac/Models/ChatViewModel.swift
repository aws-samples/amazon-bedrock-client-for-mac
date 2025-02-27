//
//  ChatViewModel.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 6/28/24.
//

import SwiftUI
import Combine

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
        
        // Enable streaming only for text generation models
        let id = model.id.lowercased()

        self.selectedPlaceholder = ChatViewModel.placeholderMessages.randomElement() ?? "No messages"
        
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
            if chatModel.id.contains("claude-3") {
                try await handleClaudeMessage(userMessage)
            }
            else if chatModel.id.contains("nova-pro") || chatModel.id.contains("nova-lite") {
                try await handleNovaMessage(userMessage) // Add this case
            }
            else {
                try await handleStandardMessage(userMessage)
            }
        } catch let error {
            // Special handling for Titan Image validation exception
            if let nsError = error as NSError?,
               nsError.localizedDescription.contains("ValidationException") && 
               nsError.localizedDescription.contains("maxLength: 512") {
                // Create a more user-friendly error message
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
    
    private func handleClaudeMessage(_ userMessage: MessageData) async throws {
        let contentBlocks = createContentBlocks(from: userMessage)
        let message = ClaudeMessageRequest.Message(role: "user", content: contentBlocks)
        chatManager.addClaudeHistory(message, for: chatId)
        
        if isStreamingEnabled {
            try await invokeClaudeModelStream(claudeMessages: chatManager.getClaudeHistory(for: chatId))
        } else {
            try await invokeClaudeModel(claudeMessages: chatManager.getClaudeHistory(for: chatId))
        }
    }
    
    // MARK: -- Step 3: (AMAZON NOVA MODEL SPECIFIC)
    // MARK: -- Handle Nova Message
    private func handleNovaMessage(_ userMessage: MessageData) async throws {
        let contentBlocks = createNovaContentBlocks(from: userMessage)
        let message = NovaModelParameters.Message(role: "user", content: contentBlocks)
        
        // Use Nova-specific history management
        chatManager.addNovaHistory(message, for: chatId)
        
        // Get Nova message history
        let novaMessages = chatManager.getNovaHistory(for: chatId)
        
        if isStreamingEnabled {
            try await invokeNovaModelStream(novaMessages: novaMessages)
        } else {
            try await invokeNovaModel(novaMessages: novaMessages)
        }
    }
    
    private func convertClaudeToNovaMessage(_ claudeMessage: ClaudeMessageRequest.Message) -> NovaModelParameters.Message {
        let novaContents = claudeMessage.content.map { claudeContent -> NovaModelParameters.Message.MessageContent in
            if claudeContent.type == "text" {
                return NovaModelParameters.Message.MessageContent(
                    text: claudeContent.text
                )
            } else if claudeContent.type == "image",
                      let source = claudeContent.source {
                return NovaModelParameters.Message.MessageContent(
                    image: NovaModelParameters.Message.MessageContent.ImageContent(
                        format: .jpeg,
                        source: NovaModelParameters.Message.MessageContent.ImageContent.ImageSource(
                            bytes: source.data
                        )
                    )
                )
            }
            // Default fallback
            return NovaModelParameters.Message.MessageContent(text: "")
        }
        
        return NovaModelParameters.Message(
            role: claudeMessage.role,
            content: novaContents
        )
    }

    // Helper function to create Nova content blocks
    private func createNovaContentBlocks(from message: MessageData) -> [NovaModelParameters.Message.MessageContent] {
        var contents: [NovaModelParameters.Message.MessageContent] = []
        
        // Add text content if present
        if !message.text.isEmpty {
            contents.append(NovaModelParameters.Message.MessageContent(
                text: message.text
            ))
        }
        
        // Add image content if present
        if let imageBase64Strings = message.imageBase64Strings {
            for (index, base64String) in imageBase64Strings.enumerated() {
                let fileExtension = sharedImageDataSource.fileExtensions.indices.contains(index)
                    ? sharedImageDataSource.fileExtensions[index].lowercased()
                    : "jpeg"
                
                let format: NovaModelParameters.Message.MessageContent.ImageContent.ImageFormat
                switch fileExtension {
                    case "jpg", "jpeg": format = .jpeg
                    case "png": format = .png
                    case "gif": format = .gif
                    case "webp": format = .webp
                    default: format = .jpeg
                }
                
                contents.append(NovaModelParameters.Message.MessageContent(
                    image: NovaModelParameters.Message.MessageContent.ImageContent(
                        format: format,
                        source: NovaModelParameters.Message.MessageContent.ImageContent.ImageSource(
                            bytes: base64String
                        )
                    )
                ))
            }
        }
        return contents
    }

    private func handleStandardMessage(_ userMessage: MessageData) async throws {
        var history = chatManager.getHistory(for: chatId)
        let trimmedHistory = trimHistory(history)
        
        history += formatHistoryAddition(userInput: userMessage.text)
        
        let isTextGenerationModel = isTextGenerationModel(chatModel.id)
        
        let prompt = createPrompt(history: trimmedHistory, userInput: userMessage.text, isTextGenerationModel: isTextGenerationModel)
        
        chatManager.setHistory(history, for: chatId)
        
        if isStreamingEnabled {
            try await invokeModelStream(prompt: prompt)
        } else {
            try await invokeModel(prompt: prompt)
        }
    }
    
    private func trimHistory(_ history: String) -> String {
        if history.count > 50000 {
            return String(history.suffix(50000))
        }
        return history
    }
    
    private func formatHistoryAddition(userInput: String) -> String {
        let modelId = chatModel.id.lowercased()
        if modelId.contains("llama3") {
            return "user\n\n\(userInput)\n\n"
        } else {
            return "\nHuman: \(userInput)"
        }
    }
    
    @MainActor
    private func addMessage(_ message: MessageData) {
        messages.append(message)
        chatManager.addMessage(message, for: chatId)
    }
    
    private func handleModelError(_ error: Error) async {
        print("Error invoking the model: \(error)")
        let errorMessage = MessageData(id: UUID(), text: "Error invoking the model: \(error)", user: "System", isError: true, sentTime: Date())
        addMessage(errorMessage)
    }
    
    private func createPrompt(history: String, userInput: String, isTextGenerationModel: Bool) -> String {
        var prompt = ""
        
        if isTextGenerationModel {
            let systemPrompt = SettingManager.shared.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !systemPrompt.isEmpty {
                prompt += "<system>\(systemPrompt)</system>\n\n"
            } else {
                prompt += "The following is a friendly conversation between a human and an AI assistant.\n"
            }
            prompt += "Current conversation:\n\(history)\n\n"
            prompt += "Human: \(userInput)\nAssistant:"
        } else {
            prompt = userInput
        }
        
        return prompt
    }
    
    /// Invokes the Nova model (Streaming)
    func invokeNovaModelStream(novaMessages: [NovaModelParameters.Message]) async throws {
        let modelId = chatModel.id
        let systemPrompt = SettingManager.shared.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        let response = try await backendModel.backend.invokeNovaModelStream(
            withId: modelId,
            messages: novaMessages,
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt
        )
        
        var streamedText = ""
        
        var isFirstChunk = true
        for try await event in response {
            switch event {
            case .chunk(let part):
                guard let jsonObject = try JSONSerialization.jsonObject(with: part.bytes!, options: []) as? [String: Any] else {
                    print("Failed to decode JSON chunk")
                    continue
                }
                
                // Debug print
                print("Received chunk:", jsonObject)
                
                // Transform Nova's response format to match the expected format for handleContentBlockDelta
                if let contentBlockDelta = jsonObject["contentBlockDelta"] as? [String: Any],
                   let delta = contentBlockDelta["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    streamedText += text
                    
                    appendTextToMessage(text, shouldCreateNewMessage: isFirstChunk)
                    isFirstChunk = false
                }
                
            case .sdkUnknown(let unknown):
                print("Unknown SDK event:", unknown)
            }
        }
        
        let assistantMessage = MessageData(
            id: UUID(),
            text: streamedText.trimmingCharacters(in: .whitespacesAndNewlines),
            user: chatModel.name,
            isError: false,
            sentTime: Date()
        )
        chatManager.addMessage(assistantMessage, for: chatId)
        
        let assistantNovaMessage = NovaModelParameters.Message(
            role: "assistant",
            content: [NovaModelParameters.Message.MessageContent(text: assistantMessage.text)]
        )
        chatManager.addNovaHistory(assistantNovaMessage, for: chatId)
    }

    func invokeClaudeModelStream(claudeMessages: [ClaudeMessageRequest.Message]) async throws {
        let modelId = chatModel.id
        let systemPrompt = SettingManager.shared.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        let response = try await backendModel.backend.invokeClaudeModelStream(
            withId: modelId,
            messages: claudeMessages,
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt
        )

        var streamedText = ""
        var thinking: String? = nil
        
        var isFirstChunk = true
        for try await event in response {
            switch event {
            case .chunk(let part):
                guard let jsonObject = try JSONSerialization.jsonObject(with: part.bytes!, options: []) as? [String: Any] else {
                    print("Failed to decode JSON")
                    continue
                }
                
                if let delta = jsonObject["delta"] as? [String: Any],
                   let type = delta["type"] as? String {
                    switch type {
                    case "text_delta":
                        if let text = delta["text"] as? String {
                            streamedText += text
                            appendTextToMessage(text, shouldCreateNewMessage: isFirstChunk)
                        }
                        isFirstChunk = false
                    case "message_delta":
                        handleMessageDelta(jsonObject)
                    case "thinking_delta":
                        if let thinkingChunk = delta["thinking"] as? String {
                            thinking = (thinking ?? "") + thinkingChunk
                            appendTextToMessage("", thinking: thinkingChunk, shouldCreateNewMessage: isFirstChunk)
                        }
                        isFirstChunk = false
                    default:
                        print("Unhandled event type: \(type)")
                    }
                }
            case .sdkUnknown(let unknown):
                print("Unknown SDK event: \"\(unknown)\"")
            }
        }
        
        let assistantMessage = MessageData(id: UUID(), text: streamedText.trimmingCharacters(in: .whitespacesAndNewlines), thinking: thinking, user: chatModel.name, isError: false, sentTime: Date())
        chatManager.addMessage(assistantMessage, for: chatId)
        
        let assistantClaudeMessage = ClaudeMessageRequest.Message(role: "assistant", content: [.init(type: "text", text: assistantMessage.text)])
        chatManager.addClaudeHistory(assistantClaudeMessage, for: chatId)
    }
    
    /// Handles message delta events.
    private func handleMessageDelta(_ jsonObject: [String: Any]) {
        if let delta = jsonObject["delta"] as? [String: Any],
           let stopReason = delta["stop_reason"] as? String,
           let stopSequence = delta["stop_sequence"] as? String,
           let usage = delta["usage"] as? [String: Any],
           let outputTokens = usage["output_tokens"] as? Int {
            DispatchQueue.main.async {
                print("\nStop reason: \(stopReason)")
                print("Stop sequence: \(stopSequence)")
                print("Output tokens: \(outputTokens)")
            }
        }
    }
    
    /// Append the text to the last message, or create a new one.
    private func appendTextToMessage(_ text: String, thinking: String? = nil, shouldCreateNewMessage: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if shouldCreateNewMessage {
                self.messages.append(MessageData(id: UUID(), text: text, thinking: thinking, user: self.chatModel.name, isError: false, sentTime: Date()))
            } else {
                if var lastMessage = self.messages.last {
                    lastMessage.text += text
                    if let thinking {
                        lastMessage.thinking = (lastMessage.thinking ?? "") + thinking
                    }
                    self.messages[self.messages.count - 1] = lastMessage
                }
            }
            self.objectWillChange.send()
        }
    }
    
    /// Invokes the Claude model.
    func invokeClaudeModel(claudeMessages: [ClaudeMessageRequest.Message]) async throws {
        let modelId = chatModel.id
        let systemPrompt = SettingManager.shared.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        let data = try await backendModel.backend.invokeClaudeModel(
            withId: modelId,
            messages: claudeMessages,
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt
        )
        let response = try JSONDecoder().decode(ClaudeMessageResponse.self, from: data)
        
        if let firstText = response.content.first?.text {
            let assistantMessage = MessageData(id: UUID(), text: firstText.trimmingCharacters(in: .whitespacesAndNewlines), user: chatModel.name, isError: false, sentTime: Date())
            messages.append(assistantMessage)
            chatManager.addMessage(assistantMessage, for: chatId)
            
            // Add assistant message to Claude history
            let assistantClaudeMessage = ClaudeMessageRequest.Message(role: "assistant", content: [.init(type: "text", text: assistantMessage.text)])
            chatManager.addClaudeHistory(assistantClaudeMessage, for: chatId)
        }
    }

    // MARK: -- Invoke Nova Model
    /// Invokes the Nova model (Non-Streaming)
    func invokeNovaModel(novaMessages: [NovaModelParameters.Message]) async throws {
        let modelId = chatModel.id
        let systemPrompt = SettingManager.shared.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let data = try await backendModel.backend.invokeNovaModel(
            withId: modelId,
            messages: novaMessages,
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt
        )
        
        let response = try JSONDecoder().decode(InvokeNovaResponse.self, from: data)
        
        if let firstText = response.output.message.content.first?.text {
            let assistantMessage = MessageData(
                id: UUID(),
                text: firstText.trimmingCharacters(in: .whitespacesAndNewlines),
                user: chatModel.name,
                isError: false,
                sentTime: Date()
            )
            messages.append(assistantMessage)
            chatManager.addMessage(assistantMessage, for: chatId)
            
            // Add assistant message to Nova history
            let assistantNovaMessage = NovaModelParameters.Message(
                role: "assistant",
                content: [NovaModelParameters.Message.MessageContent(text: assistantMessage.text)]
            )
            chatManager.addNovaHistory(assistantNovaMessage, for: chatId) // Add NovaHistory
        }
    }
    
    private func invokeModelStream(prompt: String) async throws {
        var isFirstChunk = true
        let modelId = chatModel.id
        let modelType = backendModel.backend.getModelType(modelId)
        
        var streamedText = ""
        
        // Use Converse API for supported models
        if modelType.usesConverseAPI {
            let converseResponse = try await backendModel.backend.converseStream(withId: modelId, prompt: prompt)
            
            for try await output in converseResponse {
                switch output {
                case .contentblockdelta(let deltaEvent):
                    // ContentBlockDelta 구조에 맞게 처리
                    if let delta = deltaEvent.delta {
                        // delta가 enum일 경우 switch로 처리
                        switch delta {
                        case .text(let textContent):
                            appendTextToMessage(textContent, shouldCreateNewMessage: isFirstChunk)
                            isFirstChunk = false
                            streamedText += textContent
                        default:
                            // 다른 delta 타입 처리
                            break
                        }
                    }
                case .messagestart, .contentblockstart, .contentblockstop, .messagestop, .metadata:
                    // 필요한 경우 이러한 이벤트도 처리할 수 있습니다
                    break
                case .sdkUnknown(let unknown):
                    print("Unknown ConverseStream event: \"\(unknown)\"")
                }
            }
        } else {
            let invokeResponse = try await backendModel.backend.invokeModelStream(withId: modelId, prompt: prompt)
            
            for try await event in invokeResponse {
                switch event {
                case .chunk(let part):
                    let jsonObject = try JSONSerialization.jsonObject(with: part.bytes!, options: [])
                    appendTextToMessage(extractTextFromChunk(jsonObject, modelType: modelType)!, shouldCreateNewMessage: isFirstChunk)
                    isFirstChunk = false
                    if let chunkText = extractTextFromChunk(jsonObject, modelType: modelType) {
                        streamedText += chunkText
                    }
                case .sdkUnknown(let unknown):
                    print("Unknown ResponseStream event: \"\(unknown)\"")
                }
            }
        }
        
        // After streaming is complete, update the history
        let assistantMessage = MessageData(id: UUID(), text: streamedText.trimmingCharacters(in: .whitespacesAndNewlines), user: chatModel.name, isError: false, sentTime: Date())
        chatManager.addMessage(assistantMessage, for: chatId)
        
        var history = chatManager.getHistory(for: chatId)
        if modelType == .llama3 {
            history += "assistant\n\n\(assistantMessage.text)\n\n"
        } else {
            history += "\nAssistant: \(assistantMessage.text)\n"
        }
        chatManager.setHistory(history, for: chatId)
    }

    
    private func extractTextFromChunk(_ jsonObject: Any, modelType: ModelType) -> String? {
        if let dict = jsonObject as? [String: Any] {
            switch modelType {
            case .novaPro, .novaLite, .novaMicro:
                if let contentBlockDelta = dict["contentBlockDelta"] as? [String: Any],
                   let delta = contentBlockDelta["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    return text
                }
            case .titan:
                return dict["outputText"] as? String
            case .claude:
                return dict["completion"] as? String
            case .llama2, .llama3, .mistral:
                // Check for Converse API response format
                if let message = dict["message"] as? [String: Any],
                   let content = message["content"] as? [[String: Any]],
                   let text = content.first?["text"] as? String {
                    return text
                }
                // Check for old API response format
                else if let generation = dict["generation"] as? String {
                    return generation
                } else if let outputs = dict["outputs"] as? [[String: Any]],
                          let text = outputs.first?["text"] as? String {
                    return text
                }
            default:
                return nil
            }
        }
        return nil
    }
    
    /// Handles processed text.
    private func handleProcessedText(_ processedText: String, modelType: ModelType, isFirstChunk: inout Bool) {
        if isFirstChunk {
            isFirstChunk = false
            emptyText.append(processedText.trimmingCharacters(in: .whitespacesAndNewlines))
            messages.append(MessageData(id: UUID(), text: emptyText, user: chatModel.name, isError: false, sentTime: Date()))
        } else {
            emptyText.append(processedText)
            messages[messages.count - 1].text = emptyText
        }
    }
    
    private func invokeModel(prompt: String) async throws {
        let modelId = chatModel.id
        let modelType = backendModel.backend.getModelType(modelId)
        
        if modelType != .stableDiffusion {
            let data = try await backendModel.backend.invokeModel(withId: modelId, prompt: prompt)
            try handleModelResponse(data, modelType: modelType)
        } else {
            let data = try await backendModel.backend.invokeStableDiffusionModel(withId: modelId, prompt: prompt)
            try handleStableDiffusionResponse(data)
        }
    }
    
    /// Handles model response.
    private func handleModelResponse(_ data: Data, modelType: ModelType) throws {
        let assistantMessage: MessageData
        
        switch modelType {
        case .claude:
            let response = try backendModel.backend.decode(data) as InvokeClaudeResponse
            assistantMessage = MessageData(id: UUID(), text: response.completion.trimmingCharacters(in: .whitespacesAndNewlines), user: chatModel.name, isError: false, sentTime: Date())
        case .novaPro, .novaLite, .novaMicro:
            let response = try backendModel.backend.decode(data) as InvokeNovaResponse
            let text = response.output.message.content.first?.text ?? "No response text found in Nova model output." // Add Message Data
            assistantMessage = MessageData(id: UUID(), text: text.trimmingCharacters(in: .whitespacesAndNewlines), user: chatModel.name, isError: false, sentTime: Date())
        case .titan:
            let response = try backendModel.backend.decode(data) as InvokeTitanResponse
            assistantMessage = MessageData(id: UUID(), text: response.results[0].outputText.trimmingCharacters(in: .whitespacesAndNewlines), user: chatModel.name, isError: false, sentTime: Date())
            
        case .j2:
            let response = try backendModel.backend.decode(data) as InvokeAI21Response
            assistantMessage = MessageData(id: UUID(), text: response.completions[0].data.text.trimmingCharacters(in: .whitespacesAndNewlines), user: chatModel.name, isError: false, sentTime: Date())
            
        case .titanImage:
            let response = try backendModel.backend.decode(data) as InvokeTitanImageResponse
            try handleTitanImageResponse(response)
            return // 이미지 응답은 별도로 처리되므로 여기서 반환
            
        case .novaCanvas:
            let response = try backendModel.backend.decode(data) as InvokeNovaCanvasResponse
            try handleNovaCanvasResponse(response)
            return // 이미지 응답은 별도로 처리되므로 여기서 반환
            
        case .titanEmbed:
            let response = try backendModel.backend.decode(data) as InvokeTitanEmbedResponse
            assistantMessage = MessageData(id: UUID(), text: response.embedding.map({"\($0)"}).joined(separator: ","), user: chatModel.name, isError: false, sentTime: Date())
            
        case .cohereCommand:
            let response = try backendModel.backend.decode(data) as InvokeCommandResponse
            assistantMessage = MessageData(id: UUID(), text: response.generations[0].text, user: chatModel.name, isError: false, sentTime: Date())
            
        case .cohereEmbed:
            let response = try backendModel.backend.decode(data) as InvokeCohereEmbedResponse
            assistantMessage = MessageData(id: UUID(), text: response.embeddings.map({"\($0)"}).joined(separator: ","), user: chatModel.name, isError: false, sentTime: Date())
            
        case .llama2, .llama3, .mistral:
            // Handle Converse API response format
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let outputMessage = json["output"] as? [String: Any],
               let message = outputMessage["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]],
               let text = content.first?["text"] as? String {
                
                assistantMessage = MessageData(
                    id: UUID(), 
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines), 
                    user: chatModel.name, 
                    isError: false, 
                    sentTime: Date()
                )
            }
            // Fallback to old API format
            else {
                let response = try backendModel.backend.decode(data) as InvokeLlama2Response
                assistantMessage = MessageData(
                    id: UUID(), 
                    text: response.generation, 
                    user: chatModel.name, 
                    isError: false, 
                    sentTime: Date()
                )
            }
            
        case .jambaInstruct:
            let response = try backendModel.backend.decode(data) as InvokeJambaInstructResponse
            if let firstChoice = response.choices.first {
                assistantMessage = MessageData(
                    id: UUID(),
                    text: firstChoice.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
                    user: chatModel.name,
                    isError: false,
                    sentTime: Date()
                )
            } else {
                // Handle case where there are no choices in the response
                assistantMessage = MessageData(
                    id: UUID(),
                    text: "No response from the model.",
                    user: chatModel.name,
                    isError: true,
                    sentTime: Date()
                )
            }
            
        default:
            assistantMessage = MessageData(id: UUID(), text: "Error: Unable to decode response.", user: "System", isError: false, sentTime: Date())
        }
        
        // 메시지 추가 및 히스토리 업데이트
        messages.append(assistantMessage)
        chatManager.addMessage(assistantMessage, for: chatId)
        
        // 히스토리 업데이트
        var history = chatManager.getHistory(for: chatId)
        if modelType == .llama3 {
            history += "assistant\n\n\(assistantMessage.text)\n\n"
        } else {
            history += "\nAssistant: \(assistantMessage.text)\n"
        }
        chatManager.setHistory(history, for: chatId)
    }
    
    private func handleTitanImageResponse(_ response: InvokeTitanImageResponse) throws {
        let image = response.images[0]
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let timestamp = formatter.string(from: now)
        let fileName = "\(timestamp).png"
        let tempDir = URL(fileURLWithPath: settingManager.defaultDirectory)
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try image.write(to: fileURL)
            
            if let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                let markdownImage = "![](http://localhost:8080/\(encoded))"
                let imageMessage = MessageData(id: UUID(), text: markdownImage, user: chatModel.name, isError: false, sentTime: Date())
                messages.append(imageMessage)
                chatManager.addMessage(imageMessage, for: chatId)
                
                // 이미지 응답에 대한 히스토리 업데이트
                var history = chatManager.getHistory(for: chatId)
                history += "\nAssistant: [Generated Image]\n"
                chatManager.setHistory(history, for: chatId)
            } else {
                throw NSError(domain: "ImageEncodingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image filename"])
            }
        } catch {
            throw error
        }
    }
    
    private func handleNovaCanvasResponse(_ response: InvokeNovaCanvasResponse) throws {
        // 에러 필드가 있으면 예외 처리
        if let errorMessage = response.error, !errorMessage.isEmpty {
            throw NSError(domain: "NovaCanvasError", code: 0, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }

        guard let image = response.images.first else {
            throw NSError(domain: "NovaCanvasError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No images returned"])
        }

        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let timestamp = formatter.string(from: now)
        let fileName = "\(timestamp).png"
        let tempDir = URL(fileURLWithPath: settingManager.defaultDirectory)
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try image.write(to: fileURL)
            
            if let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                let markdownImage = "![](http://localhost:8080/\(encoded))"
                let imageMessage = MessageData(id: UUID(), text: markdownImage, user: chatModel.name, isError: false, sentTime: Date())
                messages.append(imageMessage)
                chatManager.addMessage(imageMessage, for: chatId)
                
                var history = chatManager.getHistory(for: chatId)
                history += "\nAssistant: [Generated Image]\n"
                chatManager.setHistory(history, for: chatId)
            } else {
                throw NSError(domain: "ImageEncodingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image filename"])
            }
        } catch {
            throw error
        }
    }
    
    /// Handles Stable Diffusion response.
    private func handleStableDiffusionResponse(_ data: Data) throws {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let timestamp = formatter.string(from: now)
        let fileName = "\(timestamp).png"
        let tempDir = URL(fileURLWithPath: settingManager.defaultDirectory)
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            
            if let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                let markdownImage = "![](http://localhost:8080/\(encoded))"
                let imageMessage = MessageData(id: UUID(), text: markdownImage, user: chatModel.name, isError: false, sentTime: Date())
                messages.append(imageMessage)
                chatManager.addMessage(imageMessage, for: chatId)
                
                var history = chatManager.getHistory(for: chatId)
                history += "\nAssistant: [Generated Image]\n"
                chatManager.setHistory(history, for: chatId)
            } else {
                throw NSError(domain: "ImageEncodingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image filename"])
            }
        } catch {
            throw error
        }
    }
    
    private func createContentBlocks(from message: MessageData) -> [ClaudeMessageRequest.Message.Content] {
        var contentBlocks: [ClaudeMessageRequest.Message.Content] = []
        
        let textContentBlock = ClaudeMessageRequest.Message.Content(type: "text", text: message.text, source: nil)
        contentBlocks.append(textContentBlock)
        
        for base64String in message.imageBase64Strings ?? [] {
            let imageContentBlock = ClaudeMessageRequest.Message.Content(
                type: "image",
                source: ClaudeMessageRequest.Message.Content.ImageSource(
                    mediaType: "image/jpeg", // Assuming JPEG for simplicity
                    data: base64String
                )
            )
            contentBlocks.append(imageContentBlock)
        }
        
        return contentBlocks
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
    
    private static let placeholderMessages = [
        "Start a conversation!",
        "Say something to get started.",
        "Messages will appear here.",
        "Go ahead, say hi!",
        "Ready for your message!",
        "Type something to begin!"
    ]
    
    /// Updates the chat title with a summary of the input.
    func updateChatTitle(with input: String) async {
        let summaryPrompt = """
        Summarize user input <input>\(input)</input> as short as possible. Just in few words without punctuation. It should not be more than 5 words. It will be book title. Do as best as you can. If you don't know how to do summarize, please give me just 'Friendly Chat', but please do summary this without punctuation:
        """
        
        let haikuModelId = "anthropic.claude-3-haiku-20240307-v1:0"
        let message = ClaudeMessageRequest.Message(role: "user", content: [.init(type: "text", text: summaryPrompt)])
        
        do {
            let data = try await backendModel.backend.invokeClaudeModel(withId: haikuModelId, messages: [message], systemPrompt: nil)
            let response = try backendModel.backend.decode(data) as ClaudeMessageResponse
            
            if let firstText = response.content.first?.text {
                chatManager.updateChatTitle(for: chatModel.chatId, title: firstText.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } catch {
            print("Error updating chat title: \(error)")
        }
    }
}
