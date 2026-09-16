import AppKit

/// A small, predictable selection menu. OS writing tools, sharing, substitutions
/// and Services do not belong in a response or shell-output selection.
@MainActor
enum TextContextMenu {
    static func make(for textView: NSTextView) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let selection = textView.selectedRanges.contains { $0.rangeValue.length > 0 }
        if textView.isEditable {
            add("Cut", action: #selector(NSText.cut(_:)), target: textView, enabled: selection, to: menu)
        }
        add("Copy", action: #selector(NSText.copy(_:)), target: textView, enabled: selection, to: menu)
        if textView.isEditable {
            add("Paste", action: #selector(NSText.paste(_:)), target: textView, enabled: true, to: menu)
        }
        menu.addItem(.separator())
        add("Select All", action: #selector(NSText.selectAll(_:)), target: textView, enabled: !textView.string.isEmpty, to: menu)
        return menu
    }

    private static func add(_ title: String, action: Selector, target: AnyObject, enabled: Bool, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.isEnabled = enabled
        menu.addItem(item)
    }
}

final class OutputTextView: NSTextView {
    override func menu(for event: NSEvent) -> NSMenu? { TextContextMenu.make(for: self) }
}
