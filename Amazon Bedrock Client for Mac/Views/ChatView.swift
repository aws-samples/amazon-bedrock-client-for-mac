//
//  ChatView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import SwiftUI

struct Chat: View {
    @Binding var messages: [MessageData]
    @ObservedObject var chatManager: ChatManager = ChatManager.shared
    
    @State var userInput: String = ""
    @State var isMessageBarDisabled: Bool = false
    @State var isSending: Bool = false
    @State var isLoading: Bool = false
    @State var emptyText: String = ""
    
    @State private var isStreamingEnabled: Bool
    @State private var isConfigPopupPresented: Bool = false
    @State private var selectedPlaceholder: String
    
    var backend: Backend
    var modelId: String
    var modelName: String
    var chatId: String
    
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
    init(messages: Binding<[MessageData]>, backend: Backend, modelId: String, modelName: String, chatId: String) {
        self._messages = messages  // setting the Binding
        self.backend = backend
        self.modelId = modelId
        self.modelName = modelName
        self.chatId = chatId
        
        // Initialize isStreamingEnabled from UserDefaults or default to true
        let key = "isStreamingEnabled_\(chatId)"
        if let savedValue = UserDefaults.standard.value(forKey: key) as? Bool {
            _isStreamingEnabled = State(initialValue: savedValue)
        } else {
            _isStreamingEnabled = State(initialValue: modelName.contains("Claude"))
        }

        // Set the random placeholder message once during initialization
        _selectedPlaceholder = State(initialValue: placeholderMessages.randomElement() ?? "No messages")
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
                    .onChange(of: messages) { _ in
                        if let lastMessage = messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear() {
                        if let lastMessage = messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .padding()
            }
            
            MessageBarView(
                chatID: chatId,
                userInput: $userInput,
                messages: $messages,
                sendMessage: sendMessage
            )
        }.toolbar {
            ToolbarItemGroup(placement: .automatic) {
//                Spacer()
                
                HStack {
                    Text("Streaming")
                        .font(.caption)
                    Toggle("Stream", isOn: $isStreamingEnabled)
                        .toggleStyle(SwitchToggleStyle())
                        .labelsHidden()  // Optional: hides the built-in label
                }
                .onChange(of: isStreamingEnabled) { newValue in
                    // Save to UserDefaults whenever the toggle changes
                    UserDefaults.standard.set(newValue, forKey: "isStreamingEnabled_\(chatId)")
                }
            }
        }
    }
    
    func sendMessage() async {
        // 입력 확인
        guard !userInput.isEmpty else { return }
        
        // 상태 플래그 사용
        guard !isSending else { return }
        
        isSending = true
        isMessageBarDisabled = true
        
        // Add user message
        messages.append(MessageData(id: UUID(), text: userInput, user: "User", isError: false, sentTime: Date()))
        
        // Update both messages and isLoading at once
        chatManager.updateMessagesAndLoading(for: chatId, messages: messages, isLoading: true)
//        updateLastMessageDate()
        chatManager.saveChats()
        
        var history = chatManager.getHistory(for: chatId)
        
        // Check and truncate history if it exceeds 100000 characters
        if history.count > 50000 {
            let excess = history.count - 50000
            history = String(history.dropFirst(excess))
        }
        
        do {
            // Initialize emptyText to an empty string
            emptyText = ""
            
            var prompt = userInput
            if modelName.contains("Claude") {
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
            } else if modelId.contains("llama2") || modelName.contains("titan-text") {
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
            }
            
            history += "\nHuman: \(userInput)"  // Add user's message to history
            // Clear the input field
            let tempInput = userInput
            Task {
                await updateChatTitle(with: tempInput)
            }
            userInput = ""
            
            if isStreamingEnabled {
                try await invokeModelStream(prompt:prompt, history:history)
            } else {
                try await invokeModel(prompt:prompt, history:history)
            }
        } catch {
            print("Error invoking the model: \(error)")
            messages.append(MessageData(id: UUID(), text: "Error invoking the model: \(error)", user: "System", isError: true, sentTime: Date()))
        }
        
//        updateLastMessageDate()
        chatManager.saveChats()

        chatManager.setIsLoading(for: chatId, isLoading: false)  // End loading
        isMessageBarDisabled = false
        isSending = false
    }
    
    // Asynchronously update the chat title with a summary of the input
    func updateChatTitle(with input: String) async {
        let summaryPrompt = "\nHuman: Summarize user input \(input) as short as possible. Just in few words without punctuation. It should not be more than 5 words. It will be book title. Do as best as you can. If you don't know how to do summarize, please give me just 'Friendly Chat', but please do summary this without punctuation: \(input) "
        
        do {
            // Invoke the model to get a summary
            let data = try await backend.invokeModel(withId: "anthropic.claude-instant-v1", prompt: summaryPrompt)
            let response = try backend.decode(data) as InvokeClaudeResponse

            // Update the chat title with the summary
            chatManager.updateChatTitle(for: chatId, title: response.completion.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            // Handle any errors that occur during title update
            print("Error updating chat title: \(error)")
        }
    }
    
    func updateLastMessageDate() {
        if let index = chatManager.chats.firstIndex(where: { $0.chatId == self.chatId }) {
            chatManager.chats[index].lastMessageDate = Date()
        }
    }
    
    func processModelName(_ name: String) -> String {
        let parts = name.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        return parts.first.map(String.init) ?? name
    }
    
    func invokeModelStream(prompt: String, history: String) async throws {
        // History
        var currentHistory = history
        
        // Flag to indicate if it's the first chunk
        var isFirstChunk = true
        
        // Process modelName
        let modelId = processModelName(modelId)
        
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
                            messages.append(MessageData(id: UUID(), text: emptyText, user: modelName, isError: false, sentTime: Date()))
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
                            messages.append(MessageData(id: UUID(), text: emptyText, user: modelName, isError: false, sentTime: Date()))
                        } else {
                            // Append the chunk to the last message
                            emptyText.append(processedText)
                            messages[messages.count - 1].text = emptyText
                        }
                    }
                case .titan:
                    if let chunkOfText = (jsonObject as? [String: Any])?["outputText"] as? String {
                        
                        let processedText = chunkOfText
                        
                        // Trim whitespace if it's the first chunk
                        if isFirstChunk {
                            isFirstChunk = false
                            emptyText.append( chunkOfText.trimmingCharacters(in: .whitespacesAndNewlines))
                            
                            // Append a message for Bedrock's first response
                            messages.append(MessageData(id: UUID(), text: emptyText, user: modelName, isError: false, sentTime: Date()))
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
        
        chatManager.setHistory(for: chatId, history: currentHistory)
    }
    
    func invokeModel(prompt: String, history: String) async throws {
        // History
        var currentHistory = history
        
        // Process modelName
        let modelId = processModelName(modelId)
        
        // Get response from Bedrock
        let modelType = backend.getModelType(modelId)
        if modelType != .stableDiffusion {
            let data = try await backend.invokeModel(withId: modelId, prompt: prompt)
            switch modelType {
            case .claude:
                let response = try backend.decode(data) as InvokeClaudeResponse
                messages.append(MessageData(id: UUID(), text: response.completion.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), user: modelName, isError: false, sentTime: Date()))
                
            case .titan:
                let response = try backend.decode(data) as InvokeTitanResponse
                messages.append(MessageData(id: UUID(), text: response.results[0].outputText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), user: modelName, isError: false, sentTime: Date()))
                
            case .j2:
                let response = try backend.decode(data) as InvokeAI21Response
                messages.append(MessageData(id: UUID(), text: response.completions[0].data.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), user: modelName, isError: false, sentTime: Date()))

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
                        messages.append(MessageData(id: UUID(), text: markdownImage, user: modelName, isError: false, sentTime: Date()))
                    } else {
                        messages.append(MessageData(id: UUID(), text: "Invalid url path.", user: "System", isError: true, sentTime: Date()))
                    }
                    
                } catch {
                    // Handle errors, for instance by logging them
                    print("Error saving image: \(error)")
                }

            case .titanEmbed:
                let response = try backend.decode(data) as InvokeTitanEmbedResponse
                messages.append(MessageData(id: UUID(), text: response.embedding.map({"\($0)"}).joined(separator: ","), user: modelName, isError: false, sentTime: Date()))
                
            case .cohereCommand:
                let response = try backend.decode(data) as InvokeCommandResponse
                messages.append(MessageData(id: UUID(), text: response.generations[0].text, user: modelName, isError: false, sentTime: Date()))
                
            case .llama2:
                let response = try backend.decode(data) as InvokeLlama2Response
                messages.append(MessageData(id: UUID(), text: response.generation, user: modelName, isError: false, sentTime: Date()))
                
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
                    messages.append(MessageData(id: UUID(), text: markdownImage, user: modelName, isError: false, sentTime: Date()))
                } else {
                    messages.append(MessageData(id: UUID(), text: "Invalid url path.", user: "System", isError: true, sentTime: Date()))
                }
                
            } catch {
                // Handle errors, for instance by logging them
                print("Error saving image: \(error)")
            }
        }
        
        chatManager.setHistory(for: chatId, history: currentHistory)
    }
}

// MARK: - Previews
struct Chat_Previews: PreviewProvider {
    
    @State static var dummyMessages: [MessageData] = [
        MessageData(id: UUID(), text: "Hello, World!", user: "User", isError: false, sentTime: Date()),
        MessageData(id: UUID(), text: "How are you?", user: "Bedrock", isError: false, sentTime: Date())
    ]
    
    static var previews: some View {
        let backendModel: BackendModel = BackendModel()
        
        return Chat(
            messages: $dummyMessages, // Using binding
            backend: backendModel.backend,
            modelId: "ModelID",
            modelName: "ModelName",
            chatId: "ChatID"
        )
        .previewLayout(.sizeThatFits)
        .padding()
    }
}

