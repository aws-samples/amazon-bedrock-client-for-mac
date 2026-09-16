import AppKit
import SwiftUI

/// Samples native geometry only when a page or conversation changes. Scrolling
/// does not publish per-frame SwiftUI state or walk the accessibility tree.
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
    private var observation: Observation?
    private var pending: Anchor?
    private var restoreScheduled = false
    private var lastCaptured: Anchor?
    private var capturingRemoval = false

    func connect(to scrollView: NSScrollView) {
        guard self.scrollView !== scrollView else { return }
        observation = nil
        self.scrollView = scrollView
        if let document = scrollView.documentView {
            document.postsFrameChangedNotifications = true
            observation = Observation(NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: document, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRestore() }
            })
        }
        scheduleRestore()
    }

    func register(_ view: NSView, messageID: UUID) {
        views[messageID] = WeakView(view)
        if scrollView == nil, let scroll = view.enclosingScrollView { connect(to: scroll) }
        scheduleRestore()
    }

    func unregister(_ view: NSView, messageID: UUID) {
        if views[messageID]?.value === view {
            // NSViewRepresentable can dismantle before AppKit detaches it.
            captureBeforeRemoval()
            views.removeValue(forKey: messageID)
        }
    }

    func capture(preferredID: UUID? = nil) -> Anchor? {
        guard let scroll = scrollView, let document = scroll.documentView else { return lastCaptured }
        let viewport = scroll.documentVisibleRect
        func anchor(_ id: UUID, _ view: NSView) -> Anchor {
            Anchor(messageID: id, offset: view.convert(view.bounds, to: document).minY - viewport.minY)
        }
        if let preferredID, let view = views[preferredID]?.value {
            let result = anchor(preferredID, view)
            lastCaptured = result
            return result
        }
        let visible = views.compactMap { id, entry -> (UUID, NSView, CGRect)? in
            guard let view = entry.value, view.window != nil else { return nil }
            let rect = view.convert(view.bounds, to: document)
            return rect.intersects(viewport) ? (id, view, rect) : nil
        }
        guard let first = visible.min(by: { $0.2.minY < $1.2.minY }) else { return lastCaptured }
        let result = anchor(first.0, first.1)
        lastCaptured = result
        return result
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
        // A restored view may disappear again without another user gesture.
        // Keep that valid checkpoint even if all native anchors are dismantled.
        lastCaptured = anchor
        pending = anchor
        scheduleRestore()
    }

    func cancelPreservation() { pending = nil }

    func disconnect() {
        observation = nil
        scrollView = nil
        pending = nil
    }

    private func scheduleRestore() {
        guard pending != nil, !restoreScheduled else { return }
        restoreScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.restoreScheduled = false
            self.restore()
        }
    }

    /// Also runs when a newly inserted WebKit/image row reports its final height.
    /// A real user scroll cancels preservation through ConversationScrollBehavior.
    func restore() {
        guard let pending, let scroll = scrollView, let document = scroll.documentView,
              let view = views[pending.messageID]?.value else { return }
        let rect = view.convert(view.bounds, to: document)
        let desired = rect.minY - pending.offset
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
        let range: Range<Int>
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
