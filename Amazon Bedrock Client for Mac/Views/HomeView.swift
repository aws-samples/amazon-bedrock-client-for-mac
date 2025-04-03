//
//  HomeView.swift
//  Amazon Bedrock Client for Mac
//

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
            // Modern background layer
            backgroundLayer
            
            // Main content
            VStack(spacing: 24) {
                Spacer()
                
                // Branding section
                brandingSection
                
                // Tagline
                Text("Build and scale generative AI applications")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                
                // Modern new chat button
                newChatButton
                    .padding(.top, 36)
                
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
    
    // MARK: - UI Components
    
    // Modern background layer
    private var backgroundLayer: some View {
        ZStack {
            // Base background
            Color(NSColor.windowBackgroundColor)
            
            // Subtle gradient overlay
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.08),
                    Color.purple.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Pattern overlay (macOS style)
            Image(systemName: "circle.grid.2x2")
                .resizable(resizingMode: .tile)
                .foregroundStyle(Color.primary.opacity(0.03))
                .blendMode(.overlay)
        }
        .ignoresSafeArea()
    }
    
    // Modern branding section
    private var brandingSection: some View {
        VStack(spacing: 12) {
            // App icon
            Image("bedrock")
                .font(.system(size: 24))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue, .purple.opacity(0.8))
                .padding(.bottom, 8)
            
            // Title (SF Pro design)
            Text("Amazon Bedrock")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }
    
    // Modern new chat button
    private var newChatButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                createNewChat()
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                
                Text("New chat")
                    .font(.system(size: 16, weight: .medium))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .frame(width: 200)
            .background(
                Group {
                    if colorScheme == .dark {
                        // Dark mode - translucent material
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    } else {
                        // Light mode - translucent material
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        LinearGradient(
                            colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isHoveringNewChat ? 1.5 : 0
                    )
            )
            .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
            .foregroundStyle(.primary)
        }
        .buttonStyle(MacButtonStyle(isHovering: $isHoveringNewChat))
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

// MARK: - Mac Style Button
struct MacButtonStyle: ButtonStyle {
    @Binding var isHovering: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { newValue in
                if newValue {
                    isHovering = false
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hovering
                }
            }
    }
}

// Keep existing Color extension
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
