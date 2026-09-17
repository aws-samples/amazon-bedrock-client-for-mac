import AppKit
import SwiftUI

/// Observes the native transcript scroll view. Row reuse and height changes
/// preserve reading position without publishing per-frame SwiftUI geometry.
@MainActor
final class ConversationViewportController: ObservableObject {
    struct Anchor: Equatable {
        let messageID: UUID
        let offset: CGFloat
    }

    private final class WeakView {
        weak var value: NSView?
        init(_ value: NSView) { self.value = value }
    }

    private final class Observation {
        let token: NSObjectProtocol
        init(_ token: NSObjectProtocol) { self.token = token }
        deinit { NotificationCenter.default.removeObserver(token) }
    }

    private weak var scrollView: NSScrollView?
    private var views: [UUID: WeakView] = [:]
    private var measuredFrames: [UUID: CGRect] = [:]
    private var observations: [Observation] = []
    private var pending: Anchor?
    private var pendingAlignment: (messageID: UUID, fraction: CGFloat)?
    private var restoreScheduled = false
    private var resizeCallbackScheduled = false
    private var lastCaptured: Anchor?
    private var departureAnchor: Anchor?
    private var isDeparting = false
    private var interactionGeneration = 0
    private var capturingRemoval = false
    private var didScroll: ((Bool) -> Void)?
    private var didEnd: (() -> Void)?
    private var contentDidResize: (() -> Void)?

    func observeScrolling(didScroll: @escaping (Bool) -> Void, didEnd: @escaping () -> Void,
                          contentDidResize: @escaping () -> Void) {
        self.didScroll = didScroll
        self.didEnd = didEnd
        self.contentDidResize = contentDidResize
    }

    func connect(to scrollView: NSScrollView) {
        guard !isDeparting, self.scrollView !== scrollView else { return }
        observations.removeAll()
        self.scrollView = scrollView
        departureAnchor = nil
        resizeCallbackScheduled = false
        if let document = scrollView.documentView {
            document.postsFrameChangedNotifications = true
            observations.append(Observation(NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: document, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleRestore()
                    self?.scheduleResizeCallback()
                }
            }))
        }
        observations.append(Observation(NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification, object: scrollView, queue: .main
        ) { [weak self] _ in
            // Thumb tracking can resize a lazy document before didLiveScroll.
            // Stop restoring the old passage as soon as the gesture starts.
            MainActor.assumeIsolated { self?.cancelPreservation() }
        }))
        for name in [NSScrollView.didLiveScrollNotification, NSScrollView.didEndLiveScrollNotification] {
            let ended = name == NSScrollView.didEndLiveScrollNotification
            observations.append(Observation(NotificationCenter.default.addObserver(
                forName: name, object: scrollView, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let scroll = self.scrollView, let document = scroll.documentView else { return }
                    self.cancelPreservation()
                    let nearBottom = document.bounds.maxY - scroll.documentVisibleRect.maxY < 65
                    self.didScroll?(nearBottom)
                    if ended { self.didEnd?() }
                }
            }))
        }
        scheduleRestore()
    }

    func register(_ view: NSView, messageID: UUID) {
        views[messageID] = WeakView(view)
        if scrollView == nil, let scroll = view.enclosingScrollView { connect(to: scroll) }
        scheduleRestore()
    }

    func messageDidLayout(_ messageID: UUID, frame: CGRect) {
        // SwiftUI revises lazy row positions before updating or reattaching
        // their native views. Native conversion can still return the old frame,
        // even after the total document height changes. Use the actual layout.
        guard frame.minY.isFinite, frame.height.isFinite, frame.height > 0 else { return }
        measuredFrames[messageID] = frame
        // Content coordinates stay unchanged during ordinary scrolling; this
        // never publishes viewport geometry through SwiftUI state.
        guard messageID == (pendingAlignment?.messageID ?? pending?.messageID) else { return }
        scheduleRestore()
    }

    func unregister(_ view: NSView, messageID: UUID) {
        if views[messageID]?.value === view {
            // NSViewRepresentable can dismantle before AppKit detaches it.
            captureBeforeRemoval()
            views.removeValue(forKey: messageID)
            if messageID != (pendingAlignment?.messageID ?? pending?.messageID) {
                measuredFrames.removeValue(forKey: messageID)
            }
        }
    }

    func capture(preferredID: UUID? = nil) -> Anchor? {
        if let departureAnchor { return departureAnchor }
        guard let scroll = scrollView, let document = scroll.documentView else { return lastCaptured }
        let viewport = scroll.documentVisibleRect
        func anchor(_ id: UUID, _ view: NSView) -> Anchor {
            let frame = measuredFrames[id] ?? view.convert(view.bounds, to: document)
            return Anchor(messageID: id, offset: frame.minY - viewport.minY)
        }
        if let preferredID, let view = views[preferredID]?.value, view.isDescendant(of: document) {
            let result = anchor(preferredID, view)
            lastCaptured = result
            return result
        }
        let visible = views.compactMap { id, entry -> (UUID, NSView, CGRect)? in
            guard let view = entry.value, view.window != nil, view.isDescendant(of: document) else { return nil }
            let rect = measuredFrames[id] ?? view.convert(view.bounds, to: document)
            return rect.intersects(viewport) ? (id, view, rect) : nil
        }
        guard let first = visible.min(by: { $0.2.minY < $1.2.minY }) else { return lastCaptured }
        let result = anchor(first.0, first.1)
        lastCaptured = result
        return result
    }

    func prepareForDeparture() {
        // Navigation changes are published before SwiftUI dismantles the lazy
        // stack. Its partially removed rows no longer have useful coordinates.
        guard !isDeparting else { return }
        departureAnchor = capture()
        isDeparting = true
        cancelPreservation()
    }

    func captureBeforeRemoval() {
        // SwiftUI can dismantle native children before its onDisappear action.
        // Take one snapshot while they still share the document's coordinates.
        guard !capturingRemoval else { return }
        capturingRemoval = true
        _ = capture()
        DispatchQueue.main.async { [weak self] in self?.capturingRemoval = false }
    }

    func preserve(_ anchor: Anchor) {
        guard !isDeparting else { return }
        // A restored view may disappear again without another user gesture.
        // Keep that valid checkpoint even if all native anchors are dismantled.
        lastCaptured = anchor
        pending = anchor
        pendingAlignment = nil
        scheduleRestore()
    }

    func align(messageID: UUID, fraction: CGFloat) {
        pending = nil
        pendingAlignment = (messageID, min(1, max(0, fraction)))
        scheduleRestore()
    }

    func align(messageID: UUID, fraction: CGFloat, seek: @MainActor () -> Void) async {
        let generation = interactionGeneration
        align(messageID: messageID, fraction: fraction)
        for _ in 0..<4 {
            guard !Task.isCancelled, !isDeparting, generation == interactionGeneration else { return }
            seek()
            do { try await Task.sleep(for: .milliseconds(32)) } catch { return }
            guard !Task.isCancelled, !isDeparting, generation == interactionGeneration else { return }
            restore()
            if isVisible(messageID: messageID) { return }
        }
    }

    func cancelPreservation() {
        if let id = pendingAlignment?.messageID ?? pending?.messageID, views[id]?.value == nil {
            measuredFrames.removeValue(forKey: id)
        }
        pending = nil
        pendingAlignment = nil
        interactionGeneration &+= 1
    }

    /// A lazy stack may not have measured an offscreen destination during its
    /// first layout. Seek again only until that row exists at its saved offset.
    /// User input or leaving the conversation cancels this bounded operation.
    func restore(_ anchor: Anchor, seek: @MainActor () -> Void) async {
        let generation = interactionGeneration
        preserve(anchor)
        for _ in 0..<4 {
            guard !Task.isCancelled, !isDeparting, generation == interactionGeneration else { return }
            seek()
            do { try await Task.sleep(for: .milliseconds(32)) } catch { return }
            guard !Task.isCancelled, !isDeparting, generation == interactionGeneration else { return }
            restore()
            if isVisible(messageID: anchor.messageID),
               let actual = capture(preferredID: anchor.messageID),
               abs(actual.offset - anchor.offset) < 0.5 { return }
        }
    }

    func isVisible(messageID: UUID) -> Bool {
        guard let view = views[messageID]?.value, let scroll = scrollView,
              let document = scroll.documentView, view.window != nil,
              view.isDescendant(of: document) else { return false }
        let frame = measuredFrames[messageID] ?? view.convert(view.bounds, to: document)
        return frame.intersects(scroll.documentVisibleRect)
    }

    func disconnect() {
        observations.removeAll()
        scrollView = nil
        views.removeAll()
        measuredFrames.removeAll()
        resizeCallbackScheduled = false
        cancelPreservation()
        isDeparting = false
        didScroll = nil
        didEnd = nil
        contentDidResize = nil
    }

    private func scheduleResizeCallback() {
        guard !resizeCallbackScheduled, let source = scrollView else { return }
        resizeCallbackScheduled = true
        // AppKit reports document sizes during SwiftUI layout. Publishing follow
        // state from that notification would mutate SwiftUI state during an update.
        DispatchQueue.main.async { [weak self, weak source] in
            guard let self, let source, self.scrollView === source else { return }
            self.resizeCallbackScheduled = false
            self.contentDidResize?()
        }
    }

    private func scheduleRestore() {
        guard pending != nil || pendingAlignment != nil, !restoreScheduled else { return }
        restoreScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.restoreScheduled = false
            self.restore()
        }
    }

    /// Also runs when a newly inserted WebKit/image row reports its final height.
    /// A real user scroll cancels preservation through native scroll notifications.
    func restore() {
        guard let messageID = pendingAlignment?.messageID ?? pending?.messageID,
              let scroll = scrollView, let document = scroll.documentView else { return }
        let rect: CGRect
        if let measured = measuredFrames[messageID] {
            rect = measured
        } else if let view = views[messageID]?.value, view.isDescendant(of: document) {
            rect = view.convert(view.bounds, to: document)
        } else {
            return
        }
        let offset = pendingAlignment.map {
            max(0, scroll.documentVisibleRect.height - rect.height) * $0.fraction
        } ?? pending!.offset
        lastCaptured = Anchor(messageID: messageID, offset: offset)
        let desired = rect.minY - offset
        let current = scroll.documentVisibleRect.minY
        guard abs(desired - current) > 0.5 else { return }
        let clip = scroll.contentView
        var origin = clip.bounds.origin
        origin.y += desired - current
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
    }
}

struct ConversationMessageAnchor: NSViewRepresentable {
    let messageID: UUID
    let controller: ConversationViewportController

    final class AnchorView: NSView {
        var messageID: UUID?
        weak var controller: ConversationViewportController?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewWillMove(toSuperview newSuperview: NSView?) {
            // By viewWillMove(toWindow:), AppKit has already detached the
            // superview, so conversion into document coordinates is too late.
            if newSuperview == nil, superview != nil { controller?.captureBeforeRemoval() }
            super.viewWillMove(toSuperview: newSuperview)
        }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil, window != nil { controller?.captureBeforeRemoval() }
            super.viewWillMove(toWindow: newWindow)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, let messageID { controller?.register(self, messageID: messageID) }
        }
    }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.messageID = messageID
        view.controller = controller
        controller.register(view, messageID: messageID)
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        if view.messageID != messageID || view.controller !== controller {
            if let previous = view.messageID { view.controller?.unregister(view, messageID: previous) }
            view.messageID = messageID
            view.controller = controller
        }
        controller.register(view, messageID: messageID)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AnchorView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 1, height: proposal.height ?? 1)
    }

    static func dismantleNSView(_ view: AnchorView, coordinator: ()) {
        if let messageID = view.messageID { view.controller?.unregister(view, messageID: messageID) }
    }
}

/// Small window-session snapshots survive eviction of a heavyweight chat model.
/// They contain no messages, attachments, or retained view objects.
@MainActor
final class ConversationViewportMemory {
    struct Position {
        let anchor: ConversationViewportController.Anchor
    }
    static let shared = ConversationViewportMemory()
    private var values: [String: Position] = [:]
    private var order: [String] = []

    func position(for threadID: String) -> Position? { values[threadID] }

    func remember(_ position: Position?, for threadID: String) {
        values[threadID] = position
        order.removeAll { $0 == threadID }
        if position != nil { order.append(threadID) }
        while order.count > 80 { values.removeValue(forKey: order.removeFirst()) }
    }
}
