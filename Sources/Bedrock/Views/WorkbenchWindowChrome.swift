import AppKit
import SwiftUI

/// The native toolbar keeps its controls and drag area while allowing the
/// sidebar material to continue behind the traffic lights.
struct WorkbenchWindowChrome: NSViewRepresentable {
    var hidesTitle = true
    final class ChromeView: NSView {
        var hidesTitle = true
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyStyle()
        }
        func applyStyle() {
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = hidesTitle ? .hidden : .visible
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = NSColor(WorkbenchStyle.canvas)
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
