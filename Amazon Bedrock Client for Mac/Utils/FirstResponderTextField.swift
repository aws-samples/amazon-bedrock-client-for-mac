//
//  FirstResponderTextView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

/// A subclass of `NSTextView` that handles paste operations and drag-and-drop for images,
/// and commits text entries with custom actions.
final class MyTextView: NSTextView {
    var onPaste: ((NSImage) -> Void)?
    var onCommit: (() -> Void)?
    
    /// Handles the paste operation to intercept image pasting and custom text handling.
    override func paste(_ sender: Any?) {
        handlePaste()
    }
    
    /// Handles the entry of dragged items, checking for supported image formats.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let supportedTypes = [UTType.jpeg, UTType.png, UTType.gif, UTType.webP]
        
        if let fileURL = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL,
           supportedTypes.contains(UTType(filenameExtension: fileURL.pathExtension) ?? .data),
           let image = NSImage(contentsOf: fileURL),
           image.isValidImage(fileURL: fileURL, maxSize: 10 * 1024 * 1024, maxWidth: 8000, maxHeight: 8000) {
            DispatchQueue.main.async {
                self.onPaste?(image)
            }
            return true
        }
        return false
    }
    
    /// Overrides default command handling to support custom 'Enter' and 'Shift+Enter' actions.
    override func doCommand(by selector: Selector) {
        if selector == #selector(paste(_:)) {
            paste(nil)
        } else if let event = NSApp.currentEvent, event.modifierFlags.contains(.shift), selector == #selector(insertLineBreak(_:)) {
            self.insertText("\n", replacementRange: self.selectedRange())
        } else if selector == #selector(insertNewline(_:)) {
            onCommit?()
        } else {
            super.doCommand(by: selector)
        }
    }
    
    private func handlePaste() {
        let pasteboard = NSPasteboard.general
        if let imageData = pasteboard.data(forType: .tiff), let image = NSImage(data: imageData) {
            DispatchQueue.main.async {
                self.onPaste?(image)
            }
        } else if let imageData = pasteboard.data(forType: .png), let image = NSImage(data: imageData) {
            DispatchQueue.main.async {
                self.onPaste?(image)
            }
        } else if let imageData = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")), let image = NSImage(data: imageData) {
            DispatchQueue.main.async {
                self.onPaste?(image)
            }
        } else {
            // 이미지 파일이 있을 경우 처리
            let imageFilesWithNames = pasteboard.imageFilesWithNames
            if !imageFilesWithNames.isEmpty {
                DispatchQueue.main.async {
                    imageFilesWithNames.forEach { self.onPaste?($0.image) }
                }
            } else {
                super.paste(nil)
            }
        }
    }
    
    // Implement the performKeyEquivalent to catch Command+V (paste)
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.keyCode == 9 { // 9 is the keyCode for "V" on US keyboards
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}


/// Extension to validate NSImage properties against specified constraints.
extension NSImage {
    func isValidImage(fileURL: URL, maxSize: Int, maxWidth: Int, maxHeight: Int) -> Bool {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        guard let image = NSImage(contentsOf: fileURL),
              let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!) else { return false }
        
        let size = bitmap.size
        return Int(size.width) <= maxWidth && Int(size.height) <= maxHeight && fileSize <= maxSize
    }
}

/// SwiftUI view for integrating an `NSTextView` into SwiftUI, supporting dynamic height adjustments and text operations.
struct FirstResponderTextView: NSViewRepresentable, Equatable {
    @Binding var text: String
    @Binding var isDisabled: Bool
    @Binding var calculatedHeight: CGFloat
    var onCommit: () -> Void
    var onPaste: ((NSImage) -> Void)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self, onPaste: onPaste)
    }
    
    static func == (lhs: FirstResponderTextView, rhs: FirstResponderTextView) -> Bool {
        lhs.text == rhs.text && lhs.isDisabled == rhs.isDisabled
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = MyTextView.scrollableTextView()
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        
        if let textView = scrollView.documentView as? MyTextView {
            textView.delegate = context.coordinator
            textView.onPaste = { image in context.coordinator.parent.onPaste?(image) }
            textView.onCommit = { context.coordinator.parent.onCommit() }
            textView.registerForDraggedTypes([.fileURL])
            textView.font = NSFont.systemFont(ofSize: 15)
            textView.isRichText = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.allowsUndo = true
            textView.becomeFirstResponder()
            
            textView.textContainerInset = CGSize(width: 5, height: 10)
            textView.textColor = NSColor(Color.text)
            textView.backgroundColor = .clear
            
            updateHeight(textView: textView)
        }
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? MyTextView {
            if textView.string != self.text {
                textView.string = self.text
                updateHeight(textView: textView)
            }
            // textView.isEditable = !self.isDisabled
        }
    }
    
    /// Updates the height of the text view based on the content size.
    public func updateHeight(textView: MyTextView) {
        let size = textView.attributedString().boundingRect(with: NSSize(width: textView.bounds.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        DispatchQueue.main.async {
            self.calculatedHeight = max(40, min(200, size.height + textView.textContainerInset.height * 2)) // Ensure the view is at least 40 points tall and at most 200 points tall
        }
    }
}

/// Coordinator for managing updates and interactions between SwiftUI and AppKit components.
public class Coordinator: NSObject, NSTextViewDelegate {
    var parent: FirstResponderTextView
    var onPaste: ((NSImage) -> Void)?
    
    init(_ parent: FirstResponderTextView, onPaste: ((NSImage) -> Void)?) {
        self.parent = parent
        self.onPaste = onPaste
    }
    
    public func textDidChange(_ notification: Notification) {
        if let textView = notification.object as? MyTextView {
            DispatchQueue.main.async {
                self.parent.text = textView.string
                self.parent.updateHeight(textView: textView)
            }
        }
    }
    
    func textView(_ textView: MyTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSTextView.paste(_:)) {
            textView.performSelector(onMainThread: #selector(NSTextView.paste(_:)), with: nil, waitUntilDone: true)
            return true
        } else if let event = NSApp.currentEvent, event.modifierFlags.contains(.shift) {
            if commandSelector == #selector(NSResponder.insertLineBreak(_:)) {
                return false  // Allow default behavior to insert a new line
            }
        } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            parent.onCommit()
            return true
        }
        return false
    }
}

/// Extension to calculate the bounding box for an attributed string.
extension NSAttributedString {
    func height(withConstrainedWidth width: CGFloat) -> CGFloat {
        let constraintRect = CGSize(width: width, height: .greatestFiniteMagnitude)
        let boundingBox = boundingRect(with: constraintRect, options: .usesLineFragmentOrigin, context: nil)
        
        return ceil(boundingBox.height)
    }
    
    func width(withConstrainedHeight height: CGFloat) -> CGFloat {
        let constraintRect = CGSize(width: .greatestFiniteMagnitude, height: height)
        let boundingBox = boundingRect(with: constraintRect, options: .usesLineFragmentOrigin, context: nil)
        
        return ceil(boundingBox.width)
    }
}

extension NSPasteboard {
    var imageFilesWithNames: [(image: NSImage, name: String)] {
        var result: [(NSImage, String)] = []
        for item in pasteboardItems ?? [] {
            if let fileURLString = item.string(forType: .fileURL),
               let fileURL = URL(string: fileURLString) {
                if let image = NSImage(contentsOf: fileURL) {
                    result.append((image, fileURL.lastPathComponent))
                }
            }
        }
        return result
    }
}
