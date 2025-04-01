import SwiftUI

struct HomeView: View {
    // MARK: - Properties
    @Binding var selection: SidebarSelection?
    @Binding var menuSelection: SidebarSelection?
    @ObservedObject private var mcpManager = MCPManager.shared
    @ObservedObject private var chatManager = ChatManager.shared
    
    @State private var hasLoadedModels = false
    @State private var isHoveringNewChat = false
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Background color (dark mode aware)
            backgroundColor.ignoresSafeArea()
            
            // Main content - centered both horizontally and vertically
            VStack {
                Spacer()
                
                // Title section
                titleSection
                
                // Tagline - simplified
                Text("Build and scale generative AI applications")
                    .font(.system(size: 16))
                    .foregroundColor(secondaryTextColor)
                    .padding(.top, 12)
                
                // Simple New Chat button
                newChatButton
                    .padding(.top, 32)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
        }
        .onAppear {
            if menuSelection != .newChat && !hasLoadedModels {
                self.hasLoadedModels = true
            }
        }
        .onChange(of: menuSelection) { newSelection in
            onModelsLoaded()
        }
    }
    
    // MARK: - Colors (Dark Mode support)
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(hex: "121212") : Color.white
    }
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color(hex: "AAAAAA") : Color(hex: "6E6E80")
    }
    
    // MARK: - Title Section (Simplified)
    private var titleSection: some View {
        VStack(spacing: 16) {
            Text("Amazon Bedrock")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(primaryTextColor)
        }
    }
    
    // MARK: - New Chat Button (Simplified)
    private var newChatButton: some View {
        Button(action: {
            createNewChat()
        }) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 16))
                
                Text("New chat")
                    .font(.system(size: 16))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .frame(width: 200)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(colorScheme == .dark ? Color(hex: "3E3E41") : Color(hex: "DEDEDE"), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colorScheme == .dark ? Color(hex: "202123") : Color(hex: "F7F7F8"))
                    )
            )
            .foregroundColor(primaryTextColor)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHoveringNewChat = hovering
        }
        .keyboardShortcut("n", modifiers: [.command])
    }
    
    // MARK: - Methods
    func onModelsLoaded() {
        hasLoadedModels = true
    }
    
    func createNewChat() {
        if let modelSelection = menuSelection, case .chat(let model) = modelSelection {
            chatManager.createNewChat(modelId: model.id, modelName: model.name, modelProvider: model.provider) { newChat in
                newChat.lastMessageDate = Date()
                DispatchQueue.main.async {
                    selection = .chat(newChat)
                }
            }
        }
    }
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
