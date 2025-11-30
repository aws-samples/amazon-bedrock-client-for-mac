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
    var onPasteDocument: ((URL) -> Void)?
    var onPasteLargeText: ((String, String) -> Void)?  // (text content, suggested filename)
    var onCommit: (() -> Void)?
    var onPasteStarted: (() -> Void)?
    var onPasteCompleted: (() -> Void)?
    var allowImagePasting: Bool = true  // Control whether image pasting is allowed
    var treatLargeTextAsFile: Bool = true  // Control whether large text is treated as file attachment
    var largeTextThreshold: Int = 10 * 1024  // 10KB threshold for treating text as file
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
        let supportedImageTypes = [UTType.jpeg, UTType.png, UTType.gif, UTType.webP, UTType.tiff, UTType.bmp, UTType.heic]
        let supportedDocTypes = [UTType.pdf, UTType.commaSeparatedText, UTType.rtf, UTType.plainText,
                                UTType.html, UTType.xml]
        
        // Indicate paste operation has started
        notifyPasteStarted()
        
        // Process multiple dragged files with order preservation
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            var processedAnyFile = false
            
            for url in fileURLs {
                let fileType = UTType(filenameExtension: url.pathExtension) ?? .data
                
                // Handle image files - only if image pasting is allowed
                if allowImagePasting && supportedImageTypes.contains(fileType),
                   let image = NSImage(contentsOf: url),
                   image.isValidImage(fileURL: url, maxSize: 10 * 1024 * 1024, maxWidth: 8000, maxHeight: 8000) {
                    DispatchQueue.main.async {
                        self.onPaste?(image)
                        processedAnyFile = true
                    }
                }
                // Handle document files
                else if supportedDocTypes.contains(fileType) ||
                        ["doc", "docx", "xls", "xlsx", "csv", "pdf", "txt", "md"].contains(url.pathExtension.lowercased()) {
                    DispatchQueue.main.async {
                        self.onPasteDocument?(url)
                        processedAnyFile = true
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.notifyPasteCompleted()
            }
            
            return processedAnyFile
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
        var pastedDocuments: [URL] = []  // Array to store document URLs
        var pastedText: String = ""
        var fileProcessed = false // Track if any file was processed
        
        // List of supported file extensions
        let supportedImageExtensions = ["jpg", "jpeg", "png", "gif", "tiff", "bmp", "webp", "heic"]
        let supportedDocExtensions = ["pdf", "csv", "doc", "docx", "xls", "xlsx", "html", "txt", "md"]
        
        // 1. Process file URLs first - maintain order
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in fileURLs {
                // Check maximum file count
                if pastedImages.count + pastedDocuments.count >= maxImagesAllowed {
                    break
                }
                
                let ext = url.pathExtension.lowercased()
                
                // Handle image files - only if image pasting is allowed
                if allowImagePasting && supportedImageExtensions.contains(ext), let image = NSImage(contentsOf: url) {
                    pastedImages.append(image)
                    fileProcessed = true
                }
                // Handle document files
                else if supportedDocExtensions.contains(ext) {
                    pastedDocuments.append(url)  // Store document URL
                    fileProcessed = true
                }
            }
        }
        
        // 2. Process image data directly - only if no files processed yet and image pasting is allowed
        if allowImagePasting && !fileProcessed && pastedImages.isEmpty {
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
                    fileProcessed = true
                    break // Add only first valid image
                }
            }
        }
        
        // 3. Try to extract image URLs from HTML content - only if no files processed yet and image pasting is allowed
        if !fileProcessed && pastedImages.isEmpty,
           let htmlString = pasteboard.string(forType: .html) {
            let (imageUrls, extractedText) = extractContentFromHTML(htmlString)
            pastedText = extractedText
            
            // Only process image URLs if image pasting is allowed
            if allowImagePasting && !imageUrls.isEmpty {
                // Limit to maximum allowed images
                let urlsToProcess = imageUrls.prefix(maxImagesAllowed)
                
                // Process sequentially to preserve order
                let group = DispatchGroup()
                let queue = DispatchQueue(label: "com.amazon.bedrock.imagefetching", qos: .userInitiated)
                
                // Thread-safe array using NSLock
                final class ImageStorage: @unchecked Sendable {
                    private let lock = NSLock()
                    private var images: [(Int, NSImage)] = []
                    
                    func append(_ item: (Int, NSImage)) {
                        lock.lock()
                        defer { lock.unlock() }
                        images.append(item)
                    }
                    
                    func getSorted() -> [NSImage] {
                        lock.lock()
                        defer { lock.unlock() }
                        return images.sorted { $0.0 < $1.0 }.map { $0.1 }
                    }
                }
                
                let imageStorage = ImageStorage()
                
                for (index, imageURL) in urlsToProcess.enumerated() {
                    group.enter()
                    
                    queue.async {
                        URLSession.shared.dataTask(with: imageURL) { data, response, error in
                            defer { group.leave() }
                            
                            if let data = data, let image = NSImage(data: data) {
                                imageStorage.append((index, image))
                            }
                        }.resume()
                    }
                }
                
                group.notify(queue: .main) {
                    let sortedImages = imageStorage.getSorted()
                    
                    // Check for duplication (ignore if already processed)
                    if !fileProcessed {
                        pastedImages.append(contentsOf: sortedImages)
                        fileProcessed = true
                    }
                    
                    self.handlePastedContent(images: pastedImages, documents: pastedDocuments, text: pastedText, fileProcessed: fileProcessed)
                    self.notifyPasteCompleted()
                }
                
                // Return early if HTML processing is in progress
                if !urlsToProcess.isEmpty {
                    return
                }
            }
        }
        
        // 4. Process immediately if no HTML handling
        handlePastedContent(images: pastedImages, documents: pastedDocuments, text: pastedText, fileProcessed: fileProcessed)
        notifyPasteCompleted()
    }

    private func handlePastedContent(images: [NSImage], documents: [URL], text: String, fileProcessed: Bool) {
        // Process text first
        if !text.isEmpty {
            let textData = text.data(using: .utf8) ?? Data()
            // Only treat as file if setting is enabled
            if treatLargeTextAsFile && textData.count >= largeTextThreshold, let handler = onPasteLargeText {
                // Treat large text as a file attachment
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
                let filename = "pasted_text_\(dateFormatter.string(from: Date())).txt"
                handler(text, filename)
            } else {
                // Insert text normally
                self.insertText(text, replacementRange: self.selectedRange())
            }
        }
        
        // Process documents
        if !documents.isEmpty {
            documents.forEach { self.onPasteDocument?($0) }
        }
        
        // Process images - always process if available (both large text and images can coexist)
        if !images.isEmpty {
            images.forEach { self.onPaste?($0) }
        }
        
        // Fall back to standard paste if nothing was processed
        if !fileProcessed && images.isEmpty && documents.isEmpty && text.isEmpty {
            // Check if clipboard has plain text that might be large
            if let clipboardText = NSPasteboard.general.string(forType: .string) {
                let textData = clipboardText.data(using: .utf8) ?? Data()
                // Only treat as file if setting is enabled
                if treatLargeTextAsFile && textData.count >= largeTextThreshold, let handler = onPasteLargeText {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
                    let filename = "pasted_text_\(dateFormatter.string(from: Date())).txt"
                    handler(clipboardText, filename)
                    return
                }
            }
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
        // Check if search field is active
        if AppStateManager.shared.isSearchFieldActive {
            // Allow default behavior when search field is active
            return super.performKeyEquivalent(with: event)
        }
        
        // Handle Command+V when search field is not active
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
struct FirstResponderTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isDisabled: Bool
    @Binding var calculatedHeight: CGFloat
    @Binding var isPasting: Bool  // New binding for paste operation status
    var allowImagePasting: Bool = true  // Control whether image pasting is allowed
    var treatLargeTextAsFile: Bool = true  // Control whether large text is treated as file attachment
    var onCommit: () -> Void
    var onPaste: ((NSImage) -> Void)?
    var onPasteDocument: ((URL) -> Void)?
    var onPasteLargeText: ((String, String) -> Void)?  // (text content, filename) - for large text as file
    
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
        lhs.text == rhs.text && lhs.isDisabled == rhs.isDisabled && lhs.isPasting == rhs.isPasting && lhs.allowImagePasting == rhs.allowImagePasting && lhs.treatLargeTextAsFile == rhs.treatLargeTextAsFile
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
            textView.allowImagePasting = allowImagePasting
            textView.treatLargeTextAsFile = treatLargeTextAsFile
            textView.onPaste = { image in context.coordinator.parent.onPaste?(image) }
            textView.onPasteDocument = { url in
                context.coordinator.parent.onPasteDocument?(url)
            }
            textView.onPasteLargeText = { text, filename in
                context.coordinator.parent.onPasteLargeText?(text, filename)
            }
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
            
            // Add placeholder text
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
        textView.allowImagePasting = self.allowImagePasting
        textView.treatLargeTextAsFile = self.treatLargeTextAsFile
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
    
    @MainActor
    private func updateText(_ textView: MyTextView) {
        parent.text = textView.string
        parent.updateHeight(textView: textView)
    }
    
    @objc func handleTranscriptUpdate(_ notification: Notification) {
        guard let textView = self.textView else { return }
        Task { @MainActor in
            textView.moveCursorToEnd()
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
