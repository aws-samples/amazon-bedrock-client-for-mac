//
//  MainView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 4/9/24.
//

import SwiftUI

struct MainView: View {
    @State private var selection: SidebarSelection? = .newChat
    @State private var menuSelection: SidebarSelection? = nil
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var showSettings = false
    @State private var organizedChatModels: [String: [ChatModel]] = [:]
    @State private var isHovering = false
    @State private var key = UUID()  // Used to force-refresh the view
    
    @ObservedObject var backendModel: BackendModel = BackendModel()
    @ObservedObject var chatManager: ChatManager = ChatManager.shared
    
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
        .onReceive(SettingManager.shared.settingsChangedPublisher) { self.key = UUID()}
        .id(key)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
    
    @ViewBuilder
    private func contentView() -> some View {
        switch selection {
        case .newChat:
            HomeView(selection: $selection, menuSelection: $menuSelection)
        case .chat(let selectedChat):
            ChatView(messages: messagesBinding(for: selectedChat.chatId),
                     chatModel: selectedChat,
                     backend: backendModel.backend)
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
    
    func fetchModels() {
        Task {
            let result = await backendModel.backend.listFoundationModels()
            switch result {
            case .success(let modelSummaries):
                var newOrganizedChatModels: [String: [ChatModel]] = [:]
                for modelSummary in modelSummaries {
                    let chat = ChatModel.fromSummary(modelSummary)
                    newOrganizedChatModels[chat.provider, default: []].append(chat)
                }
                DispatchQueue.main.async {
                    self.organizedChatModels = newOrganizedChatModels
                    selectClaudeModel()
                }
            case .failure(let error):
                print("fail")
                DispatchQueue.main.async {
                    switch error {
                    case .genericError(let message):
                        self.alertMessage = message
                    case .tokenExpired:
                        self.alertMessage = "The token has expired."
                    default:
                        self.alertMessage = "An unknown error occurred."
                    }
                    self.showAlert = true
                }
            }
        }
    }
    
    // Function to select the Claude model
    func selectClaudeModel() {
        // Find a Claude v3 model in the organizedChatModels
        if let claudeV3Model = organizedChatModels.flatMap({ $0.value }).first(where: { $0.id.contains("claude-3") }) {
            menuSelection = .chat(claudeV3Model)
        } else if let claudeV2Model = organizedChatModels.flatMap({ $0.value }).first(where: { $0.id.contains("claude-v2") }) {
            menuSelection = .chat(claudeV2Model)
        } else if let claudeModel = organizedChatModels.flatMap({ $0.value }).first(where: { $0.name.contains("Claude") }) {
            // If there's no Claude v2, select Claude if available
            menuSelection = .chat(claudeModel)
        }
    }
    
    private func messagesBinding(for chatId: String) -> Binding<[MessageData]> {
        .init(get: { self.chatManager.chatMessages[chatId] ?? [] },
              set: { self.chatManager.chatMessages[chatId] = $0 })
    }
    
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: {}) {
                HStack(spacing: 0) {
                    selectedModelImage() // Ensure you have this image in your assets
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                    
                    customDropdownButton(currentSelectedModelName()) // Use this in the toolbar or other parts of your UI
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        
        ToolbarItem(placement: .primaryAction) {
            HStack {
                Button(action: toggleSidebar) {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                        .labelStyle(IconOnlyLabelStyle()) // Only show the icon
                }
                
                Button(action: {
                    showSettings.toggle()
                }) {
                    Image(systemName: "gearshape")
                }
                
                if case .chat(let chat) = selection, chatManager.chats.contains(where: { $0.chatId == chat.chatId }) {
                    Button(action: deleteCurrentChat) {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }
    
    func selectedModelImage() -> Image {
        guard case let .chat(chat) = menuSelection else {
            return Image("bedrock")
        }
        
        if chat.id.contains("anthropic") {
            return Image("anthropic")
        } else if chat.id.contains("meta") {
            return Image("meta")
        } else if chat.id.contains("cohere") {
            return Image("cohere")
        } else if chat.id.contains("mistral") {
            return Image("mistral")
        } else {
            
            return Image("bedrock")
        }
    }
    
    func currentSelectedModelName() -> String {
        guard case let .chat(chat) = selection else {
            return "Model Not Selected"
        }
        return chat.name
    }
    
    // Custom hoverable dropdown button
    func customDropdownButton(_ title: String) -> some View {
        VStack(alignment: .leading) {
            Menu {
                // Menu content with ForEach loop
                ForEach(organizedChatModels.keys.sorted(), id: \.self) { provider in
                    Section {
                        ForEach(organizedChatModels[provider] ?? [], id: \.self) { chat in
                            Button(action: {
                                menuSelection = .chat(chat)
                            }) {
                                Text(chat.id) // Display chat name
                                // Add an icon next to each chat if desired
                            }
                        }
                    } header: {
                        Text(provider)
                    }
                }
            } label: {
                // Entire clickable label with hover effect
                Text(menuSelection.flatMap { menuSelection -> String? in
                    if case let .chat(chat) = menuSelection {
                        return chat.name // Use the chat's name
                    } else {
                        return nil
                    }
                } ?? title)
                .font(.title2)
                .foregroundColor(isHovering ? .gray : .primary) // Change text color on hover
            }
            .background(isHovering ? Color.gray.opacity(0.2) : Color.clear)
            .cornerRadius(8)
            .onHover { hover in
                self.isHovering = hover
            }
            .buttonStyle(PlainButtonStyle())
            .onChange(of: menuSelection) { newValue in
                if case .chat(let selectedModel) = newValue {
                    if case .chat(let currentChat) = selection, chatManager.chatMessages[currentChat.chatId]?.isEmpty == true {
                        // Update the current chat with the selected model details
                        let updatedChat = currentChat
                        updatedChat.description = selectedModel.id
                        updatedChat.id = selectedModel.id
                        updatedChat.name = selectedModel.name
                        
                        selection = .chat(updatedChat)
                        
                        // Update the chat in the chat manager
                        if let index = chatManager.chats.firstIndex(where: { $0.chatId == currentChat.chatId }) {
                            chatManager.chats[index] = updatedChat
                        }
                    }
                }
            }
            
            if case let .chat(chat) = menuSelection {
                Text("\(chat.id)") // Display the selected chat's model ID
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading) // Align text to the left
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 4)
            }
            
        }
    }
    
    // Function to delete the currently selected chat and switch to the most recent one
    func deleteCurrentChat() {
        guard case .chat(let chat) = selection, chatManager.chats.contains(where: { $0.chatId == chat.chatId }) else {
            return
        }
        chatManager.chats.removeAll { $0.chatId == chat.chatId }
        chatManager.chatMessages.removeValue(forKey: chat.chatId)
        
        // Find the most recent chat, if available
        if let mostRecentChat = chatManager.chats.sorted(by: { $0.lastMessageDate > $1.lastMessageDate }).first {
            selection = .chat(mostRecentChat)  // Navigate to the most recent chat
        } else {
            selection = .newChat  // Switch to a default view if no chats are available
        }
    }
    
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
}
