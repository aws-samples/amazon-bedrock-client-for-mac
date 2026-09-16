import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

enum ImagePreviewSource: Sendable {
    case encoded(Data)
    case stored(String, directory: URL)
    case legacy(ImagePreviewBitmap)
}

/// An immutable copy for attachments that predate prepared request bytes.
/// Its representation is evaluated once on the image worker.
final class ImagePreviewBitmap: @unchecked Sendable {
    let image: NSImage
    init(_ image: NSImage) { self.image = image.copy() as! NSImage }
}

/// The CGImage and source bytes are immutable; no AppKit drawing happens here.
final class PreparedImagePreview: NSObject, @unchecked Sendable {
    let original: Data
    let preview: CGImage
    let width: Int
    let height: Int
    let type: String
    var fileExtension: String { UTType(type)?.preferredFilenameExtension ?? "png" }
    var memoryCost: Int { original.count + preview.bytesPerRow * preview.height }

    init(original: Data, preview: CGImage, width: Int, height: Int, type: String) {
        self.original = original
        self.preview = preview
        self.width = width
        self.height = height
        self.type = type
    }
}

/// Serial ImageIO work. Opening/zooming must not re-encode the original image
/// from SwiftUI's body or an AppKit layout pass.
actor ImagePreviewLoader {
    static let shared = ImagePreviewLoader()
    static let maximumInputBytes = 64_000_000
    private let cache = NSCache<NSString, PreparedImagePreview>()

    init() {
        cache.countLimit = 24
        cache.totalCostLimit = 96 * 1_024 * 1_024
    }

    func load(_ input: ImagePreviewSource, maximumPixelSize: Int = 2_560) throws -> PreparedImagePreview {
        try Task.checkCancellation()
        let data: Data
        switch input {
        case .encoded(let encoded): data = encoded
        case .stored(let reference, let directory):
            guard reference.utf8.count <= Self.maximumInputBytes * 4 / 3 + 4 else {
                throw LocalOperationError.tooLarge(Self.maximumInputBytes)
            }
            data = try LocalImageReference.read(reference, directory: directory)
        case .legacy(let bitmap):
            guard let encoded = bitmap.image.tiffRepresentation else {
                throw LocalOperationError.invalid("The image could not be opened.")
            }
            data = encoded
        }
        guard !data.isEmpty else { throw LocalOperationError.invalid("The image is empty.") }
        guard data.count <= Self.maximumInputBytes else { throw LocalOperationError.tooLarge(Self.maximumInputBytes) }
        try Task.checkCancellation()
        let dimension = min(4_096, max(64, maximumPixelSize))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let key = "\(dimension):\(digest)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let result = try Self.decode(data, maximumPixelSize: dimension)
        try Task.checkCancellation()
        cache.setObject(result, forKey: key, cost: result.memoryCost)
        return result
    }

    nonisolated static func decode(_ data: Data, maximumPixelSize: Int) throws -> PreparedImagePreview {
        guard data.count <= maximumInputBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 32_768, height <= 32_768,
              Int64(width) * Int64(height) <= 100_000_000,
              let type = CGImageSourceGetType(source) else {
            throw LocalOperationError.invalid("This image is damaged or exceeds the supported dimensions.")
        }
        try Task.checkCancellation()
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(4_096, max(64, maximumPixelSize)),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw LocalOperationError.invalid("The image preview could not be decoded.")
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let rotated = (5...8).contains(orientation)
        return .init(original: data, preview: preview, width: rotated ? height : width,
                     height: rotated ? width : height, type: type as String)
    }

    func export(_ image: PreparedImagePreview, as type: UTType) throws -> Data {
        try Task.checkCancellation()
        if image.type == type.identifier { return image.original }
        guard let source = CGImageSourceCreateWithData(image.original as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let fullSize = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(image.width, image.height),
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            throw LocalOperationError.invalid("The original image could not be exported.")
        }
        try Task.checkCancellation()
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw LocalOperationError.invalid("This image format is not supported for export.")
        }
        CGImageDestinationAddImage(destination, fullSize, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw LocalOperationError.invalid("The image could not be encoded.") }
        try Task.checkCancellation()
        return data as Data
    }

    func save(_ image: PreparedImagePreview, to url: URL) throws {
        let type: UTType = ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? .jpeg : .png
        let bytes = try export(image, as: type)
        try Task.checkCancellation()
        try bytes.write(to: url, options: .atomic)
    }
}
