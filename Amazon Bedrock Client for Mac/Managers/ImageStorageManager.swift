// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

import Foundation
import AppKit

/// Manages efficient storage and retrieval of generated images
/// Images are stored as separate files to avoid bloating conversation history JSON
@MainActor
final class ImageStorageManager: Sendable {
    static let shared = ImageStorageManager()
    
    private let fileManager = FileManager.default
    private let imageCache = NSCache<NSString, NSData>()
    
    private init() {
        // Configure cache limits
        imageCache.countLimit = 50  // Max 50 images in memory
        imageCache.totalCostLimit = 100 * 1024 * 1024  // 100MB max
    }
    
    // MARK: - Directory Management
    
    private func getImagesDirectory() -> URL {
        let baseDir = URL(fileURLWithPath: SettingManager.shared.defaultDirectory)
        let imagesDir = baseDir.appendingPathComponent("generated_images")
        
        if !fileManager.fileExists(atPath: imagesDir.path) {
            try? fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        }
        
        return imagesDir
    }
    
    private func getImagePath(for imageId: String) -> URL {
        return getImagesDirectory().appendingPathComponent("\(imageId).png")
    }
    
    // MARK: - Image Storage
    
    /// Save image data and return a reference ID
    /// Returns: Image reference ID (format: "img_<uuid>")
    func saveImage(_ data: Data) -> String {
        let imageId = "img_\(UUID().uuidString)"
        let filePath = getImagePath(for: imageId)
        
        do {
            try data.write(to: filePath)
            // Also cache in memory
            imageCache.setObject(data as NSData, forKey: imageId as NSString, cost: data.count)
            return imageId
        } catch {
            print("Failed to save image: \(error)")
            // Fall back to base64 if file save fails
            return data.base64EncodedString()
        }
    }
    
    /// Save multiple images and return reference IDs
    func saveImages(_ dataArray: [Data]) -> [String] {
        return dataArray.map { saveImage($0) }
    }
    
    // MARK: - Image Retrieval
    
    /// Load image data from reference ID or base64 string
    /// Handles both new reference format and legacy base64 format
    func loadImage(_ reference: String) -> Data? {
        // Check if it's a reference ID (starts with "img_")
        if reference.hasPrefix("img_") {
            return loadImageFromFile(imageId: reference)
        } else {
            // Legacy base64 format - decode directly
            return Data(base64Encoded: reference)
        }
    }
    
    /// Load image from file with caching
    private func loadImageFromFile(imageId: String) -> Data? {
        // Check cache first
        if let cachedData = imageCache.object(forKey: imageId as NSString) {
            return cachedData as Data
        }
        
        // Load from file
        let filePath = getImagePath(for: imageId)
        guard let data = try? Data(contentsOf: filePath) else {
            return nil
        }
        
        // Cache for future access
        imageCache.setObject(data as NSData, forKey: imageId as NSString, cost: data.count)
        return data
    }
    
    /// Load multiple images
    func loadImages(_ references: [String]) -> [Data] {
        return references.compactMap { loadImage($0) }
    }
    
    // MARK: - Base64 Conversion (for display)
    
    /// Get base64 string for display (handles both formats)
    func getBase64ForDisplay(_ reference: String) -> String? {
        if reference.hasPrefix("img_") {
            // Load from file and convert to base64
            guard let data = loadImageFromFile(imageId: reference) else {
                return nil
            }
            return data.base64EncodedString()
        } else {
            // Already base64
            return reference
        }
    }
    
    /// Get base64 strings for multiple references
    func getBase64ForDisplay(_ references: [String]) -> [String] {
        return references.compactMap { getBase64ForDisplay($0) }
    }
    
    // MARK: - Cleanup
    
    /// Delete image file
    func deleteImage(_ reference: String) {
        guard reference.hasPrefix("img_") else { return }
        
        let filePath = getImagePath(for: reference)
        try? fileManager.removeItem(at: filePath)
        imageCache.removeObject(forKey: reference as NSString)
    }
    
    /// Delete images for a chat (when chat is deleted)
    func deleteImagesForChat(imageReferences: [String]) {
        for reference in imageReferences {
            deleteImage(reference)
        }
    }
    
    /// Clear memory cache
    func clearCache() {
        imageCache.removeAllObjects()
    }
    
    /// Get total size of stored images
    func getTotalStorageSize() -> Int64 {
        let imagesDir = getImagesDirectory()
        var totalSize: Int64 = 0
        
        if let enumerator = fileManager.enumerator(at: imagesDir, includingPropertiesForKeys: [.fileSizeKey]) {
            while let fileURL = enumerator.nextObject() as? URL {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }
        
        return totalSize
    }
}

// MARK: - Convenience Extensions

extension ImageStorageManager {
    /// Check if a reference is a file reference (vs inline base64)
    static func isFileReference(_ reference: String) -> Bool {
        return reference.hasPrefix("img_")
    }
    
    /// Migrate legacy base64 images to file storage
    /// Returns new references array
    func migrateToFileStorage(_ base64Strings: [String]) -> [String] {
        return base64Strings.map { base64 in
            // Skip if already a file reference
            if base64.hasPrefix("img_") {
                return base64
            }
            
            // Convert base64 to file
            guard let data = Data(base64Encoded: base64) else {
                return base64  // Keep original if decode fails
            }
            
            return saveImage(data)
        }
    }
}
