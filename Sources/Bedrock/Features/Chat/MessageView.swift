import AppKit
import SwiftUI
import Combine

/// Only the row receiving output observes token updates. The chat list, composer,
/// model selector and all completed responses keep their existing view graphs.
struct StreamingMessageView: View {
    @ObservedObject var stream: StreamingMessageState
    let fallback: MessageData
    let searchResult: SearchMatch?
    let adjustedFontSize: CGFloat
    let showTimestamp: Bool

    var body: some View {
        MessageView(message: stream.message ?? fallback, searchResult: searchResult,
                    adjustedFontSize: adjustedFontSize, isStreaming: true, showTimestamp: showTimestamp)
            .equatable()
    }
}

struct MessageView: View, Equatable {
    let message: MessageData
    let searchResult: SearchMatch?  // Enhanced search result
    var adjustedFontSize: CGFloat = -1 // One size smaller
    var isStreaming = false
    var showTimestamp = false
    var canModify = false
    var canRetry = false
    var onAction: ((MessageAction, MessageData) -> Void)?

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message == rhs.message && lhs.searchResult == rhs.searchResult &&
        lhs.adjustedFontSize == rhs.adjustedFontSize && lhs.isStreaming == rhs.isStreaming &&
        lhs.showTimestamp == rhs.showTimestamp && lhs.canModify == rhs.canModify && lhs.canRetry == rhs.canRetry
    }

    @StateObject private var viewModel = MessagePresentationState()
    @Environment(\.fontSize) private var fontSize: CGFloat
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    private var currentHighlightIndex: Int { searchResult?.selectedRangeIndex ?? -1 }

    private let imageSize: CGFloat = 100
    private var isToolOnly: Bool {
        message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        message.toolUses?.isEmpty == false &&
        message.imageBase64Strings?.isEmpty != false && message.videoUrl == nil
    }

    var body: some View {
        Group {
            // Hide "ToolResult" messages - they are only for API history
            // Tool results are displayed in the assistant message's toolResult field
            if message.user == "ToolResult" || (message.user == "User" && message.toolUses != nil) {
                EmptyView()
            } else {
                if message.user == "User" {
                    HStack(alignment: .top) {
                        Spacer(minLength: 32)
                        userMessageBubble
                    }
                    .padding(.horizontal).padding(.vertical, 4)
                } else {
                    assistantMessageBubble.padding(.horizontal).padding(.vertical, isToolOnly ? 0 : 4)
                }
            }
        }
    }

    // MARK: - Assistant Message Bubble
    private var assistantMessageBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            assistantMessageContent
            if !isStreaming && !isToolOnly {
                HStack(spacing: 8) {
                    Button(action: copyMessageToClipboard) { Image(systemName: "doc.on.doc").font(.system(size: 12)).frame(width: 28, height: 28) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Copy response").accessibilityLabel("Copy response")
                    if canRetry {
                        Button { onAction?(.retry, message) } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 12)).frame(width: 28, height: 28)
                        }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(!canModify)
                            .help("Try again in a new branch").accessibilityLabel("Retry response")
                    }
                    if onAction != nil {
                        ActionMenu {
                            Button("Branch from here") { onAction?(.branch, message) }.disabled(!canModify)
                            Button("Message details…") { onAction?(.details, message) }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).frame(width: 28, height: 28)
                        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .foregroundStyle(.secondary).help("Message actions").accessibilityLabel("Message actions")
                    }
                    if showTimestamp { Text(format(date: message.sentTime)).font(DesignTokens.detail).foregroundStyle(.secondary) }
                    Spacer()
                }
            }
        }
        .padding(.vertical, isToolOnly ? 0 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A tool-only response can expose a single disclosure element. Keep its
        // own tool name instead of overriding it with a generic response label.
        .accessibilityElement(children: .contain)
    }

    // MARK: - Assistant Content Components
    @ViewBuilder
    private var assistantMessageContent: some View {
        // Generated video (displayed with video player)
        if let videoUrl = message.videoUrl {
            GeneratedVideoView(videoUrl: videoUrl)
                .padding(.bottom, 8)
        }

        // Generated images (displayed larger for AI-generated content)
        if let imageBase64Strings = message.imageBase64Strings,
           !imageBase64Strings.isEmpty {
            GeneratedImagesView(
                imageBase64Strings: imageBase64Strings
            ) { imageData in
                viewModel.selectImage(with: imageData)
            }
            .padding(.bottom, 8)
        }

        VStack(spacing: 8) {
            // Expandable "thinking" section
            if let thinking = message.thinking, !thinking.isEmpty {
                MessageDisclosureView(
                    header: "Thinking",
                    text: thinking,
                    fontSize: fontSize + adjustedFontSize - 2,
                    searchRanges: searchResult?.ranges ?? [],
                    summary: message.thinkingSummary,
                    isStreaming: isStreaming && message.text.isEmpty
                )
                .padding(.vertical, 2)
            }

            // Main message content (skip if empty - e.g., video-only messages)
            if !message.text.isEmpty {
                if message.isError {
                    RequestErrorView(source: message.text)
                } else {
                    MessageMarkdownView(
                        text: message.text,
                        fontSize: fontSize + adjustedFontSize,
                        searchRanges: searchResult?.ranges ?? [],
                        isStreaming: isStreaming,
                        selectedSearchIndex: searchResult?.selectedRangeIndex
                    )
                }
            }
            if let calls = message.toolUses, !calls.isEmpty { ToolCallsView(calls: calls) }

            // Tool use information display
            if message.toolUses?.isEmpty != false, let toolUse = message.toolUse {
                MessageDisclosureView(
                    header: "Using tool: \(toolUse.name)",
                    text: formatToolInput(toolUse.input),
                    fontSize: fontSize + adjustedFontSize - 2,
                    searchRanges: searchResult?.ranges ?? []
                )
                .padding(.vertical, 2)
            }

            // Expandable tool result section
            if message.toolUses?.isEmpty != false, let toolResult = message.toolResult, !toolResult.isEmpty {
                MessageDisclosureView(
                    header: "Tool Result",
                    text: toolResult,
                    fontSize: fontSize + adjustedFontSize - 2,
                    searchRanges: searchResult?.ranges ?? []
                )
                .padding(.vertical, 2)
            }
        }
        .sheet(isPresented: $viewModel.isShowingImageModal) {
            if let data = viewModel.selectedImageData {
                ImagePreviewModal(
                    source: .stored(data, directory: URL(fileURLWithPath: PreferencesStore.shared.defaultDirectory).appendingPathComponent("generated_images")),
                    filename: "Generated image.png",
                    isPresented: $viewModel.isShowingImageModal
                )
            }
        }
    }

    // Helper function to format tool input parameters as JSON
    private func formatToolInput(_ input: JSONValue) -> String {
        return "```json\n\(prettyPrintJSON(input, indent: 0))\n```"
    }

    // Helper function for recursive pretty printing of JSONValue
    private func prettyPrintJSON(_ json: JSONValue, indent: Int) -> String {
        let indentString = String(repeating: "  ", count: indent)
        let childIndentString = String(repeating: "  ", count: indent + 1)

        switch json {
        case .string(let str):
            return "\"\(escapeString(str))\""

        case .number(let num):
            return "\(num)"

        case .bool(let bool):
            return bool ? "true" : "false"

        case .null:
            return "null"

        case .array(let arr):
            if arr.isEmpty {
                return "[]"
            }

            var result = "[\n"
            for (index, item) in arr.enumerated() {
                result += "\(childIndentString)\(prettyPrintJSON(item, indent: indent + 1))"
                if index < arr.count - 1 {
                    result += ","
                }
                result += "\n"
            }
            result += "\(indentString)]"
            return result

        case .object(let obj):
            if obj.isEmpty {
                return "{}"
            }

            var result = "{\n"
            let sortedKeys = obj.keys.sorted()
            for (index, key) in sortedKeys.enumerated() {
                if let value = obj[key] {
                    result += "\(childIndentString)\"\(key)\": \(prettyPrintJSON(value, indent: indent + 1))"
                    if index < sortedKeys.count - 1 {
                        result += ","
                    }
                    result += "\n"
                }
            }
            result += "\(indentString)}"
            return result
        }
    }

    // Helper function to escape special characters in strings
    private func escapeString(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    // MARK: - User Message Bubble
    private var userMessageBubble: some View {
        // Cache complex views to avoid unnecessary recalculations
        let messageBackground = RoundedRectangle(cornerRadius: 16)
            .fill(colorScheme == .dark ?
                  Color.white.opacity(0.08) :
                  Color.black.opacity(0.04))

        let messageBorder = RoundedRectangle(cornerRadius: 16)
            .stroke(
                colorScheme == .dark ?
                Color.white.opacity(0.12) :
                Color.black.opacity(0.08),
                lineWidth: 0.5
            )

        return VStack(alignment: .trailing, spacing: 4) {
            // Main message content with optimized rendering
            VStack(alignment: .trailing, spacing: 6) {
                // Only load attachments if they exist
                if (message.imageBase64Strings?.isEmpty == false) ||
                   (message.documentBase64Strings?.isEmpty == false) ||
                   (message.pastedTexts?.isEmpty == false) {

                    MessageAttachmentsView(
                        imageBase64Strings: message.imageBase64Strings,
                        imageSize: imageSize,
                        onTapImage: viewModel.selectImage,
                        onSelectDocument: { data, ext, name in
                            viewModel.selectDocument(data: data, ext: ext, name: name)
                        },
                        documentBase64Strings: message.documentBase64Strings,
                        documentFormats: message.documentFormats,
                        documentNames: message.documentNames,
                        pastedTexts: message.pastedTexts,
                        alignment: .trailing
                    )
                }

                // Only create text if non-empty
                if !message.text.isEmpty {
                    textContent
                }
            }
            .padding(14)
            .background(messageBackground)
            .overlay(messageBorder)

            // Keep actions in the layout and in the accessibility tree. An
            // offset hover overlay disappears when the pointer crosses the
            // bubble edge, and selectable text owns its native context menu.
            HStack(spacing: 2) {
                copyButton
                if onAction != nil {
                    Button { onAction?(.edit, message) } label: {
                        Image(systemName: "pencil").font(.system(size: 12)).frame(width: 28, height: 28)
                    }.buttonStyle(.plain).disabled(!canModify)
                        .help("Edit & resend").accessibilityLabel("Edit message")
                    ActionMenu {
                        Button("Retry this message") { onAction?(.retry, message) }.disabled(!canModify)
                        Button("Branch from here") { onAction?(.branch, message) }.disabled(!canModify)
                        Button("Message details…") { onAction?(.details, message) }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).frame(width: 28, height: 28)
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .help("Message actions").accessibilityLabel("Message actions")
                }
            }.foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("Copy message", action: copyMessageToClipboard)
            if onAction != nil {
                Button("Edit & resend…") { onAction?(.edit, message) }.disabled(!canModify)
                Button("Branch from here") { onAction?(.branch, message) }.disabled(!canModify)
                Divider()
                Button("Message details…") { onAction?(.details, message) }
            }
        }
        .sheet(isPresented: $viewModel.isShowingImageModal) {
            if let imageData = viewModel.selectedImageData {
                ImagePreviewModal(
                    source: .stored(imageData, directory: URL(fileURLWithPath: PreferencesStore.shared.defaultDirectory).appendingPathComponent("generated_images")),
                    filename: "Image.png",
                    isPresented: $viewModel.isShowingImageModal
                )
            }
        }
        .sheet(isPresented: $viewModel.isShowingDocumentModal) {
            if let docData = viewModel.selectedDocumentData {
                DocumentPreviewModal(
                    documentData: docData,
                    filename: viewModel.selectedDocumentName,
                    fileExtension: viewModel.selectedDocumentExt,
                    isPresented: $viewModel.isShowingDocumentModal
                )
            }
        }
    }

    // Extract text content to a separate computed property
    private var textContent: some View {
        Group {
            if let searchResult = searchResult, !searchResult.ranges.isEmpty {
                // Use optimized highlighting when search matches exist
                createHighlightedText(message.text, ranges: searchResult.ranges)
                    .font(.system(size: fontSize + adjustedFontSize))
            } else {
                // Simple text without highlighting when no search
                Text(message.text)
                    .font(.system(size: fontSize + adjustedFontSize))
                    .foregroundColor(.primary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }

    // Extract copy button to a separate computed property
    private var copyButton: some View {
        Button(action: copyMessageToClipboard) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 12))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Copy message").accessibilityLabel("Copy message")
    }

    // Enhanced text highlighting for search matches
    private func createHighlightedText(_ text: String, ranges: [NSRange]) -> SwiftUI.Text {
        if #available(macOS 12.0, *) {
            let highlightedText = TextHighlighter.createHighlightedText(
                text: text,
                searchRanges: ranges,
                fontSize: fontSize + adjustedFontSize,
                highlightColor: .yellow,
                textColor: .primary,
                currentMatchIndex: currentHighlightIndex
            )
            return Text(highlightedText.attributedString)
        } else {
            // Fallback for older versions
            return Text(text)
        }
    }

    // MARK: - Shared Components

    private func copyMessageToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.text, forType: .string)
    }

    private func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

}


private final class MessagePresentationState: ObservableObject {
    @Published var selectedImageData: String? = nil
    @Published var isShowingImageModal: Bool = false
    @Published var selectedDocumentData: Data? = nil
    @Published var selectedDocumentExt: String = ""
    @Published var selectedDocumentName: String = ""
    @Published var isShowingDocumentModal: Bool = false
    @Published var currentHighlightedMatch: (messageIndex: Int, matchPositionIndex: Int)? = nil

    func selectImage(with data: String) {
        self.selectedImageData = data
        self.isShowingImageModal = true
    }

    func selectDocument(data: Data, ext: String, name: String) {
        self.selectedDocumentData = data
        self.selectedDocumentExt = ext
        self.selectedDocumentName = name
        self.isShowingDocumentModal = true
    }

    func clearSelection() {
        self.selectedImageData = nil
        self.isShowingImageModal = false
    }
}
