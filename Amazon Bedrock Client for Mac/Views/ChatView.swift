//
//  ChatView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import SwiftUI

struct ChatView: View {
    @Binding var messages: [MessageData]
    @ObservedObject var chatManager: ChatManager = ChatManager.shared
    @StateObject var sharedImageDataSource = SharedImageDataSource()
    
    @State var userInput: String = ""
    @State var isMessageBarDisabled: Bool = false
    @State var isSending: Bool = false
    @State var isLoading: Bool = false
    @State var emptyText: String = ""
    
    @State private var isStreamingEnabled: Bool
    @State private var isConfigPopupPresented: Bool = false
    @State private var selectedPlaceholder: String
    @State private var scrollToBottomTrigger: UUID?
    @State private var chatTask: Task<Void, Never>? = nil

    
    var backend: Backend
    // Local copy of ChatModel
    @State var chatModel: ChatModel
    
    // Placeholder messages
    private let placeholderMessages = [
        "Start a new conversation.",
        "It's quiet... too quiet.",
        "Your messages will appear here.",
        "Reach out and say hello!",
        "Nothing here yet. Break the ice!",
        "Awaiting your words..."
    ]
    
    // Move the UserDefaults logic to the init method
    init(messages: Binding<[MessageData]>, chatModel: ChatModel, backend: Backend) {
        self._messages = messages  // setting the Binding
        self._chatModel = State(initialValue: chatModel) // Use State to hold the local copy
        self.backend = backend
        
        // Initialize isStreamingEnabled from UserDefaults or default to true
        let key = "isStreamingEnabled_\(chatModel.chatId)"
        if let savedValue = UserDefaults.standard.value(forKey: key) as? Bool {
            _isStreamingEnabled = State(initialValue: savedValue)
        } else {
            _isStreamingEnabled = State(initialValue: chatModel.id.contains("mistral") || chatModel.id.contains("claude") || chatModel.id.contains("llama"))
        }
        
        // Set the random placeholder message once during initialization
        _selectedPlaceholder = State(initialValue: placeholderMessages.randomElement() ?? "No messages")
    }
    
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
            // Encoding to WEBP is not natively supported; would require additional implementation
            imageData = nil
            mediaType = "image/webp"
        case "gif":
            // Encoding to GIF is not natively supported; would require additional implementation
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
    
    
    // Function to get a random placeholder message
    private func getRandomPlaceholder() -> String {
        placeholderMessages.randomElement() ?? "No messages"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .center) {
                if messages.isEmpty {
                    Spacer()
                    Text(selectedPlaceholder).font(.title2).foregroundColor(.text)
                }
            }.textSelection(.disabled)
            
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
                        if let lastMessage = messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: messages) { _ in
                        if let lastMessageId = messages.last?.id {
                            proxy.scrollTo(lastMessageId, anchor: .bottom)
                        }
                    }
                    .onChange(of: scrollToBottomTrigger) { _ in
                        withAnimation {
                            proxy.scrollTo(scrollToBottomTrigger, anchor: .bottom)
                        }
                    }
                }
                .padding()
            }
            
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
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
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
        }
        
    }
    
    func sendMessage() async {
        chatTask?.cancel()
        
        chatTask = Task {
            // 입력 확인
            guard !userInput.isEmpty else { return }
            
            // 상태 플래그 사용
            guard !isSending else { return }
            
            isSending = true
            isMessageBarDisabled = true
            
            let userid = UUID()
            
            var imageBase64Strings: [String] = []
            
            if chatModel.id.contains("claude-3") {
                var contentBlocks: [ClaudeMessageRequest.Message.Content] = []
                
                // Add text content block
                let textContentBlock = ClaudeMessageRequest.Message.Content(type: "text", text: userInput, source: nil)
                contentBlocks.append(textContentBlock)
                
                // Iterate over images and add each as a content block
                for (index, image) in sharedImageDataSource.images.enumerated() {
                    // Assume you also have access to the image's file extension
                    let fileExtension = sharedImageDataSource.fileExtensions[index]
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
                        imageBase64Strings.append(base64String)
                    }
                }
                
                // Construct the message with all content blocks (text and images)
                let message = ClaudeMessageRequest.Message(role: "user", content: contentBlocks)
                chatManager.addClaudeHistory(for: chatModel.chatId, message: message)
            }
            
            var userMessage = MessageData(id: userid, text: userInput, user: "User", isError: false, sentTime: Date(), imageBase64Strings: imageBase64Strings)
            
            sharedImageDataSource.images.removeAll()
            sharedImageDataSource.fileExtensions.removeAll()
            
            // Add user message
            messages.append(userMessage)
            
            // 메시지 배열 업데이트 후 스크롤 위치 조정
            if let lastMessageId = self.messages.last?.id {
                withAnimation {
                    self.scrollToBottomTrigger = userid
                }
            }
            
            // Update both messages and isLoading at once
            chatManager.updateMessagesAndLoading(for: chatModel.chatId, messages: messages, isLoading: true)
            //        updateLastMessageDate()
            chatManager.saveChats()
            
            var history = chatManager.getHistory(for: chatModel.chatId)
            var claudeHistory = chatManager.getClaudeHistory(for: chatModel.chatId)
            
            // Check and truncate history if it exceeds 100000 characters
            if history.count > 50000 {
                let excess = history.count - 50000
                history = String(history.dropFirst(excess))
            }
            
            do {
                // Initialize emptyText to an empty string
                emptyText = ""
                
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
                } else if chatModel.id.contains("mistral") || chatModel.id.contains("mixtral"){
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
                
                history += "\nHuman: \(userInput)"  // Add user's message to history
                
                // Clear the input field
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
                        try await invokeModelStream(prompt:prompt, history:history)
                    } else {
                        try await invokeModel(prompt:prompt, history:history)
                    }
                }
            } catch {
                print("Error invoking the model: \(error)")
                messages.append(MessageData(id: UUID(), text: "Error invoking the model: \(error)", user: "System", isError: true, sentTime: Date()))
                //            scrollToBottomTrigger.toggle()
            }
            
            //        updateLastMessageDate()
            chatManager.saveChats()
            
            chatManager.setIsLoading(for: chatModel.chatId, isLoading: false)  // End loading
            isMessageBarDisabled = false
            
            isSending = false
            
            DispatchQueue.main.async {
                self.isSending = false
                self.isMessageBarDisabled = false
            }
        }
    }
    
    // Asynchronously update the chat title with a summary of the input
    func updateChatTitle(with input: String) async {
        let summaryPrompt = "\nHuman: Summarize user input \(input) as short as possible. Just in few words without punctuation. It should not be more than 5 words. It will be book title. Do as best as you can. If you don't know how to do summarize, please give me just 'Friendly Chat', but please do summary this without punctuation: \(input) "
        
        do {
            // Invoke the model to get a summary
            let data = try await backend.invokeModel(withId: "anthropic.claude-instant-v1", prompt: summaryPrompt)
            let response = try backend.decode(data) as InvokeClaudeResponse
            
            // Update the chat title with the summary
            chatManager.updateChatTitle(for: chatModel.chatId, title: response.completion.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            // Handle any errors that occur during title update
            print("Error updating chat title: \(error)")
        }
    }
    
    func updateLastMessageDate() {
        if let index = chatManager.chats.firstIndex(where: { $0.chatId == self.chatModel.chatId }) {
            chatManager.chats[index].lastMessageDate = Date()
        }
    }
    
    func invokeClaudeModelStream(claudeMessages: [ClaudeMessageRequest.Message]) async throws {
        // Flag to indicate if it's the first chunk
        var isFirstChunk = true
        
        // Process chatModel.name
        let modelId = chatModel.id
        
        // Get response from Bedrock specifically for Claude model
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
                        
                    case "content_block_delta":
                        if let delta = jsonObject["delta"] as? [String: Any],
                           let type = delta["type"] as? String, type == "text_delta",
                           let text = delta["text"] as? String {
                            let processedText = text
                            
                            DispatchQueue.main.async {
                                if isFirstChunk {
                                    isFirstChunk = false
                                    self.emptyText += processedText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    self.messages.append(MessageData(id: UUID(), text: self.emptyText, user: self.chatModel.name, isError: false, sentTime: Date()))
                                } else {
                                    if var lastMessage = self.messages.last {
                                        lastMessage.text += processedText
                                        self.messages[self.messages.count - 1] = lastMessage
                                    }
                                }
                            }
                        }
                        
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
            // The role is assumed to be "user"; adjust as necessary.
            chatManager.addClaudeHistory(for: chatModel.chatId, message: ClaudeMessageRequest.Message(role: "assistant", content: [content]))
        }
        
        chatManager.saveClaudeHistories()
    }
    
    func invokeModelStream(prompt: String, history: String) async throws {
        // History
        var currentHistory = history
        
        // Flag to indicate if it's the first chunk
        var isFirstChunk = true
        
        // Process chatModel.name
        let modelId = chatModel.id
        
        // Get response from Bedrock
        let response = try await backend.invokeModelStream(withId: modelId, prompt: prompt)
        let modelType = backend.getModelType(modelId)
        
        for try await event in response {
            switch event {
            case .chunk(let part):
                let jsonObject = try JSONSerialization.jsonObject(with: part.bytes!, options: [])
                switch modelType {
                case .claude:
                    if let chunkOfText = (jsonObject as? [String: Any])?["completion"] as? String {
                        
                        let processedText = chunkOfText
                        
                        // Trim whitespace if it's the first chunk
                        if isFirstChunk {
                            isFirstChunk = false
                            emptyText.append(chunkOfText.trimmingCharacters(in: .whitespacesAndNewlines))
                            
                            // Append a message for Bedrock's first response
                            messages.append(MessageData(id: UUID(), text: emptyText, user: chatModel.name, isError: false, sentTime: Date()))
                        } else {
                            // Append the chunk to the last message
                            emptyText.append(processedText)
                            messages[messages.count - 1].text = emptyText
                        }
                    }
                case .llama2:
                    if let chunkOfText = (jsonObject as? [String: Any])?["generation"] as? String {
                        
                        let processedText = chunkOfText
                        
                        // Trim whitespace if it's the first chunk
                        if isFirstChunk {
                            isFirstChunk = false
                            emptyText.append(chunkOfText.trimmingCharacters(in: .whitespacesAndNewlines))
                            
                            // Append a message for Bedrock's first response
                            messages.append(MessageData(id: UUID(), text: emptyText, user: chatModel.name, isError: false, sentTime: Date()))
                        } else {
                            // Append the chunk to the last message
                            emptyText.append(processedText)
                            messages[messages.count - 1].text = emptyText
                        }
                    }
                case .mistral:
                    do {
                        let decoder = JSONDecoder()
                        let response = try decoder.decode(InvokeMistralResponse.self, from: part.bytes!)
                        if let chunkOfText = response.outputs.first?.text {
                            let processedText = chunkOfText
                            
                            if isFirstChunk {
                                isFirstChunk = false
                                emptyText.append(chunkOfText.trimmingCharacters(in: .whitespacesAndNewlines))
                                
                                // Append a message for Bedrock's first response
                                messages.append(MessageData(id: UUID(), text: emptyText, user: chatModel.name, isError: false, sentTime: Date()))
                            } else {
                                // Append the chunk to the last message
                                emptyText.append(processedText)
                                messages[messages.count - 1].text = emptyText
                            }
                        }
                    } catch {
                        print("Error decoding JSON: \(error)")
                    }
                case .titan:
                    if let chunkOfText = (jsonObject as? [String: Any])?["outputText"] as? String {
                        
                        let processedText = chunkOfText
                        
                        // Trim whitespace if it's the first chunk
                        if isFirstChunk {
                            isFirstChunk = false
                            emptyText.append( chunkOfText.trimmingCharacters(in: .whitespacesAndNewlines))
                            
                            // Append a message for Bedrock's first response
                            messages.append(MessageData(id: UUID(), text: emptyText, user: chatModel.name, isError: false, sentTime: Date()))
                        } else {
                            // Append the chunk to the last message
                            emptyText.append(processedText)
                            messages[messages.count - 1].text = emptyText
                        }
                    }
                default:
                    break;
                }
            case .sdkUnknown(let unknown):
                print("Unknown: \"\(unknown)\"")
            }
        }
        
        if let lastMessage = messages.last {
            currentHistory += "\nAssistant: \(lastMessage.text)"
        }
        
        chatManager.setHistory(for: chatModel.chatId, history: currentHistory)
        chatManager.saveHistories()
    }
    
    func invokeClaudeModel(claudeMessages: [ClaudeMessageRequest.Message]) async throws {
        // Process chatModel.name
        let modelId = chatModel.id
        
        // Get response from Bedrock specifically for Claude model
        let data = try await backend.invokeClaudeModel(withId: modelId, messages: claudeMessages)
        
        let response = try JSONDecoder().decode(ClaudeMessageResponse.self, from: data)
        if let firstText = response.content.first?.text {
            messages.append(MessageData(id: UUID(), text: firstText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), user: chatModel.name, isError: false, sentTime: Date()))
        }
        
        if let lastMessage = messages.last {
            let content = ClaudeMessageRequest.Message.Content(type: "text", text: lastMessage.text, source: nil)
            // The role is assumed to be "user"; adjust as necessary.
            chatManager.addClaudeHistory(for: chatModel.chatId, message: ClaudeMessageRequest.Message(role: "assistant", content: [content]))
        }
        
        chatManager.saveClaudeHistories()
    }
    
    func invokeModel(prompt: String, history: String) async throws {
        // History
        var currentHistory = history
        
        // Process modelName
        let modelId = chatModel.id
        
        // Get response from Bedrock
        let modelType = backend.getModelType(modelId)
        if modelType != .stableDiffusion {
            let data = try await backend.invokeModel(withId: modelId, prompt: prompt)
            switch modelType {
            case .claude:
                let response = try backend.decode(data) as InvokeClaudeResponse
                messages.append(MessageData(id: UUID(), text: response.completion.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), user: chatModel.name, isError: false, sentTime: Date()))
                
            case .titan:
                let response = try backend.decode(data) as InvokeTitanResponse
                messages.append(MessageData(id: UUID(), text: response.results[0].outputText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), user: chatModel.name, isError: false, sentTime: Date()))
                
            case .j2:
                let response = try backend.decode(data) as InvokeAI21Response
                messages.append(MessageData(id: UUID(), text: response.completions[0].data.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), user: chatModel.name, isError: false, sentTime: Date()))
                
            case .titanImage:
                let response = try backend.decode(data) as InvokeTitanImageResponse
                let image = response.images[0]
                
                // Generate a unique file name
                let now = Date()
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
                let timestamp = formatter.string(from: now)
                
                let fileName = "\(timestamp).png"
                
                // Get the temporary directory
                let tempDir = FileManager.default.homeDirectoryForCurrentUser
                
                // Create the full file path
                let fileURL = tempDir.appendingPathComponent("Amazon Bedrock Client").appendingPathComponent(fileName)
                
                do {
                    // Write the data to the temporary file
                    try image.write(to: fileURL)
                    
                    // Create the Markdown string referencing the image
                    // Assuming your Vapor server is running on localhost:8080
                    if let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                        let markdownImage = "![](http://localhost:8080/\(encoded))"
                        messages.append(MessageData(id: UUID(), text: markdownImage, user: chatModel.name, isError: false, sentTime: Date()))
                    } else {
                        messages.append(MessageData(id: UUID(), text: "Invalid url path.", user: "System", isError: true, sentTime: Date()))
                    }
                    
                } catch {
                    // Handle errors, for instance by logging them
                    print("Error saving image: \(error)")
                }
                
            case .titanEmbed:
                let response = try backend.decode(data) as InvokeTitanEmbedResponse
                messages.append(MessageData(id: UUID(), text: response.embedding.map({"\($0)"}).joined(separator: ","), user: chatModel.name, isError: false, sentTime: Date()))
                
            case .cohereCommand:
                let response = try backend.decode(data) as InvokeCommandResponse
                messages.append(MessageData(id: UUID(), text: response.generations[0].text, user: chatModel.name, isError: false, sentTime: Date()))
                
            case .cohereEmbed:
                let response = try backend.decode(data) as InvokeCohereEmbedResponse
                messages.append(MessageData(id: UUID(), text: response.embeddings.map({"\($0)"}).joined(separator: ","), user: chatModel.name, isError: false, sentTime: Date()))
                
            case .llama2:
                let response = try backend.decode(data) as InvokeLlama2Response
                messages.append(MessageData(id: UUID(), text: response.generation, user: chatModel.name, isError: false, sentTime: Date()))
                
            case .mistral:
                let response = try backend.decode(data) as InvokeMistralResponse
                messages.append(MessageData(id: UUID(), text: response.outputs[0].text, user: chatModel.name, isError: false, sentTime: Date()))
                
            default:
                messages.append(MessageData(id: UUID(), text: "Error: Unable to decode response.", user: "System", isError: false, sentTime: Date()))
            }
            
            // Update history
            if let lastMessage = messages.last {
                currentHistory += "\nAssistant: \(lastMessage.text)"
            }
        } else {
            let data = try await backend.invokeStableDiffusionModel(withId: modelId, prompt: prompt)
            
            // Generate a unique file name
            let now = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
            let timestamp = formatter.string(from: now)
            
            let fileName = "\(timestamp).png"
            
            // Get the temporary directory
            let tempDir = FileManager.default.homeDirectoryForCurrentUser
            
            // Create the full file path
            let fileURL = tempDir.appendingPathComponent("Amazon Bedrock Client").appendingPathComponent(fileName)
            
            do {
                // Write the data to the temporary file
                try data.write(to: fileURL)
                
                // Create the Markdown string referencing the image
                // Assuming your Vapor server is running on localhost:8080
                if let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                    let markdownImage = "![](http://localhost:8080/\(encoded))"
                    messages.append(MessageData(id: UUID(), text: markdownImage, user: chatModel.name, isError: false, sentTime: Date()))
                } else {
                    messages.append(MessageData(id: UUID(), text: "Invalid url path.", user: "System", isError: true, sentTime: Date()))
                }
                
            } catch {
                // Handle errors, for instance by logging them
                print("Error saving image: \(error)")
            }
        }
        
        chatManager.setHistory(for: chatModel.chatId, history: currentHistory)
        chatManager.saveHistories()
    }
}
