//
//  AttachmentStore.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 3/7/24.
//

import Foundation
import SwiftUI

@MainActor
class AttachmentStore: ObservableObject {
    @Published var images: [NSImage] = []
    @Published var documents: [Data] = []
    private(set) var imageIDs: [UUID] = []
    private(set) var documentIDs: [UUID] = []
    @Published private(set) var isImporting = false
    @Published var importError: String?
    private var importTasks: [UUID: Task<Void, Never>] = [:]
    private var importTail: Task<Void, Never>?
    var onAttachmentsChanged: (() -> Void)?

    // Separate arrays for images
    @Published var imageExtensions: [String] = []
    @Published var imageFilenames: [String] = []
    // Images shown in the composer are small previews; retain prepared request
    // bytes to avoid repeatedly decoding and recompressing all attachments.
    var imageEncodedData: [Data?] = []

    // Separate arrays for documents
    @Published var documentExtensions: [String] = []
    @Published var documentFilenames: [String] = []
    @Published var textPreviews: [String?] = []

    // Legacy arrays for compatibility (computed from separate arrays)
    var fileExtensions: [String] {
        imageExtensions + documentExtensions
    }
    var filenames: [String] {
        imageFilenames + documentFilenames
    }
    var mediaTypes: [MediaType] {
        Array(repeating: MediaType.image, count: images.count) +
        Array(repeating: MediaType.document, count: documents.count)
    }

    var isEmpty: Bool {
        images.isEmpty && documents.isEmpty
    }

    enum MediaType {
        case image
        case document
    }

    // Helper method to add image
    func addImage(_ image: NSImage, fileExtension: String, filename: String, encodedData: Data? = nil, id: UUID = UUID()) {
        imageIDs.append(id)
        imageExtensions.append(fileExtension)
        imageFilenames.append(filename)
        imageEncodedData.append(encodedData)
        images.append(image)
        onAttachmentsChanged?()
    }

    @discardableResult
    func addPreparedImage(_ image: PreparedClipboardImage, filename: String? = nil, id: UUID = UUID()) -> Bool {
        guard let preview = NSImage(data: image.preview) else { return false }
        addImage(preview, fileExtension: image.fileExtension,
                 filename: filename ?? "pasted image \(UUID().uuidString.prefix(8)).\(image.fileExtension)", encodedData: image.data, id: id)
        return true
    }

    func imagePreviewSource(at index: Int) -> ImagePreviewSource? {
        guard images.indices.contains(index) else { return nil }
        if imageEncodedData.indices.contains(index), let data = imageEncodedData[index] { return .encoded(data) }
        return .legacy(ImagePreviewBitmap(images[index]))
    }

    func copy(from source: AttachmentStore) {
        cancelImports()
        imageIDs = source.imageIDs
        documentIDs = source.documentIDs
        imageExtensions = source.imageExtensions
        imageFilenames = source.imageFilenames
        imageEncodedData = source.imageEncodedData
        documentExtensions = source.documentExtensions
        documentFilenames = source.documentFilenames
        textPreviews = source.textPreviews
        images = source.images
        documents = source.documents
        onAttachmentsChanged?()
    }

    // Helper method to add document
    func addDocument(_ data: Data, fileExtension: String, filename: String, id: UUID = UUID()) {
        documentIDs.append(id)
        documentExtensions.append(fileExtension)
        documentFilenames.append(filename)
        textPreviews.append(nil)
        documents.append(data)
        onAttachmentsChanged?()
    }

    // Helper method to add pasted text as document with preview
    func addPastedText(_ text: String, filename: String, id: UUID = UUID()) {
        guard let textData = text.data(using: .utf8) else { return }
        documentIDs.append(id)
        documentExtensions.append("txt")
        documentFilenames.append(filename)
        textPreviews.append(text)
        documents.append(textData)
        onAttachmentsChanged?()
    }

    func updatePastedText(id: UUID, text: String) {
        guard let index = documentIDs.firstIndex(of: id), textPreviews.indices.contains(index),
              textPreviews[index] != nil else { return }
        textPreviews[index] = text
        documents[index] = Data(text.utf8)
        onAttachmentsChanged?()
    }

    func attachmentDraft() throws -> ConversationAttachmentDraft {
        guard images.count == imageIDs.count, images.count == imageEncodedData.count,
              images.count == imageFilenames.count, images.count == imageExtensions.count,
              documents.count == documentIDs.count, documents.count == documentExtensions.count,
              documents.count == documentFilenames.count, documents.count == textPreviews.count else {
            throw LocalOperationError.invalid("The attachment list is still being prepared.")
        }
        let imageItems = try images.indices.map { index in
            guard let data = imageEncodedData[index] else {
                throw LocalOperationError.invalid("An image has not finished preparing for storage.")
            }
            return DraftAttachment(id: imageIDs[index], data: data, filename: imageFilenames[index], format: imageExtensions[index])
        }
        let documentItems = documents.indices.map { index in
            DraftAttachment(id: documentIDs[index], data: documents[index], filename: documentFilenames[index],
                            format: documentExtensions[index], pastedText: textPreviews[index])
        }
        return ConversationAttachmentDraft(images: imageItems, documents: documentItems)
    }

    func restoreAttachmentDraft(_ draft: ConversationAttachmentDraft) async throws {
        try ConversationAttachmentDraftFile.validate(draft)
        isImporting = true
        defer { isImporting = !importTasks.isEmpty }
        let worker = Task.detached(priority: .userInitiated) {
            try draft.images.map { item -> (DraftAttachment, PreparedClipboardImage) in
                try Task.checkCancellation()
                return (item, try ClipboardImageProcessor.decode(item.data))
            }
        }
        let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        // Merge by stable identity if a paste completed during restoration.
        // Never replace attachments the user just added.
        for (item, image) in prepared where !imageIDs.contains(item.id) {
            _ = addPreparedImage(image, filename: item.filename, id: item.id)
        }
        for item in draft.documents where !documentIDs.contains(item.id) {
            if let text = item.pastedText { addPastedText(text, filename: item.filename, id: item.id) }
            else { addDocument(item.data, fileExtension: item.format, filename: item.filename, id: item.id) }
        }
    }

    func waitForImports() async { await importTail?.value }

    /// Restore a retry/draft using the same bounded ImageIO preparation as paste.
    /// Do all decoding before replacing the current attachments.
    func restore(_ message: MessageData, imagesDirectory directory: URL) async throws {
        let replacedImages = Set(imageIDs)
        let replacedDocuments = Set(documentIDs)
        isImporting = true
        defer { isImporting = !importTasks.isEmpty }
        let worker = Task.detached(priority: .userInitiated) {
            let images = try (message.imageBase64Strings ?? []).map {
                try ClipboardImageProcessor.decode(LocalImageReference.read($0, directory: directory))
            }
            var documents: [(Data, String, String)] = []
            for (index, value) in (message.documentBase64Strings ?? []).enumerated() {
                guard let data = Data(base64Encoded: value) else { throw LocalOperationError.invalid("The document attachment could not be decoded.") }
                let ext = message.documentFormats.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? "txt"
                let name = message.documentNames.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? "Document"
                documents.append((data, ext, name))
            }
            return (images, documents)
        }
        let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        // Decoding yields the main actor. A paste made in the meantime belongs
        // to the current draft and must survive restoring the earlier prompt.
        remove(imageIDs: replacedImages, documentIDs: replacedDocuments)
        for image in prepared.0 { _ = addPreparedImage(image) }
        for (data, ext, name) in prepared.1 { addDocument(data, fileExtension: ext, filename: name) }
        for pasted in message.pastedTexts ?? [] { addPastedText(pasted.content, filename: pasted.filename) }
    }

    // Remove image at index
    func removeImage(at index: Int) {
        guard images.indices.contains(index) else { return }
        if index < imageIDs.count { imageIDs.remove(at: index) }
        if index < imageExtensions.count { imageExtensions.remove(at: index) }
        if index < imageFilenames.count { imageFilenames.remove(at: index) }
        if index < imageEncodedData.count { imageEncodedData.remove(at: index) }
        images.remove(at: index)
        onAttachmentsChanged?()
    }

    // Remove document at index
    func removeDocument(at index: Int) {
        guard documents.indices.contains(index) else { return }
        if index < documentIDs.count { documentIDs.remove(at: index) }
        if index < documentExtensions.count { documentExtensions.remove(at: index) }
        if index < documentFilenames.count { documentFilenames.remove(at: index) }
        if index < textPreviews.count { textPreviews.remove(at: index) }
        documents.remove(at: index)
        onAttachmentsChanged?()
    }

    func remove(imageIDs capturedImages: Set<UUID>, documentIDs capturedDocuments: Set<UUID>) {
        for index in imageIDs.indices.reversed() where capturedImages.contains(imageIDs[index]) { removeImage(at: index) }
        for index in documentIDs.indices.reversed() where capturedDocuments.contains(documentIDs[index]) { removeDocument(at: index) }
    }

    // Remove all attachments
    func clear() {
        cancelImports()
        importError = nil
        imageIDs.removeAll()
        documentIDs.removeAll()
        imageExtensions.removeAll()
        imageFilenames.removeAll()
        imageEncodedData.removeAll()
        documentExtensions.removeAll()
        documentFilenames.removeAll()
        textPreviews.removeAll()
        images.removeAll()
        documents.removeAll()
        onAttachmentsChanged?()
    }

    /// A serial queue keeps repeated file selections ordered. Only prepared
    /// thumbnails and bounded document bytes are delivered to the main actor.
    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let previous = importTail
        let id = UUID()
        isImporting = true
        importError = urls.count > 25 ? "A message supports up to 20 images and 5 documents." : nil
        let task = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            defer {
                self.importTasks.removeValue(forKey: id)
                self.isImporting = !self.importTasks.isEmpty
                if self.importTasks.isEmpty { self.importTail = nil }
            }
            for url in urls.prefix(25) {
                guard !Task.isCancelled else { return }
                let worker = Task.detached(priority: .userInitiated) {
                    try await LocalAttachmentProcessor.prepare(url)
                }
                do {
                    let prepared = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: { worker.cancel() }
                    try Task.checkCancellation()
                    switch prepared {
                    case .image(let image, let filename):
                        guard self.images.count < 20 else { throw LocalOperationError.invalid("A message supports up to 20 images.") }
                        guard self.addPreparedImage(image, filename: filename) else {
                            throw LocalOperationError.invalid("The image preview could not be opened.")
                        }
                    case .document(let data, let ext, let filename):
                        guard self.documents.count < 5 else { throw LocalOperationError.invalid("A message supports up to 5 documents.") }
                        self.addDocument(data, fileExtension: ext, filename: filename)
                    }
                } catch is CancellationError { return }
                catch { self.importError = "\(url.lastPathComponent): \(error.localizedDescription)" }
            }
        }
        importTasks[id] = task
        importTail = task
    }

    func cancelImports() {
        for task in importTasks.values { task.cancel() }
        importTasks.removeAll()
        importTail = nil
        isImporting = false
    }
}

struct DocumentAttachment: Identifiable {
    var id = UUID()
    let data: Data
    var fileExtension: String
    var filename: String
    var textPreview: String? = nil  // Preview text for pasted text documents

    var isPastedText: Bool {
        textPreview != nil
    }
}

enum ImageFormat: String, Codable {
    case jpeg
    case png
    case gif
    case webp

    /// Detect format from raw image data by inspecting magic bytes
    static func detectFromData(_ data: Data) -> ImageFormat {
        guard data.count >= 4 else { return .jpeg }
        let bytes = [UInt8](data.prefix(4))
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return .png
        } else if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 {
            return .gif
        } else if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 {
            return .webp
        }
        return .jpeg
    }

    /// Detect format from a base64-encoded string
    static func detectFromBase64(_ base64String: String) -> ImageFormat {
        guard let data = Data(base64Encoded: String(base64String.prefix(16)), options: .ignoreUnknownCharacters) else {
            return .jpeg
        }
        return detectFromData(data)
    }
}
