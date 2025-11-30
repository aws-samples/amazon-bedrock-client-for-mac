//
//  SharedMediaDataSource.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 3/7/24.
//

import Foundation
import SwiftUI

class SharedMediaDataSource: ObservableObject {
    @Published var images: [NSImage] = []
    @Published var documents: [Data] = []
    
    // Separate arrays for images
    @Published var imageExtensions: [String] = []
    @Published var imageFilenames: [String] = []
    
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
    func addImage(_ image: NSImage, fileExtension: String, filename: String) {
        images.append(image)
        imageExtensions.append(fileExtension)
        imageFilenames.append(filename)
    }
    
    // Helper method to add document
    func addDocument(_ data: Data, fileExtension: String, filename: String) {
        documents.append(data)
        documentExtensions.append(fileExtension)
        documentFilenames.append(filename)
        textPreviews.append(nil)
    }
    
    // Helper method to add pasted text as document with preview
    func addPastedText(_ text: String, filename: String) {
        guard let textData = text.data(using: .utf8) else { return }
        documents.append(textData)
        documentExtensions.append("txt")
        documentFilenames.append(filename)
        textPreviews.append(text)
    }
    
    // Remove image at index
    func removeImage(at index: Int) {
        guard index < images.count else { return }
        images.remove(at: index)
        if index < imageExtensions.count { imageExtensions.remove(at: index) }
        if index < imageFilenames.count { imageFilenames.remove(at: index) }
    }
    
    // Remove document at index
    func removeDocument(at index: Int) {
        guard index < documents.count else { return }
        documents.remove(at: index)
        if index < documentExtensions.count { documentExtensions.remove(at: index) }
        if index < documentFilenames.count { documentFilenames.remove(at: index) }
        if index < textPreviews.count { textPreviews.remove(at: index) }
    }
    
    // Remove all attachments
    func clear() {
        images.removeAll()
        documents.removeAll()
        imageExtensions.removeAll()
        imageFilenames.removeAll()
        documentExtensions.removeAll()
        documentFilenames.removeAll()
        textPreviews.removeAll()
    }
}

struct DocumentAttachment: Identifiable {
    let id = UUID()
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
}
