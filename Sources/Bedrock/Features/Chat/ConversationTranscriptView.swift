import AppKit
import SwiftUI

/// Navigation does not publish scroll offsets through the SwiftUI scene.
@MainActor
final class ConversationScrollProxy: ObservableObject {
    fileprivate var seek: ((AnyHashable, UnitPoint) -> Void)?
    fileprivate weak var owner: AnyObject?

    func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint) {
        seek?(AnyHashable(id), anchor)
    }
}

/// AppKit owns the continuous document and its viewport. Each visible message
/// has an independent hosting view, so recycling rows cannot repeatedly update
/// the platform-view phase of an entire SwiftUI lazy stack.
struct ConversationTranscriptView<Item: Identifiable, Row: View>: NSViewRepresentable {
    let items: [Item]
    let proxy: ConversationScrollProxy
    let viewport: ConversationViewportController
    let followsOutput: Bool
    @ViewBuilder let row: (Item) -> Row

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.setAccessibilityIdentifier("conversation.transcript")
        context.coordinator.install(in: scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(self)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.disconnect()
    }

    @MainActor
    final class Coordinator {
        private var parent: ConversationTranscriptView
        private weak var scroll: NSScrollView?
        private let document = TranscriptDocument()
        private var observations: [NSObjectProtocol] = []
        private var cells: [AnyHashable: TranscriptCell<Row>] = [:]
        private var heights: [AnyHashable: CGFloat] = [:]
        private var ids: [AnyHashable] = []
        private var indices: [AnyHashable: Int] = [:]
        private var offsets: [CGFloat] = [12]
        private var width: CGFloat = 0
        private var scheduled = false
        private var rendering = false
        private var updateContent = true
        private var pendingSeek: (AnyHashable, UnitPoint)?
        private var connected = true

        init(_ parent: ConversationTranscriptView) { self.parent = parent }

        func install(in scroll: NSScrollView) {
            self.scroll = scroll
            scroll.documentView = document
            document.onResize = { [weak self] in self?.scheduleRender() }
            scroll.contentView.postsBoundsChangedNotifications = true
            observations.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRender() }
            })
            for view in [scroll, scroll.contentView] {
                view.postsFrameChangedNotifications = true
                observations.append(NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: view, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scheduleRender() }
                })
            }
            parent.proxy.seek = { [weak self] id, anchor in self?.seek(id, anchor: anchor) }
            parent.proxy.owner = self
            parent.viewport.connect(to: scroll)
            update(parent)
        }

        func update(_ parent: ConversationTranscriptView) {
            self.parent = parent
            let nextIDs = parent.items.map { AnyHashable($0.id) }
            if ids != nextIDs {
                ids = nextIDs
                indices = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
                let retained = Set(ids)
                heights = heights.filter { retained.contains($0.key) }
                for id in Array(cells.keys) where !retained.contains(id) { removeCell(id) }
                rebuildOffsets()
            }
            updateContent = true
            scheduleRender()
        }

        private func scheduleRender() {
            guard connected, !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scheduled = false
                self.render()
            }
        }

        private func rebuildOffsets() {
            offsets = [12]
            offsets.reserveCapacity(ids.count + 1)
            for id in ids { offsets.append(offsets.last! + (heights[id] ?? 160)) }
        }

        private func index(at y: CGFloat) -> Int {
            guard !ids.isEmpty else { return 0 }
            var lower = 0
            var upper = ids.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if offsets[middle + 1] <= y { lower = middle + 1 }
                else { upper = middle }
            }
            return min(lower, ids.count - 1)
        }

        private func range(around rect: CGRect) -> Range<Int> {
            guard !ids.isEmpty else { return 0..<0 }
            let margin = max(800, rect.height)
            let first = index(at: max(0, rect.minY - margin))
            let last = index(at: rect.maxY + margin)
            return first..<min(ids.count, last + 1)
        }

        private func seek(_ id: AnyHashable, anchor: UnitPoint) {
            parent.viewport.prepareForSeek(messageID: id.base as? UUID, fraction: anchor.y)
            pendingSeek = (id, anchor)
            render()
        }

        private func render() {
            guard connected, !rendering, let scroll else { return }
            let nextWidth = max(1, scroll.contentSize.width)
            guard nextWidth > 100, scroll.contentSize.height > 0 else { return }
            rendering = true
            defer { rendering = false }

            let wasAtBottom = parent.followsOutput && parent.viewport.isNearBottom
            let hadPendingRestoration = parent.viewport.hasPendingRestoration
            let checkpoint = !wasAtBottom && pendingSeek == nil
                ? parent.viewport.capture() : nil
            let resized = abs(width - nextWidth) > 0.5
            if resized {
                width = nextWidth
                heights.removeAll()
                rebuildOffsets()
                updateContent = true
            }
            var visible = scroll.documentVisibleRect
            if resized, let checkpoint, let index = indices[AnyHashable(checkpoint.messageID)] {
                visible.origin.y = offsets[index] - checkpoint.offset
            }
            if let (id, anchor) = pendingSeek {
                if id == AnyHashable("Bottom") {
                    visible.origin.y = max(0, (offsets.last ?? 12) + 18 - visible.height)
                } else if let index = indices[id] {
                    visible.origin.y = offsets[index] - max(0, visible.height - (heights[id] ?? 160)) * anchor.y
                }
            }

            let visibleRange = range(around: visible)
            let wanted = Set(visibleRange.map { ids[$0] })
            for id in Array(cells.keys) where !wanted.contains(id) { removeCell(id) }

            var changedHeight = false
            for index in visibleRange {
                let id = ids[index]
                let root = TranscriptCellContent(content: parent.row(parent.items[index]), width: width)
                let cell: TranscriptCell<Row>
                if let existing = cells[id] {
                    cell = existing
                    if updateContent { cell.rootView = root }
                } else {
                    cell = TranscriptCell(rootView: root)
                    cell.onSizeChange = { [weak self] in self?.scheduleRender() }
                    cells[id] = cell
                    document.addSubview(cell)
                }
                let measured = ceil(cell.fittingSize.height)
                let height = measured.isFinite ? max(1, measured) : (heights[id] ?? 160)
                if abs((heights[id] ?? 160) - height) > 0.5 {
                    heights[id] = height
                    changedHeight = true
                } else if heights[id] == nil {
                    heights[id] = height
                }
            }
            updateContent = false
            if changedHeight { rebuildOffsets() }
            let size = NSSize(width: width, height: max(scroll.contentSize.height, (offsets.last ?? 12) + 18))
            if document.frame.size != size { document.setFrameSize(size) }

            for (id, cell) in cells {
                guard let index = indices[id] else { continue }
                let frame = NSRect(x: 0, y: offsets[index], width: width, height: heights[id] ?? 160)
                if cell.frame != frame { cell.frame = frame }
                if let messageID = id.base as? UUID {
                    parent.viewport.register(cell, messageID: messageID)
                    parent.viewport.messageDidLayout(messageID, frame: frame)
                }
            }
            if let (id, anchor) = pendingSeek {
                pendingSeek = nil
                let y: CGFloat
                if id == AnyHashable("Bottom") {
                    y = max(0, document.bounds.height - scroll.contentSize.height)
                } else if let index = indices[id] {
                    y = offsets[index] - max(0, scroll.contentSize.height - (heights[id] ?? 160)) * anchor.y
                } else { return }
                setOffset(y, in: scroll)
            } else if changedHeight {
                if wasAtBottom {
                    setOffset(max(0, document.bounds.height - scroll.contentSize.height), in: scroll)
                } else if let checkpoint, !hadPendingRestoration {
                    parent.viewport.preserve(checkpoint)
                    parent.viewport.restore()
                } else {
                    parent.viewport.restore()
                }
            }
            if range(around: scroll.documentVisibleRect) != visibleRange { scheduleRender() }
        }

        private func setOffset(_ y: CGFloat, in scroll: NSScrollView) {
            var bounds = scroll.contentView.bounds
            bounds.origin.y = y
            let constrained = scroll.contentView.constrainBoundsRect(bounds)
            guard abs(constrained.minY - scroll.contentView.bounds.minY) > 0.5 else { return }
            scroll.contentView.scroll(to: constrained.origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        private func removeCell(_ id: AnyHashable) {
            guard let cell = cells.removeValue(forKey: id) else { return }
            cell.onSizeChange = nil
            if let messageID = id.base as? UUID { parent.viewport.unregister(cell, messageID: messageID) }
            cell.removeFromSuperview()
        }

        func disconnect() {
            connected = false
            observations.forEach(NotificationCenter.default.removeObserver)
            observations.removeAll()
            if parent.proxy.owner === self {
                parent.proxy.seek = nil
                parent.proxy.owner = nil
            }
            document.onResize = nil
            for id in Array(cells.keys) { removeCell(id) }
            scroll = nil
        }
    }
}

private final class TranscriptDocument: NSView {
    var onResize: (() -> Void)?
    override var isFlipped: Bool { true }
    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        if changed { onResize?() }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onResize?()
    }
}

private struct TranscriptCellContent<Content: View>: View {
    let content: Content
    let width: CGFloat
    var body: some View { content.frame(width: width) }
}

private final class TranscriptCell<Content: View>: NSHostingView<TranscriptCellContent<Content>> {
    var onSizeChange: (() -> Void)?
    required init(rootView: TranscriptCellContent<Content>) {
        super.init(rootView: rootView)
        sizingOptions = [.intrinsicContentSize]
    }
    required init?(coder: NSCoder) { nil }
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onSizeChange?()
    }
}
