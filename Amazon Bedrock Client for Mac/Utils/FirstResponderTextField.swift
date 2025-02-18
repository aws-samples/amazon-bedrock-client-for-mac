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
    var placeholderString: String? {
        didSet {
            needsDisplay = true
        }
    }
    
    func moveCursorToEnd() {
        let length = string.count
        setSelectedRange(NSRange(location: length, length: 0))
        scrollRangeToVisible(NSRange(location: length, length: 0))
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        if string.isEmpty, let placeholder = placeholderString {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.placeholderTextColor
            ]
            let rect = NSRect(x: textContainerInset.width + 5,
                              y: textContainerInset.height,
                              width: bounds.width - textContainerInset.width * 2,
                              height: bounds.height)
            placeholder.draw(in: rect, withAttributes: attributes)
        }
    }
    
    /// Handles the paste operation to intercept image pasting and custom text handling.
    override func paste(_ sender: Any?) {
        handlePaste()
        self.inputContext?.discardMarkedText()
        self.needsDisplay = true
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
    
    override func doCommand(by selector: Selector) {
        if selector == #selector(paste(_:)) {
            paste(nil)
        } else if selector == #selector(insertNewline(_:)) {
            if let event = NSApp.currentEvent, event.modifierFlags.contains(.shift) {
                super.insertText("\n", replacementRange: selectedRange())
            } else {
                onCommit?()
            }
        } else {
            super.doCommand(by: selector)
        }
    }
    
    private func handlePaste() {
        let pasteboard = NSPasteboard.general
        var pastedImages: [NSImage] = []
        var pastedText: String = ""
        
        // 지원하는 이미지 확장자 목록
        let supportedExtensions = ["jpg", "jpeg", "png", "gif", "tiff", "bmp", "webp", "heic"]
        
        // 파일 URL 처리
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in fileURLs {
                let ext = url.pathExtension.lowercased()
                if supportedExtensions.contains(ext), let image = NSImage(contentsOf: url) {
                    pastedImages.append(image)
                }
            }
        }
        
        // 이미지 데이터 직접 처리
        let types: [NSPasteboard.PasteboardType] = [
            .tiff,
            .png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("com.compuserve.gif"),
            NSPasteboard.PasteboardType("com.microsoft.bmp"),
            NSPasteboard.PasteboardType("org.webmproject.webp"),
            NSPasteboard.PasteboardType("public.heic")
        ]
        
        for type in types {
            if pastedImages.isEmpty, let imageData = pasteboard.data(forType: type), let image = NSImage(data: imageData) {
                pastedImages.append(image)
                break // 첫 번째 유효한 이미지만 추가
            }
        }
        
        // HTML 내용에서 이미지 URL 추출 시도
        if pastedImages.isEmpty, let htmlString = pasteboard.string(forType: .html) {
            let (imageUrls, extractedText) = extractContentFromHTML(htmlString)
            pastedText = extractedText
            
            let group = DispatchGroup()
            for imageURL in imageUrls {
                group.enter()
                URLSession.shared.dataTask(with: imageURL) { data, response, error in
                    defer { group.leave() }
                    if let data = data, let image = NSImage(data: data) {
                        DispatchQueue.main.async {
                            pastedImages.append(image)
                        }
                    }
                }.resume()
            }
            
            group.notify(queue: .main) {
                self.handlePastedContent(images: pastedImages, text: pastedText)
            }
        } else {
            handlePastedContent(images: pastedImages, text: pastedText)
        }
    }
    
    private func handlePastedContent(images: [NSImage], text: String) {
        if !images.isEmpty {
            images.forEach { self.onPaste?($0) }
        }
        
        if !text.isEmpty {
            self.insertText(text, replacementRange: self.selectedRange())
        }
        
        if images.isEmpty && text.isEmpty {
            // 이미지와 HTML 텍스트가 모두 없으면 일반 텍스트 붙여넣기
            super.paste(nil)
        }
    }
    
    private func extractContentFromHTML(_ html: String) -> ([URL], String) {
        let imageUrls = extractImageURLsFromHTML(html)
        let text = extractTextFromHTML(html)
        return (imageUrls, text)
    }
    
    private func extractTextFromHTML(_ html: String) -> String {
        guard let data = html.data(using: .utf8) else { return "" }
        
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        if let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributedString.string
        }
        
        return ""
    }
    
    private func extractImageURLsFromHTML(_ html: String) -> [URL] {
        let imagePattern = "<img[^>]+src\\s*=\\s*['\"]([^'\"]+)['\"][^>]*>"
        let imageRegex = try? NSRegularExpression(pattern: imagePattern, options: .caseInsensitive)
        var imageUrls: [URL] = []
        
        if let matches = imageRegex?.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) {
            for match in matches {
                if let range = Range(match.range(at: 1), in: html) {
                    let urlString = String(html[range])
                    if let url = URL(string: urlString) {
                        imageUrls.append(url)
                    }
                }
            }
        }
        
        return imageUrls
    }
    
    // Implement the performKeyEquivalent to catch Command+V (paste)
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            if event.keyCode == 9 { // 'V' key
                paste(nil)
                self.inputContext?.discardMarkedText()
                self.needsDisplay = true
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}


/// Extension to validate NSImage properties against specified constraints.
extension NSImage {
    func isValidImage(fileURL: URL, maxSize: Int, maxWidth: Int, maxHeight: Int) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? Int,
              fileSize <= maxSize,
              let image = NSImage(contentsOf: fileURL),
              let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!) else {
            return false
        }
        
        let size = bitmap.size
        return Int(size.width) <= maxWidth && Int(size.height) <= maxHeight
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
        let coordinator = Coordinator(self, onPaste: onPaste)
        
        // Add observer for transcript updates
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.handleTranscriptUpdate(_:)),
            name: .transcriptUpdated,
            object: nil
        )
        
        return coordinator
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
            
            // Placeholder 텍스트 추가
            let placeholder = "Message Bedrock (⇧ + ↩ for new line)"
            textView.placeholderString = placeholder
            
            updateHeight(textView: textView)
            
            NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.textDidChange(_:)), name: NSText.didChangeNotification, object: textView)
            
            context.coordinator.textView = textView
        }
        
        DispatchQueue.main.async {
            scrollView.window?.makeFirstResponder(scrollView.documentView)
        }
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? MyTextView else { return }
        
        if textView.string != self.text {
            let selectedRanges = textView.selectedRanges
            textView.string = self.text
            textView.selectedRanges = selectedRanges
            updateHeight(textView: textView)
        }
        textView.isEditable = !self.isDisabled
    }
    
    public func updateHeight(textView: MyTextView) {
        let layoutManager = textView.layoutManager!
        let textContainer = textView.textContainer!
        
        layoutManager.ensureLayout(for: textContainer)
        let newHeight = max(40, min(200, layoutManager.usedRect(for: textContainer).height + textView.textContainerInset.height * 2))
        
        if abs(newHeight - calculatedHeight) > 1 {
            DispatchQueue.main.async {
                self.calculatedHeight = newHeight
            }
        }
    }
}

/// Coordinator for managing updates and interactions between SwiftUI and AppKit components.
public class Coordinator: NSObject, NSTextViewDelegate {
    var parent: FirstResponderTextView
    var onPaste: ((NSImage) -> Void)?
    weak var textView: MyTextView?
    
    init(_ parent: FirstResponderTextView, onPaste: ((NSImage) -> Void)?) {
        self.parent = parent
        self.onPaste = onPaste
    }
    
    @objc public func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? MyTextView else { return }
        updateText(textView)
    }
    
    private func updateText(_ textView: MyTextView) {
        parent.text = textView.string
        parent.updateHeight(textView: textView)
    }
    
    @objc func handleTranscriptUpdate(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.textView?.moveCursorToEnd()
        }
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
