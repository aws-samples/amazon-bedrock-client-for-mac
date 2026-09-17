import AppKit
import SwiftUI

/// A single native text selection and Find bar for potentially long tool output.
/// Wrapping changes only layout; Copy retains exact whitespace and line breaks.
struct ToolOutputView: NSViewRepresentable {
    var text: String
    var findRequest: Int
    var initialQuery = ""
    var accessibilityLabel = "Tool detail text"

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        let editor = OutputTextView(frame: .zero, textContainer: container)
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        editor.isEditable = false
        editor.isSelectable = true
        editor.isRichText = false
        editor.drawsBackground = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 14, height: 14)
        editor.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        editor.textColor = .labelColor
        editor.usesFindBar = true
        editor.isIncrementalSearchingEnabled = true
        editor.isAutomaticLinkDetectionEnabled = false
        editor.allowsUndo = false
        editor.setAccessibilityLabel(accessibilityLabel)
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.accessibilityLabel() != accessibilityLabel {
            editor.setAccessibilityLabel(accessibilityLabel)
        }
        if editor.string != text {
            editor.string = text
            editor.setSelectedRange(NSRange(location: 0, length: 0))
            editor.scrollRangeToVisible(NSRange(location: 0, length: 0))
            context.coordinator.query = nil
        }
        if context.coordinator.query != initialQuery {
            context.coordinator.query = initialQuery
            if !initialQuery.isEmpty {
                let range = (text as NSString).range(of: initialQuery, options: [.caseInsensitive, .diacriticInsensitive])
                if range.location != NSNotFound {
                    editor.setSelectedRange(range)
                    editor.scrollRangeToVisible(range)
                }
            }
        }
        if context.coordinator.findRequest != findRequest {
            context.coordinator.findRequest = findRequest
            scroll.window?.makeFirstResponder(editor)
            let action = NSMenuItem()
            action.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
            editor.performFindPanelAction(action)
        }
    }
    final class Coordinator {
        var findRequest = 0
        var query: String?
    }
}

struct ConversationSearchDetail: Identifiable {
    var id = UUID()
    var title: String
    var text: String
    var query: String
}

struct ConversationSearchDetailView: View {
    let detail: ConversationSearchDetail
    @Environment(\.dismiss) private var dismiss
    @State private var findRequest = 0
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(detail.title).font(.title3.weight(.semibold)).lineLimit(1)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(detail.text, forType: .string)
                }
                Button("Find", systemImage: "magnifyingglass") { findRequest += 1 }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ToolOutputView(text: detail.text, findRequest: findRequest, initialQuery: detail.query)
                .background(DesignTokens.field, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(DesignTokens.border))
        }
        .padding(24).frame(width: 680, height: 510)
        .accessibilityIdentifier("conversation.searchDetail")
    }
}
