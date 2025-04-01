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
            HStack(spacing: 8) {
                // Model logo image (maintained from original code)
                selectedModelImage()
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                
                // Custom dropdown model selector
                ModelSelectorDropdown(
                    organizedChatModels: organizedChatModels,
                    menuSelection: $menuSelection,
                    handleSelectionChange: handleMenuSelectionChange
                )
                .frame(width: 300)
            }
        }
        
        ToolbarItem(placement: .automatic) {
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

// MARK: - ModelSelectorDropdown
/// A custom dropdown menu for model selection with search and favorites
struct ModelSelectorDropdown: View {
    let organizedChatModels: [String: [ChatModel]]
    @Binding var menuSelection: SidebarSelection?
    let handleSelectionChange: (SidebarSelection?) -> Void
    
    @State private var isShowingPopover = false
    @State private var searchText = ""
    @ObservedObject private var settingManager = SettingManager.shared
    
    var body: some View {
        Button(action: {
            isShowingPopover.toggle()
        }) {
            HStack(spacing: 8) {
                if case let .chat(model) = menuSelection {
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
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
            .frame(width: 300, height: 400)
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
    
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 검색 필드
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search models...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .focused($isSearchFocused)
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(10)
            
            Divider()
            
            // 모델 목록
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // 즐겨찾기 섹션
                    if !filteredFavorites.isEmpty {
                        SectionHeader(title: "Favorites")
                        
                        ForEach(filteredFavorites, id: \.id) { model in
                            ModelRowView(
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
                            .padding(.vertical, 5)
                    }
                    
                    // 제공자별 섹션
                    ForEach(filteredProviders, id: \.self) { provider in
                        SectionHeader(title: provider)
                        
                        ForEach(filteredModelsByProvider[provider] ?? [], id: \.id) { model in
                            ModelRowView(
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
                                .padding(.vertical, 5)
                        }
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .onAppear {
            // 팝오버가 나타날 때 검색 필드에 포커스
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
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 5)
    }
}

struct ModelRowView: View {
    let model: ChatModel
    let isSelected: Bool
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    let selectModel: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(model.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                }
                
                Text(model.id)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundColor(isFavorite ? .yellow : .gray)
                    .font(.system(size: 14))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onTapGesture(perform: selectModel)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
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
