//  ChatView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import SwiftUI
import Combine

// MARK: - ChatView
struct ChatView: View {
    // MARK: - Properties
    
    @Binding var messages: [MessageData]
    @ObservedObject var chatManager: ChatManager = ChatManager.shared
    @StateObject var sharedImageDataSource = SharedImageDataSource()
    
    @State private var userInput: String = ""
    @State private var isMessageBarDisabled: Bool = false
    @State private var isSending: Bool = false
    @State private var isLoading: Bool = false
    @State private var emptyText: String = ""
    
    @State private var isStreamingEnabled: Bool
    @State private var isConfigPopupPresented: Bool = false
    @State private var selectedPlaceholder: String
    @State private var scrollToBottomTrigger: UUID?
    @State private var chatTask: Task<Void, Never>? = nil
    
    private var backend: Backend
    @State private var chatModel: ChatModel
    
    // Placeholder messages
    private let placeholderMessages = [
        "Start a conversation!",
        "Say something to get started.",
        "Messages will appear here.",
        "Go ahead, say hi!",
        "Ready for your message!",
        "Type something to begin!"
    ]
    
    init(messages: Binding<[MessageData]>, chatModel: ChatModel, backend: Backend) {
        self._messages = messages
        self._chatModel = State(initialValue: chatModel)
        self.backend = backend
        
        let key = "isStreamingEnabled_\(chatModel.chatId)"
        if let savedValue = UserDefaults.standard.value(forKey: key) as? Bool {
            _isStreamingEnabled = State(initialValue: savedValue)
        } else {
            _isStreamingEnabled = State(initialValue: chatModel.id.contains("mistral") || chatModel.id.contains("claude") || chatModel.id.contains("llama"))
        }
        
        _selectedPlaceholder = State(initialValue: placeholderMessages.randomElement() ?? "No messages")
    }
    
    // MARK: - View
    var body: some View {
        VStack(spacing: 0) {
            placeholderView
            
            messageScrollView
            
            messageBarView
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                streamingToggle
            }
        }
        .onAppear {
            scrollToBottomTrigger = UUID()
        }
        .onChange(of: messages) { newValue in
            scrollToBottomTrigger = UUID()
        }
    }
    
    // MARK: - Subviews
    
    private var placeholderView: some View {
        VStack(alignment: .center) {
            if messages.isEmpty {
                Spacer()
                Text(selectedPlaceholder).font(.title2).foregroundColor(.text)
            }
        }
        .textSelection(.disabled)
    }
    
    private var messageScrollView: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(spacing: 16) {
                    ForEach(messages, id: \.id) { message in
                        MessageView(message: message)
                            .padding(4)
                            .id(message.id)
                    }
                }
                .onAppear {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: scrollToBottomTrigger) { _ in
                    withAnimation {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }
            .padding()
        }
    }
    
    private var messageBarView: some View {
        MessageBarView(
            chatID: chatModel.chatId,
            userInput: $userInput,
            messages: $messages,
            sharedImageDataSource: sharedImageDataSource,
            sendMessage: sendMessage,
            cancelSending: {
                chatTask?.cancel()
            },
            modelId: chatModel.id
        )
    }
    
    private var streamingToggle: some View {
        HStack {
            Text("Streaming")
                .font(.caption)
            Toggle("Stream", isOn: $isStreamingEnabled)
                .toggleStyle(SwitchToggleStyle())
                .labelsHidden()
        }
        .onChange(of: isStreamingEnabled) { newValue in
            UserDefaults.standard.set(newValue, forKey: "isStreamingEnabled_\(chatModel.chatId)")
        }
    }
    
    // MARK: - Functions
    
    /// Scrolls to the bottom of the message list.
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = messages.last {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
    
    /// Sends a message to the chat.
    func sendMessage() async {
        chatTask?.cancel()
        
        chatTask = Task {
            guard !userInput.isEmpty || !sharedImageDataSource.images.isEmpty else { return }
            guard !isSending else { return }
            
            isSending = true
            isMessageBarDisabled = true
            
            let userId = UUID()
            var imageBase64Strings: [String] = []
            
            if chatModel.id.contains("claude-3") {
                let contentBlocks = createContentBlocks()
                
                let message = ClaudeMessageRequest.Message(role: "user", content: contentBlocks)
                chatManager.addClaudeHistory(for: chatModel.chatId, message: message)
            }
            
            for (index, image) in sharedImageDataSource.images.enumerated() {
                let fileExtension = sharedImageDataSource.fileExtensions[safe: index] ?? ""
                let (base64String, mediaType) = base64EncodeImage(image, withExtension: fileExtension)
                
                if let base64String = base64String {
                    imageBase64Strings.append(base64String)
                }
            }
            
            let userMessage = MessageData(id: userId, text: userInput, user: "User", isError: false, sentTime: Date(), imageBase64Strings: imageBase64Strings)
            
            sharedImageDataSource.images.removeAll()
            sharedImageDataSource.fileExtensions.removeAll()
            
            messages.append(userMessage)
            
            if let lastMessageId = self.messages.last?.id {
                withAnimation {
                    self.scrollToBottomTrigger = userId
                }
            }
            
            chatManager.updateMessagesAndLoading(for: chatModel.chatId, messages: messages, isLoading: true)
            chatManager.saveChats()
            
            var history = chatManager.getHistory(for: chatModel.chatId)
            var claudeHistory = chatManager.getClaudeHistory(for: chatModel.chatId)
            
            if history.count > 50000 {
                let excess = history.count - 50000
                history = String(history.dropFirst(excess))
            }
            
            do {
                emptyText = ""
                var prompt = createPrompt(history: history)
                if chatModel.id.contains("llama3") {
                    history += "user\n\n\(userInput)"
                } else {
                    history += "\nHuman: \(userInput)"
                }
                
                let tempInput = userInput
                Task {
                    await updateChatTitle(with: tempInput)
                }
                userInput = ""
                
                if chatModel.id.contains("claude-3") {
                    if isStreamingEnabled {
                        try await invokeClaudeModelStream(claudeMessages: chatManager.getClaudeHistory(for: chatModel.chatId) ?? [])
                    } else {
                        try await invokeClaudeModel(claudeMessages: chatManager.getClaudeHistory(for: chatModel.chatId) ?? [])
                    }
                } else {
                    if isStreamingEnabled {
                        try await invokeModelStream(prompt: prompt, history: history)
                    } else {
                        try await invokeModel(prompt: prompt, history: history)
                    }
                }
            } catch {
                handleModelError(error)
            }
            
            chatManager.saveChats()
            chatManager.setIsLoading(for: chatModel.chatId, isLoading: false)
            isMessageBarDisabled = false
            isSending = false
            
            DispatchQueue.main.async {
                self.isSending = false
                self.isMessageBarDisabled = false
            }
        }
    }
    
    /// Creates content blocks for Claude model messages.
    private func createContentBlocks() -> [ClaudeMessageRequest.Message.Content] {
        var contentBlocks: [ClaudeMessageRequest.Message.Content] = []
        
        let textContentBlock = ClaudeMessageRequest.Message.Content(type: "text", text: userInput, source: nil)
        contentBlocks.append(textContentBlock)
        
        for (index, image) in sharedImageDataSource.images.enumerated() {
            let fileExtension = sharedImageDataSource.fileExtensions[safe: index] ?? ""
            let (base64String, mediaType) = base64EncodeImage(image, withExtension: fileExtension)
            
            if let base64String = base64String, let mediaType = mediaType {
                let imageContentBlock = ClaudeMessageRequest.Message.Content(
                    type: "image",
                    source: ClaudeMessageRequest.Message.Content.ImageSource(
                        mediaType: mediaType,
                        data: base64String
                    )
                )
                contentBlocks.append(imageContentBlock)
            }
        }
        
        return contentBlocks
    }
    
    /// Creates the prompt for the AI model based on the conversation history.
    private func createPrompt(history: String) -> String {
        var prompt = userInput
        if chatModel.name.contains("Claude") {
            prompt = """
            The following is a friendly conversation between a human and an AI.
            The AI is talkative and provides lots of specific details from its context.
            Current conversation:
            <conversation_history>
            \(history)
            </conversation_history>
            
            Here is the human's next reply:
            <human_reply>
            \(userInput)
            </human_reply>
            """
        } else if chatModel.id.contains("llama3") {
            prompt = """
            systemThe following is a friendly conversation between a human and an AI.
            The AI is talkative and provides lots of specific details from its context.
            \(history)
            user\n\n\(userInput)assistant\n\n
            """
        } else if chatModel.id.contains("llama2") || chatModel.id.contains("titan-text") {
            prompt = """
            The following is a friendly conversation between a human and an AI.
            The AI is talkative and provides lots of specific details from its context.
            Current conversation:
            <conversation_history>
            \(history)
            </conversation_history>
            
            Here is the human's next reply:
            <human_reply>
            \(userInput)
            </human_reply>
            """
        } else if chatModel.id.contains("mistral") || chatModel.id.contains("mixtral") {
            prompt = """
            The following is a friendly conversation between a human and an AI.
            The AI is talkative and provides lots of specific details from its context.
            Current conversation:
            <s>
            \(history)
            </s>
            
            Here is the human's next reply:
            [INST]
            \(userInput)
            [/INST]
            """
        }
        return prompt
    }
    
    /// Handles errors during model invocation.
    private func handleModelError(_ error: Error) {
        print("Error invoking the model: \(error)")
        messages.append(MessageData(id: UUID(), text: "Error invoking the model: \(error)", user: "System", isError: true, sentTime: Date()))
    }
    
    /// Updates the chat title with a summary of the input.
    func updateChatTitle(with input: String) async {
        let summaryPrompt = "\nHuman: Summarize user input \(input) as short as possible. Just in few words without punctuation. It should not be more than 5 words. It will be book title. Do as best as you can. If you don't know how to do summarize, please give me just 'Friendly Chat', but please do summary this without punctuation: \(input) "
        
        do {
            let data = try await backend.invokeModel(withId: "anthropic.claude-instant-v1", prompt: summaryPrompt)
            let response = try backend.decode(data) as InvokeClaudeResponse
            
            chatManager.updateChatTitle(for: chatModel.chatId, title: response.completion.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            print("Error updating chat title: \(error)")
        }
    }
    
    /// Invokes the Claude model with streaming.
    func invokeClaudeModelStream(claudeMessages: [ClaudeMessageRequest.Message]) async throws {
        var isFirstChunk = true
        let modelId = chatModel.id
        let response = try await backend.invokeClaudeModelStream(withId: modelId, messages: claudeMessages)
        
        for try await event in response {
            switch event {
            case .chunk(let part):
                guard let jsonObject = try JSONSerialization.jsonObject(with: part.bytes!, options: []) as? [String: Any] else {
                    print("Failed to decode JSON")
                    continue
                }
                
                if let type = jsonObject["type"] as? String {
                    switch type {
                    case "message_delta":
                        handleMessageDelta(jsonObject)
                    case "content_block_delta":
                        handleContentBlockDelta(jsonObject, isFirstChunk: &isFirstChunk)
                    default:
                        print("Unhandled event type: \(type)")
                    }
                }
                
            case .sdkUnknown(let unknown):
                print("Unknown SDK event: \"\(unknown)\"")
            }
        }
        
        if let lastMessage = messages.last {
            let content = ClaudeMessageRequest.Message.Content(type: "text", text: lastMessage.text, source: nil)
            chatManager.addClaudeHistory(for: chatModel.chatId, message: ClaudeMessageRequest.Message(role: "assistant", content: [content]))
        }
        
        chatManager.saveClaudeHistories()
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
    
    /// Handles content block delta events.
    private func handleContentBlockDelta(_ jsonObject: [String: Any], isFirstChunk: inout Bool) {
        if let delta = jsonObject["delta"] as? [String: Any],
           let type = delta["type"] as? String, type == "text_delta",
           let text = delta["text"] as? String {
            let processedText = text
            let firstChunk = isFirstChunk // 외부에서 복사
            
            DispatchQueue.main.async {
                if firstChunk {
                    self.emptyText += processedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.messages.append(MessageData(id: UUID(), text: self.emptyText, user: self.chatModel.name, isError: false, sentTime: Date()))
                } else {
                    if var lastMessage = self.messages.last {
                        lastMessage.text += processedText
                        self.messages[self.messages.count - 1] = lastMessage
                    }
                }
            }
            
            if firstChunk {
                isFirstChunk = false // 블록 외부에서 업데이트
            }
        }
    }
    
    /// Invokes the model with streaming.
    func invokeModelStream(prompt: String, history: String) async throws {
        var currentHistory = history
        var isFirstChunk = true
        let modelId = chatModel.id
        let response = try await backend.invokeModelStream(withId: modelId, prompt: prompt)
        let modelType = backend.getModelType(modelId)
        
        for try await event in response {
            switch event {
            case .chunk(let part):
                let jsonObject = try JSONSerialization.jsonObject(with: part.bytes!, options: [])
                handleModelChunk(jsonObject, modelType: modelType, isFirstChunk: &isFirstChunk)
            case .sdkUnknown(let unknown):
                print("Unknown: \"\(unknown)\"")
            }
        }
        
        if let lastMessage = messages.last {
            if modelType == .llama3 {
                currentHistory += "assistant\n\n\(lastMessage.text)"
            } else {
                currentHistory += "\nAssistant: \(lastMessage.text)"
            }
        }
        
        chatManager.setHistory(for: chatModel.chatId, history: currentHistory)
        chatManager.saveHistories()
    }
    
    /// Handles model chunk events.
    private func handleModelChunk(_ jsonObject: Any, modelType: ModelType, isFirstChunk: inout Bool) {
        if let chunkOfText = (jsonObject as? [String: Any])?["completion"] as? String {
            let processedText = chunkOfText
            handleProcessedText(processedText, modelType: modelType, isFirstChunk: &isFirstChunk)
        } else if let chunkOfText = (jsonObject as? [String: Any])?["generation"] as? String {
            let processedText = chunkOfText
            handleProcessedText(processedText, modelType: modelType, isFirstChunk: &isFirstChunk)
        }
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
    
    /// Invokes the Claude model.
    func invokeClaudeModel(claudeMessages: [ClaudeMessageRequest.Message]) async throws {
        let modelId = chatModel.id
        let data = try await backend.invokeClaudeModel(withId: modelId, messages: claudeMessages)
        let response = try JSONDecoder().decode(ClaudeMessageResponse.self, from: data)
        
        if let firstText = response.content.first?.text {
            messages.append(MessageData(id: UUID(), text: firstText.trimmingCharacters(in: .whitespacesAndNewlines), user: chatModel.name, isError: false, sentTime: Date()))
        }
        
        if let lastMessage = messages.last {
            let content = ClaudeMessageRequest.Message.Content(type: "text", text: lastMessage.text, source: nil)
            chatManager.addClaudeHistory(for: chatModel.chatId, message: ClaudeMessageRequest.Message(role: "assistant", content: [content]))
        }
        
        chatManager.saveClaudeHistories()
    }
    
    /// Invokes the model.
    func invokeModel(prompt: String, history: String) async throws {
        var currentHistory = history
        let modelId = chatModel.id
        let modelType = backend.getModelType(modelId)
        
        if modelType != .stableDiffusion {
            let data = try await backend.invokeModel(withId: modelId, prompt: prompt)
            try handleModelResponse(data, modelType: modelType, currentHistory: &currentHistory)
        } else {
            let data = try await backend.invokeStableDiffusionModel(withId: modelId, prompt: prompt)
            try handleStableDiffusionResponse(data)
        }
        
        chatManager.setHistory(for: chatModel.chatId, history: currentHistory)
        chatManager.saveHistories()
    }
    
    /// Handles model response.
    private func handleModelResponse(_ data: Data, modelType: ModelType, currentHistory: inout String) throws {
        switch modelType {
        case .claude:
            let response = try backend.decode(data) as InvokeClaudeResponse
            messages.append(MessageData(id: UUID(), text: response.completion.trimmingCharacters(in: .whitespacesAndNewlines), user: chatModel.name, isError: false, sentTime: Date()))
            
        case .titan:
            let response = try backend.decode(data) as InvokeTitanResponse
            messages.append(MessageData(id: UUID(), text: response.results[0].outputText.trimmingCharacters(in: .whitespacesAndNewlines), user: chatModel.name, isError: false, sentTime: Date()))
            
        case .j2:
            let response = try backend.decode(data) as InvokeAI21Response
            messages.append(MessageData(id: UUID(), text: response.completions[0].data.text.trimmingCharacters(in: .whitespacesAndNewlines), user: chatModel.name, isError: false, sentTime: Date()))
            
        case .titanImage:
            let response = try backend.decode(data) as InvokeTitanImageResponse
            try handleTitanImageResponse(response)
            
        case .titanEmbed:
            let response = try backend.decode(data) as InvokeTitanEmbedResponse
            messages.append(MessageData(id: UUID(), text: response.embedding.map({"\($0)"}).joined(separator: ","), user: chatModel.name, isError: false, sentTime: Date()))
            
        case .cohereCommand:
            let response = try backend.decode(data) as InvokeCommandResponse
            messages.append(MessageData(id: UUID(), text: response.generations[0].text, user: chatModel.name, isError: false, sentTime: Date()))
            
        case .cohereEmbed:
            let response = try backend.decode(data) as InvokeCohereEmbedResponse
            messages.append(MessageData(id: UUID(), text: response.embeddings.map({"\($0)"}).joined(separator: ","), user: chatModel.name, isError: false, sentTime: Date()))
            
        case .llama2, .llama3, .mistral:
            let response = try backend.decode(data) as InvokeLlama2Response
            messages.append(MessageData(id: UUID(), text: response.generation, user: chatModel.name, isError: false, sentTime: Date()))
            
        default:
            messages.append(MessageData(id: UUID(), text: "Error: Unable to decode response.", user: "System", isError: false, sentTime: Date()))
        }
        
        if let lastMessage = messages.last {
            if modelType == .llama3 {
                currentHistory += "assistant\n\n\(lastMessage.text)"
            } else {
                currentHistory += "\nAssistant: \(lastMessage.text)"
            }
        }
    }
    
    /// Handles Titan image response.
    private func handleTitanImageResponse(_ response: InvokeTitanImageResponse) throws {
        let image = response.images[0]
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let timestamp = formatter.string(from: now)
        let fileName = "\(timestamp).png"
        let tempDir = FileManager.default.homeDirectoryForCurrentUser
        let fileURL = tempDir.appendingPathComponent("Amazon Bedrock Client").appendingPathComponent(fileName)
        
        do {
            try image.write(to: fileURL)
            
            if let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                let markdownImage = "![](http://localhost:8080/\(encoded))"
                messages.append(MessageData(id: UUID(), text: markdownImage, user: chatModel.name, isError: false, sentTime: Date()))
            } else {
                messages.append(MessageData(id: UUID(), text: "Invalid url path.", user: "System", isError: true, sentTime: Date()))
            }
            
        } catch {
            print("Error saving image: \(error)")
        }
    }
    
    /// Handles Stable Diffusion response.
    private func handleStableDiffusionResponse(_ data: Data) throws {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let timestamp = formatter.string(from: now)
        let fileName = "\(timestamp).png"
        let tempDir = FileManager.default.homeDirectoryForCurrentUser
        let fileURL = tempDir.appendingPathComponent("Amazon Bedrock Client").appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            
            if let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                let markdownImage = "![](http://localhost:8080/\(encoded))"
                messages.append(MessageData(id: UUID(), text: markdownImage, user: chatModel.name, isError: false, sentTime: Date()))
            } else {
                messages.append(MessageData(id: UUID(), text: "Invalid url path.", user: "System", isError: true, sentTime: Date()))
            }
            
        } catch {
            print("Error saving image: \(error)")
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
}

// MARK: - Safe Array Extension
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
