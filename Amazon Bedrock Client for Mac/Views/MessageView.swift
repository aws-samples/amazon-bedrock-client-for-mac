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
    override func generate(block: Block, tight: Bool = false) -> String {
        switch block {
        case .fencedCode(let info, let lines):
            return generateCustomCodeBlock(info: info, lines: lines)
        default:
            return super.generate(block: block, tight: tight)
        }
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
    
    var body: some View {
        Button(action: onTap) {
            AsyncImage(url: URL(string: "data:image/jpeg;base64,\(imageData)")) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: size)
                case .failure:
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                @unknown default:
                    EmptyView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
            )
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

struct ExpandableMarkdownItem: View {
    @State private var isExpanded = false
    
    let header: String
    let text: String
    let fontSize: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 접기/펼치기 버튼
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Text(header)
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundColor(.gray)  // 좀 더 연한 회색
                    Spacer()
                }
            }
            .buttonStyle(.borderless)
            
            // 펼쳐졌을 때 내용 표시
            if isExpanded {
                // 추가 문구를 원한다면 text 끝에 이어붙입니다
                
                LazyMarkdownView(text: text, fontSize: fontSize - 2)
            }
        }
    }
}

// MARK: - MessageView
struct MessageView: View {
    let message: MessageData
    let searchQuery: String  // For user messages partial highlight
    
    @StateObject var viewModel = MessageViewModel()
    @Environment(\.fontSize) private var fontSize: CGFloat
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
                    nonUserMessageBubble
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
    
    // MARK: - Non-user bubble (HTML-based)
    private var nonUserMessageBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            messageHeader
            nonUserContent
            copyButton
                .opacity(isHovering ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .padding()
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    @ViewBuilder
    private var nonUserContent: some View {
        if let imageBase64Strings = message.imageBase64Strings,
           !imageBase64Strings.isEmpty {
            ImageGridView(
                imageBase64Strings: imageBase64Strings,
                imageSize: imageSize
            ) { imageData in
                viewModel.selectImage(with: imageData)
            }
        }
        VStack(spacing: 8) {
            // Expandable "thinking" section
            if let thinking = message.thinking, !thinking.isEmpty {
                ExpandableMarkdownItem(
                    header: "Thinking",
                    text: thinking,
                    fontSize: fontSize - 2
                )
                .padding(.vertical, 2)
            }
            
            // Expandable tool result section
            if let toolResult = message.toolResult, !toolResult.isEmpty {
                ExpandableMarkdownItem(
                    header: "Tool Result",
                    text: toolResult,
                    fontSize: fontSize - 2
                )
                .padding(.vertical, 2)
                .cornerRadius(8)
            }
            
            // Tool use information display
            if let toolUse = message.toolUse {
                ExpandableMarkdownItem(
                    header: "Using tool: \(toolUse.name)",
                    text: formatToolInput(toolUse.input),
                    fontSize: fontSize - 2
                )
                .padding(.vertical, 2)
            }
            
            // Main message content
            LazyMarkdownView(text: message.text, fontSize: fontSize)
                .sheet(isPresented: $viewModel.isShowingImageModal) {
                    if let data = viewModel.selectedImageData,
                       let imageToShow = NSImage(base64Encoded: data) {
                        ImageViewerModal(image: imageToShow) {
                            viewModel.clearSelection()
                        }
                    }
                }
        }
    }

    // Helper function to format tool input parameters
    private func formatToolInput(_ input: [String: String]) -> String {
        var result = "```json\n"
        result += "{\n"
        for (key, value) in input.sorted(by: { $0.key < $1.key }) {
            result += "  \"\(key)\": \"\(value)\",\n"
        }
        if !input.isEmpty {
            result.removeLast(2)  // Remove the last comma and newline
            result += "\n"
        }
        result += "}\n```"
        return result
    }
    
    // MARK: - User bubble (possible partial highlight + images)
    private var userMessageBubble: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if let imageBase64Strings = message.imageBase64Strings, !imageBase64Strings.isEmpty {
                ImageGridView(imageBase64Strings: imageBase64Strings, imageSize: imageSize) { imageData in
                    viewModel.selectImage(with: imageData)
                }
                .frame(alignment: .trailing)
            }
            
            highlightedText(message.text)
                .font(.system(size: fontSize))
                .foregroundColor(.primary)
        }
        .sheet(isPresented: $viewModel.isShowingImageModal) {
            if let imageData = viewModel.selectedImageData,
               let imageToShow = NSImage(base64Encoded: imageData) {
                ImageViewerModal(image: imageToShow) {
                    viewModel.clearSelection()
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    @available(macOS 12.0, *)
    private func highlightedText(_ text: String) -> SwiftUI.Text {
        var attributed = AttributedString(text)
        let lowerSearch = searchQuery.lowercased()
        
        guard !lowerSearch.isEmpty else {
            return SwiftUI.Text(attributed)
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
        
        return SwiftUI.Text(attributed)
    }
    
    // MARK: - Shared for non-user and user
    private var messageHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(message.user)
                .font(.system(size: fontSize))
                .bold()
            Text(format(date: message.sentTime))
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }
    
    private var copyButton: some View {
        Button(action: copyMessageToClipboard) {
            Image(systemName: "doc.on.doc")
                .foregroundColor(.secondary)
                .font(.system(size: 16))
        }
        .buttonStyle(PlainButtonStyle())
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
    @Published var currentHighlightedMatch: (messageIndex: Int, matchPositionIndex: Int)? = nil
    
    func selectImage(with data: String) {
        self.selectedImageData = data
        self.isShowingImageModal = true
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

// MARK: - ImageGridView

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

// MARK: - ImageViewerModal

struct ImageViewerModal: View {
    var image: NSImage
    var closeModal: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8).edgesIgnoringSafeArea(.all)
            
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .cornerRadius(10)
                .padding()
                .contextMenu {
                    Button(action: {
                        copyNSImageToClipboard(image: image)
                    }) {
                        Text("Copy Image")
                        Image(systemName: "doc.on.doc")
                    }
                }
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: closeModal) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white)
                            .font(.title)
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
