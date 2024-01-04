// ContentView.swift

import SwiftUI

struct ContentView: View {
    @State var selection: SidebarSelection? = .newChat
    @State var menuSelection: SidebarSelection? = .newChat
    @State var chatModels: [ChatModel] = []
    @State var showAlert: Bool = false
    @State var alertMessage: String = ""
    @State var chatMessages: [ChatModel: [MessageData]] = [:]
    @ObservedObject var backendModel: BackendModel = BackendModel()
    @State var showSettings = false
    @State private var key = UUID()  // Used to force-refresh the view
    
    @State private var isHovering = false
    
    @State private var organizedChatModels: [String: [ChatModel]] = [:]
    @State private var sectionVisibility: [String: Bool] = [:]
    @ObservedObject var messageManager: ChatManager = ChatManager.shared
    
    // Function to select the Claude model
    func selectClaudeModel() {
        // Find a Claude model in the organizedChatModels
        if let claudeModel = organizedChatModels.flatMap({ $0.value }).first(where: { $0.name.contains("Claude") }) {
            menuSelection = .chat(claudeModel)
        } else if let claudeV2Model = organizedChatModels.flatMap({ $0.value }).first(where: { $0.name.contains("Claude v2") }) {
            // If there's no Claude, select Claude v2 if available
            menuSelection = .chat(claudeV2Model)
        }
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
    
    func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
    
    // Custom hoverable dropdown button
    func customDropdownButton(_ title: String) -> some View {
        HStack {
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
            
            Text(menuSelection.flatMap { menuSelection -> String? in
                if case let .chat(chat) = menuSelection {
                    return "\(chat.id)" // Use the chat's model ID
                } else {
                    return nil
                }
            } ?? "")
            .font(.subheadline)
            .lineLimit(1)
        }
    }
    
    var body: some View {
        NavigationView {
            SidebarView(selection: $selection, menuSelection: $menuSelection)
            MainContentView(selection: $selection, menuSelection: $menuSelection, chatMessages: $chatMessages, backendModel: backendModel, organizedChatModels: organizedChatModels)
        }
        .frame(idealWidth: 1200, idealHeight: 800)
        .onReceive(SettingManager.shared.settingsChangedPublisher) {
            // Refresh the view by changing the key
            self.key = UUID()
        }.toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {}) {
                    HStack(spacing: 0) {
                        Image("bedrock") // Ensure you have this image in your assets
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                        
                        VStack(alignment: .leading) {
                            customDropdownButton("Model Not Selected") // Use this in the toolbar or other parts of your UI
                        }
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
                }
            }
        }
        .navigationTitle("")
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear(perform: fetchModels)
        .id(key)
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
}
