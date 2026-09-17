import AppKit
import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class ConversationViewportTests: XCTestCase {
    @MainActor
    private final class Document: NSView {
        override var isFlipped: Bool { true }
    }

    @MainActor
    private final class WheelRecorder: NSScrollView {
        var events: [NSEvent] = []
        override func scrollWheel(with event: NSEvent) { events.append(event) }
    }

    @MainActor
    func testShortToolPreviewScrollsItsParentWhileLongOutputScrollsItself() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let parent = WheelRecorder(frame: window.contentLayoutRect)
        let document = Document(frame: NSRect(x: 0, y: 0, width: 800, height: 4_000))
        parent.documentView = document
        window.contentView = parent
        let preview = ToolOutputScrollView(frame: NSRect(x: 20, y: 100, width: 600, height: 120))
        preview.hasVerticalScroller = true
        preview.scrollerStyle = .overlay
        let output = Document(frame: NSRect(x: 0, y: 0, width: 600, height: 40))
        preview.documentView = output
        document.addSubview(preview)
        let cgEvent = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                           wheelCount: 1, wheel1: -80, wheel2: 0, wheel3: 0))
        let event = try XCTUnwrap(NSEvent(cgEvent: cgEvent))

        preview.scrollWheel(with: event)
        XCTAssertTrue(parent.events.isEmpty, "Standalone detail output must keep its own scrolling.")
        preview.scrollsWithConversation = true
        preview.scrollWheel(with: event)
        XCTAssertEqual(parent.events.count, 1)
        XCTAssertTrue(parent.events.first === event)

        output.setFrameSize(NSSize(width: 600, height: 600))
        let before = preview.documentVisibleRect.minY
        preview.scrollWheel(with: event)
        // AppKit applies wheel input on a subsequent animation frame.
        // Observe actual movement rather than asserting before that frame.
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while preview.documentVisibleRect.minY <= before, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(parent.events.count, 1, "A long preview must remain scrollable inside its bounded pane.")
        XCTAssertGreaterThan(preview.documentVisibleRect.minY, before)
    }

    @MainActor
    func testTopBoundaryKeepsTheNativeTitlebarInset() throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 40, left: 0, bottom: 0, right: 0)
        scroll.documentView = Document(frame: NSRect(x: 0, y: 0, width: 800, height: 4_000))
        let controller = ConversationViewportController()
        let id = UUID()
        controller.observeScrolling(didScroll: { _ in }, didEnd: {}, contentDidResize: {}, firstMessageID: id)
        controller.connect(to: scroll)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: -40))
        XCTAssertEqual(scroll.documentVisibleRect.minY, -40, accuracy: 0.5)
        controller.preserve(try XCTUnwrap(controller.capture()))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 0))
        controller.restore()
        XCTAssertEqual(scroll.documentVisibleRect.minY, -40, accuracy: 0.5,
                       "Preserving the top must not move content up by the titlebar height.")
        controller.disconnect()
    }

    @MainActor
    func testTopScrollIntentSurvivesLayoutCompensationBeforeAndAfterTheGestureEnds() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        let document = Document(frame: NSRect(x: 0, y: 0, width: 800, height: 40_000))
        let first = NSView(frame: NSRect(x: 0, y: 12, width: 800, height: 300))
        let next = NSView(frame: NSRect(x: 0, y: 600, width: 800, height: 300))
        document.addSubview(first)
        document.addSubview(next)
        scroll.documentView = document
        window.contentView = scroll
        let controller = ConversationViewportController()
        let firstID = UUID()
        controller.observeScrolling(didScroll: { _ in }, didEnd: {
            if let anchor = controller.capture() { controller.preserve(anchor) }
        }, contentDidResize: {}, firstMessageID: firstID)
        controller.connect(to: scroll)
        controller.register(first, messageID: firstID)
        controller.register(next, messageID: UUID())

        scroll.contentView.scroll(to: NSPoint(x: 0, y: 20_000))
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        scroll.contentView.scroll(to: .zero)
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll)
        // The hosted UI recording reached question 0, then jumped to question
        // 32 as lazy rows acquired their real heights around mouse-up.
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 12_000))
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        XCTAssertEqual(scroll.documentVisibleRect.minY, 0, accuracy: 0.5)
        XCTAssertEqual(controller.capture(), .init(messageID: firstID, offset: 0, isAtTop: true))

        // Offset compensation can happen after the final size notification.
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 11_600))
        let corrected = expectation(description: "Late clip adjustment corrected")
        DispatchQueue.main.async { corrected.fulfill() }
        await fulfillment(of: [corrected], timeout: 1)
        XCTAssertEqual(scroll.documentVisibleRect.minY, 0, accuracy: 0.5)

        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        controller.restore()
        XCTAssertEqual(scroll.documentVisibleRect.minY, 600, accuracy: 0.5,
                       "A new user gesture must release the top boundary.")
        XCTAssertFalse(try XCTUnwrap(controller.capture()).isAtTop)
        controller.disconnect()
    }

    @MainActor
    func testLateClipAdjustmentPreservesAnInteriorPassageWithoutPublishingUserScroll() async throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let document = Document(frame: NSRect(x: 0, y: 0, width: 800, height: 4_000))
        let message = NSView(frame: NSRect(x: 0, y: 2_000, width: 800, height: 300))
        document.addSubview(message)
        scroll.documentView = document
        let controller = ConversationViewportController()
        let id = UUID()
        var userScrolls = 0
        controller.observeScrolling(didScroll: { _ in userScrolls += 1 }, didEnd: {}, contentDidResize: {})
        controller.connect(to: scroll)
        controller.register(message, messageID: id)
        controller.preserve(.init(messageID: id, offset: 80))
        controller.restore()

        scroll.contentView.scroll(to: NSPoint(x: 0, y: 2_120))
        let corrected = expectation(description: "Interior reading position corrected")
        DispatchQueue.main.async { corrected.fulfill() }
        await fulfillment(of: [corrected], timeout: 1)
        XCTAssertEqual(scroll.documentVisibleRect.minY, 1_920, accuracy: 0.5)
        XCTAssertEqual(userScrolls, 0, "Layout compensation is not a user gesture.")
        controller.disconnect()
    }

    @MainActor
    func testRestorationWaitsForALazyRowAndStopsSeekingOnceItIsPositioned() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        let document = Document(frame: NSRect(x: 0, y: 0, width: 800, height: 40_000))
        scroll.documentView = document
        window.contentView = scroll
        let controller = ConversationViewportController()
        controller.connect(to: scroll)
        let anchor = ConversationViewportController.Anchor(messageID: UUID(), offset: 80)
        var attempts = 0
        await controller.restore(anchor) {
            attempts += 1
            if attempts == 2 {
                let message = NSView(frame: NSRect(x: 0, y: 20_000, width: 800, height: 300))
                document.addSubview(message)
                controller.register(message, messageID: anchor.messageID)
            }
        }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(controller.capture(), anchor)

        attempts = 0
        await controller.restore(anchor) {
            attempts += 1
            controller.cancelPreservation()
        }
        XCTAssertEqual(attempts, 1, "A user scroll must cancel pending restoration.")
        controller.disconnect()
    }

    @MainActor
    func testSearchSeeksAgainUntilTheOffscreenRowIsActuallyCreated() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        let document = Document(frame: NSRect(x: 0, y: 0, width: 800, height: 40_000))
        scroll.documentView = document
        window.contentView = scroll
        let controller = ConversationViewportController()
        controller.connect(to: scroll)
        let id = UUID()
        var attempts = 0
        await controller.align(messageID: id, fraction: 0.5) {
            attempts += 1
            if attempts == 2 {
                let message = NSView(frame: NSRect(x: 0, y: 20_000, width: 800, height: 100))
                document.addSubview(message)
                controller.register(message, messageID: id)
            }
        }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(controller.capture()?.messageID, id)
        XCTAssertEqual(try XCTUnwrap(controller.capture()).offset, 250, accuracy: 0.5)
        controller.disconnect()
    }

    @MainActor
    func testLazyLayoutReplacesStaleNativeCoordinatesWithoutWaitingForDocumentResize() throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let document = Document(frame: NSRect(x: 0, y: 0, width: 800, height: 40_000))
        let message = NSView(frame: NSRect(x: 0, y: 20_000, width: 800, height: 100))
        document.addSubview(message)
        scroll.documentView = document
        let controller = ConversationViewportController()
        let id = UUID()
        controller.connect(to: scroll)
        controller.register(message, messageID: id)
        controller.align(messageID: id, fraction: 0.5)
        controller.restore()
        XCTAssertEqual(scroll.documentVisibleRect.minY, 19_750, accuracy: 0.5)

        // During a real lazy-stack seek, SwiftUI reported a corrected target
        // 1,104 points below its still-attached native view. Total estimated
        // document height had not changed, so neither old signal was sufficient.
        controller.messageDidLayout(id, frame: NSRect(x: 0, y: 21_104, width: 800, height: 100))
        controller.restore()
        XCTAssertEqual(message.frame.minY, 20_000)
        XCTAssertEqual(document.frame.height, 40_000)
        XCTAssertEqual(scroll.documentVisibleRect.minY, 20_854, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(controller.capture(preferredID: id)).offset, 250, accuracy: 0.5)

        // Repositioning may briefly detach the native view. The measured target
        // must survive long enough to bring that same row back into the viewport.
        controller.unregister(message, messageID: id)
        message.removeFromSuperview()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 19_750))
        controller.restore()
        XCTAssertEqual(scroll.documentVisibleRect.minY, 20_854, accuracy: 0.5)

        controller.cancelPreservation()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 10_000))
        controller.messageDidLayout(id, frame: NSRect(x: 0, y: 23_000, width: 800, height: 100))
        controller.restore()
        XCTAssertEqual(scroll.documentVisibleRect.minY, 10_000, accuracy: 0.5)
        controller.disconnect()
    }

    @MainActor
    func testSearchDoesNotFinishBeforeTheNativeRowReachesItsMeasuredPosition() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        let document = Document(frame: NSRect(x: 0, y: 0, width: 800, height: 40_000))
        let message = NSView(frame: NSRect(x: 0, y: 20_000, width: 800, height: 100))
        document.addSubview(message)
        scroll.documentView = document
        window.contentView = scroll
        let controller = ConversationViewportController()
        defer { controller.disconnect() }
        let id = UUID()
        controller.connect(to: scroll)
        controller.register(message, messageID: id)
        controller.align(messageID: id, fraction: 0.5)
        controller.messageDidLayout(id, frame: NSRect(x: 0, y: 21_065, width: 800, height: 100))
        controller.restore()
        XCTAssertFalse(controller.isVisible(messageID: id),
                       "Projected search coordinates are not evidence that the result is onscreen.")
        message.setFrameOrigin(NSPoint(x: 0, y: 21_065))
        XCTAssertTrue(controller.isVisible(messageID: id))
    }

    @MainActor
    func testDepartureCheckpointIgnoresPartiallyDismantledRowCoordinates() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        let document = Document(frame: NSRect(x: 0, y: 0, width: 800, height: 4_000))
        let message = NSView(frame: NSRect(x: 0, y: 2_000, width: 800, height: 300))
        document.addSubview(message)
        scroll.documentView = document
        window.contentView = scroll
        let controller = ConversationViewportController()
        let id = UUID()
        controller.connect(to: scroll)
        controller.register(message, messageID: id)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 1_920))
        controller.prepareForDeparture()

        message.setFrameOrigin(NSPoint(x: 0, y: 1_000))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 900))
        controller.captureBeforeRemoval()
        controller.unregister(message, messageID: id)
        message.removeFromSuperview()
        XCTAssertEqual(controller.capture(), .init(messageID: id, offset: 80))
        controller.disconnect()
    }

    @MainActor
    func testSearchAlignmentUsesTheFinalMeasuredRowAndCancelsForUserScrolling() throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let document = Document(frame: NSRect(x: 0, y: 0, width: 800, height: 40_000))
        scroll.documentView = document
        let controller = ConversationViewportController()
        let id = UUID()
        controller.connect(to: scroll)
        controller.align(messageID: id, fraction: 0.5)
        // Search can request the row before a lazy stack creates its native view.
        let message = NSView(frame: NSRect(x: 0, y: 20_000, width: 800, height: 100))
        document.addSubview(message)
        controller.register(message, messageID: id)
        controller.restore()
        XCTAssertEqual(message.frame.minY - scroll.documentVisibleRect.minY, 250, accuracy: 0.5)

        // Offscreen Markdown finishes measuring above the search result.
        message.setFrameOrigin(NSPoint(x: 0, y: 22_000))
        message.setFrameSize(NSSize(width: 800, height: 200))
        controller.restore()
        XCTAssertEqual(message.frame.minY - scroll.documentVisibleRect.minY, 200, accuracy: 0.5)

        controller.cancelPreservation()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 21_000))
        message.setFrameOrigin(NSPoint(x: 0, y: 23_000))
        controller.restore()
        XCTAssertEqual(scroll.documentVisibleRect.minY, 21_000, accuracy: 0.5)
        controller.disconnect()
    }

    @MainActor
    func testResizeCallbacksWaitForLayoutAndAreCancelledOnDisconnect() async throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let document = Document(frame: NSRect(x: 0, y: 0, width: 800, height: 4_000))
        scroll.documentView = document
        let controller = ConversationViewportController()
        let resized = expectation(description: "One callback after layout")
        var callbackCount = 0
        controller.observeScrolling(didScroll: { _ in }, didEnd: {}, contentDidResize: {
            callbackCount += 1
            resized.fulfill()
        })
        controller.connect(to: scroll)
        for height in 4_001...4_010 {
            document.setFrameSize(NSSize(width: 800, height: height))
        }
        XCTAssertEqual(callbackCount, 0, "Layout must finish before publishing SwiftUI state.")
        await fulfillment(of: [resized], timeout: 1)
        XCTAssertEqual(callbackCount, 1)

        document.setFrameSize(NSSize(width: 800, height: 5_000))
        controller.disconnect()
        let drained = expectation(description: "Queued callbacks drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 1)
        XCTAssertEqual(callbackCount, 1, "A dismissed conversation must not receive stale resize callbacks.")
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
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
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
