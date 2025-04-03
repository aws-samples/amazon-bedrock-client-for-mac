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
    @Published var fileExtensions: [String] = [] // Extensions for all attachments
    @Published var filenames: [String] = [] // Names for all attachments
    @Published var mediaTypes: [MediaType] = [] // Type of each item
    
    enum MediaType {
        case image
        case document
    }
    
    // Helper method to correctly manage indices when adding images
    func addImage(_ image: NSImage, fileExtension: String, filename: String) {
        images.append(image)
        
        let imageIndex = images.count - 1
        
        // Ensure mediaTypes has enough space for the image index
        while mediaTypes.count <= imageIndex {
            mediaTypes.append(.image)
        }
        
        // Extend fileExtensions and filenames arrays
        while fileExtensions.count <= imageIndex {
            fileExtensions.append("")
        }
        
        while filenames.count <= imageIndex {
            filenames.append("")
        }
        
        fileExtensions[imageIndex] = fileExtension
        filenames[imageIndex] = filename
    }
    
    // Helper method to correctly manage indices when adding documents
    func addDocument(_ data: Data, fileExtension: String, filename: String) {
        documents.append(data)
        
        let totalCount = images.count + documents.count - 1
        
        // Add document type to mediaTypes
        while mediaTypes.count <= totalCount {
            mediaTypes.append(.document)
        }
        
        // Extend fileExtensions and filenames arrays
        while fileExtensions.count <= totalCount {
            fileExtensions.append("")
        }
        
        while filenames.count <= totalCount {
            filenames.append("")
        }
        
        fileExtensions[totalCount] = fileExtension
        filenames[totalCount] = filename
    }
    
    // Remove all attachments
    func clearAll() {
        images.removeAll()
        documents.removeAll()
        fileExtensions.removeAll()
        filenames.removeAll()
        mediaTypes.removeAll()
    }
}

struct DocumentAttachment: Identifiable {
    let id = UUID()
    let data: Data
    var fileExtension: String
    var filename: String
}

enum ImageFormat: String, Codable {
    case jpeg
    case png
    case gif
    case webp
}
