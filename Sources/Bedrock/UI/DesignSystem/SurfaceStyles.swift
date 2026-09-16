import AppKit
import SwiftUI

struct SidebarMaterial: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency {
            DesignTokens.sidebar
        } else {
            Rectangle().fill(.regularMaterial)
                .overlay(colorScheme == .dark ? Color.black.opacity(0.12) : Color.white.opacity(0.52))
        }
    }
}

/// One material layer and divider span the entire window, including its titlebar.
/// A second material behind the sidebar content creates a visible color seam.
struct SplitWindowSurface: View {
    let sidebarWidth: CGFloat
    var body: some View {
        HStack(spacing: 0) {
            SidebarMaterial().frame(width: sidebarWidth)
            DesignTokens.border.frame(width: sidebarWidth > 0 ? 1 : 0)
            DesignTokens.canvas
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Popovers opened from an NSToolbar item must own keyboard focus too.
/// Otherwise keys can continue to edit the message underneath the controls.
struct PopoverFocus: NSViewRepresentable {
    final class FocusView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak window] in window?.makeKey() }
        }
    }
    func makeNSView(context: Context) -> NSView { FocusView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct ComposerSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        Group {
            if #available(macOS 26.0, *), !reduceTransparency {
                content.glassEffect(.regular, in: .rect(cornerRadius: 20))
            } else {
                content.background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(DesignTokens.composerBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}
