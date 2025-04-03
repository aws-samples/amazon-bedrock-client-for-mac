//
//  NSImage.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 4/2/25.
//

import SwiftUI

extension NSImage {
    func compressedData(maxFileSize: Int, maxDimension: CGFloat, format: ImageFormat) -> Data? {
        // Get the best representation of the image
        guard let tiffData = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        // Scale down the image if needed
        let scaledImage: NSBitmapImageRep
        if self.size.width > maxDimension || self.size.height > maxDimension {
            let scale = min(maxDimension / self.size.width, maxDimension / self.size.height)
            let newWidth = self.size.width * scale
            let newHeight = self.size.height * scale
            
            // Create a new bitmap representation for the scaled image
            guard let resizedImage = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(newWidth),
                pixelsHigh: Int(newHeight),
                bitsPerSample: bitmapImage.bitsPerSample,
                samplesPerPixel: bitmapImage.samplesPerPixel,
                hasAlpha: bitmapImage.hasAlpha,
                isPlanar: bitmapImage.isPlanar,
                colorSpaceName: bitmapImage.colorSpaceName,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else {
                return nil
            }
            
            resizedImage.size = NSSize(width: newWidth, height: newHeight)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resizedImage)
            self.draw(in: NSRect(x: 0, y: 0, width: newWidth, height: newHeight), from: .zero, operation: .copy, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            
            scaledImage = resizedImage
        } else {
            scaledImage = bitmapImage
        }
        
        // Compress the image with the specified format
        let properties: [NSBitmapImageRep.PropertyKey: Any]
        switch format {
        case .jpeg:
            properties = [.compressionFactor: 0.8]
            return scaledImage.representation(using: .jpeg, properties: properties)
        case .png:
            properties = [:]
            return scaledImage.representation(using: .png, properties: properties)
        case .gif:
            print("GIF format not directly supported in macOS. Falling back to PNG.")
            properties = [:]
            return scaledImage.representation(using: .png, properties: properties)
        case .webp:
            print("WebP format not directly supported in macOS. Falling back to PNG.")
            properties = [:]
            return scaledImage.representation(using: .png, properties: properties)
        }

    }
}
