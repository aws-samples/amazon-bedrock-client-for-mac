import AppKit
import SwiftUI
import MCP

struct MultilineRoundedTextField: View {
    @Binding var text: String
    var placeholder: String
    @FocusState private var isFocused: Bool
    @State private var localText = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $localText)
                .font(DesignTokens.body)
                .padding(6)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("System prompt")
                .accessibilityIdentifier("settings.systemPromptEditor")
            if localText.isEmpty {
                Text(placeholder)
                    .font(DesignTokens.body).foregroundStyle(.tertiary)
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(isFocused ? DesignTokens.accent.opacity(0.65) : DesignTokens.border, lineWidth: 1))
        .onAppear { localText = text }
        .onChange(of: localText) { _, value in
            saveTask?.cancel()
            guard value != text else { return }
            saveTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                if text != value { text = value }
            }
        }
        .onChange(of: text) { _, value in
            guard value != localText else { return }
            saveTask?.cancel()
            localText = value
        }
        .onChange(of: isFocused) { _, focused in if !focused { flush() } }
        .onDisappear { flush() }
    }

    private func flush() {
        saveTask?.cancel()
        if text != localText { text = localText }
    }
}

// MARK: - Server Row
