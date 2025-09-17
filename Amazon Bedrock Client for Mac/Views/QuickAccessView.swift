//
//  QuickAccessView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Kiro on 2025/09/17.
//

import SwiftUI
import Logging
import MarkdownKit

struct QuickAccessView: View {
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var response: String = ""
    @State private var errorMessage: String = ""
    
    @StateObject private var chatManager = ChatManager.shared
    @StateObject private var settingManager = SettingManager.shared
    
    private let onClose: () -> Void
    private let logger = Logger(label: "QuickAccessView")
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content area
            contentView
            
            Divider()
            
            // Input area
            inputView
        }
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .cornerRadius(12)
        .shadow(radius: 20)
        .onAppear {
            // Focus on input field when window appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "bolt.fill")
                .foregroundColor(.blue)
                .font(.title2)
            
            Text("Quick Access")
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Model selector
            Picker("Model", selection: $settingManager.selectedModel) {
                ForEach(settingManager.availableModels, id: \.self) { model in
                    Text(model.displayName)
                        .tag(model)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .frame(width: 150)
            
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title2)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
    }
    
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Thinking...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                } else if !response.isEmpty {
                    LazyMarkdownView(
                        text: response,
                        fontSize: 14,
                        searchRanges: []
                    )
                    .padding()
                } else if !errorMessage.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                    .padding()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "message.circle")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        
                        Text("Ask anything...")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        Text("Type your question below and press Enter")
                            .font(.caption)
                            .foregroundColor(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
        }
        .frame(minHeight: 200)
    }
    
    private var inputView: some View {
        HStack(spacing: 12) {
            TextField("Ask Amazon Bedrock...", text: $inputText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onSubmit {
                    sendMessage()
                }
                .disabled(isLoading)
            
            Button(action: sendMessage) {
                Image(systemName: isLoading ? "stop.circle.fill" : "paperplane.fill")
                    .foregroundColor(isLoading ? .red : .blue)
                    .font(.title2)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading)
        }
        .padding()
    }
    
    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        if isLoading {
            // Stop current request (implement this later)
            isLoading = false
            return
        }
        
        let userMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""
        response = ""
        errorMessage = ""
        isLoading = true
        
        logger.info("Sending quick access message: \(userMessage)")
        
        // For now, simulate a response
        // TODO: Integrate with actual ChatManager/BackendModel
        Task {
            do {
                // Simulate API delay
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                await MainActor.run {
                    response = "This is a placeholder response for: \"\(userMessage)\"\n\nThe quick access feature is implemented and ready. To complete the integration, we need to connect this with the actual ChatManager and BackendModel for real AI responses."
                    isLoading = false
                    logger.info("Quick access response completed (placeholder)")
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Error: \(error.localizedDescription)"
                    logger.error("Quick access error: \(error)")
                }
            }
        }
    }
}

// MARK: - Visual Effect View for background blur
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}