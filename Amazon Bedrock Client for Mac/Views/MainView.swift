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
    @State private var isCreatingInitialChat = false // 중복 생성 방지 플래그
    @SwiftUI.Environment(\.colorScheme) private var colorScheme: ColorScheme
    private var logger = Logger(label: "MainView")
    
    @StateObject var backendModel: BackendModel = BackendModel()
    @StateObject var chatManager: ChatManager = ChatManager.shared
    @ObservedObject var settingManager: SettingManager = SettingManager.shared
    
    var body: some View {
        NavigationView {
            SidebarView(selection: $selection, menuSelection: $menuSelection)
            contentView()
        }
        .alert(item: $alertInfo) { info in
            Alert(
                title: Text(info.title),
                message: Text(info.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear(perform: setup)
        .toolbar {
            toolbarContent()
        }
        .navigationTitle("")
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
        .onChange(of: organizedChatModels) { _, _ in
            // Auto-create chat when models are loaded (only once)
            if hasInitialized && selection == nil && !isCreatingInitialChat {
                createNewChatIfNeeded()
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
        VStack(spacing: 32) {
            Spacer()
            
            // Modern service icon with subtle elevation
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.quaternary, lineWidth: 0.5)
                    )
                
                Image("bedrock")
                    .font(.system(size: 32, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
            }
            
            // Clean title section
            VStack(spacing: 12) {
                Text("Amazon Bedrock")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .tracking(-0.8)
                
                Text("Initializing generative AI models...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Modern loading indicator
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                    .scaleEffect(0.9)
                    .opacity(0.8)
                
                Text("This may take a moment")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                // Clean background
                Color(NSColor.windowBackgroundColor)
                
                // Subtle radial overlay for depth
                RadialGradient(
                    colors: [
                        Color.accentColor.opacity(0.03),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 200,
                    endRadius: 600
                )
            }
            .ignoresSafeArea()
        )
    }
    
    // MARK: - Lifecycle
    
    private func setup() {
        hasInitialized = true
        fetchModels()
    }
    
    private func fetchModels() {
        Task {
            logger.info("Fetching models...")

            async let foundationModelsResult = backendModel.backend.listFoundationModels()
            async let inferenceProfilesResult = backendModel.backend.listInferenceProfiles()
            
            do {
                let (foundationModels, inferenceProfiles) = try await (
                    foundationModelsResult,
                    inferenceProfilesResult
                )
                
                let foundationChatModels = Dictionary(
                    grouping: try foundationModels.get().map(ChatModel.fromSummary)
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
                    
                    // Auto-create first chat if none exists
                    if selection == nil {
                        createNewChatIfNeeded()
                    }
                }
            } catch {
                await MainActor.run {
                    self.handleFetchModelsError(error)
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
            if let claudeModel = allModels.first(where: { $0.id.contains("claude-3-5") })
                ?? allModels.first(where: { $0.id.contains("claude-3") })
                ?? allModels.first(where: { $0.id.contains("claude-v2") })
                ?? allModels.first(where: { $0.name.contains("Claude") }) {
                menuSelection = .chat(claudeModel)
            }
        }
    }
    
    // MARK: - Chat Creation
    
    private func createNewChatIfNeeded() {
        // 이미 채팅 생성 중이면 중단
        guard !isCreatingInitialChat else {
            logger.info("Chat creation already in progress, skipping...")
            return
        }
        
        // Only create if we have a selected model and no current chat
        guard case let .chat(selectedModel) = menuSelection,
              selection == nil || selection == .newChat else {
            return
        }
        
        // 중복 생성 방지 플래그 설정
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
                self.isCreatingInitialChat = false // 플래그 해제
                self.logger.info("Successfully created new chat: \(newChat.chatId)")
            }
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                Spacer().frame(width: 1)
                
                ModelSelectorDropdown(
                    organizedChatModels: organizedChatModels,
                    menuSelection: $menuSelection,
                    handleSelectionChange: handleMenuSelectionChange
                )
                .frame(width: 350)
            }
        }
        
        ToolbarItem(placement: .automatic) {
            HStack(spacing: 16) {
                if case .chat(let chat) = selection,
                   chatManager.chats.contains(where: { $0.chatId == chat.chatId }) {
                    Button(action: deleteCurrentChat) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(ToolbarButtonStyle())
                    .help("Delete current chat")
                }
                
                Button(action: {
                    let settingsView = SettingsView()
                    SettingsWindowManager.shared.openSettings(view: settingsView)
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(ToolbarButtonStyle())
                .help("Settings")
                
                if case .chat(let selectedModel) = menuSelection {
                    InferenceConfigDropdown(
                        currentModelId: .constant(selectedModel.id),
                        backend: backendModel.backend
                    )
                }
            }
            .padding(.trailing, 8)
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

// MARK: - ToolbarButtonStyle
struct ToolbarButtonStyle: ButtonStyle {
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(6)
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
