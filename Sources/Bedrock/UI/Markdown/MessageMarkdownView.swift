import SwiftUI
import MarkdownKit
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
        let result = MarkdownHTMLGenerator().generate(doc: document.block)
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

// MARK: - MessageMarkdownView
struct MessageMarkdownView: View {
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
                HTMLMarkdownView(
                    htmlContent: html,
                    fontSize: fontSize,
                    searchQuery: searchTerms.first,
                    selectedMatchIndex: selectedSearchIndex,
                    dynamicHeight: $height
                )
                .frame(maxWidth: .infinity)
                .frame(height: height > 0 ? height : nativeHeight)
            } else {
                MarkdownRenderer(document: renderer.native, fontSize: fontSize, highlights: searchTerms)
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

// MARK: - MarkdownHTMLGenerator
class MarkdownHTMLGenerator: HtmlGenerator {
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
