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
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
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
        .toolbar { toolbarContent() }
        .navigationTitle("")
        .onChange(of: backendModel.backend) { _ in
            fetchModels()
        }.onChange(of: selection) { newValue in
            if case .chat(let chat) = newValue {
                if !chatManager.chats.contains(where: { $0.chatId == chat.chatId }) {
                    selection = .newChat
                }
                menuSelection = .chat(chat)
            }
        }
    }
    
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
    
    private func setup() {
        fetchModels()
        UpdateManager().checkForUpdates()
    }
    
    private func fetchModels() {
        Task {
            print("Fetching models...")
            let result = await backendModel.backend.listFoundationModels()
            switch result {
            case .success(let modelSummaries):
                let newOrganizedChatModels = Dictionary(grouping: modelSummaries.map(ChatModel.fromSummary)) { $0.provider }
                DispatchQueue.main.async {
                    self.organizedChatModels = newOrganizedChatModels
                    self.selectClaudeModel()
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.handleFetchModelsError(error)
                }
            }
        }
    }
    
    private func handleFetchModelsError(_ error: Error) {
        if let awsError = error as? AWSClientRuntime.AWSServiceError {
            let errorType = awsError.typeName ?? "Unknown AWS Error"
            var errorMessage = awsError.message ?? "No error message provided"
            
            if errorType == "ExpiredTokenException" {
                errorMessage += "\nPlease log in again."
            }
            
            self.alertInfo = AlertInfo(
                title: "\(errorType)",
                message: errorMessage
            )
        } else if let crtError = error as? AwsCommonRuntimeKit.CRTError {
            self.alertInfo = AlertInfo(
                title: "CRT Error",
                message: "Code: \(crtError.code), Message: \(crtError.message)"
            )
        } else if let commonRunTimeError = error as? AwsCommonRuntimeKit.CommonRunTimeError {
            self.alertInfo = AlertInfo(
                title: "CommonRunTime Error",
                message: "Error: \(commonRunTimeError)"
            )
        } else {
            // 알 수 없는 에러 타입에 대한 더 자세한 정보 제공
            self.alertInfo = AlertInfo(
                title: "Unknown Error",
                message: "Type: \(type(of: error)), Description: \(error.localizedDescription)"
            )
        }
        
        // 로깅 추가
        print("Error type: \(type(of: error))")
        print("Error description: \(error)")
        
        if let alertInfo = self.alertInfo {
            logger.error("Fetch Models Error - \(alertInfo.title): \(alertInfo.message)")
        } else {
            logger.error("Fetch Models Error occurred, but alertInfo is nil")
        }
        logger.error("Error details: \(String(describing: error))")
    }
    
    private func selectClaudeModel() {
        // Flatten all chat models into a single array
        let allModels = organizedChatModels.values.flatMap { $0 }
        
        // Claude model selection logic
        if let claudeModel = allModels.first(where: { $0.id.contains("claude-3-5") }) ?? // 1. Prioritize Claude-3-5 model
            allModels.first(where: { $0.id.contains("claude-3") }) ?? // 2. Select Claude-3 model
            allModels.first(where: { $0.id.contains("claude-v2") }) ?? // 3. Select Claude-v2 model
            allModels.first(where: { $0.name.contains("Claude") }) { // 4. Select any model with "Claude" in its name
            
            // Set menu selection to the chosen Claude model
            menuSelection = .chat(claudeModel)
        }
        // Note: If no suitable Claude model is found, menuSelection remains unchanged
    }
    
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: {}) {
                HStack(spacing: 0) {
                    selectedModelImage()
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                    
                    customDropdownButton(currentSelectedModelName())
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        
        ToolbarItem(placement: .primaryAction) {
            HStack {
                Button(action: toggleSidebar) {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                        .labelStyle(IconOnlyLabelStyle())
                }
                
                if case .chat(let chat) = selection, chatManager.chats.contains(where: { $0.chatId == chat.chatId }) {
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
        case let id where id.contains("stability"):
            return Image("stability ai")
        default:
            return Image("bedrock")
        }
    }
    
    func currentSelectedModelName() -> String {
        guard case let .chat(chat) = menuSelection else {
            return "Model Not Selected"
        }
        return chat.name
    }
    
    func customDropdownButton(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                ForEach(organizedChatModels.keys.sorted(), id: \.self) { provider in
                    Section(header: Text(provider)) {
                        ForEach(organizedChatModels[provider] ?? [], id: \.self) { chat in
                            Button(chat.id) {
                                menuSelection = .chat(chat)
                            }
                        }
                    }
                }
            } label: {
                menuLabel(title)
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .background(hoverBackground)
            .cornerRadius(8)
            .onHover { self.isHovering = $0 }
            .onChange(of: menuSelection, perform: handleMenuSelectionChange)
            
            if case let .chat(chat) = menuSelection {
                Text(chat.id)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 4)
            }
        }
    }
    
    private func menuLabel(_ title: String) -> some View {
        Text(menuSelection.flatMap { menuSelection -> String? in
            if case let .chat(chat) = menuSelection {
                return chat.name
            }
            return nil
        } ?? title)
        .font(.title2)
        .foregroundColor(isHovering ? .gray : .primary)
    }
    
    private var hoverBackground: some View {
        isHovering ? Color.gray.opacity(0.2) : Color.clear
    }
    
    private func handleMenuSelectionChange(_ newValue: SidebarSelection?) {
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
    
    func deleteCurrentChat() {
        guard case .chat(let chat) = selection else { return }
        selection = chatManager.deleteChat(with: chat.chatId)
    }
    
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
}

struct AlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
