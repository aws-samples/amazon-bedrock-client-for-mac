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
import MCPInterface
import Smithy

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
        
        // Helper to convert from file extension
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
    // MARK: - Properties
    let chatId: String
    let chatManager: ChatManager
    let sharedMediaDataSource: SharedMediaDataSource
    @ObservedObject private var settingManager = SettingManager.shared
    @ObservedObject private var mcpManager = MCPManager.shared
    
    @ObservedObject var backendModel: BackendModel
    @Published var chatModel: ChatModel
    @Published var messages: [MessageData] = []
    @Published var userInput: String = ""
    @Published var isMessageBarDisabled: Bool = false
    @Published var isSending: Bool = false
    @Published var isStreamingEnabled: Bool = false
    @Published var selectedPlaceholder: String
    @Published var emptyText: String = ""
    @Published var availableTools: [MCPToolInfo] = []
    
    private var logger = Logger(label: "ChatViewModel")
    private var cancellables: Set<AnyCancellable> = []
    private var messageTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init(chatId: String, backendModel: BackendModel, chatManager: ChatManager = .shared, sharedMediaDataSource: SharedMediaDataSource) {
        self.chatId = chatId
        self.backendModel = backendModel
        self.chatManager = chatManager
        self.sharedMediaDataSource = sharedMediaDataSource
        
        guard let model = chatManager.getChatModel(for: chatId) else {
            fatalError("Chat model not found for id: \(chatId)")
        }
        self.chatModel = model
        
        self.selectedPlaceholder = ""
        
        setupStreamingEnabled()
        setupBindings()
    }
    
    // MARK: - Setup Methods
    
    private func setupStreamingEnabled() {
        // Enable streaming for all text generation models
        self.isStreamingEnabled = isTextGenerationModel(chatModel.id)
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
        logger.error("Error: Chat model not found for id: \(chatId)")
    }
    
    // MARK: - Public Methods
    
    func loadInitialData() {
        messages = chatManager.getMessages(for: chatId)
    }
    
    func sendMessage() {
        guard !userInput.isEmpty else { return }
        
        messageTask?.cancel()
        messageTask = Task { await sendMessageAsync() }
    }
    
    func cancelSending() {
        messageTask?.cancel()
        chatManager.setIsLoading(false, for: chatId)
    }
    
    // MARK: - Private Message Handling Methods
    
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
            sharedMediaDataSource.images.removeAll()
            sharedMediaDataSource.fileExtensions.removeAll()
            sharedMediaDataSource.documents.removeAll()
        }
        
        do {
            // Determine model type and choose appropriate handling
            if backendModel.backend.isImageGenerationModel(chatModel.id) {
                try await handleImageGenerationModel(userMessage)
            } else if backendModel.backend.isEmbeddingModel(chatModel.id) {
                try await handleEmbeddingModel(userMessage)
            } else {
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
            // Generic error handling
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
    
    private func createUserMessage() -> MessageData {
        // Process images
        let imageBase64Strings = sharedMediaDataSource.images.enumerated().compactMap { index, image -> String? in
            guard index < sharedMediaDataSource.fileExtensions.count else {
                logger.error("Missing extension for image at index \(index)")
                return nil
            }
            
            let fileExtension = sharedMediaDataSource.fileExtensions[index]
            let result = base64EncodeImage(image, withExtension: fileExtension)
            return result.base64String
        }
        
        // Process documents
        var documentBase64Strings: [String] = []
        var documentFormats: [String] = []
        var documentNames: [String] = []
        
        for (index, docData) in sharedMediaDataSource.documents.enumerated() {
            let docIndex = sharedMediaDataSource.images.count + index
            
            // Get document metadata
            let fileExt = docIndex < sharedMediaDataSource.fileExtensions.count ?
            sharedMediaDataSource.fileExtensions[docIndex] : "pdf"
            
            let filename = docIndex < sharedMediaDataSource.filenames.count ?
            sharedMediaDataSource.filenames[docIndex] : "document\(index+1)"
            
            // Encode document data
            let base64String = docData.base64EncodedString()
            documentBase64Strings.append(base64String)
            documentFormats.append(fileExt)
            documentNames.append(filename)
        }
        
        // Create message with all attachments
        return MessageData(
            id: UUID(),
            text: userInput,
            user: "User",
            isError: false,
            sentTime: Date(),
            imageBase64Strings: imageBase64Strings.isEmpty ? nil : imageBase64Strings,
            documentBase64Strings: documentBase64Strings.isEmpty ? nil : documentBase64Strings,
            documentFormats: documentFormats.isEmpty ? nil : documentFormats,
            documentNames: documentNames.isEmpty ? nil : documentNames
        )
    }
    
    // MARK: - Text LLM Integration with MCP
    
    /**
     * Tool use tracker class to maintain state across streaming chunks.
     * Used to accumulate information about a tool use request over multiple events.
     */
    class ToolUseTracker {
        static let shared = ToolUseTracker()
        
        var toolUseId: String?
        var name: String?
        var inputString = ""
        var currentBlockIndex: Int?
        
        func reset() {
            toolUseId = nil
            name = nil
            inputString = ""
            currentBlockIndex = nil
        }
        
        func getToolUseInfo() -> (toolUseId: String, name: String, input: Any)? {
            guard let toolUseId = toolUseId, let name = name, !inputString.isEmpty else {
                return nil
            }
            
            // Return empty object for empty input
            if inputString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (toolUseId: toolUseId, name: name, input: [:])
            }
            
            // Parse JSON string to Any type
            if let data = inputString.data(using: .utf8) {
                do {
                    // Don't use if let since jsonObject returns Any, not optional
                    let json = try JSONSerialization.jsonObject(with: data)
                    return (toolUseId: toolUseId, name: name, input: json)
                } catch {
                    // Return original string on parsing failure
                    return (toolUseId: toolUseId, name: name, input: inputString)
                }
            }
            
            // Return original string if all parsing attempts fail
            return (toolUseId: toolUseId, name: name, input: inputString)
        }
    }
    
    /**
     * Converts MCP tools to AWS Bedrock format for use with the Converse API.
     * Transforms tool specifications from MCP format to Bedrock's expected structure.
     *
     * @param tools Array of MCP tool information objects
     * @return Bedrock-compatible tool configuration
     */
    private func convertMCPToolsToBedrockFormat(_ tools: [MCPManager.MCPToolInfo]) -> AWSBedrockRuntime.BedrockRuntimeClientTypes.ToolConfiguration {
        logger.debug("Converting \(tools.count) MCP tools to Bedrock format")
        
        let bedrockTools: [AWSBedrockRuntime.BedrockRuntimeClientTypes.Tool] = tools.compactMap { toolInfo in
            var propertiesDict: [String: Any] = [:]
            var required: [String] = []
            
            // 패턴 매칭을 사용하여 JSON enum에서 데이터 추출
            if case .object(let schemaDict) = toolInfo.tool.inputSchema {
                // 속성(properties) 추출
                if case .object(let propertiesMap)? = schemaDict["properties"] {
                    for (key, value) in propertiesMap {
                        if case .object(let propDetails) = value,
                           case .string(let typeValue)? = propDetails["type"] {
                            propertiesDict[key] = ["type": typeValue]
                            logger.debug("Added property \(key) with type \(typeValue) for tool \(toolInfo.toolName)")
                        }
                    }
                }
                
                // 필수 필드(required) 추출
                if case .array(let requiredArray)? = schemaDict["required"] {
                    for item in requiredArray {
                        if case .string(let fieldName) = item {
                            required.append(fieldName)
                        }
                    }
                }
            }
            
            // 스키마 딕셔너리 생성
            let schemaDict: [String: Any] = [
                "properties": propertiesDict,
                "required": required,
                "type": "object"
            ]
            
            do {
                // Smithy Document로 변환
                let jsonDocument = try Smithy.Document.make(from: schemaDict)
                
                // 도구 사양 생성
                let toolSpec = AWSBedrockRuntime.BedrockRuntimeClientTypes.ToolSpecification(
                    description: toolInfo.tool.description,
                    inputSchema: .json(jsonDocument), // 이 부분은 API에 맞게 조정 필요
                    name: toolInfo.toolName
                )
                
                return AWSBedrockRuntime.BedrockRuntimeClientTypes.Tool.toolspec(toolSpec)
            } catch {
                logger.error("Failed to create schema document for tool \(toolInfo.toolName): \(error)")
                return nil
            }
        }
        
        return AWSBedrockRuntime.BedrockRuntimeClientTypes.ToolConfiguration(
            toolChoice: .auto(AWSBedrockRuntime.BedrockRuntimeClientTypes.AutoToolChoice()),
            tools: bedrockTools
        )
    }
    
    /**
     * Extracts tool use information from a streaming response chunk.
     * Processes different types of events in the stream to build complete tool use data.
     *
     * @param chunk A single chunk from the Bedrock Converse streaming response
     * @return Tuple with tool use ID, name and input parameters, or nil if not a complete tool use
     */
    private func extractToolUseFromChunk(_ chunk: BedrockRuntimeClientTypes.ConverseStreamOutput) -> (toolUseId: String, name: String, input: Any)? {
        let tracker = ToolUseTracker.shared
        
        // Handle contentBlockStart events
        if case .contentblockstart(let blockStartEvent) = chunk,
           let start = blockStartEvent.start,
           case .tooluse(let toolUseBlockStart) = start {
            
            // Ensure we have non-nil values for required fields
            guard let toolUseId = toolUseBlockStart.toolUseId,
                  let name = toolUseBlockStart.name else {
                logger.warning("Received incomplete tool use block start")
                return nil
            }
            
            tracker.reset()
            tracker.toolUseId = toolUseId
            tracker.name = name
            tracker.currentBlockIndex = blockStartEvent.contentBlockIndex
            
            logger.info("Tool use start detected: \(name) with ID: \(toolUseId)")
            return nil  // Return nil as we need to collect input from deltas
        }
        
        // Handle contentBlockDelta events to collect input
        if case .contentblockdelta(let deltaEvent) = chunk,
           let delta = deltaEvent.delta,
           tracker.currentBlockIndex == deltaEvent.contentBlockIndex {
            
            if case .tooluse(let toolUseDelta) = delta {
                if let inputStr = toolUseDelta.input {
                    tracker.inputString += inputStr
                    logger.info("Accumulated tool input: \(inputStr)")
                }
            }
            return nil
        }
        
        // Handle contentBlockStop events to finalize tool use
        if case .contentblockstop(let stopEvent) = chunk,
           tracker.currentBlockIndex == stopEvent.contentBlockIndex,
           let toolUseId = tracker.toolUseId,
           let name = tracker.name {
            
            logger.info("Tool use block completed for \(name). Input string: \(tracker.inputString)")
            
            // Handle empty input
            if tracker.inputString.isEmpty {
                logger.info("Tool use with empty input parameters")
                defer { tracker.reset() }
                return (toolUseId: toolUseId, name: name, input: [:])
            }
            
            // Try parsing JSON
            if let data = tracker.inputString.data(using: .utf8) {
                do {
                    let json = try JSONSerialization.jsonObject(with: data)
                    logger.info("Successfully parsed tool input JSON for \(name)")
                    defer { tracker.reset() }
                    return (toolUseId: toolUseId, name: name, input: json)
                } catch {
                    logger.warning("Failed to parse JSON, using raw string")
                    defer { tracker.reset() }
                    return (toolUseId: toolUseId, name: name, input: tracker.inputString)
                }
            }
            
            // Use original string if parsing fails
            defer { tracker.reset() }
            return (toolUseId: toolUseId, name: name, input: tracker.inputString)
        }
        
        // Handle messageStop events with tool_use reason
        if case .messagestop(let stopEvent) = chunk,
           stopEvent.stopReason == .toolUse,
           let toolUseId = tracker.toolUseId,
           let name = tracker.name {
            
            if !tracker.inputString.isEmpty {
                if let data = tracker.inputString.data(using: .utf8) {
                    do {
                        let json = try JSONSerialization.jsonObject(with: data)
                        defer { tracker.reset() }
                        logger.info("Tool use detected from messageStop: \(name)")
                        return (toolUseId: toolUseId, name: name, input: json)
                    } catch {
                        defer { tracker.reset() }
                        return (toolUseId: toolUseId, name: name, input: tracker.inputString)
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Handles all text-based LLM models using converseStream API
    private func handleTextLLMWithConverseStream(_ userMessage: MessageData) async throws {
        // Create message content from user message
        var messageContents: [MessageContent] = []
        
        // Always include a text prompt as required when sending documents
        let textToSend = userMessage.text.isEmpty &&
        (userMessage.documentBase64Strings?.isEmpty == false) ?
        "Please analyze this document." : userMessage.text
        messageContents.append(.text(textToSend))
        
        // Add images if present
        if let imageBase64Strings = userMessage.imageBase64Strings, !imageBase64Strings.isEmpty {
            for (index, base64String) in imageBase64Strings.enumerated() {
                let fileExtension = index < sharedMediaDataSource.fileExtensions.count ?
                sharedMediaDataSource.fileExtensions[index].lowercased() : "jpeg"
                
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
                
                // Create document content
                let docFormat = MessageContent.DocumentFormat.fromExtension(fileExt)
                messageContents.append(.document(MessageContent.DocumentContent(
                    format: docFormat,
                    base64Data: base64String,
                    name: fileName
                )))
            }
        }
        
        // Get conversation history
        var conversationHistory = await getConversationHistory()
        
        // Do not uncomment this - this will create duplicate user messages.
        // conversationHistory.append(userMsg)
        
        // Save updated history
        await saveConversationHistory(conversationHistory)
        
        // Get system prompt
        let systemPrompt = SettingManager.shared.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Get tool configurations if MCP is enabled - directly from MCPManager
        var toolConfig: AWSBedrockRuntime.BedrockRuntimeClientTypes.ToolConfiguration? = nil
        
        if SettingManager.shared.mcpEnabled &&
            !MCPManager.shared.toolInfos.isEmpty &&
            backendModel.backend.isStreamingToolUseSupported(chatModel.id) {
            logger.info("MCP enabled with \(MCPManager.shared.toolInfos.count) tools for supported model \(chatModel.id).")
            toolConfig = convertMCPToolsToBedrockFormat(MCPManager.shared.toolInfos)
        } else if SettingManager.shared.mcpEnabled && !MCPManager.shared.toolInfos.isEmpty {
            logger.info("MCP enabled, but model \(chatModel.id) does not support streaming tool use. Tools disabled.")
        }
        
        // Add MAX_TURNS constant at the beginning
        let MAX_TURNS = 3
        var turn_count = 0
        
        // Get Bedrock messages in AWS SDK format
        let bedrockMessages = try conversationHistory.map { try convertToBedrockMessage($0, modelId: chatModel.id) }

        // Invoke the model stream
        var streamedText = ""
        var thinking: String? = nil
        var thinkingSignature: String? = nil
        var isFirstChunk = true
        var isToolUseDetected = false
        var currentToolInfo: ToolInfo? = nil
        var toolUseId: String? = nil
        
        // Reset tool tracker to ensure clean state
        ToolUseTracker.shared.reset()
        
        // Convert to system prompt format used by AWS SDK
        let systemContentBlock: [AWSBedrockRuntime.BedrockRuntimeClientTypes.SystemContentBlock]? =
        systemPrompt.isEmpty ? nil : [.text(systemPrompt)]
        
        logger.info("Starting converseStream request with model ID: \(chatModel.id)")
        
        // Create a recursive function to handle tool use cycles
        func processToolCycles(messages: [AWSBedrockRuntime.BedrockRuntimeClientTypes.Message]) async throws {
            if turn_count >= MAX_TURNS {
                logger.info("Maximum number of tool use turns (\(MAX_TURNS)) reached")
                return
            }
            
            for try await chunk in try await backendModel.backend.converseStream(
                withId: chatModel.id,
                messages: messages,
                systemContent: systemContentBlock,
                inferenceConfig: nil,
                toolConfig: toolConfig
            ) {
                // Check for tool use
                if let toolUseInfo = extractToolUseFromChunk(chunk) {
                    // Increment turn count for each tool use
                    turn_count += 1
                    logger.info("Tool use cycle \(turn_count) of \(MAX_TURNS)")
                    
                    logger.info("Tool use detected: \(toolUseInfo.name) with ID: \(toolUseInfo.toolUseId)")
                    
                    // Create a tool info object
                    currentToolInfo = ToolInfo(
                        id: toolUseInfo.toolUseId,
                        name: toolUseInfo.name,
                        input: JSONValue.from(toolUseInfo.input)
                    )
                    
                    toolUseId = toolUseInfo.toolUseId
                    
                    // Add partial message for tool use
                    let partialMessage = MessageData(
                        id: UUID(),
                        text: "Using tool: \(toolUseInfo.name)...",
                        user: chatModel.name,
                        isError: false,
                        sentTime: Date(),
                        toolUse: currentToolInfo
                    )
                    
                    await addMessage(partialMessage)
                    
                    // Execute the tool
                    logger.info("Executing MCP tool: \(toolUseInfo.name) with input: \(toolUseInfo.input)")
                    let toolResult = await executeMCPTool(
                        id: toolUseInfo.toolUseId,
                        name: toolUseInfo.name,
                        input: toolUseInfo.input
                    )
                    
                    // Update message with tool result
                    let status = toolResult["status"] as? String ?? "error"
                    let resultText: String
                    
                    if status == "success",
                       let content = toolResult["content"] as? [[String: Any]],
                       let firstContent = content.first,
                       let jsonContent = firstContent["json"],
                       let json = jsonContent as? [String: String],
                       let text = json["text"] {
                        resultText = text
                    } else {
                        resultText = "Tool execution failed"
                    }
                    
                    logger.info("Tool execution completed with status: \(status)")
                    
                    chatManager.updateMessageWithToolInfo(
                        for: chatId,
                        messageId: partialMessage.id,
                        newText: resultText,
                        toolInfo: currentToolInfo!,
                        toolResult: resultText
                    )
                    
                    // Create tool result message for conversation history
                    let toolResultMessage = createToolResultMessage(toolUseId: toolUseInfo.toolUseId, result: resultText)
                    conversationHistory.append(toolResultMessage)
                    
                    // Create updated messages list
                    var updatedMessages = try conversationHistory.map { try convertToBedrockMessage($0, modelId: chatModel.id) }

                    // Reset streaming state for next cycle
                    isFirstChunk = true
                    streamedText = ""
                    
                    // Recursively continue conversation with tool results if under MAX_TURNS
                    if turn_count < MAX_TURNS {
                        logger.info("Continuing conversation for tool cycle \(turn_count)")
                        try await processToolCycles(messages: updatedMessages)
                        return
                    } else {
                        logger.info("Maximum tool turns reached (\(MAX_TURNS))")
                        return
                    }
                }
                
                // Process regular text chunk
                if let textChunk = extractTextFromChunk(chunk) {
                    streamedText += textChunk
                    appendTextToMessage(textChunk, shouldCreateNewMessage: isFirstChunk)
                    isFirstChunk = false
                }
                
                // Process thinking chunk
                let thinkingResult = extractThinkingFromChunk(chunk)
                if let thinkingText = thinkingResult.text {
                    thinking = (thinking ?? "") + thinkingText
                    appendTextToMessage("", thinking: thinkingText, shouldCreateNewMessage: isFirstChunk)
                    isFirstChunk = false
                }
                
                if let thinkingSignatureText = thinkingResult.signature {
                    thinkingSignature = thinkingSignatureText
                }
            }
            
            // Create assistant message when streaming is complete (if no more tool was used)
            let assistantText = streamedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let assistantMessage = MessageData(
                id: UUID(),
                text: assistantText,
                thinking: thinking,
                signature: thinkingSignature,
                user: chatModel.name,
                isError: false,
                sentTime: Date()
            )
            
            logger.info("Conversation completed after \(turn_count) tool use cycles")
            
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
                content: thinking != nil ? [
                    .text(assistantText),
                    .thinking(MessageContent.ThinkingContent(
                        text: thinking!,
                        signature: thinkingSignature ?? UUID().uuidString
                    ))
                ] : [.text(assistantText)]
            )
            
            // Add assistant response to history and save
            conversationHistory.append(assistantMsg)
            await saveConversationHistory(conversationHistory)
        }
        
        // Start the first cycle
        try await processToolCycles(messages: bedrockMessages)
    }
    
    /// Continue conversation after a tool has been used
    private func continueConversationWithToolResult(
        _ messages: [AWSBedrockRuntime.BedrockRuntimeClientTypes.Message],
        systemContentBlock: [AWSBedrockRuntime.BedrockRuntimeClientTypes.SystemContentBlock]?,
        toolConfig: AWSBedrockRuntime.BedrockRuntimeClientTypes.ToolConfiguration?
    ) async throws {
        // Create fresh variables for this conversation turn
        var streamedText = ""
        var thinking: String? = nil
        var thinkingSignature: String? = nil
        var isFirstChunk = true
        var conversationHistory = await getConversationHistory()
        
        // Reset tool tracker to ensure clean state for this continuation
        ToolUseTracker.shared.reset()
        
        logger.info("Starting new conversation stream with tool result")
        
        // Invoke the model with updated conversation including tool result
        for try await chunk in try await backendModel.backend.converseStream(
            withId: chatModel.id,
            messages: messages,
            systemContent: systemContentBlock,
            inferenceConfig: nil,
            toolConfig: toolConfig
        ) {
            // Process text chunk
            if let textChunk = extractTextFromChunk(chunk) {
                streamedText += textChunk
                appendTextToMessage(textChunk, shouldCreateNewMessage: isFirstChunk)
                isFirstChunk = false
            }
            
            // Process thinking chunk
            let thinkingResult = extractThinkingFromChunk(chunk)
            if let thinkingText = thinkingResult.text {
                thinking = (thinking ?? "") + thinkingText
                appendTextToMessage("", thinking: thinkingText, shouldCreateNewMessage: isFirstChunk)
                isFirstChunk = false
            }
            
            if let thinkingSignatureText = thinkingResult.signature {
                thinkingSignature = thinkingSignatureText
            }
            
            // We could handle nested tool calls here if needed
            // For now, we only handle one level of tool use
        }
        
        // Create assistant message
        let assistantText = streamedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistantMessage = MessageData(
            id: UUID(),
            text: assistantText,
            thinking: thinking,
            signature: thinkingSignature,
            user: chatModel.name,
            isError: false,
            sentTime: Date()
        )
        
        logger.info("Conversation with tool result completed")
        
        // Only save if we haven't already streamed it
        if isFirstChunk {
            addMessage(assistantMessage)
        } else {
            // Update the already streamed message in chat history
            chatManager.addMessage(assistantMessage, for: chatId)
        }
        
        // Add to conversation history
        let assistantMsg = BedrockMessage(
            role: .assistant,
            content: thinking != nil ? [
                .text(assistantText),
                .thinking(MessageContent.ThinkingContent(
                    text: thinking!,
                    signature: thinkingSignature ?? UUID().uuidString
                ))
            ] : [.text(assistantText)]
        )
        
        conversationHistory.append(assistantMsg)
        await saveConversationHistory(conversationHistory)
    }
    
    /// Create a tool result message for the conversation history
    private func createToolResultMessage(toolUseId: String, result: String) -> BedrockMessage {
        logger.debug("Creating tool result message for tool \(toolUseId)")
        return BedrockMessage(
            role: .user,
            content: [
                .text("Tool result for \(toolUseId): \(result)")
            ]
        )
    }
    
    /// Execute an MCP tool and return the result
    private func executeMCPTool(id: String, name: String, input: Any) async -> [String: Any] {
        logger.info("Executing MCP tool: \(name) with ID: \(id) and Input: \(input)")
        return await mcpManager.executeBedrockTool(id: id, name: name, input: input)
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
    private func extractThinkingFromChunk(_ chunk: BedrockRuntimeClientTypes.ConverseStreamOutput) -> (text: String?, signature: String?) {
        var text: String? = nil
        var signature: String? = nil
        
        if case .contentblockdelta(let deltaEvent) = chunk,
           let delta = deltaEvent.delta,
           case .reasoningcontent(let reasoningChunk) = delta {
            
            // Process different types of reasoning content
            switch reasoningChunk {
            case .text(let textContent):
                text = textContent
            case .signature(let signatureContent):
                signature = signatureContent
            case .redactedcontent, .sdkUnknown:
                break // Handle if needed
            }
        }
        
        return (text, signature)
    }
    
    // MARK: - Conversation History Management
    
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
            
            // Add thinking content if present
            if let thinking = message.thinking, !thinking.isEmpty {
                contents.append(.thinking(MessageContent.ThinkingContent(
                    text: thinking,
                    signature: UUID().uuidString // Generate a signature for the thinking content
                )))
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
            
            // Add documents if present
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
            
            let bedrockMessage = BedrockMessage(role: role, content: contents)
            bedrockMessages.append(bedrockMessage)
        }
        
        // Save newly converted history
        await saveConversationHistory(bedrockMessages)
        
        return bedrockMessages
    }
    
    /// Saves conversation history (Revised for Consistency)
    private func saveConversationHistory(_ history: [BedrockMessage]) async {
        var newConversationHistory = ConversationHistory(chatId: chatId, modelId: chatModel.id, messages: [])
        logger.debug("[SaveHistory] Processing \(history.count) Bedrock messages for saving.")
        
        var lastToolUseId: String? = nil // Track the last tool use ID from assistant
        
        for bedrockMessage in history {
            let roleString = bedrockMessage.role == .user ? "user" : "assistant"
            var text = ""
            var thinkingText: String? = nil
            var thinkingSignature: String? = nil
            var toolUsageForStorage: ConversationHistory.Message.ToolUsage? = nil // ToolUsage to store
            var extractedResultTextForUserMessage: String? = nil // Temp store result text found in a user message
            
            // Extract content from the current BedrockMessage
            for content in bedrockMessage.content {
                switch content {
                case .text(let txt): text += txt // Append text chunks
                case .thinking(let tc):
                    thinkingText = (thinkingText ?? "") + tc.text
                    if thinkingSignature == nil { thinkingSignature = tc.signature }
                case .tooluse(let tu):
                    // If this is an assistant message with toolUse, prepare ToolUsage for storage
                    if bedrockMessage.role == .assistant {
                        toolUsageForStorage = .init(toolId: tu.toolUseId, toolName: tu.name, inputs: tu.input, result: nil) // Result is initially nil
                        lastToolUseId = tu.toolUseId // Remember this ID for the next user message
                        logger.debug("[SaveHistory] Found toolUse in ASSISTANT message: ID=\(tu.toolUseId)")
                    } else {
                        logger.warning("[SaveHistory] Found toolUse in non-assistant message. Ignoring for ToolUsage struct.")
                    }
                case .toolresult(let tr):
                    // If this is a user message with toolResult, store the result text temporarily
                    if bedrockMessage.role == .user {
                        extractedResultTextForUserMessage = tr.result
                        // Verify the ID matches the last assistant tool use
                        if tr.toolUseId == lastToolUseId {
                            logger.debug("[SaveHistory] Found toolResult in USER message matching last toolUse ID (\(tr.toolUseId)): Result=\(tr.result)")
                        } else {
                            logger.warning("[SaveHistory] Found toolResult in USER message (ID: \(tr.toolUseId)) but it doesn't match last assistant toolUse ID (\(lastToolUseId ?? "nil")).")
                        }
                        // Clear lastToolUseId as the result has been found
                        lastToolUseId = nil
                    } else {
                        logger.warning("[SaveHistory] Found toolResult in non-user message. Ignoring.")
                    }
                    // Ignore image/document for simplicity in this fix
                case .image, .document: break
                }
            }
            
            // Override the main 'text' if this user message represents a tool result
            // This makes loading simpler and ensures the result text is preserved.
            if bedrockMessage.role == .user, let resultText = extractedResultTextForUserMessage {
                text = resultText // Store the result as the primary text for this user message in history
                logger.debug("[SaveHistory] Storing tool result text in main 'text' field for user message.")
            }
            
            // Create the ConversationHistory.Message
            let unifiedMessage = ConversationHistory.Message(
                id: UUID(), text: text, // Use potentially overridden text
                thinking: thinkingText, thinkingSignature: thinkingSignature,
                role: roleString, timestamp: Date(), isError: false,
                // Other fields like images/docs would be handled here too
                imageBase64Strings: nil, documentBase64Strings: nil, documentFormats: nil, documentNames: nil,
                // Attach toolUsage only if it was created (for assistant messages)
                toolUsage: toolUsageForStorage
            )
            newConversationHistory.addMessage(unifiedMessage)
            
        } // End loop through bedrockMessages
        
        logger.info("[SaveHistory] Finished processing. Saving \(newConversationHistory.messages.count) messages.")
        chatManager.saveConversationHistory(newConversationHistory, for: chatId)
    }
    
    /// Converts a ConversationHistory to Bedrock messages
    private func convertConversationHistoryToBedrockMessages(_ history: ConversationHistory) -> [BedrockMessage] {
        return history.messages.map { message in
            let role: MessageRole = message.role == "user" ? .user : .assistant
            
            var contents: [MessageContent] = []
            
            // Add thinking content if present
            if role == .assistant, let thinking = message.thinking, !thinking.isEmpty {
                let signatureToUse = message.thinkingSignature ?? UUID().uuidString // Use stored signature
                contents.append(.thinking(.init(text: thinking, signature: signatureToUse)))
                if message.thinkingSignature == nil {
                    logger.warning("[ConvertHistory] Missing thinkingSignature for assistant message ID \(message.id). Using generated UUID.")
                }
            }
            
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
            
            // Add documents if present
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
            
            // Handle Tool Result (User Only, Following Assistant Tool Use)
            if role == .user, let toolUsage = message.toolUsage {
                contents.append(.tooluse(.init(toolUseId: toolUsage.toolId, name: toolUsage.toolName, input: toolUsage.inputs)))
                logger.trace("Added .tooluse for assistant (ID: \(toolUsage.toolId))")
            }
            
            return BedrockMessage(role: role, content: contents)
        }
    }
    
    private func isDeepSeekModel(_ modelId: String) -> Bool {
        return modelId.lowercased().contains("deepseek")
    }
    
    /// Converts a BedrockMessage to AWS SDK format
    private func convertToBedrockMessage(_ message: BedrockMessage, modelId: String = "") throws -> AWSBedrockRuntime.BedrockRuntimeClientTypes.Message {
        // Separate collections for thinking and non-thinking blocks
        var thinkingBlocks: [AWSBedrockRuntime.BedrockRuntimeClientTypes.ContentBlock] = []
        var otherBlocks: [AWSBedrockRuntime.BedrockRuntimeClientTypes.ContentBlock] = []
        
        // Process all content blocks with the original switch structure
        for content in message.content {
            switch content {
            case .text(let text):
                otherBlocks.append(.text(text))
                
            case .thinking(let thinkingContent):
                // Skip reasoning content for user messages
                // Also skip for DeepSeek models due to a server-side validation error
                // that occurs when reasoning content is included in multi-turn conversations
                if message.role == .user || isDeepSeekModel(modelId) {
                    continue
                }
                
                // Add thinking content as a reasoning block
                let reasoningTextBlock = AWSBedrockRuntime.BedrockRuntimeClientTypes.ReasoningTextBlock(
                    signature: thinkingContent.signature,
                    text: thinkingContent.text
                )
                thinkingBlocks.append(.reasoningcontent(.reasoningtext(reasoningTextBlock)))
                
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
                
                otherBlocks.append(.image(AWSBedrockRuntime.BedrockRuntimeClientTypes.ImageBlock(
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
                
                otherBlocks.append(.document(AWSBedrockRuntime.BedrockRuntimeClientTypes.DocumentBlock(
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
                
                otherBlocks.append(.toolresult(toolResultBlock))
                
            case .tooluse(let toolUseContent):
                // Convert to AWS tool use format
                do {
                    // 1. Convert JSONValue input back to standard Swift [String: Any] or other Any type
                    // CORRECTED: Access asAny as a property (no parentheses)
                    let swiftInputObject = toolUseContent.input.asAny
                    
                    // 2. Create Smithy Document directly from the Swift object/array/value
                    let inputDocument = try Smithy.Document.make(from: swiftInputObject)
                    
                    // 3. Create the ToolUseBlock
                    let toolUseBlock = AWSBedrockRuntime.BedrockRuntimeClientTypes.ToolUseBlock(
                        input: inputDocument,
                        name: toolUseContent.name,
                        toolUseId: toolUseContent.toolUseId
                    )
                    
                    otherBlocks.append(.tooluse(toolUseBlock))
                    logger.debug("Successfully converted toolUse block for '\(toolUseContent.name)' with input: \(inputDocument)")
                    
                } catch {
                    // Log the specific error and the input that failed
                    logger.error("Failed to convert tool use input (\(toolUseContent.input)) to Smithy Document: \(error). Skipping this toolUse block in the request.")
                    // Handle error appropriately (e.g., skip, send empty input)
                }
            }
        }
        
        // Combine blocks - thinking blocks first, then others
        let contentBlocks = thinkingBlocks + otherBlocks
        
        // Create Message that matches SDK documentation
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
            id.contains("jamba")
        }
    }
    
    /// Handles image generation models that don't use converseStream
    private func handleImageGenerationModel(_ userMessage: MessageData) async throws {
        let modelId = chatModel.id
        
        if modelId.contains("titan-image") {
            try await invokeTitanImageModel(prompt: userMessage.text)
        } else if modelId.contains("nova-canvas") {
            try await invokeNovaCanvasModel(prompt: userMessage.text)
        } else if modelId.contains("stable") || modelId.contains("sd3") {
            try await invokeStableDiffusionModel(prompt: userMessage.text)
        } else {
            throw NSError(domain: "ChatViewModel", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported image generation model: \(modelId)"
            ])
        }
    }
    
    /// Handles embedding models by directly parsing JSON responses
    private func handleEmbeddingModel(_ userMessage: MessageData) async throws {
        // Invoke embedding model to get raw data response
        let responseData = try await backendModel.backend.invokeEmbeddingModel(
            withId: chatModel.id,
            text: userMessage.text
        )
        
        let modelId = chatModel.id.lowercased()
        var responseText = ""
        
        // Parse JSON data directly
        if let json = try? JSONSerialization.jsonObject(with: responseData, options: []) {
            if modelId.contains("titan-embed") || modelId.contains("titan-e1t") {
                // For Titan embedding models, extract the "embedding" field
                if let jsonDict = json as? [String: Any],
                   let embedding = jsonDict["embedding"] as? [Double] {
                    responseText = embedding.map { "\($0)" }.joined(separator: ",")
                } else {
                    responseText = "Failed to extract Titan embedding data"
                }
            } else if modelId.contains("cohere") {
                // For Cohere embedding models, extract the "embeddings" field
                if let jsonDict = json as? [String: Any],
                   let embeddings = jsonDict["embeddings"] as? [[Double]],
                   let firstEmbedding = embeddings.first {
                    responseText = firstEmbedding.map { "\($0)" }.joined(separator: ",")
                } else {
                    responseText = "Failed to extract Cohere embedding data"
                }
            } else {
                // For other models, convert the entire JSON to a string
                if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    responseText = jsonString
                } else {
                    responseText = "Unknown embedding format"
                }
            }
        } else {
            // If JSON parsing fails, convert the original data to string
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
        
        // Update conversation history
        var conversationHistory = await getConversationHistory()
        conversationHistory.append(BedrockMessage(
            role: .assistant,
            content: [.text(responseText)]
        ))
        await saveConversationHistory(conversationHistory)
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
            addMessage(imageMessage)
            
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
    
    // MARK: - Helper Methods
    
    @MainActor
    private func addMessage(_ message: MessageData) {
        messages.append(message)
        chatManager.addMessage(message, for: chatId)
    }
    
    private func handleModelError(_ error: Error) async {
        logger.error("Error invoking the model: \(error)")
        let errorMessage = MessageData(
            id: UUID(),
            text: "Error invoking the model: \(error)",
            user: "System",
            isError: true,
            sentTime: Date()
        )
        await addMessage(errorMessage)
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
            logger.error("Error updating chat title: \(error)")
        }
    }
}
