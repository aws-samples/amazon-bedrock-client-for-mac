//
//  MainView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 4/9/24.
//

import SwiftUI
import Combine

struct MainView: View {
    @State private var selection: SidebarSelection? = .newChat
    @State private var menuSelection: SidebarSelection? = nil
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var organizedChatModels: [String: [ChatModel]] = [:]
    @State private var isHovering = false
    
    @StateObject var backendModel: BackendModel = BackendModel()
    @StateObject var chatManager: ChatManager = ChatManager.shared
    @ObservedObject var settingManager: SettingManager = SettingManager.shared
    
    var body: some View {
        NavigationView {
            SidebarView(selection: $selection, menuSelection: $menuSelection)
            contentView()
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
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
                    self.alertMessage = error.localizedDescription
                    self.showAlert = true
                }
            }
        }
    }
    
    private func selectClaudeModel() {
        let allModels = organizedChatModels.values.flatMap { $0 }
        if let claudeModel = allModels.first(where: { $0.id.contains("claude-3") }) ??
            allModels.first(where: { $0.id.contains("claude-v2") }) ??
            allModels.first(where: { $0.name.contains("Claude") }) {
            menuSelection = .chat(claudeModel)
        }
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
        guard case let .chat(chat) = selection else {
            return "Model Not Selected"
        }
        return chat.name
    }
    
    func customDropdownButton(_ title: String) -> some View {
        VStack(alignment: .leading) {
            Menu {
                ForEach(organizedChatModels.keys.sorted(), id: \.self) { provider in
                    Section(header: Text(provider)) {
                        ForEach(organizedChatModels[provider] ?? [], id: \.self) { chat in
                            Button(action: {
                                menuSelection = .chat(chat)
                            }) {
                                Text(chat.id)
                            }
                        }
                    }
                }
            } label: {
                Text(menuSelection.flatMap { menuSelection -> String? in
                    if case let .chat(chat) = menuSelection {
                        return chat.name
                    }
                    return nil
                } ?? title)
                .font(.title2)
                .foregroundColor(isHovering ? .gray : .primary)
            }
            .background(isHovering ? Color.gray.opacity(0.2) : Color.clear)
            .cornerRadius(8)
            .onHover { hover in
                self.isHovering = hover
            }
            .buttonStyle(PlainButtonStyle())
            .onChange(of: menuSelection) { newValue in
                if case .chat(let selectedModel) = newValue,
                   case .chat(let currentChat) = selection,
                   chatManager.getMessages(for: currentChat.chatId).isEmpty {
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
    
    func deleteCurrentChat() {
        guard case .chat(let chat) = selection else { return }
        selection = chatManager.deleteChat(with: chat.chatId)
    }
    
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
}
