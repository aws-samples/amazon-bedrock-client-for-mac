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
    @State private var selection: SidebarSelection? = .newChat
    @State private var menuSelection: SidebarSelection? = nil
    @State private var organizedChatModels: [String: [ChatModel]] = [:]
    @State private var isHovering = false
    @State private var alertInfo: AlertInfo?
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
            emptyStateView
        }
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
            
            Text("Select a chat or start a new conversation")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Lifecycle
    
    private func setup() {
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
                }
            } catch {
                await MainActor.run {
                    self.handleFetchModelsError(error)
                }
            }
        }
    }
    
    private func handleFetchModelsError(_ error: Error) {
        // Create a BedrockError from the raw error
        let bedrockError = BedrockError(error: error)
        
        // Set the alert info using the BedrockError's title and message
        self.alertInfo = AlertInfo(
            title: bedrockError.title,
            message: bedrockError.message
        )
        
        // Log detailed error information
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
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                // Trick for model selector
                Spacer().frame(width: 1)
                
                // Enhanced model selector
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
            }
            .padding(.trailing, 8)
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

// MARK: - ModelSelectorDropdown
/// A custom dropdown menu for model selection with search and favorites
struct ModelSelectorDropdown: View {
    let organizedChatModels: [String: [ChatModel]]
    @Binding var menuSelection: SidebarSelection?
    let handleSelectionChange: (SidebarSelection?) -> Void
    
    @State private var isShowingPopover = false
    @State private var searchText = ""
    @State private var isHovering = false
    @ObservedObject private var settingManager = SettingManager.shared
    @SwiftUI.Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isShowingPopover.toggle()
            }
        }) {
            HStack(spacing: 10) {
                if case let .chat(model) = menuSelection {
                    // Display model image inside dropdown button
                    getModelImage(for: model.id)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.provider)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(model.name)
                            .fontWeight(.medium)
                    }
                } else {
                    Text("Select Model")
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                Image(systemName: "chevron.down")
                    .foregroundColor(.secondary)
                    .rotationEffect(isShowingPopover ? Angle(degrees: 180) : Angle(degrees: 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isShowingPopover)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ?
                          Color(NSColor.controlBackgroundColor).opacity(0.8) :
                            Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isHovering ? Color.blue.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(isHovering ? 0.1 : 0.05), radius: isHovering ? 3 : 2, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
            
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            ModelSelectorPopoverContent(
                organizedChatModels: organizedChatModels,
                searchText: $searchText,
                menuSelection: $menuSelection,
                handleSelectionChange: { selection in
                    handleSelectionChange(selection)
                    isShowingPopover = false
                },
                isShowingPopover: $isShowingPopover
            )
            .frame(width: 360, height: 400)
        }
    }
    
    // Helper function to get model image based on ID
    private func getModelImage(for modelId: String) -> Image {
        switch modelId.lowercased() {
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
}

// MARK: - ModelSelectorPopoverContent
struct ModelSelectorPopoverContent: View {
    let organizedChatModels: [String: [ChatModel]]
    @Binding var searchText: String
    @Binding var menuSelection: SidebarSelection?
    let handleSelectionChange: (SidebarSelection?) -> Void
    @Binding var isShowingPopover: Bool
    @ObservedObject private var settingManager = SettingManager.shared
    @SwiftUI.Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Enhanced search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                TextField("Search models...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 14))
                    .focused($isSearchFocused)
                
                if !searchText.isEmpty {
                    Button(action: {
                        withAnimation {
                            searchText = ""
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .transition(.opacity)
                }
            }
            .padding(12)
            .background(Color(NSColor.textBackgroundColor).opacity(0.7))
            
            Divider()
            
            // Enhanced model list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Favorites section
                    if !filteredFavorites.isEmpty {
                        SectionHeader(title: "Favorites")
                        
                        ForEach(filteredFavorites, id: \.id) { model in
                            EnhancedModelRowView(
                                model: model,
                                isSelected: isModelSelected(model),
                                isFavorite: true,
                                toggleFavorite: {
                                    settingManager.toggleFavoriteModel(model.id)
                                },
                                selectModel: {
                                    selectModel(model)
                                }
                            )
                        }
                        
                        Divider()
                            .padding(.vertical, 8)
                    }
                    
                    // Providers by section
                    ForEach(filteredProviders, id: \.self) { provider in
                        SectionHeader(title: provider)
                        
                        ForEach(filteredModelsByProvider[provider] ?? [], id: \.id) { model in
                            EnhancedModelRowView(
                                model: model,
                                isSelected: isModelSelected(model),
                                isFavorite: settingManager.isModelFavorite(model.id),
                                toggleFavorite: {
                                    settingManager.toggleFavoriteModel(model.id)
                                },
                                selectModel: {
                                    selectModel(model)
                                }
                            )
                        }
                        
                        if provider != filteredProviders.last {
                            Divider()
                                .padding(.vertical, 8)
                        }
                    }
                    
                    // No results state
                    if filteredProviders.isEmpty && filteredFavorites.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                                .padding(.top, 40)
                            
                            Text("No models found")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Try a different search term")
                                .font(.subheadline)
                                .foregroundStyle(.secondary.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .onAppear {
            // Focus search field when popover appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
    }
    
    // Helper methods
    private func isModelSelected(_ model: ChatModel) -> Bool {
        if case let .chat(selectedModel) = menuSelection {
            return selectedModel.id == model.id
        }
        return false
    }
    
    private func selectModel(_ model: ChatModel) {
        menuSelection = .chat(model)
        handleSelectionChange(menuSelection)
    }
    
    // Filtering methods
    private var filteredModelsByProvider: [String: [ChatModel]] {
        var result: [String: [ChatModel]] = [:]
        
        for (provider, models) in organizedChatModels {
            let filteredModels = models.filter { model in
                searchText.isEmpty ||
                model.name.localizedCaseInsensitiveContains(searchText) ||
                model.id.localizedCaseInsensitiveContains(searchText) ||
                provider.localizedCaseInsensitiveContains(searchText)
            }
            
            if !filteredModels.isEmpty {
                result[provider] = filteredModels
            }
        }
        
        return result
    }
    
    private var filteredProviders: [String] {
        return filteredModelsByProvider.keys.sorted()
    }
    
    private var filteredFavorites: [ChatModel] {
        var favorites: [ChatModel] = []
        
        for models in organizedChatModels.values {
            for model in models {
                if settingManager.isModelFavorite(model.id) &&
                    (searchText.isEmpty ||
                     model.name.localizedCaseInsensitiveContains(searchText) ||
                     model.id.localizedCaseInsensitiveContains(searchText)) {
                    favorites.append(model)
                }
            }
        }
        
        return favorites
    }
}

// MARK: - Helper Views

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)
    }
}

struct EnhancedModelRowView: View {
    let model: ChatModel
    let isSelected: Bool
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    let selectModel: () -> Void
    
    @State private var isHovering = false
    @SwiftUI.Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    var body: some View {
        HStack(spacing: 8) {
            getModelImage(for: model.id)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                
                Text(model.id)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundColor(isFavorite ? .yellow : .gray)
                    .font(.system(size: 12))
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(isHovering || isFavorite ? 1.0 : 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ?
                      Color.blue.opacity(colorScheme == .dark ? 0.2 : 0.1) :
                        (isHovering ? Color.gray.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .onTapGesture(perform: selectModel)
    }
    
    // Helper function to get model image based on ID
    private func getModelImage(for modelId: String) -> Image {
        switch modelId.lowercased() {
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
    
    // Provider-specific gradient colors
    private func providerGradient(for provider: String) -> [Color] {
        switch provider.lowercased() {
        case let p where p.contains("anthropic"):
            return [Color(hex: "5436DA"), Color(hex: "7B6EE6")]
        case let p where p.contains("meta"):
            return [Color(hex: "1877F2"), Color(hex: "5BB5FF")]
        case let p where p.contains("cohere"):
            return [Color(hex: "63DBD9"), Color(hex: "2F95E0")]
        case let p where p.contains("mistral"):
            return [Color(hex: "00A9A5"), Color(hex: "00C8A0")]
        case let p where p.contains("ai21"):
            return [Color(hex: "FF4571"), Color(hex: "FF7547")]
        case let p where p.contains("amazon"):
            return [Color(hex: "FF9900"), Color(hex: "FFB347")]
        case let p where p.contains("stability"):
            return [Color(hex: "7C3AED"), Color(hex: "A78BFA")]
        default:
            return [Color.blue, Color.purple.opacity(0.8)]
        }
    }
}

// MARK: - AlertInfo
struct AlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// 중복 init(hex:) 함수는 제거했습니다 - HomeView에 이미 정의되어 있음
