import AppKit
import Combine
import MarkdownKit
import SwiftUI
import WebKit
import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class MarkdownRenderingTests: XCTestCase {
    @MainActor
    func testReadOnlySelectionMenuKeepsOnlyCopyAndSelectAll() {
        let view = MarkdownSelectionTextView()
        view.install(rows: MarkdownLayoutRow.flatten(ExtendedMarkdownParser().parse("- First\n- Second")),
                     fontSize: 14, highlights: [], dark: false)
        view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
        let menu = TextContextMenu.make(for: view)
        XCTAssertEqual(menu.items.filter { !$0.isSeparatorItem }.map(\.title), ["Copy", "Select All"])
        XCTAssertTrue(menu.items.first?.isEnabled == true)
        XCTAssertTrue(menu.items.first?.target === view)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertFalse(TextContextMenu.make(for: view).items[0].isEnabled)
    }

    @MainActor
    func testComposerContextMenuKeepsEditingAndUsesTheActualPasteHandler() {
        let view = ComposerTextView()
        view.isEditable = true
        view.string = "Draft with Korean 한글"
        view.setSelectedRange(NSRange(location: 0, length: 5))
        let items = TextContextMenu.make(for: view).items.filter { !$0.isSeparatorItem }
        XCTAssertEqual(items.map(\.title), ["Cut", "Copy", "Paste", "Select All"])
        XCTAssertEqual(items[2].action, #selector(ComposerTextView.paste(_:)))
        XCTAssertTrue(items[2].target === view)
        XCTAssertEqual(view.string, "Draft with Korean 한글")
    }

    @MainActor
    func testNativeSelectionCopiesAcrossParagraphsBulletsTableAndCode() throws {
        let source = """
        Opening **paragraph**.

        - First bullet
        - 두 번째 bullet 😀

        | Name | Result |
        | --- | --- |
        | Fixture | Passed |

        ```swift
        let literal = "<script>not HTML</script>"
        print(literal)
        ```

        Closing paragraph.
        """
        let view = MarkdownSelectionTextView()
        view.install(rows: MarkdownLayoutRow.flatten(ExtendedMarkdownParser().parse(source)),
                     fontSize: 14, highlights: [], dark: false)
        XCTAssertGreaterThan(view.measuredSize(width: 600).height, 100)
        view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
        let pasteboard = NSPasteboard(name: .init("bedrock-selection-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.declareTypes([.string], owner: nil)
        XCTAssertTrue(view.writeSelection(to: pasteboard, type: .string))
        let copied = try XCTUnwrap(pasteboard.string(forType: .string))
        for text in ["Opening paragraph.", "First bullet", "두 번째 bullet 😀", "Name", "Result", "Fixture", "Passed",
                     #"let literal = "<script>not HTML</script>""#, "print(literal)", "Closing paragraph."] {
            XCTAssertTrue(copied.contains(text), "Missing rendered content: \(text)")
        }
        XCTAssertFalse(copied.contains("•"), "Decorative list markers must not be part of a drag selection.")
        XCTAssertEqual(view.listMarkers.map(\.text), ["•", "•"])
        XCTAssertEqual(view.codeBlocks.first?.source, "let literal = \"<script>not HTML</script>\"\nprint(literal)\n")
    }

    @MainActor
    func testNativeQuotesUseDecorationsAndTableKeepsSpaceAfterCode() throws {
        let source = """
        > First quoted paragraph.
        >
        > - Quoted list item.
        >
        > > Nested quote.

        ```swift
        let value = 42
        ```

        | Name | Value |
        | --- | --- |
        | Example | 42 |
        """
        let view = MarkdownSelectionTextView()
        view.install(rows: MarkdownLayoutRow.flatten(ExtendedMarkdownParser().parse(source)),
                     fontSize: 14, highlights: [], dark: false)
        _ = view.measuredSize(width: 600)
        XCTAssertEqual(view.quoteBlocks.map(\.indent), [0, 16])
        XCTAssertTrue(view.string.contains("First quoted paragraph.\nQuoted list item.\nNested quote."))
        XCTAssertFalse(view.string.contains(">"))
        XCTAssertFalse(view.string.contains("•"))
        let manager = try XCTUnwrap(view.layoutManager)
        let container = try XCTUnwrap(view.textContainer)
        let code = try XCTUnwrap(view.codeBlocks.first)
        let codeRect = manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: code.range, actualCharacterRange: nil),
                                           in: container)
        let header = (view.string as NSString).range(of: "Name")
        let tableRect = manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: header, actualCharacterRange: nil),
                                            in: container)
        XCTAssertGreaterThan(tableRect.minY - codeRect.maxY, 12)
    }

    @MainActor
    func testNativeStreamingPreservesSelectionAcrossTwoListItems() {
        let view = MarkdownSelectionTextView()
        let parser = ExtendedMarkdownParser()
        let prefix = "- First item\n- 한글 second item\n\n"
        view.install(rows: MarkdownLayoutRow.flatten(parser.parse(prefix + "Partial")), fontSize: 14, highlights: [], dark: false, isStreaming: true)
        let selected = (view.string as NSString).range(of: "First item\n한글 second item")
        XCTAssertNotEqual(selected.location, NSNotFound)
        view.setSelectedRange(selected)
        view.install(rows: MarkdownLayoutRow.flatten(parser.parse(prefix + "Partial response completed.")),
                     fontSize: 14, highlights: [], dark: false, isStreaming: false)
        XCTAssertEqual(view.selectedRange(), selected)
        XCTAssertEqual((view.string as NSString).substring(with: selected), "First item\n한글 second item")
    }

    @MainActor
    func testNativeMarkdownLinksKeepReadableLabelsWithoutUnsafeTargets() {
        let rows = MarkdownLayoutRow.flatten(ExtendedMarkdownParser().parse(
            "[Safe](https://example.com) [Unsafe](javascript:alert) [Local](file:///tmp/private)"))
        let result = MarkdownNativeAttributedDocument.render(rows, fontSize: 14, highlights: [], dark: false, isStreaming: false)
        var urls: [URL] = []
        result.text.enumerateAttribute(.link, in: NSRange(location: 0, length: result.text.length)) { value, _, _ in
            if let url = value as? URL { urls.append(url) }
        }
        XCTAssertEqual(urls.map(\.absoluteString), ["https://example.com"])
        XCTAssertTrue(result.text.string.contains("Safe Unsafe Local"))
    }

    func testFindKeepsUTF16RangesAndComposedCharacters() throws {
        let source = String(repeating: "👩🏽‍💻 ", count: 80) + "마지막 café needle 🌊"
        let message = MessageData(text: source, user: "Assistant", sentTime: Date())
        let result = SearchEngine().search(query: "needle", in: [message])
        let match = try XCTUnwrap(result.matches.first)
        XCTAssertEqual(result.totalMatches, 1)
        XCTAssertEqual(match.ranges, [(source as NSString).range(of: "needle")])
        XCTAssertTrue(match.snippet.contains("needle"))
        let highlighted = TextHighlighter.createHighlightedText(text: source, searchRanges: match.ranges, fontSize: 14)
        XCTAssertEqual(String(highlighted.attributedString.characters), source)
        XCTAssertTrue(highlighted.attributedString.runs.contains { $0.backgroundColor != nil })
        XCTAssertEqual(SearchEngine().search(query: "cafe", in: [message]).totalMatches, 1)
    }

    func testFindCacheTracksChangedAndAppendedMessages() {
        let engine = SearchEngine()
        var message = MessageData(text: "Before streaming", user: "Assistant", sentTime: Date())
        XCTAssertEqual(engine.search(query: "arrived", in: [message]).totalMatches, 0)
        message.text += " — arrived"
        XCTAssertEqual(engine.search(query: "arrived", in: [message]).totalMatches, 1)
        let next = MessageData(text: "Arrived again", user: "Assistant", sentTime: Date())
        XCTAssertEqual(engine.search(query: "arrived", in: [message, next]).totalMatches, 2)
    }

    func testFindMatchesTheWholePhrase() {
        let message = MessageData(text: "local settings; file tools; local file", user: "Assistant", sentTime: Date())
        let result = SearchEngine().search(query: "local file", in: [message])
        XCTAssertEqual(result.totalMatches, 1)
        XCTAssertEqual(result.matches.first?.ranges, [(message.text as NSString).range(of: "local file")])
    }

    @MainActor
    func testRenderedHTMLCannotExecuteScriptsOrOpenActiveContent() async throws {
        let webView = WKWebView()
        let ready = expectation(description: "Sanitizer page loaded")
        let delegate = MarkdownPageDelegate(ready)
        webView.navigationDelegate = delegate
        webView.loadHTMLString("<html><body><main id='bedrock-content'></main><script>\(MarkdownDOMUpdateScript.source)</script></body></html>", baseURL: nil)
        await fulfillment(of: [ready], timeout: 10)
        let html = """
        <p onclick="window.attacked=true">Safe <strong>Markdown</strong></p>
        <script>window.attacked=true</script>
        <iframe srcdoc="<script>parent.attacked=true</script>"></iframe>
        <img src="invalid" onerror="window.attacked=true">
        <img src="https://example.invalid/image.png" alt="Remote image">
        <a href="javascript:window.attacked=true">Unsafe link</a>
        <a href="file:///tmp/private">Local link</a>
        <a href="https://user:password@example.com">Credential link</a>
        <a href="https://example.com">Normal link</a>
        <svg onload="window.attacked=true"><animate attributeName="href" values="javascript:alert(1)"></animate><path d="M0 0"></path></svg>
        <pre><code>&lt;script&gt;print("literal code")&lt;/script&gt;</code></pre>
        <button class="copy-button-bottom" data-code-id="code-1" onclick="window.attacked=true">Copy</button>
        """
        let value = try await webView.callAsyncJavaScript("""
            bedrockUpdateContent(html, 14);
            const content = document.getElementById('bedrock-content');
            content.querySelector('p').click();
            content.querySelector('button').click();
            return {
                attacked: window.attacked === true,
                activeTags: content.querySelectorAll('script,iframe,animate,img').length,
                eventAttributes: Array.from(content.querySelectorAll('*')).some(node => Array.from(node.attributes).some(a => a.name.startsWith('on'))),
                links: Array.from(content.querySelectorAll('a[href]')).map(node => node.href),
                text: content.querySelector('p').textContent,
                code: content.querySelector('code').textContent,
                copyID: content.querySelector('button').dataset.codeId
            };
            """, arguments: ["html": html], in: nil, contentWorld: .page)
        let result = try XCTUnwrap(value as? [String: Any])
        XCTAssertEqual(result["attacked"] as? Bool, false)
        XCTAssertEqual(result["activeTags"] as? Int, 0)
        XCTAssertEqual(result["eventAttributes"] as? Bool, false)
        XCTAssertEqual(result["links"] as? [String], ["https://example.invalid/image.png", "https://example.com/"])
        XCTAssertEqual(result["text"] as? String, "Safe Markdown")
        XCTAssertEqual(result["code"] as? String, "<script>print(\"literal code\")</script>")
        XCTAssertEqual(result["copyID"] as? String, "code-1")
        webView.stopLoading()
        withExtendedLifetime(delegate) {}
    }

    @MainActor
    func testWebFindReturnsTheSelectedLineAndIncludesCode() async throws {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 720, height: 80))
        let ready = expectation(description: "Search page loaded")
        let delegate = MarkdownPageDelegate(ready)
        webView.navigationDelegate = delegate
        let spacer = String(repeating: "<p>Filler paragraph.</p>", count: 180)
        webView.loadHTMLString("""
            <html><body><main id="bedrock-content">
            <p>First marker.</p>\(spacer)<pre><code>Second MARKER. café 한국어 🌊</code></pre>
            <p>final <strong>target</strong> phrase</p><button>marker</button>
            </main><script>\(MarkdownSearchScript.source)</script></body></html>
            """, baseURL: nil)
        await fulfillment(of: [ready], timeout: 10)
        let value = try await webView.callAsyncJavaScript("""
            const result = bedrockFind(query, 1);
            return {...result, selected: document.querySelector('.search-highlight-current').textContent,
                    codeMatch: !!document.querySelector('code .search-highlight-current')};
            """, arguments: ["query": "marker"], in: nil, contentWorld: .page)
        let result = try XCTUnwrap(value as? [String: Any])
        XCTAssertEqual(result["count"] as? Int, 2, "Copy controls must not add phantom search matches.")
        XCTAssertEqual(result["selected"] as? String, "MARKER")
        XCTAssertEqual(result["codeMatch"] as? Bool, true)
        XCTAssertGreaterThan(try XCTUnwrap(result["top"] as? Double), 3_000)
        for (query, expected) in [("target phrase", "target phrase"), ("한국어 🌊", "한국어 🌊"), ("cafe", "café")] {
            let selected = try await webView.callAsyncJavaScript("""
                bedrockFind(query, 0);
                return Array.from(document.querySelectorAll('.search-highlight-current')).map(node => node.textContent).join('');
                """, arguments: ["query": query], in: nil, contentWorld: .page)
            XCTAssertEqual(selected as? String, expected)
        }
        let remaining = try await webView.callAsyncJavaScript("bedrockClearSearch(); return document.querySelectorAll('.search-highlight,.search-highlight-current').length;",
                                                             arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(remaining as? Int, 0)
        webView.stopLoading()
        withExtendedLifetime(delegate) {}
    }

    @MainActor
    func testWebExtentUpdatesWithoutAVisibleAnimationFrame() async throws {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 720, height: 80))
        let ready = expectation(description: "Offscreen Markdown page loaded")
        let delegate = MarkdownPageDelegate(ready)
        webView.navigationDelegate = delegate
        webView.loadHTMLString("""
            <html><head><style>
            body { margin: 0; font-size: var(--message-font-size); line-height: 1.5; }
            main { display: flow-root; width: 720px; }
            p { margin: 0 0 12px; }
            </style></head><body><main id="bedrock-content"></main>
            <script>\(MarkdownDOMUpdateScript.source)</script></body></html>
            """, baseURL: nil)
        await fulfillment(of: [ready], timeout: 10)
        let html = (1...120).map {
            "<p>Section \($0): A long paragraph that wraps when the conversation is narrowed. 한국어 문장과 마지막 줄도 잘리지 않아야 합니다.</p>"
        }.joined()
        func extent(font: Int, width: Int) async throws -> Double {
            let value = try await webView.callAsyncJavaScript("""
                document.getElementById('bedrock-content').style.width = `${width}px`;
                return bedrockUpdateContent(html, font);
                """, arguments: ["html": html, "font": font, "width": width], in: nil, contentWorld: .page)
            return try XCTUnwrap(value as? Double)
        }
        let original = try await extent(font: 14, width: 720)
        let larger = try await extent(font: 18, width: 720)
        let narrow = try await extent(font: 18, width: 420)
        let restored = try await extent(font: 14, width: 720)
        XCTAssertGreaterThan(original, 3_000)
        XCTAssertGreaterThan(larger, original)
        XCTAssertGreaterThan(narrow, larger)
        XCTAssertEqual(restored, original, accuracy: 1)
        webView.stopLoading()
        withExtendedLifetime(delegate) {}
    }

    @MainActor
    func testWebStreamingKeepsCompletedDOMAndSelection() async throws {
        let webView = WKWebView()
        let ready = expectation(description: "Markdown page loaded")
        let delegate = MarkdownPageDelegate(ready)
        webView.navigationDelegate = delegate
        webView.loadHTMLString("<html><body><main id='bedrock-content'></main><script>\(MarkdownDOMUpdateScript.source)</script></body></html>", baseURL: nil)
        await fulfillment(of: [ready], timeout: 10)
        let prefix = "<h2>Heading</h2><p>안녕, stable paragraph.</p>"
        _ = try await webView.callAsyncJavaScript("bedrockUpdateContent(html, 14); window.savedParagraph = document.querySelector('p'); const range = document.createRange(); range.selectNodeContents(savedParagraph); getSelection().addRange(range);",
                                                   arguments: ["html": prefix + "<pre><code>let a = 1</code></pre>"], in: nil, contentWorld: .page)
        let result = try await webView.callAsyncJavaScript("""
            bedrockUpdateContent(html, 18);
            return {
                retained: savedParagraph === document.querySelector('p'),
                selection: getSelection().toString(),
                code: document.querySelector('code').textContent,
                count: document.getElementById('bedrock-content').children.length,
                font: document.documentElement.style.getPropertyValue('--message-font-size')
            };
            """, arguments: ["html": prefix + "<pre><code>let a = \"한글\";\n</code></pre><p>Appended.</p>"], in: nil, contentWorld: .page)
        let values = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(values["retained"] as? Bool, true)
        XCTAssertEqual(values["selection"] as? String, "안녕, stable paragraph.")
        XCTAssertEqual(values["code"] as? String, "let a = \"한글\";\n")
        XCTAssertEqual(values["count"] as? Int, 4)
        XCTAssertEqual(values["font"] as? String, "18px")
        let count = try await webView.callAsyncJavaScript("bedrockUpdateContent(html, 18); return document.getElementById('bedrock-content').children.length;",
                                                         arguments: ["html": prefix], in: nil, contentWorld: .page)
        XCTAssertEqual(count as? Int, 2)
        webView.stopLoading()
        withExtendedLifetime(delegate) {}
    }

    func testNestedListsKeepMarkersAndContinuationIndentation() {
        let source = """
        ## Deployment

        1. **Build**
           - Compile Swift
           - 한국어 확인
        2. **Validate**

           Keep this paragraph with the second item.

        Finished.
        """
        let rows = MarkdownLayoutRow.flatten(ExtendedMarkdownParser().parse(source))
        XCTAssertEqual(rows.compactMap(\.marker), ["1.", "•", "•", "2."])
        let child = rows.first { $0.block.string.contains("한국어") }
        let continuation = rows.first { $0.block.string.contains("Keep this paragraph") }
        XCTAssertEqual(child?.indent, 48)
        XCTAssertEqual(continuation?.indent, 24)
        XCTAssertNil(continuation?.marker)
        XCTAssertEqual(rows.last?.indent, 0)
    }

    func testAnOpenCodeFenceDoesNotInvalidateCompletedParagraphs() {
        let prefix = """
        ## Stable heading

        A **completed** paragraph with 한글.

        ```python
        """
        let before = MarkdownLayoutRow.flatten(ExtendedMarkdownParser().parse(prefix + "\nprint("))
        let after = MarkdownLayoutRow.flatten(ExtendedMarkdownParser().parse(prefix + "\nprint(\"끝\")\n```\n\nNext paragraph."))
        XCTAssertEqual(Array(before.prefix(2)), Array(after.prefix(2)))
        guard case .fencedCode(let language, let lines) = after[2].block else {
            return XCTFail("The streamed code must remain a code block.")
        }
        XCTAssertEqual(language, "python")
        XCTAssertEqual(lines.joined(), "print(\"끝\")\n")
        XCTAssertEqual(before[0].revision, after[0].revision)
        XCTAssertNotEqual(before[2].revision, after[2].revision)
    }

    func testTablesQuotesAndCodeRemainSeparateBlocks() {
        let source = """
        > A **quoted** paragraph.
        >
        > Another paragraph.

        | Model | Region |
        | --- | --- |
        | Example | Local |

        ```json
        {"enabled":true,"count":2}
        ```
        """
        let rows = MarkdownLayoutRow.flatten(ExtendedMarkdownParser().parse(source))
        XCTAssertEqual(rows.prefix(2).map(\.quoteDepth), [1, 1])
        XCTAssertEqual(rows.prefix(2).map(\.indent), [16, 16])
        XCTAssertTrue(rows.contains { if case .table = $0.block { return true }; return false })
        XCTAssertTrue(rows.contains { if case .fencedCode = $0.block { return true }; return false })
        XCTAssertEqual(rows.last?.indent, 0)
    }

    func testStreamingOnlyNotifiesTheChangedBlock() async {
        let prefix = "## Heading\n\nA **stable** paragraph.\n\n```swift\n"
        await MainActor.run {
            let parser = ExtendedMarkdownParser()
            let document = MarkdownDocumentState(rows: MarkdownLayoutRow.flatten(parser.parse(prefix)), isStreaming: true)
            let heading = document.blocks[0]
            let code = document.blocks[2]
            var collectionUpdates = 0
            var headingUpdates = 0
            var codeUpdates = 0
            let subscriptions = [
                document.$blocks.dropFirst().sink { _ in collectionUpdates += 1 },
                heading.$content.dropFirst().sink { _ in headingUpdates += 1 },
                code.$content.dropFirst().sink { _ in codeUpdates += 1 }
            ]
            for count in 1...8 {
                let source = prefix + String(repeating: "let value = 1\n", count: count)
                document.update(rows: MarkdownLayoutRow.flatten(parser.parse(source)), isStreaming: true)
            }
            XCTAssertEqual(collectionUpdates, 0, "Tokens must not invalidate every completed block.")
            XCTAssertEqual(headingUpdates, 0)
            XCTAssertEqual(codeUpdates, 8)
            XCTAssertTrue(document.blocks[0] === heading)
            XCTAssertTrue(document.blocks[2] === code)
            document.update(rows: MarkdownLayoutRow.flatten(parser.parse(prefix + "let value = 1\n```\n\nDone.")), isStreaming: false)
            XCTAssertEqual(collectionUpdates, 1)
            XCTAssertEqual(headingUpdates, 0)
            XCTAssertFalse(code.content.isStreaming)
            withExtendedLifetime(subscriptions) {}
        }
    }

    func testLongReplyReflowsAndRetainsHeightOnRepeatedLayout() async {
        let source = (1...60).map { index in
            """
            ## CHECK_\(index)

            A paragraph with **emphasis**, `inline code`, and 한국어 text that wraps at a narrow window width.

            1. Verify the main window.
               - Keep nested text indented.
               - Preserve selection and scrolling.
            2. Verify settings.

            ```python
            assert marker == "CHECK_\(index)"
            ```

            """
        }.joined(separator: "\n")
        let rows = MarkdownLayoutRow.flatten(ExtendedMarkdownParser().parse(source))
        await MainActor.run {
            let start = ProcessInfo.processInfo.systemUptime
            let host = NSHostingView(rootView: MarkdownRenderer(rows: rows, fontSize: 14, highlights: []).frame(width: 720))
            let wide = host.fittingSize
            XCTAssertGreaterThan(wide.height, 10_000)
            XCTAssertEqual(wide.width, 720, accuracy: 1)
            XCTAssertEqual(host.fittingSize.height, wide.height, accuracy: 1)
            host.rootView = MarkdownRenderer(rows: rows, fontSize: 14, highlights: []).frame(width: 420)
            let narrow = host.fittingSize
            XCTAssertGreaterThan(narrow.height, wide.height)
            XCTAssertEqual(narrow.width, 420, accuracy: 1)
            host.rootView = MarkdownRenderer(rows: rows, fontSize: 14, highlights: []).frame(width: 720)
            XCTAssertEqual(host.fittingSize.height, wide.height, accuracy: 1)
            print("Native Markdown layout: \(rows.count) rows; width 720 → 420 → 720; \(ProcessInfo.processInfo.systemUptime - start)s")
        }
    }
}

@MainActor
private final class MarkdownPageDelegate: NSObject, WKNavigationDelegate {
    let ready: XCTestExpectation
    init(_ ready: XCTestExpectation) { self.ready = ready }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready.fulfill() }
}
