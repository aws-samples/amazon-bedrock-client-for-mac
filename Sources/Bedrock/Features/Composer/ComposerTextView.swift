//
//  ComposerTextView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

enum ComposerNavigationKey { case up, down, accept, dismiss }

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
final class ComposerTextView: NSTextView {
    override func menu(for event: NSEvent) -> NSMenu? { TextContextMenu.make(for: self) }
    private static let imagePasteboardTypes: [NSPasteboard.PasteboardType] = [
        .png, .init("public.jpeg"), .init("public.heic"), .init("org.webmproject.webp"),
        .init("com.compuserve.gif"), .tiff, .init("com.microsoft.bmp")
    ]
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        // AppKit validates Command-V before invoking our paste handler. A plain
        // NSTextView otherwise disables Paste for Finder URLs or image-only data.
        var types = super.readablePasteboardTypes + [.fileURL, .html]
        if allowImagePasting { types += Self.imagePasteboardTypes }
        var seen = Set<NSPasteboard.PasteboardType>()
        return types.filter { seen.insert($0).inserted }
    }
    var onPaste: ((NSImage) -> Void)?
    var onPastePreparedImage: ((PreparedClipboardImage) -> Void)?
    var onPasteError: ((String) -> Void)?
    var onPasteDocument: ((URL) -> Void)?
    var onPasteLargeText: ((String, String) -> Void)?  // (text content, suggested filename)
    var onCommit: (() -> Void)?
    var onComposerCommand: ((ComposerNavigationKey) -> Bool)?
    var onPasteStarted: (() -> Void)?
    var onPasteCompleted: (() -> Void)?
    var allowImagePasting: Bool = true  // Control whether image pasting is allowed
    var treatLargeTextAsFile: Bool = true  // Control whether large text is treated as file attachment
    var sendWithCommandReturn = false
    var largeTextThreshold: Int = 10 * 1024  // 10KB threshold for treating text as file
    var placeholderString: String? {
        didSet {
            needsDisplay = true
        }
    }

    // Maximum number of images allowed for paste operation
    private let maxImagesAllowed = ClipboardHTMLParser.maximumImages
    // Track if a paste operation is in progress
    private var isPasteInProgress = false
    private var pasteJobs: [UUID: Task<Void, Never>] = [:]
    private var lastPasteJob: Task<Void, Never>?
    private var commandModifiers: NSEvent.ModifierFlags = []

    override func keyDown(with event: NSEvent) {
        let previous = commandModifiers
        commandModifiers = event.modifierFlags
        defer { commandModifiers = previous }
        super.keyDown(with: event)
    }

    func moveCursorToEnd() {
        let length = (string as NSString).length
        setSelectedRange(NSRange(location: length, length: 0))
        scrollRangeToVisible(NSRange(location: length, length: 0))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if string.isEmpty, let placeholder = placeholderString {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let rect = NSRect(x: textContainerInset.width + 5,
                              y: textContainerInset.height,
                              width: bounds.width - textContainerInset.width * 2,
                              height: bounds.height)
            placeholder.draw(in: rect, withAttributes: attributes)
        }
    }

    override func paste(_ sender: Any?) {
        _ = handlePasteboard(.general)
        inputContext?.discardMarkedText()
        needsDisplay = true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        handlePasteboard(sender.draggingPasteboard)
    }

    override func cancelOperation(_ sender: Any?) {
        if !pasteJobs.isEmpty { cancelPendingPastes() }
        else { super.cancelOperation(sender) }
    }

    func cancelPendingPastes() {
        for job in pasteJobs.values { job.cancel() }
        pasteJobs.removeAll()
        lastPasteJob = nil
        notifyPasteCompleted()
    }

    override func doCommand(by selector: Selector) {
        // Commands from accessibility or input methods must not inherit a
        // stale Command/Shift modifier from another window's last event.
        let flags = commandModifiers
        if !hasMarkedText(), flags.intersection([.command, .control, .option, .shift]).isEmpty {
            let key: ComposerNavigationKey?
            switch selector {
            case #selector(moveUp(_:)): key = .up
            case #selector(moveDown(_:)): key = .down
            case #selector(insertNewline(_:)), #selector(insertTab(_:)): key = .accept
            case #selector(cancelOperation(_:)): key = .dismiss
            default: key = nil
            }
            if let key, onComposerCommand?(key) == true { return }
        }
        if selector == #selector(paste(_:)) {
            paste(nil)
        } else if selector == #selector(insertNewline(_:)) {
            if hasMarkedText() {
                super.doCommand(by: selector)
                return
            }
            if flags.contains(.shift) || (sendWithCommandReturn && !flags.contains(.command)) {
                super.insertText("\n", replacementRange: selectedRange())
            } else {
                onCommit?()
            }
        } else {
            super.doCommand(by: selector)
        }
    }

    private struct PasteResult: Sendable {
        var text = ""
        var images: [PreparedClipboardImage] = []
        var errors: [String] = []
    }

    @discardableResult
    func handlePasteboard(_ pasteboard: NSPasteboard) -> Bool {
        let imageExtensions = LocalAttachmentProcessor.imageExtensions
        let documentExtensions = LocalAttachmentProcessor.documentInputExtensions
        var images: [ClipboardImageInput] = []
        var documents: [URL] = []
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        for url in urls.prefix(maxImagesAllowed) where url.isFileURL {
            let ext = url.pathExtension.lowercased()
            if allowImagePasting && imageExtensions.contains(ext) { images.append(.file(url)) }
            else if documentExtensions.contains(ext) { documents.append(url) }
        }
        let hasFiles = !images.isEmpty || !documents.isEmpty
        // Prefer compressed clipboard types. Asking for TIFF first can expand a
        // modest screenshot into hundreds of megabytes on the UI thread.
        if allowImagePasting && !hasFiles {
            for item in (pasteboard.pasteboardItems ?? []).prefix(maxImagesAllowed) {
                for type in Self.imagePasteboardTypes where item.types.contains(type) {
                    if let data = item.data(forType: type) { images.append(.data(data)); break }
                }
            }
        }
        let plainText = hasFiles ? nil : pasteboard.string(forType: .string)
        let html = hasFiles ? nil : pasteboard.string(forType: .html)
        // Browsers already supply their selected text. Never send it through
        // NSAttributedString's HTML importer (which enters WebKit synchronously).
        if let plainText { insertPastedText(plainText) }
        documents.forEach { onPasteDocument?($0) }
        guard !images.isEmpty || html != nil else { return plainText != nil || !documents.isEmpty }

        let inputs = images
        let includeImages = allowImagePasting
        let needsText = plainText == nil
        let previous = lastPasteJob
        let id = UUID()
        notifyPasteStarted()
        let job = Task { [weak self] in
            // Preserve order across successive pastes without decoding batches
            // concurrently or holding full-resolution NSImages in the editor.
            await previous?.value
            guard !Task.isCancelled else { self?.finishPaste(id); return }
            let worker = Task.detached(priority: .userInitiated) { () -> PasteResult in
                var result = PasteResult()
                var sources = inputs
                if let html {
                    do {
                        let content = try ClipboardHTMLParser.parse(html, includeText: needsText)
                        if needsText { result.text = content.text }
                        if includeImages && sources.isEmpty { sources = content.imageSources.map(ClipboardImageInput.source) }
                    } catch { result.errors.append(error.localizedDescription) }
                }
                let deadline = Date().addingTimeInterval(20)
                for (index, source) in sources.prefix(ClipboardHTMLParser.maximumImages).enumerated() {
                    if Task.isCancelled { break }
                    if Date() > deadline { result.errors.append("Some image URLs took too long to load. Paste those images directly to attach them."); break }
                    do { result.images.append(try await ClipboardImageProcessor.prepare(source)) }
                    catch is CancellationError { break }
                    catch { result.errors.append("Image \(index + 1): \(error.localizedDescription)") }
                }
                return result
            }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard let self else { return }
            defer { self.finishPaste(id) }
            guard !Task.isCancelled else { return }
            if needsText { self.insertPastedText(result.text) }
            if self.allowImagePasting {
                for image in result.images {
                    if let handler = self.onPastePreparedImage { handler(image) }
                    else if let native = NSImage(data: image.data) { self.onPaste?(native) }
                }
            }
            if !result.errors.isEmpty { self.onPasteError?(result.errors.prefix(3).joined(separator: "\n")) }
        }
        pasteJobs[id] = job
        lastPasteJob = job
        return true
    }

    private func finishPaste(_ id: UUID) {
        pasteJobs.removeValue(forKey: id)
        if pasteJobs.isEmpty { lastPasteJob = nil; notifyPasteCompleted() }
    }

    private func insertPastedText(_ text: String) {
        guard !text.isEmpty else { return }
        guard text.utf8.count <= ClipboardHTMLParser.maximumTextBytes else {
            onPasteError?("Pasted text exceeds the 4.5 MB attachment limit.")
            return
        }
        if treatLargeTextAsFile && text.utf8.count >= largeTextThreshold, let handler = onPasteLargeText {
            handler(text, "pasted text \(UUID().uuidString.prefix(8)).txt")
        } else {
            insertText(text, replacementRange: selectedRange())
        }
    }

    // Implement the performKeyEquivalent to catch Command+V (paste)
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if sendWithCommandReturn && event.modifierFlags.contains(.command) && [36, 76].contains(event.keyCode) && !hasMarkedText() {
            onCommit?()
            return true
        }
        // Check if search field is active
        if EditorFocusState.shared.isSearchFieldActive {
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
            onPasteStarted?()
        }
    }

    // Notify that paste operation has completed
    private func notifyPasteCompleted() {
        if isPasteInProgress {
            isPasteInProgress = false
            onPasteCompleted?()
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
struct ComposerEditor: NSViewRepresentable {
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
    var onPastePreparedImage: ((PreparedClipboardImage) -> Void)?
    var onPasteError: ((String) -> Void)?
    var onComposerCommand: ((ComposerNavigationKey) -> Bool)? = nil

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(self, onPaste: onPaste)

        // Add observer for transcript updates
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.handleTranscriptUpdate(_:)),
            name: .transcriptUpdated,
            object: nil
        )
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.focusComposer(_:)),
            name: .focusBedrockComposer,
            object: nil
        )

        return coordinator
    }

    static func == (lhs: ComposerEditor, rhs: ComposerEditor) -> Bool {
        lhs.text == rhs.text && lhs.isDisabled == rhs.isDisabled && lhs.isPasting == rhs.isPasting && lhs.allowImagePasting == rhs.allowImagePasting && lhs.treatLargeTextAsFile == rhs.treatLargeTextAsFile
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ComposerTextView.scrollableTextView()
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay

        if let textView = scrollView.documentView as? ComposerTextView {
            textView.setAccessibilityIdentifier("composer.editor")
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
            textView.onPastePreparedImage = { context.coordinator.parent.onPastePreparedImage?($0) }
            if onPastePreparedImage == nil { textView.onPastePreparedImage = nil }
            textView.onPasteError = { context.coordinator.parent.onPasteError?($0) }
            textView.onCommit = { context.coordinator.parent.onCommit() }
            textView.onComposerCommand = { context.coordinator.parent.onComposerCommand?($0) ?? false }

            // Set up paste operation callbacks
            textView.onPasteStarted = {
                context.coordinator.parent.isPasting = true
            }

            textView.onPasteCompleted = {
                context.coordinator.parent.isPasting = false
            }

            textView.registerForDraggedTypes([.fileURL, .png, .tiff, .html, .string])
            textView.layoutManager?.allowsNonContiguousLayout = true
            textView.font = NSFont.systemFont(ofSize: 15)
            textView.isRichText = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.allowsUndo = true
            textView.becomeFirstResponder()

            textView.textContainerInset = CGSize(width: 5, height: 10)
            textView.textColor = NSColor(Color.text)
            textView.backgroundColor = .clear

            // Add placeholder text
            let placeholder = "Ask anything, or use / for commands"
            textView.placeholderString = placeholder

            updateHeight(textView: textView)

            context.coordinator.textView = textView
        }

        DispatchQueue.main.async { [weak scrollView] in
            guard let scrollView, let window = scrollView.window,
                  window.isKeyWindow, window.attachedSheet == nil else { return }
            // Opening a selected history row must not take focus away from the
            // native list after every arrow key. New chat/⌘N explicitly request
            // composer focus through focusBedrockComposer.
            var focusedView = window.firstResponder as? NSView
            while let view = focusedView {
                if view is NSTableView || view is NSCollectionView { return }
                focusedView = view.superview
            }
            window.makeFirstResponder(scrollView.documentView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? ComposerTextView else { return }

        if textView.string != self.text && !textView.hasMarkedText() {
            let selected = textView.selectedRange()
            textView.string = self.text
            let length = (self.text as NSString).length
            let start = min(selected.location, length)
            textView.setSelectedRange(NSRange(location: start, length: min(selected.length, length - start)))
            updateHeight(textView: textView)
        }
        textView.isEditable = !self.isDisabled
        textView.allowImagePasting = self.allowImagePasting
        textView.treatLargeTextAsFile = self.treatLargeTextAsFile
        textView.sendWithCommandReturn = AppStore.shared.preferences.sendWithCommandReturn
    }
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        (nsView.documentView as? ComposerTextView)?.cancelPendingPastes()
        (nsView.documentView as? NSTextView)?.delegate = nil
        coordinator.textView = nil
    }

    public func updateHeight(textView: ComposerTextView) {
        let layoutManager = textView.layoutManager!
        let textContainer = textView.textContainer!

        let newHeight: CGFloat
        if textView.string.utf16.count > 8_192 {
            newHeight = 200
        } else {
            layoutManager.ensureLayout(forBoundingRect: NSRect(x: 0, y: 0, width: max(1, textContainer.containerSize.width), height: 200), in: textContainer)
            newHeight = max(40, min(200, layoutManager.usedRect(for: textContainer).height + textView.textContainerInset.height * 2))
        }

        if abs(newHeight - calculatedHeight) > 1 {
            DispatchQueue.main.async {
                self.calculatedHeight = newHeight
            }
        }
    }
}

/// Coordinator for managing updates and interactions between SwiftUI and AppKit components.
@MainActor
public class Coordinator: NSObject, NSTextViewDelegate {
    var parent: ComposerEditor
    var onPaste: ((NSImage) -> Void)?
    weak var textView: ComposerTextView?

    init(_ parent: ComposerEditor, onPaste: ((NSImage) -> Void)?) {
        self.parent = parent
        self.onPaste = onPaste
    }

    @objc public func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? ComposerTextView else { return }
        updateText(textView)
    }

    @MainActor
    private func updateText(_ textView: ComposerTextView) {
        parent.text = textView.string
        parent.updateHeight(textView: textView)
    }

    @objc func handleTranscriptUpdate(_ notification: Notification) {
        guard let textView = self.textView else { return }
        Task { @MainActor in
            textView.moveCursorToEnd()
        }
    }

    @objc func focusComposer(_ notification: Notification) {
        guard let textView, let window = textView.window,
              window.isKeyWindow, window.attachedSheet == nil,
              !textView.isHiddenOrHasHiddenAncestor else { return }
        window.makeFirstResponder(textView)
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
