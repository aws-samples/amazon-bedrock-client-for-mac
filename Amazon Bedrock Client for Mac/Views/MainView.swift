//
//  MainView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 4/9/24.
//

import SwiftUI
import Combine
import AWSClientRuntime
import AwsCommonRuntimeKit
import Logging

struct MainView: View {
    @State private var selection: SidebarSelection? = .newChat
    @State private var menuSelection: SidebarSelection? = nil
    @State private var organizedChatModels: [String: [ChatModel]] = [:]
    @State private var isHovering = false
    @State private var alertInfo: AlertInfo?
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
            ToolbarItem(placement: .cancellationAction) {
                Button(action: Amazon_Bedrock_Client_for_MacApp.toggleSidebar) {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                        .labelStyle(IconOnlyLabelStyle())
                }
            }
            
            toolbarContent()
        }
        .navigationTitle("")
        .onChange(of: backendModel.backend) { _ in
            fetchModels()
        }
        .onChange(of: selection) { newValue in
            // If the selected chat doesn't exist, revert to newChat
            if case .chat(let chat) = newValue {
                if !chatManager.chats.contains(where: { $0.chatId == chat.chatId }) {
                    selection = .newChat
                }
                menuSelection = .chat(chat)
            }
        }
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private func contentView() -> some View {
        switch selection {
        case .newChat:
            HomeView(selection: $selection, menuSelection: $menuSelection)
        case .chat(let selectedChat):
            ChatView(chatId: selectedChat.chatId, backendModel: backendModel)
                .background(Color.background)
                .id(selectedChat.chatId)
        case .none:
            Text("Select a chat or start a new conversation")
        }
    }
    
    // MARK: - Lifecycle
    
    private func setup() {
        fetchModels()
        UpdateManager().checkForUpdates()
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
                
                DispatchQueue.main.async {
                    self.organizedChatModels = mergedChatModels
                    self.selectDefaultModel()
                    settingManager.availableModels = mergedChatModels.values.flatMap { $0 }
                }
            } catch {
                DispatchQueue.main.async {
                    self.handleFetchModelsError(error)
                }
            }
        }
    }
    
    private func handleFetchModelsError(_ error: Error) {
        let bedrockError = BedrockError(error: error)
        switch bedrockError {
        case .expiredToken(let message):
            self.alertInfo = AlertInfo(
                title: "Expired Token",
                message: message ?? "Your AWS credentials have expired. Please log in again."
            )
        case .invalidResponse(let message):
            self.alertInfo = AlertInfo(
                title: "Invalid Response",
                message: message ?? "The response from Bedrock was invalid."
            )
        case .unknown(let message):
            self.alertInfo = AlertInfo(
                title: "Unknown Error",
                message: message ?? "An unknown error occurred."
            )
        }
        logger.error("Fetch Models Error - \(self.alertInfo?.title ?? "Error"): \(self.alertInfo?.message ?? "No message")")
        logger.error("Error type: \(type(of: error))")
        logger.error("Error description: \(error)")
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
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 0) {
                selectedModelImage()
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                
                // A custom hover button that opens the SwiftUI Menu
                HoveringMenuLabel(
                    title: currentSelectedModelName(),
                    organizedChatModels: organizedChatModels,
                    menuSelection: $menuSelection,
                    handleSelectionChange: handleMenuSelectionChange
                )
            }
        }
        
        ToolbarItem(placement: .primaryAction) {
            HStack {
                
                if case .chat(let chat) = selection,
                   chatManager.chats.contains(where: { $0.chatId == chat.chatId }) {
                    Button(action: deleteCurrentChat) {
                        Image(systemName: "trash")
                    }
                }
                
                Button(action: {
                    let settingsView = SettingsView()
                    SettingsWindowManager.shared.openSettings(view: settingsView)
                }) {
                    Image(systemName: "slider.horizontal.3")
                }
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
        selection = chatManager.deleteChat(with: chat.chatId)
    }
    
    private func handleMenuSelectionChange(_ newValue: SidebarSelection?) {
        // If the chat is brand-new, update it when user picks a model
        guard case let .chat(selectedModel) = newValue,
              case let .chat(currentChat) = selection,
              chatManager.getMessages(for: currentChat.chatId).isEmpty else {
            return
        }
        
        let updatedChat = currentChat
        updatedChat.description = selectedModel.id
        updatedChat.id = selectedModel.id
        updatedChat.name = selectedModel.name
        
        selection = .chat(updatedChat)
        
        if let index = chatManager.chats.firstIndex(where: { $0.chatId == currentChat.chatId }) {
            chatManager.chats[index] = updatedChat
        }
    }
}

// MARK: - HoveringMenuLabel
/// A simple label that hovers with minor animation, opening a SwiftUI Menu with provider submenus.
fileprivate struct HoveringMenuLabel: View {
    let title: String
    let organizedChatModels: [String: [ChatModel]]
    @Binding var menuSelection: SidebarSelection?
    let handleSelectionChange: (SidebarSelection?) -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Menu {
            ForEach(organizedChatModels.keys.sorted(), id: \.self) { provider in
                Menu(provider) {
                    ForEach(organizedChatModels[provider] ?? [], id: \.id) { model in
                        Button {
                            menuSelection = .chat(model)
                            handleSelectionChange(menuSelection)
                        } label: {
                            Text(model.name)
                            Text(model.id)
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
        } label: {
            modelInfoView
        }
        .menuStyle(BorderlessButtonMenuStyle())
    }
    
    private var modelInfoView: some View {
        Group {
            if case let .chat(model) = menuSelection {
                HStack(spacing: 8) {
                    Text(model.name)
                        .fontWeight(.semibold)
                    Text(model.id)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            } else {
                Text("Select Model")
                    .fontWeight(.medium)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.gray.opacity(0.2) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
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
