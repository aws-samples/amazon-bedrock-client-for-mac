import AppKit
import SwiftUI
import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

@MainActor
final class NativeTranscriptTests: XCTestCase {
    private struct Row: Identifiable {
        let id = UUID()
        var text: String
        var minimumHeight: CGFloat = 64
    }

    private final class Content: ObservableObject {
        @Published var rows: [Row]
        @Published var followsOutput = false

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
                Text(row.text)
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
}
