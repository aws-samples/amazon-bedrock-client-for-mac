//
//  MainView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 4/9/24.
//

import SwiftUI
import AppKit
import Combine
import AWSClientRuntime
import AwsCommonRuntimeKit
import Logging

struct MainView: View {
    @State private var selection: SidebarSelection? = nil
    @State private var menuSelection: SidebarSelection? = nil
    @State private var organizedChatModels: [String: [ChatModel]] = [:]
    @State private var isHovering = false
    @State private var alertInfo: AlertInfo?
    @State private var hasInitialized = false
    @State private var isCreatingInitialChat = false // Flag to prevent duplicate creation
    @SwiftUI.Environment(\.colorScheme) private var colorScheme: ColorScheme
    private var logger = Logger(label: "MainView")
    
    @StateObject var backendModel: BackendModel = BackendModel()
    @StateObject var chatManager: ChatManager = ChatManager.shared
    @ObservedObject var settingManager: SettingManager = SettingManager.shared
    
    var body: some View {
        NavigationView {
            SidebarView(selection: $selection, menuSelection: $menuSelection)
            contentView()
                .toolbar {
                    toolbarContent()
                }
                .navigationTitle("")
        }
        .alert(item: $alertInfo) { info in
            Alert(
                title: Text(info.title),
                message: Text(info.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            setupQuickAccessMessageHandler()
            setup()
        }
        .onChange(of: backendModel.backend) { _, _ in
            fetchModels()
        }
        .onChange(of: selection) { _, newValue in
            // If the selected chat doesn't exist, create a new one
            if case .chat(let chat) = newValue {
                if !chatManager.chats.contains(where: { $0.chatId == chat.chatId }) {
                    createNewChatIfNeeded()
                }
                menuSelection = .chat(chat)
            }
        }
        .onChange(of: organizedChatModels) { oldValue, newValue in
            // Only auto-create chat if:
            // 1. We just loaded models for the first time (oldValue empty, newValue not empty)
            // 2. User has NO existing chats (first time user)
            // 3. Not already creating a chat
            let isFirstLoad = oldValue.isEmpty && !newValue.isEmpty
            if selection == nil && !isCreatingInitialChat && chatManager.chats.isEmpty && isFirstLoad {
                createNewChatIfNeeded()
            }
        }
        .onAppear {
            // Mark as initialized on appear to prevent infinite loading
            if !hasInitialized {
                hasInitialized = true
            }
        }
        .onChange(of: backendModel.alertMessage) { _, newMessage in
            // Show credential/backend error alerts
            if let message = newMessage {
                alertInfo = AlertInfo(
                    title: "AWS Credential Error",
                    message: message
                )
                // Clear the alert message after showing
                backendModel.alertMessage = nil
            }
        }
    }
    
    // MARK: - Content
    @ViewBuilder
    private func contentView() -> some View {
        if let currentSelection = selection {
            switch currentSelection {
            case .newChat:
                // This case shouldn't happen anymore, but fallback to creating new chat
                Color.clear
                    .onAppear {
                        createNewChatIfNeeded()
                    }
            case .chat(let selectedChat):
                ChatView(chatId: selectedChat.chatId, backendModel: backendModel)
                    .background(Color.background)
                    .id(selectedChat.chatId)
            }
        } else {
            // Show loading or placeholder while initializing
            welcomePlaceholderView
        }
    }
    
    // MARK: - Welcome Placeholder View (shown while loading models)
    private var welcomePlaceholderView: some View {
        VStack {
            Spacer()
            
            if hasInitialized && !organizedChatModels.isEmpty {
                // Show nothing when ready - user can use sidebar to create new chat
                EmptyView()
            } else if hasInitialized && organizedChatModels.isEmpty {
                // Models loaded but no chats exist
                EmptyView()
            } else {
                // Still loading models - show progress indicator
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.5)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Lifecycle
    
    private func setup() {
        fetchModels()
    }
    
    private func fetchModels() {
        let backend = backendModel.backend
        
        Task {
            logger.info("Fetching models...")
            
            do {
                async let foundationModelsResult = backend.listFoundationModels()
                async let inferenceProfilesResult = backend.listInferenceProfiles()
                
                let (foundationModels, inferenceProfiles) = await (
                    foundationModelsResult,
                    inferenceProfilesResult
                )
                
                // Check for errors in foundation models
                let foundationModelsList = try foundationModels.get()
                
                let foundationChatModels = Dictionary(
                    grouping: foundationModelsList.map(ChatModel.fromSummary)
                ) { $0.provider }
                
                let inferenceChatModels = Dictionary(
                    grouping: inferenceProfiles.map { ChatModel.fromInferenceProfile($0) }
                ) { $0.provider }
                
                // Merge
                let mergedChatModels = foundationChatModels.merging(inferenceChatModels) { current, _ in
                    current
                }
                
                await MainActor.run {
                    self.organizedChatModels = mergedChatModels
                    self.selectDefaultModel()
                    settingManager.availableModels = mergedChatModels.values.flatMap { $0 }
                    
                    // Mark as initialized after models are loaded
                    self.hasInitialized = true
                    
                    // Only auto-create chat if we have existing chats (user has used the app before)
                    // or if user explicitly requests it
                    if selection == nil && !chatManager.chats.isEmpty {
                        createNewChatIfNeeded()
                    }
                }
            } catch {
                await MainActor.run {
                    handleFetchModelsError(error)
                }
            }
        }
    }
    
    private func handleFetchModelsError(_ error: Error) {
        let bedrockError = BedrockError(error: error)
        
        self.alertInfo = AlertInfo(
            title: bedrockError.title,
            message: bedrockError.message
        )
        
        logger.error("\(bedrockError.title): \(bedrockError.message)")
        logger.error("Original error type: \(type(of: error))")
        logger.error("Original error description: \(error)")
    }
    
    private func selectDefaultModel() {
        let defaultModelId = SettingManager.shared.defaultModelId
        let allModels = organizedChatModels.values.flatMap { $0 }
        
        if let defaultModel = allModels.first(where: { $0.id == defaultModelId }) {
            menuSelection = .chat(defaultModel)
        } else {
            // Try to pick a "Claude" model if any
            if let claudeModel = allModels.first(where: { $0.id.contains("claude-3-7") })
                ?? allModels.first(where: { $0.id.contains("claude-3") })
                ?? allModels.first(where: { $0.id.contains("claude-v2") })
                ?? allModels.first(where: { $0.name.contains("Claude") }) {
                menuSelection = .chat(claudeModel)
            }
        }
    }
    
    // MARK: - Chat Creation
    
    private func createNewChatIfNeeded() {
        // Stop if chat creation is already in progress
        guard !isCreatingInitialChat else {
            logger.info("Chat creation already in progress, skipping...")
            return
        }
        
        // Only create if we have a selected model
        guard case let .chat(selectedModel) = menuSelection else {
            logger.info("No model selected, cannot create chat")
            return
        }
        
        // Set flag to prevent duplicate creation
        isCreatingInitialChat = true
        logger.info("Creating new chat with model: \(selectedModel.name)")
        
        chatManager.createNewChat(
            modelId: selectedModel.id,
            modelName: selectedModel.name,
            modelProvider: selectedModel.provider
        ) { newChat in
            newChat.lastMessageDate = Date()
            DispatchQueue.main.async {
                self.selection = .chat(newChat)
                self.isCreatingInitialChat = false // Clear flag
                self.logger.info("Successfully created new chat: \(newChat.chatId)")
            }
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        // Left side - New Chat button
        ToolbarItem(placement: .navigation) {
            Button(action: createNewChat) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(LiquidGlassToolbarButtonStyle())
            .help("New Chat")
        }
        
        // Left side - Model selector (right after pencil button)
        ToolbarItem(placement: .principal) {
            ModelSelectorDropdown(
                organizedChatModels: organizedChatModels,
                menuSelection: $menuSelection,
                handleSelectionChange: handleMenuSelectionChange
            )
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 200, maxWidth: 420)
        }

        // Right side - Inference config dropdown
        ToolbarItem(placement: .primaryAction) {
            if case .chat(let selectedModel) = menuSelection {
                InferenceConfigDropdown(
                    currentModelId: .constant(selectedModel.id),
                    backend: backendModel.backend
                )
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
        
        // Right side - Delete button
        ToolbarItem(placement: .primaryAction) {
            if case .chat(let chat) = selection,
               chatManager.chats.contains(where: { $0.chatId == chat.chatId }) {
                Button(action: deleteCurrentChat) {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(LiquidGlassToolbarButtonStyle())
                .help("Delete current chat")
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
        
        // Right side - Settings button
        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                let settingsView = SettingsView()
                SettingsWindowManager.shared.openSettings(view: settingsView)
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(LiquidGlassToolbarButtonStyle())
            .help("Settings")
        }
    }
    
    // MARK: - Actions
    
    private func createNewChat() {
        guard case let .chat(selectedModel) = menuSelection else { return }
        
        chatManager.createNewChat(
            modelId: selectedModel.id,
            modelName: selectedModel.name,
            modelProvider: selectedModel.provider
        ) { newChat in
            newChat.lastMessageDate = Date()
            DispatchQueue.main.async {
                self.selection = .chat(newChat)
            }
        }
    }
    
    func selectedModelImage() -> Image {
        guard case let .chat(chat) = menuSelection else {
            return Image("bedrock")
        }
        
        switch chat.id {
        case let id where id.contains("anthropic"):
            return Image("anthropic")
        case let id where id.contains("meta"):
            return Image("meta")
        case let id where id.contains("cohere"):
            return Image("cohere")
        case let id where id.contains("mistral"):
            return Image("mistral")
        case let id where id.contains("ai21"):
            return Image("AI21")
        case let id where id.contains("amazon"):
            return Image("amazon")
        case let id where id.contains("deepseek"):
            return Image("deepseek")
        case let id where id.contains("stability"):
            return Image("stability ai")
        default:
            return Image("bedrock")
        }
    }
    
    func currentSelectedModelName() -> String {
        guard case let .chat(chat) = menuSelection else {
            return "Select Model"
        }
        return chat.name
    }
    
    func deleteCurrentChat() {
        guard case .chat(let chat) = selection else { return }
        let newSelection = chatManager.deleteChat(with: chat.chatId)
        
        // If we deleted the last chat, create a new one
        if newSelection == .newChat || chatManager.chats.isEmpty {
            createNewChatIfNeeded()
        } else {
            selection = newSelection
        }
    }
    
    private func setupQuickAccessMessageHandler() {
        // Quick Access processing is handled only in SidebarView, removed from MainView
        // Keep as empty function to prevent duplicate NotificationCenter registration
    }
    
    private func handleMenuSelectionChange(_ newValue: SidebarSelection?) {
        guard case let .chat(selectedModel) = newValue else { return }
        
        // If current selection is a chat
        if case let .chat(currentChat) = selection {
            // If the chat is brand-new (no messages), just update it
            if chatManager.getMessages(for: currentChat.chatId).isEmpty {
                let updatedChat = currentChat
                updatedChat.description = selectedModel.id
                updatedChat.id = selectedModel.id
                updatedChat.name = selectedModel.name
                
                selection = .chat(updatedChat)
                
                if let index = chatManager.chats.firstIndex(where: { $0.chatId == currentChat.chatId }) {
                    chatManager.chats[index] = updatedChat
                }
            }
            // If model changed and chat has messages, create new chat with the selected model
            else if currentChat.id != selectedModel.id {
                chatManager.createNewChat(
                    modelId: selectedModel.id,
                    modelName: selectedModel.name,
                    modelProvider: selectedModel.provider
                ) { newChat in
                    newChat.lastMessageDate = Date()
                    self.selection = .chat(newChat)
                }
            }
        } else {
            // If no chat is currently selected, create a new one
            chatManager.createNewChat(
                modelId: selectedModel.id,
                modelName: selectedModel.name,
                modelProvider: selectedModel.provider
            ) { newChat in
                newChat.lastMessageDate = Date()
                self.selection = .chat(newChat)
            }
        }
    }
}

// MARK: - Liquid Glass Toolbar Button Style (macOS 26+ Tahoe compatible)
struct LiquidGlassToolbarButtonStyle: ButtonStyle {
    @State private var isHovering = false
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            // macOS 26+ (Tahoe): Show background only on hover
            configuration.label
                .padding(8)
                .background(
                    Group {
                        if isHovering || configuration.isPressed {
                            Circle()
                                .fill(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.15))
                        }
                    }
                )
                .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        NSCursor.pointingHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
        } else {
            // macOS 25 and earlier: Show background only on hover
            configuration.label
                .padding(8)
                .background(
                    Circle()
                        .fill(configuration.isPressed ?
                              Color.gray.opacity(0.2) :
                                (isHovering ? Color.gray.opacity(0.1) : Color.clear))
                )
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        NSCursor.pointingHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
        }
    }
}



// MARK: - Scroll Edge Effect Modifier (Shared)
struct ScrollEdgeEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

// MARK: - AlertInfo
struct AlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
