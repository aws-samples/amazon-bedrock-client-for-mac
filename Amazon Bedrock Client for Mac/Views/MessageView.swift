//
//  MessageView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import MarkdownKit
import WebKit
import Combine
import Foundation

// MARK: - LazyMarkdownView
struct LazyMarkdownView: View {
    let text: String
    let fontSize: CGFloat
    let searchRanges: [NSRange]
    @State private var height: CGFloat = .zero
    
    private let parser: ExtendedMarkdownParser
    private let htmlGenerator: CustomHtmlGenerator
    
    init(text: String, fontSize: CGFloat, searchRanges: [NSRange] = []) {
        self.text = text
        self.fontSize = fontSize
        self.searchRanges = searchRanges
        self.parser = ExtendedMarkdownParser()
        self.htmlGenerator = CustomHtmlGenerator()
    }
    
    var body: some View {
        HTMLStringView(
            htmlContent: generateHTML(from: text),
            fontSize: fontSize,
            searchRanges: searchRanges,
            dynamicHeight: $height
        )
        .frame(height: height)
    }
    
    private func generateHTML(from markdown: String) -> String {
        let document = parser.parse(markdown)
        return htmlGenerator.generate(doc: document)
    }
}

// MARK: - CustomHtmlGenerator
class CustomHtmlGenerator: HtmlGenerator {
    override func generate(block: Block, parent: Parent, tight: Bool = false) -> String {
        switch block {
        case .fencedCode(let info, let lines):
            return generateCustomCodeBlock(info: info, lines: lines)
        default:
            return super.generate(block: block, parent: parent, tight: tight)
        }
    }
    
    override func generate(doc: Block) -> String {
        guard case .document(let blocks) = doc else {
            preconditionFailure("cannot generate HTML from \(doc)")
        }
        return self.generate(blocks: blocks, parent: .none)
    }
    
    private func generateCustomCodeBlock(info: String?, lines: Lines) -> String {
        let languageIdentifier = info?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let languageDisplay = languageIdentifier.isEmpty ? "Code" : languageIdentifier.capitalized
        
        let copyButtonSVG = """
        <svg aria-hidden="true" height="16" viewBox="0 0 16 16" width="16">
            <path fill="currentColor" d="M3 2.5A1.5 1.5 0 014.5 1h6A1.5 1.5 0 0112 2.5V3h.5A1.5 1.5 0 0114 4.5v8A1.5 1.5 0 0112.5 14h-6A1.5 1.5 0 015 12.5V12H4.5A1.5 1.5 0 013 10.5v-8zM5 12.5a.5.5 0 00.5.5h6a.5.5 0 00.5-.5v-8a.5.5 0 00-.5-.5H12v6A1.5 1.5 0 0110.5 12H5v.5zM4 10.5v-8a.5.5 0 01.5-.5H5v6A1.5 1.5 0 006.5 9H12v1.5a.5.5 0 01-.5.5H5A1.5 1.5 0 013.5 9V4.5a.5.5 0 01.5-.5H4v6z"></path>
        </svg>
        """
        
        let checkmarkSVG = """
        <svg aria-hidden="true" height="16" viewBox="0 0 16 16" width="16">
            <path fill="currentColor" d="M13.78 4.22a.75.75 0 010 1.06l-7.25 7.25a.75.75 0 01-1.06 0L2.22 9.28a.75.75 0 011.06-1.06L6 10.94l6.72-6.72a.75.75 0 011.06 0z"></path>
        </svg>
        """
        
        let code = lines.joined(separator: "")
        let escapedCode = escapeHtml(code)
        let codeBlockId = "code-block-\(UUID().uuidString.prefix(8))"
        
        return """
        <div class="code-block-container">
            <div class="code-header">
                <span class="language">\(languageDisplay)</span>
            </div>
            <pre id="\(codeBlockId)"><code class="language-\(languageIdentifier)">\(escapedCode)</code></pre>
            <div class="code-footer">
                <button class="copy-button-bottom" onclick="copyCodeAdvanced(this, '\(codeBlockId)')" data-code-id="\(codeBlockId)">
                    <span class="copy-icon">\(copyButtonSVG)</span>
                    <span class="copy-text">Copy code</span>
                    <span class="copied-icon" style="display: none;">\(checkmarkSVG)</span>
                    <span class="copied-text" style="display: none;">Copied!</span>
                </button>
            </div>
        </div>
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func escapeHtml(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

// MARK: - LazyImageView
// MARK: - Image Cache for Performance
private final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private var cache = NSCache<NSString, NSImage>()
    private let lock = NSLock()
    
    init() {
        cache.countLimit = 100
        cache.totalCostLimit = 200 * 1024 * 1024  // 200MB
    }
    
    func image(for key: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache.object(forKey: key as NSString)
    }
    
    func setImage(_ image: NSImage, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.setObject(image, forKey: key as NSString)
    }
}

struct LazyImageView: View {
    let imageData: String
    let size: CGFloat
    let onTap: () -> Void
    var isGeneratedImage: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var loadedImage: NSImage?
    @State private var isLoading = true
    
    private var displaySize: CGFloat {
        isGeneratedImage ? max(size, 400) : size
    }
    
    // Use hash of first 100 chars as cache key (full base64 is too long)
    private var cacheKey: String {
        let prefix = String(imageData.prefix(100))
        return "\(prefix.hashValue)"
    }
    
    var body: some View {
        Button(action: onTap) {
            Group {
                if let image = loadedImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: displaySize, maxHeight: displaySize)
                        .clipShape(RoundedRectangle(cornerRadius: isGeneratedImage ? 12 : 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: isGeneratedImage ? 12 : 10)
                                .stroke(
                                    colorScheme == .dark ?
                                    Color.white.opacity(0.15) :
                                        Color.primary.opacity(0.1),
                                    lineWidth: 1
                                )
                        )
                        .shadow(
                            color: Color.black.opacity(isGeneratedImage ? 0.15 : 0.05),
                            radius: isGeneratedImage ? 8 : 2,
                            x: 0,
                            y: isGeneratedImage ? 4 : 1
                        )
                } else if isLoading {
                    // Loading placeholder
                    RoundedRectangle(cornerRadius: isGeneratedImage ? 12 : 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                        .frame(width: displaySize * 0.8, height: displaySize * 0.6)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                        )
                } else {
                    // Error state
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                        .frame(width: size, height: size / 2)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadImageAsync()
        }
        .contextMenu {
            Button(action: copyImageToClipboard) {
                Label("Copy Image", systemImage: "doc.on.doc")
            }
            
            Button(action: saveImageToFile) {
                Label("Save Image...", systemImage: "square.and.arrow.down")
            }
        }
    }
    
    private func loadImageAsync() {
        // Check cache first
        if let cached = ImageCache.shared.image(for: cacheKey) {
            loadedImage = cached
            isLoading = false
            return
        }
        
        // Load on background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            var image: NSImage?
            
            // Try loading from ImageStorageManager (handles both file refs and base64)
            if let data = ImageStorageManager.shared.loadImage(imageData) {
                image = NSImage(data: data)
            } else if let data = Data(base64Encoded: imageData) {
                // Fallback to direct base64 decode
                image = NSImage(data: data)
            }
            
            DispatchQueue.main.async {
                if let img = image {
                    ImageCache.shared.setImage(img, for: cacheKey)
                    loadedImage = img
                }
                isLoading = false
            }
        }
    }
    
    private func copyImageToClipboard() {
        guard let image = loadedImage else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
    
    private func saveImageToFile() {
        guard let image = loadedImage else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]
        savePanel.nameFieldStringValue = "generated-image-\(Date().timeIntervalSince1970).png"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                if let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData) {
                    let fileExtension = url.pathExtension.lowercased()
                    let imageData: Data?
                    
                    if fileExtension == "png" {
                        imageData = bitmap.representation(using: .png, properties: [:])
                    } else {
                        imageData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95])
                    }
                    
                    if let data = imageData {
                        try? data.write(to: url)
                    }
                }
            }
        }
    }
}

// MARK: - GeneratedImageView (for AI-generated images)
struct GeneratedImageView: View {
    let imageBase64Strings: [String]
    let onTapImage: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Display images in a responsive grid
            ForEach(imageBase64Strings, id: \.self) { imageData in
                LazyImageView(
                    imageData: imageData,
                    size: 512,
                    onTap: { onTapImage(imageData) },
                    isGeneratedImage: true
                )
            }
        }
    }
}

// MARK: - ExpandableMarkdownItem
struct ExpandableMarkdownItem: View {
    @State private var isExpanded = false
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    let header: String
    let text: String
    let fontSize: CGFloat
    let searchRanges: [NSRange]
    var summary: String? = nil  // Optional summary to show in header
    var isStreaming: Bool = false  // Whether content is still streaming
    
    init(header: String, text: String, fontSize: CGFloat, searchRanges: [NSRange] = [], summary: String? = nil, isStreaming: Bool = false) {
        self.header = header
        self.text = text
        self.fontSize = fontSize
        self.searchRanges = searchRanges
        self.summary = summary
        self.isStreaming = isStreaming
    }
    
    // Display text for header - shows summary if available
    private var displayHeader: String {
        if let summary = summary, !summary.isEmpty {
            return summary
        } else {
            return header
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Toggle button with summary
            Button(action: {
                isExpanded.toggle()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: fontSize - 4))
                        .foregroundColor(.secondary)
                    
                    // Show animated dots only when streaming without summary
                    if isStreaming && summary == nil {
                        ThinkingDotsView(fontSize: fontSize)
                    } else {
                        Text(displayHeader)
                            .font(.system(size: fontSize - 1, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(.borderless)
            
            // Expandable content
            if isExpanded {
                LazyMarkdownView(
                    text: text,
                    fontSize: fontSize - 2,
                    searchRanges: searchRanges
                )
                .padding(.leading, fontSize / 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    colorScheme == .dark ?
                    Color.white.opacity(0.05) :
                        Color.black.opacity(0.03)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    colorScheme == .dark ?
                    Color.white.opacity(0.1) :
                        Color.black.opacity(0.06),
                    lineWidth: 0.5
                )
        )
    }
}

// Separate view for animated dots using TimelineView
private struct ThinkingDotsView: View {
    let fontSize: CGFloat
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { timeline in
            let seconds = Calendar.current.component(.nanosecond, from: timeline.date) / 100_000_000
            let dotCount = (seconds % 3) + 1
            Text("Thinking" + String(repeating: ".", count: dotCount))
                .font(.system(size: fontSize - 1, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - MessageView
struct MessageView: View {
    let message: MessageData
    let searchResult: SearchMatch?  // Enhanced search result
    var adjustedFontSize: CGFloat = -1 // One size smaller
    
    @StateObject var viewModel = MessageViewModel()
    @Environment(\.fontSize) private var fontSize: CGFloat
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var isHovering = false
    @State private var currentHighlightIndex = 0
    @State private var scrollToMatchNotification: AnyCancellable?
    
    private let imageSize: CGFloat = 100
    
    var body: some View {
        Group {
            // Hide "ToolResult" messages - they are only for API history
            // Tool results are displayed in the assistant message's toolResult field
            if message.user == "ToolResult" {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        if message.user == "User" {
                            Spacer()
                            userMessageBubble
                                .padding(.horizontal)
                        } else {
                            assistantMessageBubble
                                .padding(.horizontal)
                            Spacer()
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovering = hovering
                    }
                }
            }
        }
        .onAppear {
            setupScrollToMatchNotification()
        }
        .onDisappear {
            scrollToMatchNotification?.cancel()
        }
        .textSelection(.enabled)
    }
    
    // MARK: - Assistant Message Bubble
    private var assistantMessageBubble: some View {
        ZStack(alignment: .bottomTrailing) {
            // Main content
            VStack(alignment: .leading, spacing: 4) {
                // Message header with user name and timestamp
                messageHeader
                    .padding(.bottom, 2)
                
                // Message content with images and markdown
                assistantMessageContent
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ?
                          Color(NSColor.controlBackgroundColor).opacity(0.5) :
                            Color(NSColor.controlBackgroundColor).opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        colorScheme == .dark ?
                        Color.white.opacity(0.08) :
                            Color.black.opacity(0.06),
                        lineWidth: 0.5
                    )
            )
            
            // Copy button as overlay at bottom left
            Button(action: copyMessageToClipboard) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.8))
                    .padding(6)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ?
                                  Color.gray.opacity(0.3) :
                                    Color.white.opacity(0.9))
                            .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .offset(x: 8, y: 8)
            .opacity(isHovering ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
    }
    
    // MARK: - Assistant Content Components
    @ViewBuilder
    private var assistantMessageContent: some View {
        // Generated images (displayed larger for AI-generated content)
        if let imageBase64Strings = message.imageBase64Strings,
           !imageBase64Strings.isEmpty {
            GeneratedImageView(
                imageBase64Strings: imageBase64Strings
            ) { imageData in
                viewModel.selectImage(with: imageData)
            }
            .padding(.bottom, 8)
        }
        
        VStack(spacing: 8) {
            // Expandable "thinking" section
            if let thinking = message.thinking, !thinking.isEmpty {
                ExpandableMarkdownItem(
                    header: "Thinking",
                    text: thinking,
                    fontSize: fontSize + adjustedFontSize - 2,
                    searchRanges: searchResult?.ranges ?? [],
                    summary: message.thinkingSummary,
                    isStreaming: message.text.isEmpty  // Still streaming if no text yet
                )
                .padding(.vertical, 2)
            }
            
            // Main message content
            LazyMarkdownView(
                text: message.text, 
                fontSize: fontSize + adjustedFontSize,
                searchRanges: searchResult?.ranges ?? []
            )
                .sheet(isPresented: $viewModel.isShowingImageModal) {
                    if let data = viewModel.selectedImageData,
                       let imageToShow = NSImage(base64Encoded: data) {
                        ImagePreviewModal(
                            image: imageToShow,
                            filename: "image-\(Date().timeIntervalSince1970).png",
                            isPresented: $viewModel.isShowingImageModal
                        )
                    }
                }
            
            // Tool use information display
            if let toolUse = message.toolUse {
                ExpandableMarkdownItem(
                    header: "Using tool: \(toolUse.name)",
                    text: formatToolInput(toolUse.input),
                    fontSize: fontSize + adjustedFontSize - 2,
                    searchRanges: searchResult?.ranges ?? []
                )
                .padding(.vertical, 2)
            }

            // Expandable tool result section
            if let toolResult = message.toolResult, !toolResult.isEmpty {
                ExpandableMarkdownItem(
                    header: "Tool Result",
                    text: toolResult,
                    fontSize: fontSize + adjustedFontSize - 2,
                    searchRanges: searchResult?.ranges ?? []
                )
                .padding(.vertical, 2)
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
        
        return ZStack(alignment: .bottomTrailing) {
            // Main message content with optimized rendering
            VStack(alignment: .trailing, spacing: 6) {
                // Only load attachments if they exist
                if (message.imageBase64Strings?.isEmpty == false) ||
                   (message.documentBase64Strings?.isEmpty == false) ||
                   (message.pastedTexts?.isEmpty == false) {
                    
                    AttachmentsView(
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
            
            // Copy button with optimized rendering
            if isHovering {
                copyButton
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $viewModel.isShowingImageModal) {
            if let imageData = viewModel.selectedImageData,
               let imageToShow = NSImage(base64Encoded: imageData) {
                ImagePreviewModal(
                    image: imageToShow,
                    filename: "image-\(Date().timeIntervalSince1970).png",
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
    }

    // Extract copy button to a separate computed property
    private var copyButton: some View {
        Button(action: copyMessageToClipboard) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 12))
                .foregroundColor(colorScheme == .dark ?
                                 Color.white.opacity(0.9) :
                                 Color.black.opacity(0.8))
                .padding(6)
                .background(
                    Circle()
                        .fill(colorScheme == .dark ?
                              Color.gray.opacity(0.3) :
                              Color.white.opacity(0.9))
                        .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .offset(x: 8, y: 8)
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
    
    private var messageHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(message.user)
                .font(.system(size: fontSize + adjustedFontSize, weight: .semibold))
                .foregroundColor(.primary) // Original color
            
            Text(format(date: message.sentTime))
                .font(.system(size: fontSize + adjustedFontSize - 2))
                .foregroundColor(.secondary) // Original color
        }
    }
    
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
    
    // MARK: - Search Match Scrolling
    
    private func setupScrollToMatchNotification() {
        scrollToMatchNotification = NotificationCenter.default
            .publisher(for: NSNotification.Name("ScrollToSearchMatch"))
            .sink { notification in
                guard let userInfo = notification.userInfo,
                      let messageIndex = userInfo["messageIndex"] as? Int,
                      let matchIndex = userInfo["matchIndex"] as? Int,
                      let searchQuery = userInfo["searchQuery"] as? String else {
                    return
                }
                
                // Check if this notification is for this message
                if let searchMatch = searchResult,
                   searchMatch.messageIndex == messageIndex {
                    currentHighlightIndex = matchIndex
                    scrollToSpecificMatch(matchIndex: matchIndex, searchQuery: searchQuery)
                }
            }
    }
    
    private func scrollToSpecificMatch(matchIndex: Int, searchQuery: String) {
        guard let searchMatch = searchResult,
              matchIndex < searchMatch.ranges.count else {
            return
        }
        
        let targetRange = searchMatch.ranges[matchIndex]
        
        // For WebView content (markdown), send JavaScript to scroll to the match
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(
                name: NSNotification.Name("ScrollToMatchInWebView"),
                object: nil,
                userInfo: [
                    "range": targetRange,
                    "searchQuery": searchQuery,
                    "matchIndex": matchIndex
                ]
            )
        }
    }
}

// MARK: - CustomWKWebView

class CustomWKWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            // Horizontal scrolling: handle in the web view
            super.scrollWheel(with: event)
        } else {
            // Vertical scrolling: pass to the next responder
            self.nextResponder?.scrollWheel(with: event)
        }
    }
}

// MARK: - HTMLStringView

struct HTMLStringView: NSViewRepresentable {
    let htmlContent: String
    let fontSize: CGFloat
    let searchRanges: [NSRange]
    @Binding var dynamicHeight: CGFloat
    @State private var scrollToMatchNotification: AnyCancellable?
    
    init(htmlContent: String, fontSize: CGFloat, searchRanges: [NSRange] = [], dynamicHeight: Binding<CGFloat>) {
        self.htmlContent = htmlContent
        self.fontSize = fontSize
        self.searchRanges = searchRanges
        self._dynamicHeight = dynamicHeight
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        // Set up message handler for copy action
        config.userContentController.add(context.coordinator, name: "copyHandler")
        config.userContentController.add(context.coordinator, name: "searchHandler")
        
        let webView = CustomWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        
        // Disable WKWebView's scrolling
        if let scrollView = webView.enclosingScrollView {
            scrollView.hasVerticalScroller = false
            scrollView.verticalScrollElasticity = .none
            scrollView.scrollerStyle = .overlay
        }
        
        // Set up scroll to match notification
        context.coordinator.setupScrollToMatchNotification(webView: webView)
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        let htmlWithHighlights = addSearchHighlights(to: wrapHTMLContent(htmlContent))
        
        // Only reload if content has actually changed to preserve text selection
        if htmlWithHighlights != context.coordinator.lastLoadedContent {
            context.coordinator.lastLoadedContent = htmlWithHighlights
            nsView.loadHTMLString(htmlWithHighlights, baseURL: nil)
        }
        
        context.coordinator.searchRanges = searchRanges
    }
    
    private func addSearchHighlights(to html: String) -> String {
        guard !searchRanges.isEmpty else { return html }
        
        // Enhanced CSS for highlighting with better visibility
        let highlightCSS = """
        <style>
        .search-highlight {
            background-color: #ffff00 !important;
            color: #000000 !important;
            font-weight: bold !important;
            padding: 1px 2px !important;
            border-radius: 2px !important;
            box-shadow: 0 0 3px rgba(255, 255, 0, 0.5) !important;
        }
        .search-highlight-current {
            background-color: #ff6b35 !important;
            color: #ffffff !important;
            animation: pulse 1s ease-in-out !important;
        }
        @keyframes pulse {
            0% { transform: scale(1); }
            50% { transform: scale(1.05); }
            100% { transform: scale(1); }
        }
        </style>
        """
        
        return html.replacingOccurrences(of: "<head>", with: "<head>\(highlightCSS)")
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: HTMLStringView
        var searchRanges: [NSRange] = []
        var lastLoadedContent: String = "" // Track last loaded content to prevent unnecessary reloads
        private var scrollToMatchNotification: AnyCancellable?
        
        init(_ parent: HTMLStringView) {
            self.parent = parent
        }
        
        func setupScrollToMatchNotification(webView: WKWebView) {
            scrollToMatchNotification = NotificationCenter.default
                .publisher(for: NSNotification.Name("ScrollToMatchInWebView"))
                .sink { notification in
                    guard let userInfo = notification.userInfo,
                          let range = userInfo["range"] as? NSRange,
                          let searchQuery = userInfo["searchQuery"] as? String,
                          let matchIndex = userInfo["matchIndex"] as? Int else {
                        return
                    }
                    
                    self.scrollToMatchInWebView(webView: webView, range: range, searchQuery: searchQuery, matchIndex: matchIndex)
                }
        }
        
        private func scrollToMatchInWebView(webView: WKWebView, range: NSRange, searchQuery: String, matchIndex: Int) {
            let escapedQuery = searchQuery.replacingOccurrences(of: "'", with: "\\'")
            
            let javascript = """
            (function() {
                // Remove previous highlights
                document.querySelectorAll('.search-highlight, .search-highlight-current').forEach(el => {
                    el.outerHTML = el.innerHTML;
                });
                
                // Function to highlight text
                function highlightText(node, query, targetIndex) {
                    if (node.nodeType === Node.TEXT_NODE) {
                        const text = node.textContent;
                        const regex = new RegExp(query.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&'), 'gi');
                        let match;
                        let currentIndex = 0;
                        let lastIndex = 0;
                        const fragments = [];
                        
                        while ((match = regex.exec(text)) !== null) {
                            // Add text before match
                            if (match.index > lastIndex) {
                                fragments.push(document.createTextNode(text.substring(lastIndex, match.index)));
                            }
                            
                            // Create highlighted span
                            const span = document.createElement('span');
                            span.className = currentIndex === targetIndex ? 'search-highlight-current' : 'search-highlight';
                            span.textContent = match[0];
                            fragments.push(span);
                            
                            // Scroll to current match
                            if (currentIndex === targetIndex) {
                                setTimeout(() => {
                                    span.scrollIntoView({ behavior: 'smooth', block: 'center' });
                                }, 100);
                            }
                            
                            lastIndex = regex.lastIndex;
                            currentIndex++;
                        }
                        
                        // Add remaining text
                        if (lastIndex < text.length) {
                            fragments.push(document.createTextNode(text.substring(lastIndex)));
                        }
                        
                        if (fragments.length > 1) {
                            const parent = node.parentNode;
                            fragments.forEach(fragment => parent.insertBefore(fragment, node));
                            parent.removeChild(node);
                        }
                    } else if (node.nodeType === Node.ELEMENT_NODE) {
                        // Skip code blocks and other elements that shouldn't be highlighted
                        if (!['CODE', 'PRE', 'SCRIPT', 'STYLE'].includes(node.tagName)) {
                            Array.from(node.childNodes).forEach(child => highlightText(child, query, targetIndex));
                        }
                    }
                }
                
                // Start highlighting from body
                highlightText(document.body, '\(escapedQuery)', \(matchIndex));
            })();
            """
            
            webView.evaluateJavaScript(javascript) { result, error in
                if let error = error {
                    print("JavaScript error: \(error)")
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("""
                function getContentHeight() {
                    var body = document.body;
                    var html = document.documentElement;
                    var height = Math.max(body.scrollHeight, body.offsetHeight,
                                          html.clientHeight, html.scrollHeight, html.offsetHeight);
                    return height;
                }
                getContentHeight();
            """) { (result, error) in
                if let height = result as? CGFloat {
                    DispatchQueue.main.async {
                        self.parent.dynamicHeight = height
                    }
                }
            }
        }
        
        // Handle link clicks - open in default browser instead of loading inline
        @MainActor
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    // Open in default browser instead of loading inline
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
        
        // Handle messages from JavaScript
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "copyHandler", let code = message.body as? String {
                // Copy code to clipboard
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(code, forType: .string)
            }
        }
    }
    
    // MARK: - HTML Content Wrapping
    
    private func wrapHTMLContent(_ content: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <link
              rel="stylesheet"
              href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.5.1/styles/github.min.css"
              media="(prefers-color-scheme: light)"
            >
            <link
              rel="stylesheet"
              href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.5.1/styles/github-dark.min.css"
              media="(prefers-color-scheme: dark)"
            >
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.5.1/highlight.min.js"></script>
            <style>
                :root {
                    --background-color: #ffffff;
                    --text-color: #24292e;
                    --secondary-text-color: #6a737d;
                    --code-background-color: #ffffff;
                    --code-text-color: #24292e;
                    --border-color: #e1e4e8;
                    --header-background-color: #f6f8fa;
                    --inline-code-background-color: #f0f0f0;
                    --inline-code-text-color: #24292e;
                }
        
                @media (prefers-color-scheme: dark) {
                    :root {
                        --background-color: #0d1117;
                        --text-color: #c9d1d9;
                        --secondary-text-color: #8b949e;
                        --code-background-color: #0d1117;
                        --code-text-color: #c9d1d9;
                        --border-color: #30363d;
                        --header-background-color: #21262d;
                        --inline-code-background-color: #2d333b;
                        --inline-code-text-color: #adbac7;
                    }
                }
        
                body {
                    background-color: transparent;
                    color: var(--text-color);
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Helvetica', 'Arial', sans-serif;
                    font-size: \(fontSize)px;
                    line-height: 1.5;
                    margin: 0;
                    padding: 0;
                    overflow-wrap: break-word;
                }
                p {
                    margin: 0;
                    padding: 0;
                }
                h1, h2, h3, h4, h5, h6 {
                    margin: 0;
                    padding: 0;
                }
                /* Code block styling - seamless integration */
                .code-block-container {
                    position: relative;
                    background-color: #f6f8fa;
                    border-radius: 12px;
                    overflow: hidden;
                    margin: 12px 0;
                    border: 0.5px solid var(--border-color);
                }
                
                @media (prefers-color-scheme: dark) {
                    .code-block-container {
                        background-color: #0d1117;
                        border: 0.5px solid rgba(255, 255, 255, 0.1);
                    }
                }
                
                .code-header {
                    display: flex;
                    justify-content: flex-start;
                    align-items: center;
                    background-color: var(--header-background-color);
                    padding: 10px 14px;
                    font-size: 12px;
                    color: var(--secondary-text-color);
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Helvetica', 'Arial', sans-serif;
                    border-bottom: 0.5px solid var(--border-color);
                }
                
                .code-header .language {
                    font-weight: 600;
                    font-size: 13px;
                    color: var(--text-color);
                    line-height: 1.4;
                }
                
                .code-wrapper {
                    position: relative;
                }
                
                pre {
                    background-color: var(--code-background-color);
                    padding: 14px;
                    margin: 0;
                    overflow: auto;
                    white-space: pre;
                    font-family: 'SF Mono', 'Menlo', 'Monaco', 'Courier New', monospace;
                    font-size: \(fontSize - 2)px;
                    color: var(--code-text-color);
                    max-width: 100%;
                    border-radius: 0;
                    line-height: 1.5;
                }
                
                pre code {
                    display: block;
                    background-color: transparent;
                    color: var(--code-text-color);
                    margin: 0;
                    border: none;
                    border-radius: 0;
                    padding: 0;
                    line-height: 1.5;
                }
                
                .code-footer {
                    background-color: var(--header-background-color);
                    padding: 10px 14px;
                    border-top: 0.5px solid var(--border-color);
                    display: flex;
                    justify-content: flex-end;
                }
                
                .copy-button-bottom {
                    background: #ffffff;
                    border: 1px solid #d0d7de;
                    color: #24292f;
                    cursor: pointer !important;
                    display: inline-flex;
                    align-items: center;
                    font-size: 11px;
                    padding: 5px 10px;
                    border-radius: 6px;
                    transition: all 0.15s ease;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Helvetica', 'Arial', sans-serif;
                    min-width: 90px;
                    justify-content: center;
                    user-select: none;
                    -webkit-user-select: none;
                    pointer-events: auto !important;
                    z-index: 9999 !important;
                    line-height: 1.4;
                    position: relative;
                    isolation: isolate;
                }
                
                @media (prefers-color-scheme: dark) {
                    .copy-button-bottom {
                        background: rgba(255, 255, 255, 0.06);
                        border: 0.5px solid rgba(255, 255, 255, 0.12);
                        color: #c9d1d9;
                    }
                }
                
                .copy-button-bottom:hover {
                    background: #f3f4f6;
                    border-color: #b1b8c0;
                    color: #24292f;
                }
                
                @media (prefers-color-scheme: dark) {
                    .copy-button-bottom:hover {
                        background: rgba(255, 255, 255, 0.1);
                        border-color: rgba(255, 255, 255, 0.2);
                        color: #c9d1d9;
                    }
                }
                
                .copy-button-bottom:active {
                    background: #e8eaed;
                    border-color: #9ca3af;
                }
                
                @media (prefers-color-scheme: dark) {
                    .copy-button-bottom:active {
                        background: rgba(255, 255, 255, 0.12);
                    }
                }
                
                .copy-button-bottom svg {
                    margin-right: 5px;
                    flex-shrink: 0;
                    width: 12px;
                    height: 12px;
                }
                
                .copy-button-bottom.copying {
                    background: #f3f4f6;
                    border-color: #b1b8c0;
                    color: #24292f;
                }
                
                @media (prefers-color-scheme: dark) {
                    .copy-button-bottom.copying {
                        background: rgba(255, 255, 255, 0.12);
                        border-color: rgba(255, 255, 255, 0.25);
                        color: #c9d1d9;
                    }
                }
                
                .copy-button-bottom.copying .copy-icon,
                .copy-button-bottom.copying .copy-text {
                    display: none;
                }
                
                .copy-button-bottom.copying .copied-icon,
                .copy-button-bottom.copying .copied-text {
                    display: inline-flex !important;
                }
                
                /* Ensure button stays clickable during text generation */
                .copy-button-bottom {
                    pointer-events: auto !important;
                    z-index: 10 !important;
                }
                
                /* Animation for copy feedback */
                @keyframes copySuccess {
                    0% { transform: scale(1); }
                    50% { transform: scale(1.05); }
                    100% { transform: scale(1); }
                }
                
                .copy-button-bottom.success {
                    animation: copySuccess 0.3s ease;
                }
                code {
                    font-family: 'SF Mono', 'Menlo', 'Monaco', 'Courier New', monospace;
                    font-size: \(fontSize - 2)px;
                    background-color: var(--inline-code-background-color);
                    padding: 3px 6px;
                    border-radius: 6px;
                    color: var(--inline-code-text-color);
                }
                table {
                    border-collapse: collapse;
                    width: 100%;
                    margin-bottom: 1em;
                    word-wrap: break-word;
                    table-layout: fixed;
                    color: var(--text-color);
                }
                th, td {
                    border: 1px solid var(--border-color);
                    padding: 8px;
                    text-align: left;
                    vertical-align: top;
                }
                th {
                    background-color: var(--header-background-color);
                }
        
            
                /* Scrollbar style */
                ::-webkit-scrollbar {
                    width: 8px;
                    height: 8px;
                }
        
                ::-webkit-scrollbar-track {
                    background: transparent;
                }
        
                ::-webkit-scrollbar-thumb {
                    background: rgba(0, 0, 0, 0.2);
                    border-radius: 4px;
                }
        
                ::-webkit-scrollbar-thumb:hover {
                    background: rgba(0, 0, 0, 0.4);
                }
        
                /* Hide scrollbars by default */
                * {
                    scrollbar-width: none;
                    -ms-overflow-style: none;
                }
        
                *::-webkit-scrollbar {
                    display: none;
                }
        
                /* Scroll style for pre elements (code blocks) */
                pre {
                    scrollbar-width: thin;
                    scrollbar-color: rgba(0, 0, 0, 0.2) transparent;
                }
        
                pre::-webkit-scrollbar {
                    width: 8px;
                    height: 8px;
                }
        
                pre::-webkit-scrollbar-track {
                    background: transparent;
                }
        
                pre::-webkit-scrollbar-thumb {
                    background-color: rgba(0, 0, 0, 0.2);
                    border-radius: 4px;
                }
        
                pre::-webkit-scrollbar-thumb:hover {
                    background-color: rgba(0, 0, 0, 0.4);
                }
            </style>
        </head>
        <body>
            \(content)
            <script>
                hljs.highlightAll();
                
                // Enhanced copy function with better reliability
                function copyCodeAdvanced(button, codeBlockId) {
                    // Prevent multiple clicks during animation
                    if (button.classList.contains('copying')) {
                        return;
                    }
                    
                    try {
                        // Get the code content more reliably
                        const codeBlock = document.getElementById(codeBlockId);
                        if (!codeBlock) {
                            console.error('Code block not found:', codeBlockId);
                            return;
                        }
                        
                        const codeElement = codeBlock.querySelector('code');
                        if (!codeElement) {
                            console.error('Code element not found in block:', codeBlockId);
                            return;
                        }
                        
                        // Get the raw text content, preserving formatting
                        let codeText = codeElement.textContent || codeElement.innerText || '';
                        
                        // Clean up any extra whitespace but preserve code structure
                        codeText = codeText.trim();
                        
                        // Send to native clipboard handler
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.copyHandler) {
                            window.webkit.messageHandlers.copyHandler.postMessage(codeText);
                        } else {
                            // Fallback for testing
                            console.log('Code copied:', codeText);
                        }
                        
                        // Visual feedback
                        showCopyFeedback(button);
                        
                    } catch (error) {
                        console.error('Error copying code:', error);
                        showCopyError(button);
                    }
                }
                
                function showCopyFeedback(button) {
                    // Add copying state
                    button.classList.add('copying', 'success');
                    
                    // Update button content
                    const copyIcon = button.querySelector('.copy-icon');
                    const copyText = button.querySelector('.copy-text');
                    const copiedIcon = button.querySelector('.copied-icon');
                    const copiedText = button.querySelector('.copied-text');
                    
                    if (copyIcon) copyIcon.style.display = 'none';
                    if (copyText) copyText.style.display = 'none';
                    if (copiedIcon) copiedIcon.style.display = 'inline';
                    if (copiedText) copiedText.style.display = 'inline';
                    
                    // Reset after delay
                    setTimeout(() => {
                        button.classList.remove('copying', 'success');
                        
                        if (copyIcon) copyIcon.style.display = 'inline';
                        if (copyText) copyText.style.display = 'inline';
                        if (copiedIcon) copiedIcon.style.display = 'none';
                        if (copiedText) copiedText.style.display = 'none';
                    }, 2000);
                }
                
                function showCopyError(button) {
                    const originalText = button.innerHTML;
                    button.innerHTML = '❌ Error';
                    button.style.color = '#ef4444';
                    
                    setTimeout(() => {
                        button.innerHTML = originalText;
                        button.style.color = '';
                    }, 2000);
                }
                
                // Legacy function for backward compatibility
                function copyCode(button) {
                    try {
                        const codeElement = button.parentElement.nextElementSibling;
                        if (codeElement && codeElement.tagName === 'CODE') {
                            const code = codeElement.textContent || codeElement.innerText || '';
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.copyHandler) {
                                window.webkit.messageHandlers.copyHandler.postMessage(code.trim());
                            }
                            showCopyFeedback(button);
                        }
                    } catch (error) {
                        console.error('Error in legacy copy function:', error);
                        showCopyError(button);
                    }
                }
                
                // Ensure buttons remain clickable during dynamic content updates
                function ensureButtonsClickable() {
                    const copyButtons = document.querySelectorAll('.copy-button-bottom');
                    copyButtons.forEach(button => {
                        button.style.pointerEvents = 'auto';
                        button.style.zIndex = '9999';
                        button.style.position = 'relative';
                        button.style.isolation = 'isolate';
                    });
                }
                
                // Run immediately
                ensureButtonsClickable();
                
                // Run on DOM ready
                document.addEventListener('DOMContentLoaded', function() {
                    ensureButtonsClickable();
                    
                    // Set up mutation observer to maintain button functionality
                    const observer = new MutationObserver(function(mutations) {
                        ensureButtonsClickable();
                    });
                    
                    observer.observe(document.body, {
                        childList: true,
                        subtree: true,
                        characterData: true
                    });
                });
                
                // Also run periodically during streaming
                setInterval(ensureButtonsClickable, 100);
                
                // Text selection preservation functions
                let savedSelection = null;
                
                function saveSelection() {
                    const selection = window.getSelection();
                    if (selection.rangeCount > 0) {
                        const range = selection.getRangeAt(0);
                        savedSelection = {
                            startContainer: range.startContainer,
                            startOffset: range.startOffset,
                            endContainer: range.endContainer,
                            endOffset: range.endOffset,
                            collapsed: range.collapsed
                        };
                    }
                }
                
                function restoreSelection() {
                    if (savedSelection && window.getSelection) {
                        try {
                            const selection = window.getSelection();
                            const range = document.createRange();
                            
                            // Verify nodes still exist in DOM
                            if (document.contains(savedSelection.startContainer) && 
                                document.contains(savedSelection.endContainer)) {
                                range.setStart(savedSelection.startContainer, savedSelection.startOffset);
                                range.setEnd(savedSelection.endContainer, savedSelection.endOffset);
                                
                                selection.removeAllRanges();
                                selection.addRange(range);
                            }
                        } catch (e) {
                            // Selection restoration failed, clear saved selection
                            savedSelection = null;
                        }
                    }
                }
                
                // Save selection before any potential DOM updates
                document.addEventListener('selectionchange', function() {
                    saveSelection();
                });
                
                // Prevent text selection interference with copy buttons
                document.addEventListener('selectstart', function(e) {
                    if (e.target.closest('.copy-button-bottom')) {
                        e.preventDefault();
                    }
                });
            </script>
        </body>
        </html>
        """
    }
}

// MARK: - MessageViewModel

class MessageViewModel: ObservableObject {
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

// MARK: - NSImage Extension

extension NSImage {
    convenience init?(base64Encoded: String) {
        guard let imageData = Data(base64Encoded: base64Encoded) else {
            return nil
        }
        self.init(data: imageData)
    }
}

// MARK: - AttachmentsView

struct ImageGridView: View {
    let imageBase64Strings: [String]
    let imageSize: CGFloat
    let onTapImage: (String) -> Void
    var isGeneratedContent: Bool = false  // For AI-generated images
    
    var body: some View {
        if isGeneratedContent {
            // Vertical layout for generated images (larger display)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(imageBase64Strings, id: \.self) { imageData in
                    LazyImageView(
                        imageData: imageData,
                        size: max(imageSize, 400),
                        onTap: { onTapImage(imageData) },
                        isGeneratedImage: true
                    )
                }
            }
        } else {
            // Horizontal layout for user-attached images (thumbnails)
            HStack(spacing: 10) {
                ForEach(imageBase64Strings, id: \.self) { imageData in
                    LazyImageView(
                        imageData: imageData,
                        size: imageSize,
                        onTap: { onTapImage(imageData) },
                        isGeneratedImage: false
                    )
                }
            }
        }
    }
}

struct AttachmentsView: View {
    // Image properties
    let imageBase64Strings: [String]?
    let imageSize: CGFloat
    let onTapImage: (String) -> Void
    var onSelectDocument: (Data, String, String) -> Void

    // Document properties
    let documentBase64Strings: [String]?
    let documentFormats: [String]?
    let documentNames: [String]?
    
    // Pasted text properties
    let pastedTexts: [PastedTextInfo]?
    
    // Alignment control
    let alignment: HorizontalAlignment
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.fontSize) private var fontSize
    
    private var hasAttachments: Bool {
        return (imageBase64Strings?.isEmpty == false) ||
        (documentBase64Strings?.isEmpty == false) ||
        (pastedTexts?.isEmpty == false)
    }
    
    var body: some View {
        Group {
            if hasAttachments {
                HStack(spacing: 10) {
                    // Pasted text attachments (displayed as chips)
                    if let pastedTexts = pastedTexts, !pastedTexts.isEmpty {
                        ForEach(pastedTexts) { pastedText in
                            pastedTextContent(pastedText: pastedText)
                        }
                    }
                    
                    // Document attachments
                    if let documentBase64Strings = documentBase64Strings,
                       let documentFormats = documentFormats,
                       let documentNames = documentNames,
                       !documentBase64Strings.isEmpty {
                        
                        ForEach(0..<min(documentBase64Strings.count,
                                  min(documentFormats.count, documentNames.count)),
                               id: \.self) { index in
                            documentContent(name: documentNames[index], format: documentFormats[index])
                        }
                    }
                    
                    // Image attachments
                    if let imageBase64Strings = imageBase64Strings, !imageBase64Strings.isEmpty {
                        ForEach(imageBase64Strings, id: \.self) { imageData in
                            LazyImageView(imageData: imageData, size: imageSize) {
                                onTapImage(imageData)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Pasted text content view
    private func pastedTextContent(pastedText: PastedTextInfo) -> some View {
        Button(action: {
            if let data = pastedText.content.data(using: .utf8) {
                onSelectDocument(data, "txt", pastedText.filename)
            }
        }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(pastedText.preview)
                    .font(.system(size: fontSize - 3))
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 250, alignment: .leading)
                
                HStack(spacing: 6) {
                    Text("PASTED")
                        .font(.system(size: fontSize - 5, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                )
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ?
                          Color.white.opacity(0.08) :
                          Color.black.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pastedText.content, forType: .string)
            } label: {
                Label("Copy Content", systemImage: "doc.on.doc")
            }
        }
    }
    
    // Document content extracted to its own function
    private func documentContent(name: String, format: String) -> some View {
        let docColor = documentColor(for: format)
        let isTextFile = ["txt", "md"].contains(format.lowercased())
        let isPastedText = isTextFile && name.lowercased().contains("pasted")
        
        // Get text preview for all text documents (txt, md)
        let textPreview: String? = {
            if isTextFile,
               let index = documentNames?.firstIndex(of: name),
               let docStrings = documentBase64Strings,
               index < docStrings.count,
               let docData = Data(base64Encoded: docStrings[index]),
               let text = String(data: docData, encoding: .utf8) {
                let truncated = String(text.prefix(150))
                let cleaned = truncated
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.count > 100 ? String(cleaned.prefix(97)) + "..." : cleaned
            }
            return nil
        }()
        
        return Button(action: {
            if let index = documentNames?.firstIndex(of: name),
               let docStrings = documentBase64Strings,
               index < docStrings.count,
               let docData = Data(base64Encoded: docStrings[index]) {
                onSelectDocument(docData, format, name)
            }
        }) {
            if let preview = textPreview {
                // Text file preview style (Claude Desktop style)
                VStack(alignment: .leading, spacing: 6) {
                    Text(preview)
                        .font(.system(size: fontSize - 3))
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 250, alignment: .leading)
                    
                    HStack(spacing: 6) {
                        // Show "PASTED" for pasted text, filename for regular files
                        Text(isPastedText ? "PASTED" : name)
                            .font(.system(size: fontSize - 5, weight: .semibold))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        if !isPastedText {
                            Text("•")
                                .font(.system(size: fontSize - 5))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text(format.uppercased())
                                .font(.system(size: fontSize - 5, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                    )
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ?
                              Color.white.opacity(0.08) :
                              Color.black.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
            } else {
                // Regular document style
                HStack(spacing: 10) {
                    // Document icon with color
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(docColor.opacity(0.15))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: documentIcon(for: format))
                            .font(.system(size: 18))
                            .foregroundColor(docColor)
                    }
                    
                    // Document name
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: fontSize - 2, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text("\(format.uppercased()) document")
                            .font(.system(size: fontSize - 4))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ?
                              Color.gray.opacity(0.15) :
                              Color.gray.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(docColor.opacity(0.3), lineWidth: 1)
                )
            }
        }.buttonStyle(PlainButtonStyle())
    }
    
    // Helper function to determine document icon based on file extension
    private func documentIcon(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "txt", "md": return "doc.plaintext.fill"
        case "html": return "globe"
        default: return "doc.fill"
        }
    }
    
    // Helper function to determine document color based on file extension
    private func documentColor(for fileExtension: String) -> Color {
        switch fileExtension.lowercased() {
        case "pdf": return .red
        case "doc", "docx": return .blue
        case "xls", "xlsx", "csv": return .green
        case "txt", "md": return .gray
        case "html": return .orange
        default: return .gray
        }
    }
}

// MARK: - ImageViewerModal

struct ImageViewerModal: View {
    var image: NSImage
    var closeModal: () -> Void
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8).edgesIgnoringSafeArea(.all)
            
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .cornerRadius(10)
                .padding()
                .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                .contextMenu {
                    Button(action: {
                        copyNSImageToClipboard(image: image)
                    }) {
                        Text("Copy Image")
                        Image(systemName: "doc.on.doc")
                    }
                    
                    Button(action: {
                        saveImage(image)
                    }) {
                        Text("Save Image")
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: closeModal) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white)
                            .font(.title)
                            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 0)
                    }
                    .padding([.top, .trailing])
                    .buttonStyle(PlainButtonStyle())
                }
                Spacer()
            }
        }
    }
    
    func copyNSImageToClipboard(image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
    
    func saveImage(_ image: NSImage) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]
        savePanel.nameFieldStringValue = "image.png"
        
        savePanel.begin { response in
            if response == .OK {
                guard let url = savePanel.url else { return }
                
                if let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData) {
                    
                    let fileExtension = url.pathExtension.lowercased()
                    let imageData: Data?
                    
                    if fileExtension == "png" {
                        imageData = bitmap.representation(using: .png, properties: [:])
                    } else {
                        imageData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                    }
                    
                    if let data = imageData {
                        try? data.write(to: url)
                    }
                }
            }
        }
    }
}

// MARK: - NSImage Resizing Extension

extension NSImage {
    func resized(to targetSize: NSSize) -> NSImage? {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        defer { newImage.unlockFocus() }
        self.draw(in: NSRect(origin: .zero, size: targetSize),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: 1.0)
        return newImage
    }
    
    func resizedMaintainingAspectRatio(maxDimension: CGFloat) -> NSImage? {
        let aspectRatio = self.size.width / self.size.height
        let newSize: NSSize
        if self.size.width > self.size.height {
            newSize = NSSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = NSSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        return resized(to: newSize)
    }
    
    func compressedData(maxFileSize: Int, maxDimension: CGFloat, format: NSBitmapImageRep.FileType = .jpeg) -> Data? {
        guard let resizedImage = self.resizedMaintainingAspectRatio(maxDimension: maxDimension),
              let tiffRepresentation = resizedImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        
        var compressionFactor: CGFloat = 1.0
        var data = bitmapImage.representation(using: format, properties: [.compressionFactor: compressionFactor])
        
        while let imageData = data, imageData.count > maxFileSize && compressionFactor > 0 {
            compressionFactor -= 0.1
            data = bitmapImage.representation(using: format, properties: [.compressionFactor: compressionFactor])
        }
        
        return data
    }
}


