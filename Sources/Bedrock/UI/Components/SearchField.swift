import AppKit
import SwiftUI

struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain).font(DesignTokens.body)
                .foregroundStyle(.primary).focused($focused)
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { text = ""; focused = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .background(DesignTokens.field, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(focused ? DesignTokens.accent.opacity(0.55) : DesignTokens.border, lineWidth: 1))
    }
}
