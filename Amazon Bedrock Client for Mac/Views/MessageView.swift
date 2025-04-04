//
//  MessageView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import MarkdownKit
import WebKit

// MARK: - LazyMarkdownView
struct LazyMarkdownView: View {
    let text: String
    let fontSize: CGFloat
    @State private var height: CGFloat = .zero
    
    private let parser: ExtendedMarkdownParser
    private let htmlGenerator: CustomHtmlGenerator
    
    init(text: String, fontSize: CGFloat) {
        self.text = text
        self.fontSize = fontSize
        self.parser = ExtendedMarkdownParser()
        self.htmlGenerator = CustomHtmlGenerator()
    }
    
    var body: some View {
        HTMLStringView(
            htmlContent: generateHTML(from: text),
            fontSize: fontSize,
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
        
        let codeHeader = """
        <div class="code-header"><span class="language">\(languageDisplay)</span><button onclick="copyCode(this)">\(copyButtonSVG) Copy code</button></div>
        """
        
        let code = lines.joined(separator: "")
        let escapedCode = escapeHtml(code)
        
        return """
        <pre>\(codeHeader)<code class="language-\(languageIdentifier)">\(escapedCode)</code></pre>
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
struct LazyImageView: View {
    let imageData: String
    let size: CGFloat
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    var body: some View {
        Button(action: onTap) {
            AsyncImage(url: URL(string: "data:image/jpeg;base64,\(imageData)")) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: size, height: size/2)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: size)
                case .failure:
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                        .frame(width: size, height: size/2)
                @unknown default:
                    EmptyView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        colorScheme == .dark ?
                        Color.white.opacity(0.15) :
                            Color.primary.opacity(0.1),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(action: {
                copyImageToClipboard(imageData: imageData)
            }) {
                Text("Copy Image")
                Image(systemName: "doc.on.doc")
            }
        }
    }
    
    private func copyImageToClipboard(imageData: String) {
        if let data = Data(base64Encoded: imageData),
           let image = NSImage(data: data) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Toggle button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: fontSize - 4))
                        .foregroundColor(.secondary)
                    
                    Text(header)
                        .font(.system(size: fontSize - 1, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
            .buttonStyle(.borderless)
            
            // Expandable content
            if isExpanded {
                LazyMarkdownView(text: text, fontSize: fontSize - 2)
                    .padding(.leading, fontSize / 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    colorScheme == .dark ?
                    Color.gray.opacity(0.1) :
                        Color.gray.opacity(0.05)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    colorScheme == .dark ?
                    Color.gray.opacity(0.2) :
                        Color.gray.opacity(0.1),
                    lineWidth: 0.5
                )
        )
    }
}

// MARK: - MessageView
struct MessageView: View {
    let message: MessageData
    let searchQuery: String  // For highlighting search matches
    var adjustedFontSize: CGFloat = -1 // One size smaller
    
    @StateObject var viewModel = MessageViewModel()
    @Environment(\.fontSize) private var fontSize: CGFloat
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var isHovering = false
    
    private let imageSize: CGFloat = 100
    
    var body: some View {
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
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ?
                          Color(NSColor.controlBackgroundColor).opacity(0.4) :
                            Color(NSColor.controlBackgroundColor).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        colorScheme == .dark ?
                        Color.gray.opacity(0.2) :
                            Color.gray.opacity(0.15),
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
        // Image grid (if present)
        if let imageBase64Strings = message.imageBase64Strings,
           !imageBase64Strings.isEmpty {
            ImageGridView(
                imageBase64Strings: imageBase64Strings,
                imageSize: imageSize
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
                    fontSize: fontSize + adjustedFontSize - 2
                )
                .padding(.vertical, 2)
            }
            
            // Expandable tool result section
            if let toolResult = message.toolResult, !toolResult.isEmpty {
                ExpandableMarkdownItem(
                    header: "Tool Result",
                    text: toolResult,
                    fontSize: fontSize + adjustedFontSize - 2
                )
                .padding(.vertical, 2)
            }
            
            // Tool use information display
            if let toolUse = message.toolUse {
                ExpandableMarkdownItem(
                    header: "Using tool: \(toolUse.name)",
                    text: formatToolInput(toolUse.input),
                    fontSize    : fontSize + adjustedFontSize - 2
                )
                .padding(.vertical, 2)
            }
            
            // Main message content
            LazyMarkdownView(text: message.text, fontSize: fontSize + adjustedFontSize)
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
        let messageBackground = RoundedRectangle(cornerRadius: 12)
            .fill(colorScheme == .dark ?
                  Color.gray.opacity(0.25) :
                  Color.gray.opacity(0.15))
        
        let messageBorder = RoundedRectangle(cornerRadius: 12)
            .stroke(
                colorScheme == .dark ?
                Color.gray.opacity(0.25) :
                Color.gray.opacity(0.2),
                lineWidth: 0.5
            )
        
        return ZStack(alignment: .bottomTrailing) {
            // Main message content with optimized rendering
            VStack(alignment: .trailing, spacing: 6) {
                // Only load attachments if they exist
                if (message.imageBase64Strings?.isEmpty == false) ||
                   (message.documentBase64Strings?.isEmpty == false) {
                    
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
                        alignment: .trailing
                    )
                }
                
                // Only create text if non-empty
                if !message.text.isEmpty {
                    textContent
                }
            }
            .padding(10)
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
            if searchQuery.isEmpty {
                // Simple text without highlighting when no search
                Text(message.text)
                    .font(.system(size: fontSize + adjustedFontSize))
                    .foregroundColor(.primary)
            } else {
                // Only use expensive highlighting when needed
                createHighlightedText(message.text)
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

    // Text highlighting for search matches
    private func createHighlightedText(_ text: String) -> SwiftUI.Text {
        if #available(macOS 12.0, *) {
            var attributed = AttributedString(text)
            let lowerSearch = searchQuery.lowercased()
            
            guard !lowerSearch.isEmpty else {
                return Text(attributed)
            }
            
            let lowerText = text.lowercased()
            var searchStartIndex = lowerText.startIndex
            while let range = lowerText.range(of: lowerSearch, options: .caseInsensitive, range: searchStartIndex..<lowerText.endIndex) {
                if let start = AttributedString.Index(range.lowerBound, within: attributed),
                   let end = AttributedString.Index(range.upperBound, within: attributed) {
                    let attrRange = start..<end
                    attributed[attrRange].backgroundColor = .yellow.opacity(0.8)
                    attributed[attrRange].foregroundColor = .black
                }
                searchStartIndex = range.upperBound
            }
            
            return Text(attributed)
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
    @Binding var dynamicHeight: CGFloat
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        // Set up message handler for copy action
        config.userContentController.add(context.coordinator, name: "copyHandler")
        
        let webView = CustomWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        
        // Disable WKWebView's scrolling
        if let scrollView = webView.enclosingScrollView {
            scrollView.hasVerticalScroller = false
            scrollView.verticalScrollElasticity = .none
            scrollView.scrollerStyle = .overlay
        }
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadHTMLString(wrapHTMLContent(htmlContent), baseURL: nil)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: HTMLStringView
        
        init(_ parent: HTMLStringView) {
            self.parent = parent
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
              href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.5.1/styles/github-dark.min.css"
            >
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.5.1/highlight.min.js"></script>
            <style>
                :root {
                    --background-color: #ffffff;
                    --text-color: #24292e;
                    --secondary-text-color: #6a737d;
                    --code-background-color: #f6f8fa;
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
                        --code-background-color: #161b22;
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
                pre {
                    position: relative;
                    background-color: var(--code-background-color);
                    padding: 0;
                    border-radius: 6px;
                    overflow: auto;
                    white-space: pre;
                    font-family: 'SF Mono', 'Menlo', 'Monaco', 'Courier New', monospace;
                    font-size: \(fontSize - 2)px;
                    color: var(--code-text-color);
                    margin: 16px 0;
                    max-width: 100%;
                }
                pre code {
                    display: block;
                    padding: 12px;
                    background-color: var(--code-background-color);
                    color: var(--code-text-color);
                    margin: 0;
                }
                .code-header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    background-color: #21262d;
                    padding: 4px 8px;
                    font-size: 12px;
                    color: #8b949e;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Helvetica', 'Arial', sans-serif;
                }
                .code-header .language {
                    font-weight: 500;
                    margin-left: 8px; /* Added spacing for alignment */
                }
                .code-header button {
                    background: none;
                    border: none;
                    color: #8b949e;
                    cursor: pointer;
                    display: flex;
                    align-items: center;
                    font-size: 12px;
                }
                .code-header button svg {
                    margin-right: 4px;
                }
                code {
                    font-family: 'SF Mono', 'Menlo', 'Monaco', 'Courier New', monospace;
                    font-size: \(fontSize - 2)px;
                    background-color: var(--inline-code-background-color);
                    padding: 2px 4px;
                    border-radius: 0 0 4px 4px;
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
        
                function copyCode(button) {
                    var code = button.parentElement.nextElementSibling.innerText;
                    window.webkit.messageHandlers.copyHandler.postMessage(code);
        
                    button.innerHTML = '<svg aria-hidden="true" height="16" viewBox="0 0 16 16" width="16"><path fill="currentColor" d="M3 2.5A1.5 1.5 0 014.5 1h6A1.5 1.5 0 0112 2.5V3h.5A1.5 1.5 0 0114 4.5v8A1.5 1.5 0 0112.5 14h-6A1.5 1.5 0 015 12.5V12H4.5A1.5 1.5 0 013 10.5v-8zM5 12.5a.5.5 0 00.5.5h6a.5.5 0 00.5-.5v-8a.5.5 0 00-.5-.5H12v6A1.5 1.5 0 0110.5 12H5v.5zM4 10.5v-8a.5.5 0 01.5-.5H5v6A1.5 1.5 0 006.5 9H12v1.5a.5.5 0 01-.5.5H5A1.5 1.5 0 013.5 9V4.5a.5.5 0 01.5-.5H4v6z"></path></svg> Copied';
                    setTimeout(function() {
                        button.innerHTML = '<svg aria-hidden="true" height="16" viewBox="0 0 16 16" width="16"><path fill="currentColor" d="M3 2.5A1.5 1.5 0 014.5 1h6A1.5 1.5 0 0112 2.5V3h.5A1.5 1.5 0 0114 4.5v8A1.5 1.5 0 0112.5 14h-6A1.5 1.5 0 015 12.5V12H4.5A1.5 1.5 0 013 10.5v-8zM5 12.5a.5.5 0 00.5.5h6a.5.5 0 00.5-.5v-8a.5.5 0 00-.5-.5H12v6A1.5 1.5 0 0110.5 12H5v.5zM4 10.5v-8a.5.5 0 01.5-.5H5v6A1.5 1.5 0 006.5 9H12v1.5a.5.5 0 01-.5.5H5A1.5 1.5 0 013.5 9V4.5a.5.5 0 01.5-.5H4v6z"></path></svg> Copy code';
                    }, 2000);
                }
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
    
    var body: some View {
        HStack(spacing: 10) {
            ForEach(imageBase64Strings, id: \.self) { imageData in
                LazyImageView(imageData: imageData, size: imageSize) {
                    onTapImage(imageData)
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
    
    // Alignment control
    let alignment: HorizontalAlignment
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.fontSize) private var fontSize
    
    private var hasAttachments: Bool {
        return (imageBase64Strings?.isEmpty == false) ||
        (documentBase64Strings?.isEmpty == false)
    }
    
    var body: some View {
        Group {
            if hasAttachments {
                HStack(spacing: 10) {
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
    
    // Document content extracted to its own function
    private func documentContent(name: String, format: String) -> some View {
        Button(action: {
            if let index = documentNames?.firstIndex(of: name),
               let docStrings = documentBase64Strings,
               index < docStrings.count,
               let docData = Data(base64Encoded: docStrings[index]) {
                onSelectDocument(docData, format, name)
            }
        }) {
            HStack(spacing: 10) {
                // Document icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ?
                              Color.gray.opacity(0.2) :
                                Color.gray.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: documentIcon(for: format))
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
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
            .padding(6) // Reduced padding
            .background(
                RoundedRectangle(cornerRadius: 8) // Reduced corner radius
                    .fill(colorScheme == .dark ?
                          Color.gray.opacity(0.15) :
                            Color.gray.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        colorScheme == .dark ?
                        Color.gray.opacity(0.3) :
                            Color.gray.opacity(0.2),
                        lineWidth: 1
                    )
            )
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
