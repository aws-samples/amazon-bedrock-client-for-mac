import AppKit
import SwiftUI

/// Keep AppKit's scrolling, hit testing and accessibility while avoiding a separate
/// opaque track beside a transparent sidebar. Resolve the List's scroll view once;
/// no scroll notifications, custom drag handling or per-frame traversal is needed.
struct SidebarScrollChrome: NSViewRepresentable {
    var viewport: ConversationViewportController?
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) {
        view.viewport = viewport
        view.scheduleUpdate()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ChromeView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 1, height: proposal.height ?? 1)
    }

    final class ChromeView: NSView {
        weak var viewport: ConversationViewportController?
        private var updateScheduled = false
        private weak var styledScrollView: NSScrollView?
        private var resolutionAttempts = 0

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            scheduleUpdate()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            styledScrollView = nil
            resolutionAttempts = 0
            scheduleUpdate()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            scheduleUpdate()
        }

        override func layout() {
            super.layout()
            if styledScrollView == nil, resolutionAttempts < 3 { scheduleUpdate() }
        }

        func scheduleUpdate() {
            guard !updateScheduled else { return }
            updateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateScheduled = false
                guard self.window != nil, let scroll = self.styledScrollView ?? self.findListScrollView() else { return }
                self.styledScrollView = scroll
                self.viewport?.connect(to: scroll)
                if !(scroll.verticalScroller is SidebarScroller) {
                    let previous = scroll.verticalScroller
                    let scroller = SidebarScroller(frame: previous?.frame ?? .zero)
                    scroller.floatValue = previous?.floatValue ?? 0
                    scroller.knobProportion = previous?.knobProportion ?? 1
                    scroll.verticalScroller = scroller
                }
                if scroll.scrollerStyle != .overlay { scroll.scrollerStyle = .overlay }
                if scroll.drawsBackground { scroll.drawsBackground = false }
                if scroll.contentView.drawsBackground { scroll.contentView.drawsBackground = false }
                if scroll.borderType != .noBorder { scroll.borderType = .noBorder }
                if scroll.hasHorizontalScroller { scroll.hasHorizontalScroller = false }
                if scroll.verticalScroller?.controlSize != .small { scroll.verticalScroller?.controlSize = .small }
                let knob: NSScroller.KnobStyle = self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .light : .dark
                if scroll.scrollerKnobStyle != knob { scroll.scrollerKnobStyle = knob }
            }
        }

        private func findListScrollView() -> NSScrollView? {
            if let enclosingScrollView { return enclosingScrollView }
            guard resolutionAttempts < 3, bounds.width > 1, bounds.height > 1,
                  let root = window?.contentView else { return nil }
            resolutionAttempts += 1
            // SwiftUI may place a List's background outside its AppKit subtree.
            // Match the public scroll-view geometry to this List's background,
            // rather than depending on private class names or a fixed hierarchy.
            let target = convert(bounds, to: nil)
            var pending: [NSView] = [root]
            var index = 0
            var matches: [NSScrollView] = []
            while index < pending.count, index < 512 {
                let view = pending[index]
                index += 1
                if let scroll = view as? NSScrollView {
                    let frame = scroll.convert(scroll.bounds, to: nil)
                    if frame.insetBy(dx: -1, dy: -1).contains(target) {
                        matches.append(scroll)
                    }
                }
                pending.append(contentsOf: view.subviews)
            }
            #if DEBUG
            if ProcessInfo.processInfo.environment["BEDROCK_RENDER_DIAGNOSTICS"] == "1" {
                NSLog("[SidebarScroll] target=%@ matches=%ld inspected=%ld", NSStringFromRect(target), matches.count, index)
            }
            #endif
            return matches.count == 1 ? matches.first : nil
        }
    }

    /// SwiftUI can restore the system's "Always" scroller style after List layout.
    /// Its native drag/page/keyboard behavior is kept in that style too; only the
    /// opaque slot is removed and the thumb receives a restrained rounded shape.
    private final class SidebarScroller: NSScroller {
        override class var isCompatibleWithOverlayScrollers: Bool { true }
        override var isOpaque: Bool { false }

        override func draw(_ dirtyRect: NSRect) { drawKnob() }
        override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

        override func drawKnob() {
            guard isEnabled, knobProportion < 1 else { return }
            let knob = rect(for: .knob)
            guard knob.height > 0 else { return }
            let thumb = NSRect(x: knob.midX - 2.5, y: knob.minY + 2, width: 5, height: max(0, knob.height - 4))
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            (dark ? NSColor.white : .black).withAlphaComponent(isHighlighted ? 0.45 : 0.22).setFill()
            NSBezierPath(roundedRect: thumb, xRadius: 2.5, yRadius: 2.5).fill()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }
    }
}
