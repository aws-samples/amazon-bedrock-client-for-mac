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

/**
 * A specialized NSTextView that handles image paste operations, drag-and-drop,
 * and custom text entry behaviors for the Bedrock client.
 *
 * Features:
 * - Multi-image paste support (limited to 10 images)
 * - Order-preserving image processing
 * - Loading indicator during paste operations
 * - Placeholder text support
 * - Custom keyboard shortcuts handling
 */
final class MyTextView: NSTextView {
    var onPaste: ((NSImage) -> Void)?
    var onCommit: (() -> Void)?
    var onPasteStarted: (() -> Void)?
    var onPasteCompleted: (() -> Void)?
    var placeholderString: String? {
        didSet {
            needsDisplay = true
        }
    }
    
    // Maximum number of images allowed for paste operation
    private let maxImagesAllowed = 10
    // Track if a paste operation is in progress
    private var isPasteInProgress = false
    
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
        // Indicate paste operation has started
        notifyPasteStarted()
        
        // Perform paste handling
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
        
        // Indicate paste operation has started
        notifyPasteStarted()
        
        // Process multiple dragged files with order preservation
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let validURLs = fileURLs.filter { url in
                let fileType = UTType(filenameExtension: url.pathExtension) ?? .data
                return supportedTypes.contains(fileType)
            }
            
            if !validURLs.isEmpty {
                // Limit to maximum allowed images
                let imagesToProcess = validURLs.prefix(maxImagesAllowed)
                
                // Process images sequentially to preserve order
                DispatchQueue.global(qos: .userInitiated).async {
                    var processedImages = 0
                    
                    for url in imagesToProcess {
                        if let image = NSImage(contentsOf: url),
                           image.isValidImage(fileURL: url, maxSize: 10 * 1024 * 1024, maxWidth: 8000, maxHeight: 8000) {
                            DispatchQueue.main.sync {
                                self.onPaste?(image)
                                processedImages += 1
                            }
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.notifyPasteCompleted()
                    }
                }
                
                return true
            }
        }
        
        notifyPasteCompleted()
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
        var imageProcessed = false // Track if image was already processed
        
        // List of supported image extensions
        let supportedExtensions = ["jpg", "jpeg", "png", "gif", "tiff", "bmp", "webp", "heic"]
        
        // 1. Process file URLs first - maintain order
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in fileURLs {
                // Check maximum image count
                if pastedImages.count >= maxImagesAllowed {
                    break
                }
                
                let ext = url.pathExtension.lowercased()
                if supportedExtensions.contains(ext), let image = NSImage(contentsOf: url) {
                    pastedImages.append(image)
                    imageProcessed = true // Set image processed flag
                }
            }
        }
        
        // 2. Process image data directly - only if no images processed yet
        if !imageProcessed && pastedImages.isEmpty {
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
                if let imageData = pasteboard.data(forType: type),
                   let image = NSImage(data: imageData) {
                    pastedImages.append(image)
                    imageProcessed = true // Set image processed flag
                    break // Add only first valid image
                }
            }
        }
        
        // 3. Try to extract image URLs from HTML content - only if no images processed yet
        if !imageProcessed && pastedImages.isEmpty,
           let htmlString = pasteboard.string(forType: .html) {
            let (imageUrls, extractedText) = extractContentFromHTML(htmlString)
            pastedText = extractedText
            
            if !imageUrls.isEmpty {
                // Limit to maximum allowed images
                let urlsToProcess = imageUrls.prefix(maxImagesAllowed)
                
                // Process sequentially to preserve order
                let group = DispatchGroup()
                let queue = DispatchQueue(label: "com.amazon.bedrock.imagefetching", qos: .userInitiated)
                
                // Array to process image URLs sequentially
                var orderedImages = [(Int, NSImage)]()
                
                for (index, imageURL) in urlsToProcess.enumerated() {
                    group.enter()
                    
                    queue.async {
                        URLSession.shared.dataTask(with: imageURL) { data, response, error in
                            defer { group.leave() }
                            
                            if let data = data, let image = NSImage(data: data) {
                                // Store image with index
                                orderedImages.append((index, image))
                            }
                        }.resume()
                    }
                }
                
                group.notify(queue: .main) {
                    // Sort images by original order
                    let sortedImages = orderedImages.sorted { $0.0 < $1.0 }.map { $0.1 }
                    
                    // Check for duplication (ignore if already processed)
                    if !imageProcessed {
                        pastedImages.append(contentsOf: sortedImages)
                        imageProcessed = true
                    }
                    
                    self.handlePastedContent(images: pastedImages, text: pastedText, imageProcessed: imageProcessed)
                    self.notifyPasteCompleted()
                }
                
                // Return early if HTML processing is in progress
                if !urlsToProcess.isEmpty {
                    return
                }
            }
        }
        
        // 4. Process immediately if no HTML handling
        handlePastedContent(images: pastedImages, text: pastedText, imageProcessed: imageProcessed)
        notifyPasteCompleted()
    }

    private func handlePastedContent(images: [NSImage], text: String, imageProcessed: Bool) {
        if !images.isEmpty {
            // Process images in order
            images.forEach { self.onPaste?($0) }
        }
        
        if !text.isEmpty {
            self.insertText(text, replacementRange: self.selectedRange())
        }
        
        if !imageProcessed && images.isEmpty && text.isEmpty {
            // Fall back to standard paste if no images or HTML text
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
        // 검색 필드가 활성화되었는지 확인
        if AppStateManager.shared.isSearchFieldActive {
            // 검색 필드가 활성화된 경우 기본 동작 허용
            return super.performKeyEquivalent(with: event)
        }
        
        // 검색 필드가 활성화되지 않은 경우 Command+V 처리
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
    
    // Notify that paste operation has started
    private func notifyPasteStarted() {
        if !isPasteInProgress {
            isPasteInProgress = true
            DispatchQueue.main.async {
                self.onPasteStarted?()
            }
        }
    }
    
    // Notify that paste operation has completed
    private func notifyPasteCompleted() {
        if isPasteInProgress {
            isPasteInProgress = false
            DispatchQueue.main.async {
                self.onPasteCompleted?()
            }
        }
    }
}

/// Extension to validate NSImage properties against specified constraints.
extension NSImage {
    func isValidImage(fileURL: URL, maxSize: Int, maxWidth: Int, maxHeight: Int) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? Int,
              fileSize <= maxSize else {
            return false
        }
        
        guard let tiffData = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
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
    @Binding var isPasting: Bool  // New binding for paste operation status
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
        lhs.text == rhs.text && lhs.isDisabled == rhs.isDisabled && lhs.isPasting == rhs.isPasting
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
            
            // Set up paste operation callbacks
            textView.onPasteStarted = {
                DispatchQueue.main.async {
                    context.coordinator.parent.isPasting = true
                }
            }
            
            textView.onPasteCompleted = {
                DispatchQueue.main.async {
                    context.coordinator.parent.isPasting = false
                }
            }
            
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

// Utility extensions
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

// Optimized pasteboard extension
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
