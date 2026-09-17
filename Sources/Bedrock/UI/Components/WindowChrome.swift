import AppKit
import SwiftUI

/// The native toolbar keeps its controls and drag area while allowing the
/// sidebar material to continue behind the traffic lights.
struct WindowChrome: NSViewRepresentable {
    var hidesTitle = true
    final class ChromeView: NSView {
        var hidesTitle = true
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyStyle()
        }
        func applyStyle() {
            guard let window else { return }
            // SwiftUI updates this representable during typing, scrolling and
            // sidebar animations. Reassigning styleMask rebuilds AppKit's window
            // frame even when the mask is unchanged, invalidating layout/focus.
            if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
            let visibility: NSWindow.TitleVisibility = hidesTitle ? .hidden : .visible
            if window.titleVisibility != visibility { window.titleVisibility = visibility }
            if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
            if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
            let background = NSColor(DesignTokens.canvas)
            if window.backgroundColor != background { window.backgroundColor = background }
        }
    }
    func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView()
        view.hidesTitle = hidesTitle
        return view
    }
    func updateNSView(_ nsView: ChromeView, context: Context) {
        nsView.hidesTitle = hidesTitle
        nsView.applyStyle()
    }
}
