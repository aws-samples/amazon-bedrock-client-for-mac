import AppKit
import SwiftUI
import WebKit

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

final class MarkdownWebView: WKWebView {
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
        callAsyncJavaScript("return window.bedrockSelectionPayload();",
                            arguments: [:], in: nil, in: .page) { result in
            guard case .success(let value) = result, let payload = value as? [String: String],
                  let text = payload["text"], let html = payload["html"], !html.isEmpty else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.declareTypes([.html, .string], owner: nil)
            pasteboard.setString(MarkdownClipboard.document(html), forType: .html)
            pasteboard.setString(text, forType: .string)
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

// MARK: - HTMLMarkdownView

struct HTMLMarkdownView: NSViewRepresentable {
    let htmlContent: String
    let fontSize: CGFloat
    let searchQuery: String?
    let selectedMatchIndex: Int?
    var isStreaming = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var dynamicHeight: CGFloat

    init(htmlContent: String, fontSize: CGFloat, searchQuery: String? = nil, selectedMatchIndex: Int? = nil,
         isStreaming: Bool = false, dynamicHeight: Binding<CGFloat>) {
        self.htmlContent = htmlContent
        self.fontSize = fontSize
        self.searchQuery = searchQuery
        self.selectedMatchIndex = selectedMatchIndex
        self.isStreaming = isStreaming
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

        let webView = MarkdownWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        let contentChanged = context.coordinator.sourceHTML != htmlContent ||
                             context.coordinator.sourceFontSize != fontSize ||
                             context.coordinator.sourceIsStreaming != isStreaming ||
                             context.coordinator.sourceReduceMotion != reduceMotion
        let selectionChanged = context.coordinator.sourceSearchQuery != searchQuery ||
                               context.coordinator.sourceSelectedIndex != selectedMatchIndex
        guard contentChanged || selectionChanged else { return }
        context.coordinator.sourceHTML = htmlContent
        context.coordinator.sourceFontSize = fontSize
        context.coordinator.sourceIsStreaming = isStreaming
        context.coordinator.sourceReduceMotion = reduceMotion
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
        var parent: HTMLMarkdownView
        var sourceSearchQuery: String?
        var sourceSelectedIndex: Int?
        var hasStartedLoading = false
        var sourceHTML: String?
        var sourceFontSize: CGFloat?
        var sourceIsStreaming = false
        var sourceReduceMotion = false
        private var isReady = false
        private var isApplyingContent = false
        private var appliedHTML: String?
        private var appliedFontSize: CGFloat?
        private var appliedIsStreaming = false
        private var appliedReduceMotion = false
        private var active = true
        private var pendingSearch: (query: String, index: Int)?
        private var searchGeneration = 0
        private var pendingHeight: (height: CGFloat, width: CGFloat)?
        private var heightUpdateScheduled = false

        init(_ parent: HTMLMarkdownView) {
            self.parent = parent
        }

        func stop() {
            active = false
            pendingSearch = nil
            pendingHeight = nil
            searchGeneration += 1
        }

        func applyLatestContent(to webView: WKWebView) {
            guard active, isReady, !isApplyingContent,
                  let html = sourceHTML, let size = sourceFontSize,
                  html != appliedHTML || size != appliedFontSize ||
                    sourceIsStreaming != appliedIsStreaming || sourceReduceMotion != appliedReduceMotion else { return }
            isApplyingContent = true
            let streaming = sourceIsStreaming
            let reduced = sourceReduceMotion
            // Arguments are data, never interpolated into executable JavaScript.
            webView.callAsyncJavaScript("return window.bedrockUpdateContent(html, fontSize, streaming, reduced);",
                                        arguments: ["html": html, "fontSize": size, "streaming": streaming, "reduced": reduced], in: nil, in: .page) { [weak self, weak webView] result in
                guard let self, self.active else { return }
                self.isApplyingContent = false
                if case .success = result {
                    self.appliedHTML = html
                    self.appliedFontSize = size
                    self.appliedIsStreaming = streaming
                    self.appliedReduceMotion = reduced
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
            if ProcessInfo.processInfo.environment["BEDROCK_RENDER_DIAGNOSTICS"] == "1" {
                webView.evaluateJavaScript("JSON.stringify({width:innerWidth,height:document.getElementById('bedrock-content').getBoundingClientRect().height,characters:document.getElementById('bedrock-content').textContent.length})") { value, error in
                    print("Markdown page: \(value ?? "no result")\(error.map { " · \($0.localizedDescription)" } ?? "")")
                }
            }
        }

        private func updateHeight(_ height: CGFloat, width: CGFloat, in webView: WKWebView) {
            if ProcessInfo.processInfo.environment["BEDROCK_RENDER_DIAGNOSTICS"] == "1" {
                print("Markdown extent: \(height) × \(width), view=\(webView.bounds), previous=\(parent.dynamicHeight)")
            }
            guard active, height.isFinite, height > 0, width.isFinite,
                  abs(webView.bounds.width - width) < 1 else { return }
            let measured = min(ceil(height), 2_000_000)
            pendingHeight = (measured, width)
            guard !heightUpdateScheduled else { return }
            heightUpdateScheduled = true
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self else { return }
                self.heightUpdateScheduled = false
                guard self.active, let pending = self.pendingHeight, let webView else { return }
                self.pendingHeight = nil
                guard abs(webView.bounds.width - pending.width) < 1,
                      abs(self.parent.dynamicHeight - pending.height) > 0.5 else { return }
                self.parent.dynamicHeight = pending.height
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
            if message.name == "heightHandler", let size = message.body as? [String: Double],
               let height = size["height"], let width = size["width"], let webView = message.webView {
                updateHeight(height, width: width, in: webView)
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
                \(MarkdownClipboardScript.source)
                (() => {
                    const content = document.getElementById('bedrock-content');
                    let previousHeight = 0, previousWidth = 0;
                    const measure = () => {
                        const rect = content.getBoundingClientRect();
                        const height = Math.ceil(rect.height), width = rect.width;
                        if (height > 0 && (height !== previousHeight || width !== previousWidth)) {
                            previousHeight = height;
                            previousWidth = width;
                            window.webkit.messageHandlers.heightHandler.postMessage({height, width});
                        }
                    };
                    // One ordered channel owns the extent. JS completion
                    // callbacks and initial-load probes must not apply older
                    // heights after a newer ResizeObserver measurement.
                    window.bedrockReportContentSize = measure;
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
