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

private final class MarkdownRenderCache: @unchecked Sendable {
    static let shared = MarkdownRenderCache()
    private let values = NSCache<NSString, NSString>()
    private let documents = NSCache<NSString, Document>()
    // The parser finishes before this immutable tree is handed to the UI.
    final class Document: NSObject, @unchecked Sendable {
        let block: Block
        let isNative: Bool
        let rows: [MarkdownLayoutRow]
        init(_ block: Block, sourceBytes: Int) {
            self.block = block
            let candidates = sourceBytes <= 4_000 && MarkdownRenderCache.supportsNative(block) ?
                MarkdownLayoutRow.flatten(block) : []
            // Preserve the original WebKit path for long documents. Hundreds
            // of selectable SwiftUI blocks create an expensive view graph.
            isNative = sourceBytes <= 4_000 && candidates.count <= 48 && MarkdownRenderCache.supportsNative(block)
            rows = isNative ? candidates : []
        }
    }
    private init() {
        values.totalCostLimit = 8 * 1_024 * 1_024; values.countLimit = 160
        documents.totalCostLimit = 4 * 1_024 * 1_024; documents.countLimit = 256
    }
    func document(_ text: String, cache: Bool = true) -> Document {
        if let cached = documents.object(forKey: text as NSString) { return cached }
        let document = Document(ExtendedMarkdownParser().parse(text), sourceBytes: text.utf8.count)
        // Do not retain hundreds of increasingly large prefixes of a live reply.
        if cache { documents.setObject(document, forKey: text as NSString, cost: text.utf8.count * 3) }
        return document
    }
    func cachedDocument(_ text: String) -> Document? { documents.object(forKey: text as NSString) }
    func html(_ text: String, document: Document, cache: Bool) -> String {
        if let cached = values.object(forKey: text as NSString) { return cached as String }
        let result = CustomHtmlGenerator().generate(doc: document.block)
        if cache { values.setObject(result as NSString, forKey: text as NSString, cost: text.utf8.count + result.utf8.count) }
        return result
    }
    private static func supportsNative(_ block: Block) -> Bool {
        func inline(_ text: MarkdownKit.Text) -> Bool {
            text.allSatisfy {
                switch $0 {
                case .html, .image: return false
                case .emph(let children), .strong(let children), .link(let children, _, _): return inline(children)
                default: return true
                }
            }
        }
        switch block {
        case .document(let children), .blockquote(let children), .list(_, _, let children), .listItem(_, _, let children):
            return children.allSatisfy(supportsNative)
        case .paragraph(let text), .heading(_, let text): return inline(text)
        case .table(let header, _, let rows): return header.allSatisfy(inline) && rows.allSatisfy { $0.allSatisfy(inline) }
        case .htmlBlock, .custom: return false
        default: return true
        }
    }
}

private struct MarkdownSnapshot: Sendable {
    let source: String
    let document: MarkdownRenderCache.Document
    let html: String?

    init(source: String, cache: Bool) {
        self.source = source
        document = MarkdownRenderCache.shared.document(source, cache: cache)
        html = document.isNative ? nil : MarkdownRenderCache.shared.html(source, document: document, cache: cache)
    }
}

private actor MarkdownParsingWorker {
    static let shared = MarkdownParsingWorker()

    func parse(_ text: String, cache: Bool) -> MarkdownSnapshot? {
        // A superseded stream update must not build up a queue of old parses.
        guard !Task.isCancelled else { return nil }
        return MarkdownSnapshot(source: text, cache: cache)
    }
}

enum MarkdownPreparation {
    static func prewarm(_ texts: [String]) async {
        for text in texts where !text.isEmpty {
            guard !Task.isCancelled else { return }
            _ = await MarkdownParsingWorker.shared.parse(text, cache: true)
        }
    }

    static func usesWebRenderer(_ text: String) -> Bool {
        if let document = MarkdownRenderCache.shared.cachedDocument(text) { return !document.isNative }
        return text.utf8.count > 4_000
    }
}

@MainActor
private final class MarkdownMessageRenderer: ObservableObject {
    @Published private(set) var html: String?
    let native: MarkdownDocumentState
    private var source: String
    private var isFinal: Bool

    init(text: String, isStreaming: Bool) {
        if let cached = MarkdownRenderCache.shared.cachedDocument(text) {
            native = MarkdownDocumentState(rows: cached.rows, isStreaming: isStreaming)
            html = cached.isNative ? nil : MarkdownRenderCache.shared.html(text, document: cached, cache: !isStreaming)
            source = text
            isFinal = !isStreaming
        } else {
            // Cold documents are parsed by the worker. Never make a sidebar
            // click wait for a large or malformed Markdown/HTML document.
            native = MarkdownDocumentState(rows: [], isStreaming: isStreaming)
            html = nil
            source = ""
            isFinal = isStreaming
        }
    }

    func update(text: String, isStreaming: Bool) async {
        guard source != text || isFinal == isStreaming else { return }
        guard let next = await MarkdownParsingWorker.shared.parse(text, cache: !isStreaming),
              !Task.isCancelled else { return }
        if next.document.isNative {
            native.update(rows: next.document.rows, isStreaming: isStreaming)
        }
        // Updating native text must not invalidate the entire document view.
        if html != next.html { html = next.html }
        source = text
        isFinal = !isStreaming
    }
}

private enum CodeHighlightAssets {
    static let javascript = resource("highlight.min", extension: "js")
        .replacingOccurrences(of: "</script", with: "<\\/script")
    static let lightCSS = resource("highlight-github", extension: "css")
    static let darkCSS = resource("highlight-github-dark", extension: "css")

    private static func resource(_ name: String, extension fileExtension: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension),
              let value = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return value
    }
}

@MainActor
private enum MarkdownWebEnvironment {
    static let dataStore = WKWebsiteDataStore.nonPersistent()
}

// MARK: - LazyMarkdownView
struct LazyMarkdownView: View {
    let text: String
    let fontSize: CGFloat
    let searchRanges: [NSRange]
    let selectedSearchIndex: Int?
    var isStreaming: Bool
    @StateObject private var renderer: MarkdownMessageRenderer
    @State private var height: CGFloat = 0
    @State private var nativeHeight: CGFloat = 80

    private struct Revision: Equatable {
        let text: String
        let isStreaming: Bool
    }
    
    init(text: String, fontSize: CGFloat, searchRanges: [NSRange] = [], isStreaming: Bool = false, selectedSearchIndex: Int? = nil) {
        self.text = text
        self.fontSize = fontSize
        self.searchRanges = searchRanges
        self.selectedSearchIndex = selectedSearchIndex
        self.isStreaming = isStreaming
        _renderer = StateObject(wrappedValue: MarkdownMessageRenderer(text: text, isStreaming: isStreaming))
    }
    
    var body: some View {
        Group {
            if let html = renderer.html {
                HTMLStringView(
                    htmlContent: html,
                    fontSize: fontSize,
                    searchQuery: searchTerms.first,
                    selectedMatchIndex: selectedSearchIndex,
                    dynamicHeight: $height
                )
                .frame(maxWidth: .infinity)
                .frame(height: height > 0 ? height : nativeHeight)
            } else {
                WorkbenchMarkdown(document: renderer.native, fontSize: fontSize, highlights: searchTerms)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        if $0 > 0, nativeHeight != $0 { nativeHeight = $0 }
                    }
            }
        }
        .task(id: Revision(text: text, isStreaming: isStreaming)) {
            await renderer.update(text: text, isStreaming: isStreaming)
        }
    }

    private var searchTerms: [String] {
        let source = text as NSString
        return Array(Set(searchRanges.compactMap {
            guard $0.location != NSNotFound, $0.location >= 0, $0.length > 0, NSMaxRange($0) <= source.length else { return nil }
            return source.substring(with: $0)
        })).sorted()
    }
}

// MARK: - CustomHtmlGenerator
class CustomHtmlGenerator: HtmlGenerator {
    private var codeBlockIndex = 0
    override func generate(block: Block, parent: Parent, tight: Bool = false) -> String {
        switch block {
        case .fencedCode(let info, let lines):
            return generateCustomCodeBlock(info: info, lines: lines)
        default:
            return super.generate(block: block, parent: parent, tight: tight)
        }
    }
    
    override func generate(doc: Block) -> String {
        codeBlockIndex = 0
        guard case .document(let blocks) = doc else {
            preconditionFailure("cannot generate HTML from \(doc)")
        }
        return self.generate(blocks: blocks, parent: .none)
    }
    
    private func generateCustomCodeBlock(info: String?, lines: Lines) -> String {
        let language = info?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let languageIdentifier = escapeHtml(language)
        let languageDisplay = language.isEmpty ? "Code" : escapeHtml(language.capitalized)
        
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
        codeBlockIndex += 1
        let codeBlockId = "code-block-\(codeBlockIndex)"
        
        return """
        <div class="code-block-container">
            <div class="code-header">
                <span class="language">\(languageDisplay)</span>
                <button class="copy-button-bottom" data-code-id="\(codeBlockId)">
                    <span class="copy-icon">\(copyButtonSVG)</span>
                    <span class="copy-text">Copy code</span>
                    <span class="copied-icon" style="display: none;">\(checkmarkSVG)</span>
                    <span class="copied-text" style="display: none;">Copied!</span>
                </button>
            </div>
            <pre id="\(codeBlockId)"><code class="language-\(languageIdentifier)">\(escapedCode)</code></pre>
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
struct LazyImageView: View {
    let imageData: String
    let size: CGFloat
    let onTap: () -> Void
    var isGeneratedImage: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var loadedImage: PreparedImagePreview?
    @State private var isLoading = true
    
    private var displaySize: CGFloat {
        isGeneratedImage ? max(size, 400) : size
    }
    
    var body: some View {
        Button(action: onTap) {
            Group {
                if let image = loadedImage {
                    Image(decorative: image.preview, scale: 1)
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
        .accessibilityLabel(isGeneratedImage ? "Open generated image" : "Open image attachment")
        .task(id: imageData) { await loadImageAsync() }
        .contextMenu {
            Button(action: copyImageToClipboard) {
                Label("Copy Image", systemImage: "doc.on.doc")
            }
            
            Button(action: saveImageToFile) {
                Label("Save Image...", systemImage: "square.and.arrow.down")
            }
        }
    }
    
    private func loadImageAsync() async {
        isLoading = true
        let directory = URL(fileURLWithPath: SettingManager.shared.defaultDirectory).appendingPathComponent("generated_images")
        do {
            let image = try await WorkbenchImageIO.shared.load(.stored(imageData, directory: directory),
                                                               maximumPixelSize: isGeneratedImage ? 1_024 : 480)
            try Task.checkCancellation()
            loadedImage = image
            isLoading = false
        } catch is CancellationError {
        } catch { isLoading = false }
    }
    
    private func copyImageToClipboard() {
        guard let image = loadedImage else { return }
        Task {
            do {
                let data = try await WorkbenchImageIO.shared.export(image, as: .png)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setData(data, forType: .png)
            } catch { WorkbenchStore.shared.errorMessage = error.localizedDescription }
        }
    }
    
    private func saveImageToFile() {
        guard let image = loadedImage else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]
        savePanel.nameFieldStringValue = "generated-image.png"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                Task {
                    do { try await WorkbenchImageIO.shared.save(image, to: url) }
                    catch { WorkbenchStore.shared.errorMessage = error.localizedDescription }
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

// MARK: - GeneratedVideoView (for AI-generated videos)
import AVKit

struct GeneratedVideoView: View {
    let videoUrl: URL
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var player: AVPlayer?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Video player
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit).frame(maxWidth: 640)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                colorScheme == .dark ?
                                Color.white.opacity(0.15) :
                                    Color.primary.opacity(0.1),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
            } else {
                // Loading placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    .aspectRatio(16 / 9, contentMode: .fit).frame(maxWidth: 640)
                    .overlay(
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Loading video...")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    )
            }
            
            // Video controls
            HStack(spacing: 12) {
                Button(action: { openInFinder() }) {
                    Label("Show in Finder", systemImage: "folder")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                
                Button(action: { saveVideoToFile() }) {
                    Label("Save Video...", systemImage: "square.and.arrow.down")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
            }
            .foregroundColor(.secondary)
        }
        .onAppear {
            loadVideo()
        }
        .onDisappear {
            player?.pause()
        }
    }
    
    private func loadVideo() {
        guard FileManager.default.fileExists(atPath: videoUrl.path) else { return }
        player = AVPlayer(url: videoUrl)
    }
    
    private func openInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([videoUrl])
    }
    
    private func saveVideoToFile() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.mpeg4Movie]
        savePanel.nameFieldStringValue = "generated-video-\(Date().timeIntervalSince1970).mp4"
        
        savePanel.begin { response in
            if response == .OK, let destinationUrl = savePanel.url {
                try? FileManager.default.copyItem(at: videoUrl, to: destinationUrl)
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
                    searchRanges: searchRanges,
                    isStreaming: isStreaming
                )
                .padding(.leading, fontSize / 2)
            }
        }
        .padding(.vertical, 6)
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
    var onAction: ((WorkbenchMessageAction, MessageData) -> Void)?

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message == rhs.message && lhs.searchResult == rhs.searchResult &&
        lhs.adjustedFontSize == rhs.adjustedFontSize && lhs.isStreaming == rhs.isStreaming &&
        lhs.showTimestamp == rhs.showTimestamp && lhs.canModify == rhs.canModify && lhs.canRetry == rhs.canRetry
    }
    
    @StateObject var viewModel = MessageViewModel()
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
                        WorkbenchActionMenu {
                            Button("Branch from here") { onAction?(.branch, message) }.disabled(!canModify)
                            Button("Message details…") { onAction?(.details, message) }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).frame(width: 28, height: 28)
                        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .foregroundStyle(.secondary).help("Message actions").accessibilityLabel("Message actions")
                    }
                    if showTimestamp { Text(format(date: message.sentTime)).font(WorkbenchStyle.detail).foregroundStyle(.secondary) }
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
                    isStreaming: isStreaming && message.text.isEmpty
                )
                .padding(.vertical, 2)
            }
            
            // Main message content (skip if empty - e.g., video-only messages)
            if !message.text.isEmpty {
                if message.isError {
                    WorkbenchRequestError(source: message.text)
                } else {
                    LazyMarkdownView(
                        text: message.text,
                        fontSize: fontSize + adjustedFontSize,
                        searchRanges: searchResult?.ranges ?? [],
                        isStreaming: isStreaming,
                        selectedSearchIndex: searchResult?.selectedRangeIndex
                    )
                }
            }
            if let calls = message.toolUses, !calls.isEmpty { WorkbenchToolCallsView(calls: calls) }
            
            // Tool use information display
            if message.toolUses?.isEmpty != false, let toolUse = message.toolUse {
                ExpandableMarkdownItem(
                    header: "Using tool: \(toolUse.name)",
                    text: formatToolInput(toolUse.input),
                    fontSize: fontSize + adjustedFontSize - 2,
                    searchRanges: searchResult?.ranges ?? []
                )
                .padding(.vertical, 2)
            }

            // Expandable tool result section
            if message.toolUses?.isEmpty != false, let toolResult = message.toolResult, !toolResult.isEmpty {
                ExpandableMarkdownItem(
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
                    source: .stored(data, directory: URL(fileURLWithPath: SettingManager.shared.defaultDirectory).appendingPathComponent("generated_images")),
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
                    WorkbenchActionMenu {
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
                    source: .stored(imageData, directory: URL(fileURLWithPath: SettingManager.shared.defaultDirectory).appendingPathComponent("generated_images")),
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

// MARK: - CustomWKWebView

class CustomWKWebView: WKWebView {
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        // Do not depend on WebKit's private menu tags or localized titles.
        menu.removeAllItems()
        menu.autoenablesItems = false
        let copy = NSMenuItem(title: "Copy", action: #selector(copySelectedText(_:)), keyEquivalent: "")
        copy.target = self
        menu.addItem(copy)
        menu.addItem(.separator())
        let select = NSMenuItem(title: "Select All", action: #selector(selectResponse(_:)), keyEquivalent: "")
        select.target = self
        menu.addItem(select)
    }

    @objc private func copySelectedText(_ sender: Any?) {
        callAsyncJavaScript("return window.getSelection()?.toString() ?? '';",
                            arguments: [:], in: nil, in: .page) { result in
            guard case .success(let value) = result, let text = value as? String, !text.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
    @objc private func selectResponse(_ sender: Any?) {
        evaluateJavaScript("""
        const range = document.createRange();
        range.selectNodeContents(document.getElementById('bedrock-content') || document.body);
        const selection = window.getSelection();
        selection.removeAllRanges(); selection.addRange(range);
        """)
    }

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
           let scroll = enclosingScrollView {
            // Forward directly to the conversation's scroll view. A SwiftUI
            // hosting responder can route the event back into this WebView.
            scroll.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }
}

// MARK: - HTMLStringView

struct HTMLStringView: NSViewRepresentable {
    let htmlContent: String
    let fontSize: CGFloat
    let searchQuery: String?
    let selectedMatchIndex: Int?
    @Binding var dynamicHeight: CGFloat
    
    init(htmlContent: String, fontSize: CGFloat, searchQuery: String? = nil, selectedMatchIndex: Int? = nil, dynamicHeight: Binding<CGFloat>) {
        self.htmlContent = htmlContent
        self.fontSize = fontSize
        self.searchQuery = searchQuery
        self.selectedMatchIndex = selectedMatchIndex
        self._dynamicHeight = dynamicHeight
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = MarkdownWebEnvironment.dataStore
        
        // Set up message handler for copy action
        config.userContentController.add(context.coordinator, name: "copyHandler")
        config.userContentController.add(context.coordinator, name: "searchHandler")
        config.userContentController.add(context.coordinator, name: "heightHandler")
        
        let webView = CustomWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        let contentChanged = context.coordinator.sourceHTML != htmlContent ||
                             context.coordinator.sourceFontSize != fontSize
        let selectionChanged = context.coordinator.sourceSearchQuery != searchQuery ||
                               context.coordinator.sourceSelectedIndex != selectedMatchIndex
        guard contentChanged || selectionChanged else { return }
        context.coordinator.sourceHTML = htmlContent
        context.coordinator.sourceFontSize = fontSize
        context.coordinator.sourceSearchQuery = searchQuery
        context.coordinator.sourceSelectedIndex = selectedMatchIndex
        if !context.coordinator.hasStartedLoading {
            context.coordinator.hasStartedLoading = true
            nsView.loadHTMLString(addSearchHighlights(to: wrapHTMLContent(htmlContent)), baseURL: nil)
        } else if contentChanged {
            context.coordinator.applyLatestContent(to: nsView)
        }
        if selectionChanged { context.coordinator.selectSearch(in: nsView) }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        nsView.stopLoading()
        nsView.navigationDelegate = nil
        for name in ["copyHandler", "searchHandler", "heightHandler"] {
            nsView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }
    
    private func addSearchHighlights(to html: String) -> String {
        // Enhanced CSS for highlighting with better visibility
        let highlightCSS = """
        <style>
        .search-highlight {
            background-color: #ffff00 !important;
            color: #000000 !important;
            border-radius: 2px !important;
        }
        .search-highlight-current {
            background-color: #f6cf69 !important;
            color: #202124 !important;
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
        var sourceSearchQuery: String?
        var sourceSelectedIndex: Int?
        var hasStartedLoading = false
        var sourceHTML: String?
        var sourceFontSize: CGFloat?
        private var isReady = false
        private var isApplyingContent = false
        private var appliedHTML: String?
        private var appliedFontSize: CGFloat?
        private var active = true
        private var pendingSearch: (query: String, index: Int)?
        private var searchGeneration = 0
        
        init(_ parent: HTMLStringView) {
            self.parent = parent
        }
        
        func stop() {
            active = false
            pendingSearch = nil
            searchGeneration += 1
        }

        func applyLatestContent(to webView: WKWebView) {
            guard active, isReady, !isApplyingContent,
                  let html = sourceHTML, let size = sourceFontSize,
                  html != appliedHTML || size != appliedFontSize else { return }
            isApplyingContent = true
            // Arguments are data, never interpolated into executable JavaScript.
            webView.callAsyncJavaScript("return window.bedrockUpdateContent(html, fontSize);",
                                        arguments: ["html": html, "fontSize": size], in: nil, in: .page) { [weak self, weak webView] result in
                guard let self, self.active else { return }
                self.isApplyingContent = false
                if case .success(let value) = result {
                    self.appliedHTML = html
                    self.appliedFontSize = size
                    if let height = value as? NSNumber { self.updateHeight(CGFloat(height.doubleValue)) }
                    if let webView {
                        self.applyLatestContent(to: webView)
                        self.performPendingSearch(in: webView)
                    }
                }
            }
        }
        
        func clearSearch(in webView: WKWebView) {
            searchGeneration += 1
            pendingSearch = nil
            if isReady { webView.evaluateJavaScript("window.bedrockClearSearch();") }
        }

        func selectSearch(in webView: WKWebView) {
            guard let query = sourceSearchQuery, let index = sourceSelectedIndex else {
                clearSearch(in: webView)
                return
            }
            searchGeneration += 1
            pendingSearch = (query, index)
            if ProcessInfo.processInfo.environment["BEDROCK_RENDER_DIAGNOSTICS"] == "1" {
                print("Markdown find selection: index=\(index) ready=\(isReady) updating=\(isApplyingContent)")
            }
            performPendingSearch(in: webView)
        }

        private func performPendingSearch(in webView: WKWebView) {
            guard active, isReady, !isApplyingContent, let search = pendingSearch else { return }
            pendingSearch = nil
            let generation = searchGeneration
            webView.callAsyncJavaScript("return window.bedrockFind(query, matchIndex);",
                                       arguments: ["query": search.query, "matchIndex": search.index], in: nil, in: .page) { [weak self, weak webView] result in
                if ProcessInfo.processInfo.environment["BEDROCK_RENDER_DIAGNOSTICS"] == "1" {
                    print("Markdown find geometry: \(result); nativeScroll=\(webView?.enclosingScrollView != nil)")
                }
                guard let self, self.active, self.searchGeneration == generation, let webView,
                      case .success(let value) = result, let match = value as? [String: Any],
                      let top = match["top"] as? Double, let height = match["height"] as? Double,
                      let scroll = webView.enclosingScrollView, let document = scroll.documentView else { return }
                // WKWebView occupies the entire reply. Scroll the native chat,
                // not an invisible inner page or every WebView in the thread.
                let y = webView.isFlipped ? top : webView.bounds.height - top - height
                let line = webView.convert(NSRect(x: 0, y: y, width: webView.bounds.width, height: height), to: document)
                var target = scroll.documentVisibleRect
                target.origin.y = line.midY - target.height / 2
                let bounded = scroll.contentView.constrainBoundsRect(target)
                scroll.contentView.scroll(to: bounded.origin)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            applyLatestContent(to: webView)
            webView.evaluateJavaScript("document.getElementById('bedrock-content').getBoundingClientRect().height") { [weak self] result, _ in
                if let height = result as? CGFloat { self?.updateHeight(height) }
            }
            if ProcessInfo.processInfo.environment["BEDROCK_RENDER_DIAGNOSTICS"] == "1" {
                webView.evaluateJavaScript("JSON.stringify({width:innerWidth,height:document.getElementById('bedrock-content').getBoundingClientRect().height,characters:document.getElementById('bedrock-content').textContent.length})") { value, error in
                    print("Markdown page: \(value ?? "no result")\(error.map { " · \($0.localizedDescription)" } ?? "")")
                }
            }
        }

        private func updateHeight(_ height: CGFloat) {
            guard active, height.isFinite, height > 0 else { return }
            let measured = min(ceil(height), 2_000_000)
            guard abs(parent.dynamicHeight - measured) > 0.5 else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.active, abs(self.parent.dynamicHeight - measured) > 0.5 else { return }
                self.parent.dynamicHeight = measured
            }
        }
        
        // Handle link clicks - open in default browser instead of loading inline
        @MainActor
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url,
                   MarkdownLinkPolicy.allowsExternalLink(url) {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
            } else {
                decisionHandler(navigationAction.request.url?.scheme == "about" ? .allow : .cancel)
            }
        }
        
        // Handle messages from JavaScript
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard active, message.frameInfo.isMainFrame else { return }
            if message.name == "heightHandler", let height = message.body as? NSNumber {
                updateHeight(CGFloat(height.doubleValue))
                return
            }
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
        let nonce = UUID().uuidString
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-\(nonce)'; style-src 'unsafe-inline'; img-src data:; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'">
            <style>
                \(CodeHighlightAssets.lightCSS)
                @media (prefers-color-scheme: dark) { \(CodeHighlightAssets.darkCSS) }
            </style>
            <script nonce="\(nonce)">\(CodeHighlightAssets.javascript)</script>
            <style>
                .copied-icon, .copied-text { display: none; }
                :root {
                    --message-font-size: \(fontSize)px;
                    --background-color: #ffffff;
                    --text-color: #202124;
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
                        --text-color: #e5e7eb;
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
                    font-size: var(--message-font-size);
                    line-height: 1.5;
                    margin: 0;
                    padding: 0;
                    overflow-wrap: break-word;
                }
                #bedrock-content {
                    display: flow-root;
                    width: 100%;
                }
                p {
                    margin: 0 0 12px;
                    padding: 0;
                }
                p:last-child { margin-bottom: 0; }
                h1, h2, h3, h4, h5, h6 {
                    margin: 20px 0 8px;
                    padding: 0;
                    font-weight: 600;
                    line-height: 1.3;
                }
                h1 { font-size: calc(var(--message-font-size) + 8px); }
                h2 { font-size: calc(var(--message-font-size) + 6px); }
                h3 { font-size: calc(var(--message-font-size) + 4px); }
                h4 { font-size: calc(var(--message-font-size) + 2px); }
                h5, h6 { font-size: var(--message-font-size); }
                #bedrock-content > :first-child { margin-top: 0; }
                ul, ol { margin: 8px 0 12px; padding-left: 24px; }
                li { margin: 6px 0; }
                li > p { margin-bottom: 0; }
                li > ul, li > ol { margin: 4px 0; }
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
                    justify-content: space-between;
                    align-items: center;
                    background-color: var(--header-background-color);
                    padding: 8px 12px;
                    font-size: 12px;
                    color: var(--secondary-text-color);
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Helvetica', 'Arial', sans-serif;
                    border-bottom: 0.5px solid var(--border-color);
                }
                
                .code-header .language {
                    font-weight: 500;
                    font-size: 12px;
                    color: var(--secondary-text-color);
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
                    font-size: calc(var(--message-font-size) - 1px);
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
                    background: transparent;
                    border: 0;
                    color: var(--secondary-text-color);
                    cursor: pointer !important;
                    display: inline-flex;
                    align-items: center;
                    font-size: 11px;
                    padding: 4px 6px;
                    border-radius: 6px;
                    transition: all 0.15s ease;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Helvetica', 'Arial', sans-serif;
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
                    font-size: calc(var(--message-font-size) - 1px);
                    background-color: var(--inline-code-background-color);
                    padding: 1px 4px;
                    border-radius: 4px;
                    box-decoration-break: clone;
                    -webkit-box-decoration-break: clone;
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
            <main id="bedrock-content"></main>
            <script nonce="\(nonce)">
                if (typeof hljs !== 'undefined') hljs.highlightAll();
                \(MarkdownDOMUpdateScript.source)
                \(MarkdownSearchScript.source)
                (() => {
                    const content = document.getElementById('bedrock-content');
                    let previousHeight = 0;
                    const measure = () => {
                        const height = Math.ceil(content.getBoundingClientRect().height);
                        if (height > 0 && height !== previousHeight) {
                            previousHeight = height;
                            window.webkit.messageHandlers.heightHandler.postMessage(height);
                        }
                    };
                    new ResizeObserver(measure).observe(content);
                    window.addEventListener('resize', measure);
                    document.fonts.ready.then(measure);
                    measure();
                })();
                
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
                
                // Prevent text selection interference with copy buttons
                document.addEventListener('selectstart', function(e) {
                    if (e.target.closest('.copy-button-bottom')) {
                        e.preventDefault();
                    }
                });
                document.addEventListener('click', function(e) {
                    const button = e.target.closest('button.copy-button-bottom[data-code-id]');
                    if (button) {
                        e.preventDefault();
                        copyCodeAdvanced(button, button.dataset.codeId);
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
    /// Initialize from base64 string or image file reference (img_xxx)
    /// Note: For file references, this loads synchronously from disk
    convenience init?(base64Encoded: String) {
        // Check if it's a file reference (img_xxx format)
        if base64Encoded.hasPrefix("img_") {
            // Read defaultDirectory from UserDefaults (same key as @AppStorage in SettingManager)
            // This avoids MainActor issues while staying in sync with SettingManager
            let defaultDir = UserDefaults.standard.string(forKey: "defaultDirector")
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Amazon Bedrock Client").path
            let baseDir = URL(fileURLWithPath: defaultDir)
            let filePath = baseDir.appendingPathComponent("generated_images/\(base64Encoded).png")
            guard let imageData = try? Data(contentsOf: filePath) else {
                return nil
            }
            self.init(data: imageData)
        } else {
            // Direct base64 decode
            guard let imageData = Data(base64Encoded: base64Encoded) else {
                return nil
            }
            self.init(data: imageData)
        }
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
