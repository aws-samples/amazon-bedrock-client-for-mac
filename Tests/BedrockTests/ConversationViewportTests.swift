import AppKit
import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class ConversationViewportTests: XCTestCase {
    @MainActor
    private final class Document: NSView {
        override var isFlipped: Bool { true }
    }

    @MainActor
    func testRowHeightChangesKeepTheSameMessageAtTheSamePixelOffset() throws {
        _ = NSApplication.shared
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let document = Document(frame: NSRect(x: 0, y: 0, width: 800, height: 4_000))
        let message = NSView(frame: NSRect(x: 0, y: 2_000, width: 800, height: 300))
        document.addSubview(message)
        scroll.documentView = document
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 1_920))
        let controller = ConversationViewportController()
        let id = UUID()
        controller.connect(to: scroll)
        controller.register(message, messageID: id)
        let anchor = try XCTUnwrap(controller.capture(preferredID: id))
        XCTAssertEqual(anchor.offset, 80, accuracy: 0.5)
        controller.preserve(anchor)

        // A previously offscreen Markdown row receives its measured height.
        document.setFrameSize(NSSize(width: 800, height: 5_000))
        message.setFrameOrigin(NSPoint(x: 0, y: 3_000))
        controller.restore()
        XCTAssertEqual(message.frame.minY - scroll.documentVisibleRect.minY, 80, accuracy: 0.5)

        // Another row grows above while a row below shrinks. Total content
        // height is unchanged, so height-delta anchoring would fail.
        message.setFrameOrigin(NSPoint(x: 0, y: 4_000))
        controller.restore()
        XCTAssertEqual(message.frame.minY - scroll.documentVisibleRect.minY, 80, accuracy: 0.5)

        // An asynchronous image/HTML layout above the anchor grows later.
        message.setFrameOrigin(NSPoint(x: 0, y: 4_150))
        controller.restore()
        XCTAssertEqual(message.frame.minY - scroll.documentVisibleRect.minY, 80, accuracy: 0.5)
        controller.disconnect()
    }

    @MainActor
    func testNativeScrollingChangesFollowModeWithoutTreatingLayoutAsAGesture() throws {
        _ = NSApplication.shared
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let document = Document(frame: NSRect(x: 0, y: 0, width: 800, height: 4_000))
        scroll.documentView = document
        let controller = ConversationViewportController()
        var nearBottom: [Bool] = []
        var ended = 0
        controller.observeScrolling(didScroll: { nearBottom.append($0) }, didEnd: { ended += 1 },
                                    contentDidResize: {})
        controller.connect(to: scroll)
        document.setFrameSize(NSSize(width: 800, height: 5_000))
        XCTAssertTrue(nearBottom.isEmpty)
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll)
        XCTAssertEqual(nearBottom, [false])
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 4_400))
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        XCTAssertEqual(nearBottom, [false, true])
        XCTAssertEqual(ended, 1)
        controller.disconnect()
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        XCTAssertEqual(ended, 1)
    }

    @MainActor
    func testUserScrollingCancelsPendingLayoutCorrection() throws {
        _ = NSApplication.shared
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let document = Document(frame: NSRect(x: 0, y: 0, width: 800, height: 4_000))
        let message = NSView(frame: NSRect(x: 0, y: 2_000, width: 800, height: 300))
        document.addSubview(message)
        scroll.documentView = document
        let controller = ConversationViewportController()
        let id = UUID()
        controller.connect(to: scroll)
        controller.register(message, messageID: id)
        controller.preserve(try XCTUnwrap(controller.capture(preferredID: id)))
        controller.cancelPreservation()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 250))
        message.setFrameOrigin(NSPoint(x: 0, y: 2_800))
        controller.restore()
        XCTAssertEqual(scroll.documentVisibleRect.minY, 250, accuracy: 0.5)
        controller.disconnect()
    }

    @MainActor
    func testReadingPositionIsCapturedBeforeNativeViewsLeaveTheWindow() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        let document = Document(frame: NSRect(x: 0, y: 0, width: 800, height: 4_000))
        let controller = ConversationViewportController()
        let id = UUID()
        let message = ConversationMessageAnchor.AnchorView(frame: NSRect(x: 0, y: 2_000, width: 800, height: 300))
        message.messageID = id
        message.controller = controller
        document.addSubview(message)
        scroll.documentView = document
        window.contentView = scroll
        controller.connect(to: scroll)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 1_920))
        XCTAssertEqual(try XCTUnwrap(controller.capture()).offset, 80, accuracy: 0.5)

        // No per-frame publisher is needed. The last scroll must still be
        // checkpointed before SwiftUI removes the background anchor view.
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 1_840))
        message.removeFromSuperview()
        controller.unregister(message, messageID: id)
        XCTAssertEqual(try XCTUnwrap(controller.capture()).offset, 160, accuracy: 0.5)
        controller.disconnect()
    }

    @MainActor
    func testRestoredPositionSurvivesDismantlingWithoutAnotherScroll() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        let document = Document(frame: NSRect(x: 0, y: 0, width: 800, height: 4_000))
        let controller = ConversationViewportController()
        let id = UUID()
        let message = ConversationMessageAnchor.AnchorView(frame: NSRect(x: 0, y: 2_000, width: 800, height: 300))
        message.messageID = id
        message.controller = controller
        document.addSubview(message)
        scroll.documentView = document
        window.contentView = scroll
        controller.connect(to: scroll)

        let saved = ConversationViewportController.Anchor(messageID: id, offset: 160)
        controller.preserve(saved)
        controller.restore()
        XCTAssertEqual(scroll.documentVisibleRect.minY, 1_840, accuracy: 0.5)
        // SwiftUI is allowed to dismantle before AppKit's removal callbacks.
        ConversationMessageAnchor.dismantleNSView(message, coordinator: ())
        message.removeFromSuperview()
        XCTAssertEqual(controller.capture(), saved)
        controller.disconnect()
    }
}
