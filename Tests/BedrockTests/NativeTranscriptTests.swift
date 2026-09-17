import AppKit
import SwiftUI
import XCTest
import WebKit
@testable import Amazon_Bedrock_Client_for_Mac

@MainActor
final class NativeTranscriptTests: XCTestCase {
    private final class LiveRow: ObservableObject, Identifiable {
        let id = UUID()
        @Published var height: CGFloat = 80
        var topPositions: [CGFloat] = []
    }

    private struct LiveRowView: View {
        @ObservedObject var row: LiveRow

        var body: some View {
            VStack(spacing: 0) {
                Color.clear.frame(height: 1)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                        row.topPositions.append($0)
                    }
                Text("A response whose content updates independently of the conversation.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(height: row.height)
        }
    }

    private struct Row: Identifiable {
        let id = UUID()
        var text: String
        var minimumHeight: CGFloat = 64
    }

    private final class Content: ObservableObject {
        @Published var rows: [Row]
        @Published var followsOutput = false
        var rowConstructionCounts: [UUID: Int] = [:]

        init(count: Int) {
            rows = (0..<count).map { Row(text: "Message \($0)") }
        }
    }

    private struct Transcript: View {
        @ObservedObject var content: Content
        let proxy: ConversationScrollProxy
        let viewport: ConversationViewportController

        var body: some View {
            ConversationTranscriptView(
                items: content.rows, proxy: proxy, viewport: viewport,
                followsOutput: content.followsOutput
            ) { row in
                content.rowConstructionCounts[row.id, default: 0] += 1
                return Text(row.text)
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: row.minimumHeight, alignment: .leading)
                    .padding(.horizontal, 12)
            }
        }
    }

    @MainActor
    private struct Fixture {
        let content: Content
        let proxy = ConversationScrollProxy()
        let viewport = ConversationViewportController()
        let window: NSWindow

        init(count: Int = 1_000) {
            _ = NSApplication.shared
            content = Content(count: count)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            viewport.observeScrolling(didScroll: { _ in }, didEnd: {}, contentDidResize: {},
                                      firstMessageID: content.rows.first?.id)
            window.contentView = NSHostingView(
                rootView: Transcript(content: content, proxy: proxy, viewport: viewport))
            window.orderFront(nil)
        }

        var scroll: NSScrollView? {
            func find(in view: NSView) -> NSScrollView? {
                if let scroll = view as? NSScrollView { return scroll }
                return view.subviews.lazy.compactMap { find(in: $0) }.first
            }
            return window.contentView.flatMap { find(in: $0) }
        }

        func close() {
            window.contentView = nil
            window.close()
            viewport.disconnect()
        }
    }

    @MainActor
    private struct LiveFixture {
        let rows: [LiveRow]
        let proxy = ConversationScrollProxy()
        let viewport = ConversationViewportController()
        let window: NSWindow

        init(count: Int = 4, followsOutput: Bool = false) {
            _ = NSApplication.shared
            rows = (0..<count).map { _ in LiveRow() }
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            viewport.observeScrolling(didScroll: { _ in }, didEnd: {}, contentDidResize: {},
                                      firstMessageID: rows.first?.id)
            window.contentView = NSHostingView(rootView: ConversationTranscriptView(
                items: rows, proxy: proxy, viewport: viewport, followsOutput: followsOutput
            ) { LiveRowView(row: $0) })
            window.orderFront(nil)
        }

        var scroll: NSScrollView? {
            func find(in view: NSView) -> NSScrollView? {
                if let scroll = view as? NSScrollView { return scroll }
                return view.subviews.lazy.compactMap { find(in: $0) }.first
            }
            return window.contentView.flatMap { find(in: $0) }
        }

        func close() {
            window.contentView = nil
            window.close()
            viewport.disconnect()
        }
    }

    private func settle(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date(timeIntervalSinceNow: 3)
        repeat {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            if condition() { return }
        } while Date() < deadline
        XCTFail("The native transcript did not settle.", file: file, line: line)
    }

    func testWholeHistoryIsReachableWithBoundedNativeViews() throws {
        let fixture = Fixture(count: 10_000)
        defer { fixture.close() }
        settle { fixture.scroll?.documentView?.subviews.isEmpty == false }

        for index in [9_999, 5_000, 0] {
            let id = fixture.content.rows[index].id
            fixture.proxy.scrollTo(id, anchor: index == 0 ? .top : .center)
            settle { fixture.viewport.isVisible(messageID: id) }
            let document = try XCTUnwrap(fixture.scroll?.documentView)
            XCTAssertLessThan(document.subviews.count, 64,
                              "Scrolling must not instantiate the entire conversation.")
            XCTAssertGreaterThan(document.bounds.height, 100_000,
                                 "The scroll document must include the full history.")
        }
    }

    func testScrollingUnchangedContentReusesVisibleRowsAndStillAppliesEdits() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        settle { fixture.scroll?.documentView?.subviews.isEmpty == false }
        let id = fixture.content.rows[500].id
        fixture.proxy.scrollTo(id, anchor: .center)
        settle { fixture.viewport.isVisible(messageID: id) }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        let scroll = try XCTUnwrap(fixture.scroll)
        let origin = scroll.contentView.bounds.origin
        let before = fixture.content.rowConstructionCounts
        for step in 0..<20 {
            scroll.contentView.scroll(to: NSPoint(x: origin.x, y: origin.y + CGFloat(step % 2 == 0 ? 2 : -2)))
            scroll.reflectScrolledClipView(scroll.contentView)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        }
        XCTAssertTrue(fixture.viewport.isVisible(messageID: id))
        XCTAssertEqual(fixture.content.rowConstructionCounts[id], before[id],
                       "Wheel movement must not rebuild a visible row whose content and width have not changed.")
        fixture.content.rows[500].minimumHeight = 380
        settle {
            (fixture.content.rowConstructionCounts[id] ?? 0) > (before[id] ?? 0) &&
                scroll.documentView?.subviews.contains { abs($0.frame.height - 380) < 0.5 } == true
        }
    }

    func testEarlierRowGrowthPreservesThePassageBeingRead() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        settle { fixture.scroll?.documentView?.subviews.isEmpty == false }
        let id = fixture.content.rows[500].id
        fixture.proxy.scrollTo(id, anchor: .center)
        settle { fixture.viewport.isVisible(messageID: id) }
        let before = try XCTUnwrap(fixture.viewport.capture(preferredID: id))
        fixture.viewport.preserve(before)

        fixture.content.rows[499].minimumHeight += 240
        settle {
            guard let actual = fixture.viewport.capture(preferredID: id) else { return false }
            return abs(actual.offset - before.offset) < 0.5
                && fixture.scroll?.documentView?.subviews.contains(where: { $0.frame.height >= 304 }) == true
        }
        XCTAssertEqual(try XCTUnwrap(fixture.viewport.capture(preferredID: id)).offset,
                       before.offset, accuracy: 0.5)
    }

    func testWidthChangesPreserveReadingPositionDuringReflow() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        for index in 490...510 {
            fixture.content.rows[index].text = String(repeating: "A passage that wraps as the sidebar changes. ", count: 18)
        }
        settle { fixture.scroll?.documentView?.subviews.isEmpty == false }
        let id = fixture.content.rows[500].id
        fixture.proxy.scrollTo(id, anchor: .center)
        settle { fixture.viewport.isVisible(messageID: id) }
        let before = try XCTUnwrap(fixture.viewport.capture(preferredID: id))
        fixture.viewport.preserve(before)

        for width: CGFloat in [420, 800] {
            fixture.window.setContentSize(NSSize(width: width, height: 600))
            settle {
                guard let actual = fixture.viewport.capture(preferredID: id), let scroll = fixture.scroll else { return false }
                return fixture.viewport.isVisible(messageID: id) && abs(actual.offset - before.offset) < 0.5
                    && abs((scroll.documentView?.frame.width ?? 0) - scroll.contentSize.width) < 1
                    && abs(scroll.frame.width - width) < 1
            }
            XCTAssertEqual(fixture.scroll?.documentView?.frame.width ?? 0,
                           fixture.scroll?.contentSize.width ?? 0, accuracy: 1,
                           "Host: \(String(describing: fixture.window.contentView?.frame)); scroll: \(String(describing: fixture.scroll?.frame))")
            XCTAssertTrue(fixture.viewport.isVisible(messageID: id), "The passage left the viewport at width \(width).")
            XCTAssertEqual(try XCTUnwrap(fixture.viewport.capture(preferredID: id)).offset,
                           before.offset, accuracy: 0.5, "Reading offset at width \(width).")
        }
    }

    func testGrowingResponseFollowsOnlyWhenTheReaderIsAtTheBottom() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.content.followsOutput = true
        settle { fixture.scroll?.documentView?.subviews.isEmpty == false }
        fixture.proxy.scrollTo("Bottom", anchor: .bottom)
        settle { fixture.viewport.isNearBottom }
        fixture.content.rows[999].minimumHeight = 500
        settle {
            fixture.viewport.isNearBottom
                && fixture.scroll?.documentView?.subviews.contains(where: { $0.frame.height >= 500 }) == true
        }

        fixture.content.followsOutput = false
        let id = fixture.content.rows[500].id
        fixture.proxy.scrollTo(id, anchor: .center)
        settle { fixture.viewport.isVisible(messageID: id) }
        let before = try XCTUnwrap(fixture.viewport.capture(preferredID: id))
        fixture.content.rows[999].minimumHeight = 900
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
        XCTAssertTrue(fixture.viewport.isVisible(messageID: id))
        XCTAssertEqual(try XCTUnwrap(fixture.viewport.capture(preferredID: id)).offset,
                       before.offset, accuracy: 0.5)
        XCTAssertFalse(fixture.viewport.isNearBottom)
    }

    func testScrollerWidthChangesDoNotRecycleTheLongResponseBeingRead() throws {
        let fixture = LiveFixture()
        defer { fixture.close() }
        settle { fixture.scroll != nil }
        let scroll = try XCTUnwrap(fixture.scroll)
        let document = try XCTUnwrap(scroll.documentView)
        scroll.hasVerticalScroller = false
        scroll.tile()
        fixture.rows[1].height = 9_000
        settle { document.subviews.contains { $0.frame.height == 9_000 } }
        fixture.proxy.scrollTo("Bottom", anchor: .bottom)
        settle { fixture.viewport.isNearBottom }
        let response = try XCTUnwrap(document.subviews.first { $0.frame.height == 9_000 })
        let originalWidth = scroll.contentSize.width

        // "Always show scroll bars" reserves a narrow slot only once the
        // asynchronously loaded document becomes taller than its viewport.
        scroll.scrollerStyle = .legacy
        scroll.hasVerticalScroller = true
        scroll.tile()
        settle {
            scroll.contentSize.width < originalWidth
                && abs(document.frame.width - scroll.contentSize.width) < 1
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        XCTAssertTrue(response.superview === document,
                      "Changing the scrollbar slot must not discard the loaded reply and its WebKit state.")
        XCTAssertEqual(response.frame.height, 9_000, accuracy: 1)
        XCTAssertGreaterThan(document.frame.height, 9_000)
        XCTAssertTrue(fixture.viewport.isVisible(messageID: fixture.rows[1].id))
    }

    func testIndependentlyGrowingResponseMovesTheFollowingRows() throws {
        let fixture = LiveFixture()
        defer { fixture.close() }
        settle { fixture.scroll != nil }
        let scroll = try XCTUnwrap(fixture.scroll)
        let document = try XCTUnwrap(scroll.documentView)
        settle { document.subviews.count == 4 && document.subviews.allSatisfy { $0.frame.height == 80 } }

        // Streaming and asynchronous Markdown layout update the hosted row
        // without republishing the transcript's item array. A retry, edit or
        // collapsed disclosure can also shrink that same independently held row.
        for height: CGFloat in [1_200, 96, 2_400, 48] {
            fixture.rows[1].height = height
            settle { document.subviews.contains { abs($0.frame.height - height) < 0.5 } }
            fixture.proxy.scrollTo(fixture.rows[2].id, anchor: .center)
            settle { fixture.viewport.isVisible(messageID: fixture.rows[2].id) }
            let cells = document.subviews.sorted { $0.frame.minY < $1.frame.minY }
            XCTAssertEqual(document.frame.height, max(scroll.contentSize.height, height + 270), accuracy: 1)
            for (previous, next) in zip(cells, cells.dropFirst()) {
                XCTAssertGreaterThanOrEqual(next.frame.minY, previous.frame.maxY - 0.5,
                                            "A resizing response must move later messages, not draw over them.")
            }
            XCTAssertTrue(cells.allSatisfy(\.clipsToBounds),
                          "A pending asynchronous measurement must not paint into an adjacent message.")
        }
    }

    func testStreamingContentDoesNotRecenterInsideItsPreviousHeight() throws {
        let fixture = LiveFixture()
        defer { fixture.close() }
        settle {
            fixture.scroll?.documentView?.subviews.count == 4 &&
            fixture.rows.allSatisfy { !$0.topPositions.isEmpty }
        }
        let row = fixture.rows[1]
        let initialTop = try XCTUnwrap(row.topPositions.last)
        row.topPositions.removeAll()
        for height: CGFloat in [240, 520, 960, 1_600, 2_400] {
            row.height = height
            settle { fixture.scroll?.documentView?.subviews.contains { abs($0.frame.height - height) < 0.5 } == true }
        }
        // onGeometryChange emits nothing when the first line stays put.
        XCTAssertTrue(row.topPositions.allSatisfy { abs($0 - initialTop) < 0.5 },
                      "The first line must remain at \(initialTop) while the host catches up: \(row.topPositions)")
    }

    func testIndependentContentGrowthKeepsTheFollowingPassageAtItsReadingPosition() throws {
        let fixture = LiveFixture(count: 60)
        defer { fixture.close() }
        settle { fixture.scroll?.documentView?.subviews.isEmpty == false }
        let id = fixture.rows[30].id
        fixture.proxy.scrollTo(id, anchor: .center)
        settle { fixture.viewport.isVisible(messageID: id) }
        let before = try XCTUnwrap(fixture.viewport.capture(preferredID: id))
        fixture.viewport.preserve(before)

        fixture.rows[29].height = 1_200
        settle {
            guard let actual = fixture.viewport.capture(preferredID: id) else { return false }
            return abs(actual.offset - before.offset) < 0.5
                && fixture.scroll?.documentView?.subviews.contains(where: { $0.frame.height == 1_200 }) == true
        }
        XCTAssertEqual(try XCTUnwrap(fixture.viewport.capture(preferredID: id)).offset,
                       before.offset, accuracy: 0.5)
        XCTAssertLessThan(try XCTUnwrap(fixture.scroll?.documentView).subviews.count, 40)
    }

    func testIndependentStreamingGrowthFollowsTheBottomWithoutPullingTheReaderBack() throws {
        let fixture = LiveFixture(count: 30, followsOutput: true)
        defer { fixture.close() }
        settle { fixture.scroll?.documentView?.subviews.isEmpty == false }
        let scroll = try XCTUnwrap(fixture.scroll)
        let document = try XCTUnwrap(scroll.documentView)
        let last = try XCTUnwrap(fixture.rows.last)
        fixture.proxy.scrollTo("Bottom", anchor: .bottom)
        settle { fixture.viewport.isNearBottom }
        last.height = 1_800
        settle {
            document.subviews.contains { $0.frame.height == 1_800 }
                && abs(scroll.documentVisibleRect.maxY - document.bounds.maxY) < 1
        }

        fixture.proxy.scrollTo(last.id, anchor: .top)
        settle { !fixture.viewport.isNearBottom && fixture.viewport.isVisible(messageID: last.id) }
        let before = try XCTUnwrap(fixture.viewport.capture(preferredID: last.id))
        fixture.viewport.preserve(before)
        last.height = 2_800
        settle { document.subviews.contains { $0.frame.height == 2_800 } }
        XCTAssertEqual(try XCTUnwrap(fixture.viewport.capture(preferredID: last.id)).offset,
                       before.offset, accuracy: 0.5)
        XCTAssertFalse(fixture.viewport.isNearBottom)
    }

    @MainActor
    func testCompletedStreamSnapshotCannotBeClearedOrRecommittedByTheNextToolTurn() {
        let first = StreamingMessageState()
        let final = MessageData(text: "First response is complete.", user: "Assistant", sentTime: Date())
        first.update(final)
        XCTAssertEqual(first.pendingMessage, final)
        XCTAssertEqual(first.finish(), final)
        XCTAssertNil(first.pendingMessage)
        XCTAssertNil(first.finish(), "Persist the stream once; later tool updates must not be overwritten.")
        let next = StreamingMessageState()
        next.update(MessageData(text: "Next tool turn", user: "Assistant", sentTime: Date()))
        first.update(nil)
        XCTAssertEqual(first.message, final, "A cell awaiting its new root still owns the previous final snapshot.")
        XCTAssertNotEqual(next.message?.id, first.message?.id)
    }

    @MainActor
    func testCompletingAStreamKeepsTheRenderedBodyUntilTheTranscriptCommits() async throws {
        let first = MessageData(text: "First token", user: "Assistant", sentTime: Date())
        var final = first
        final.text = (1...30).map { index in
            "## Completed section \(index)\n\nA **stable** paragraph with 한국어 text and `inline code`.\n\n- Keep the passage visible.\n- Keep the whole reply.\n"
        }.joined(separator: "\n") + "\nCOMPLETION_LAST_LINE"
        let stream = StreamingMessageState()
        stream.update(first)
        let attachments = MessageAttachmentPresenter()
        func row(_ message: MessageData, stream: StreamingMessageState?) -> some View {
            ConversationMessageView(message: message, stream: stream, searchResult: nil,
                                    adjustedFontSize: 0, showTimestamp: false, canModify: stream == nil,
                                    canRetry: true, attachments: attachments, onAction: { _, _ in })
                .frame(width: 640).fixedSize(horizontal: false, vertical: true)
        }
        let host = NSHostingView(rootView: row(first, stream: stream))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        func webView(in view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap { webView(in: $0) }.first
        }
        stream.update(final)
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline, host.fittingSize.height < 2_000 {
            try await Task.sleep(for: .milliseconds(20))
        }
        let web = try XCTUnwrap(webView(in: host))
        let baseline = host.fittingSize.height
        XCTAssertGreaterThan(baseline, 2_000)
        _ = try await web.evaluateJavaScript("""
            window.completionParagraph = document.querySelector('#bedrock-content p');
            const range = document.createRange(); range.selectNodeContents(completionParagraph);
            getSelection().removeAllRanges(); getSelection().addRange(range);
            """)
        XCTAssertEqual(stream.finish(), final)
        // The independent hosting cell still has its first-token input until
        // the transcript's scheduled root update. No frame may fall back to it.
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(10))
            let retained = try await web.evaluateJavaScript("""
                document.getElementById('bedrock-content').textContent.includes('COMPLETION_LAST_LINE')
                """)
            XCTAssertEqual(retained as? Bool, true, "Completion must not repaint the first-token fallback.")
            XCTAssertEqual(host.fittingSize.height, baseline, accuracy: 1,
                           "Finishing must not collapse the live response before the row commits.")
        }
        host.rootView = row(final, stream: nil)
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(10))
            XCTAssertTrue(webView(in: host) === web, "The loaded Markdown page must survive completion.")
            XCTAssertEqual(host.fittingSize.height, baseline, accuracy: 1,
                           "Revealing response actions must not move the conversation.")
        }
        let retained = try await web.evaluateJavaScript("""
            completionParagraph === document.querySelector('#bedrock-content p') && getSelection().toString().length > 0
            """)
        XCTAssertEqual(retained as? Bool, true)
    }

    @MainActor
    func testColdLongMessageReportsItsExtentWithoutRecreatingThePage() async throws {
        let source = "COLD_\(UUID().uuidString)\n\n" + (1...24).map { index in
            """
            ## Section \(index)

            A long **formatted** response with 한국어 text and `inline code`.

            - First item with enough text to wrap in a narrower window.
            - Second item.

            """
        }.joined(separator: "\n")
        let host = NSHostingView(rootView: MessageMarkdownView(text: source, fontSize: 14)
            .frame(width: 640).fixedSize(horizontal: false, vertical: true))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        func webView(in view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap { webView(in: $0) }.first
        }
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline, host.fittingSize.height < 2_000 {
            try await Task.sleep(for: .milliseconds(20))
        }
        let web = try XCTUnwrap(webView(in: host))
        let extentValue = try await web.evaluateJavaScript(
            "document.getElementById('bedrock-content').getBoundingClientRect().height")
        let extent = try XCTUnwrap(extentValue as? Double)
        XCTAssertGreaterThan(extent, 2_000)
        XCTAssertEqual(host.fittingSize.height, ceil(extent), accuracy: 1,
                       "The full message wrapper must apply the page's initial height.")
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(25))
            XCTAssertTrue(webView(in: host) === web, "A height update must retain the loaded page.")
            XCTAssertEqual(host.fittingSize.height, ceil(extent), accuracy: 1)
        }
    }

}
