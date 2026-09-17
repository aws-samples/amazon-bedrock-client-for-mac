import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ClipboardImageInput: Sendable {
    case file(URL), data(Data), source(String)
}

struct PreparedClipboardImage: Sendable {
    let data: Data
    let preview: Data
    let fileExtension: String
    let width: Int
    let height: Int
}

enum PreparedLocalAttachment: Sendable {
    case image(PreparedClipboardImage, filename: String)
    case document(Data, fileExtension: String, filename: String)
}

enum LocalAttachmentProcessor {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "tif", "tiff", "webp", "heic", "bmp", "svg"]
    static let documentExtensions: Set<String> = ["pdf", "csv", "doc", "docx", "xls", "xlsx", "html", "txt", "md"]
    static let sourceExtensions: Set<String> = [
        "swift", "json", "jsonl", "yaml", "yml", "toml", "xml", "ini", "conf",
        "js", "jsx", "ts", "tsx", "py", "rs", "go", "java", "kt", "kts",
        "c", "h", "cpp", "hpp", "cs", "rb", "sh", "zsh", "bash",
        "css", "scss", "sql", "graphql", "tf", "log", "diff", "patch"
    ]
    static let documentInputExtensions = documentExtensions.union(sourceExtensions)
    static let maximumDocumentBytes = 4_500_000

    static func prepare(_ url: URL) async throws -> PreparedLocalAttachment {
        try Task.checkCancellation()
        guard url.isFileURL else { throw LocalOperationError.invalid("Choose a local file.") }
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) {
            let image = try await ClipboardImageProcessor.prepare(.file(url))
            return .image(image, filename: url.deletingPathExtension().lastPathComponent + "." + image.fileExtension)
        }
        let isSource = sourceExtensions.contains(ext)
        guard documentInputExtensions.contains(ext) else {
            throw LocalOperationError.invalid("The file type .\(ext) is not supported as an attachment.")
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw LocalOperationError.invalid("Choose a regular document file.") }
        guard (values.fileSize ?? 0) <= maximumDocumentBytes else { throw LocalOperationError.tooLarge(maximumDocumentBytes) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumDocumentBytes + 1) ?? Data()
        guard data.count <= maximumDocumentBytes else { throw LocalOperationError.tooLarge(maximumDocumentBytes) }
        try Task.checkCancellation()
        if isSource {
            guard !data.contains(0), String(data: data, encoding: .utf8) != nil else {
                throw LocalOperationError.invalid("This source file must contain UTF-8 text.")
            }
        }
        // Converse supports text documents, not language-specific file formats.
        // Keep exact source bytes and use its supported text format on the wire.
        return .document(data, fileExtension: isSource ? "txt" : ext,
                         filename: documentName(url.deletingPathExtension().lastPathComponent))
    }

    static func documentName(_ name: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-()[]")
        let pieces = name.unicodeScalars.map { allowed.contains($0) ? String($0) : " " }.joined()
        let normalized = pieces.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return normalized.isEmpty ? "Document" : normalized
    }
}

enum ClipboardImageProcessor {
    static let maximumInputBytes = 64_000_000 // TIFF clipboard representations can be large.
    static let maximumOutputBytes = 3_500_000

    static func prepare(_ input: ClipboardImageInput) async throws -> PreparedClipboardImage {
        try Task.checkCancellation()
        let data: Data
        switch input {
        case .data(let value): data = value
        case .file(let url):
            guard url.isFileURL else { throw LocalOperationError.invalid("Choose a local image file.") }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { throw LocalOperationError.invalid("Choose a regular image file.") }
            guard (values.fileSize ?? 0) <= maximumInputBytes else { throw LocalOperationError.tooLarge(maximumInputBytes) }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: maximumInputBytes + 1) ?? Data()
        case .source(let source):
            guard ClipboardHTMLParser.isImageSourceAllowed(source) else {
                throw LocalOperationError.invalid("This clipboard image source is unsupported.")
            }
            if source.lowercased().hasPrefix("data:") {
                guard source.utf8.count <= ClipboardHTMLParser.maximumHTMLBytes,
                      let comma = source.firstIndex(of: ","),
                      let decoded = Data(base64Encoded: String(source[source.index(after: comma)...]), options: .ignoreUnknownCharacters) else {
                    throw LocalOperationError.invalid("The clipboard image data is invalid.")
                }
                data = decoded
            } else {
                data = try await ClipboardImageDownload.fetch(try LocalPath.validatedWebURL(source, allowedDomains: ""))
            }
        }
        try Task.checkCancellation()
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> PreparedClipboardImage {
        guard data.count <= maximumInputBytes else { throw LocalOperationError.tooLarge(maximumInputBytes) }
        if SVGClipboardRasterizer.isSVG(data) {
            let image = try SVGClipboardRasterizer.rasterize(data, maximumPixelSize: 2560)
            guard let png = encode(image, type: UTType.png.identifier) else {
                throw LocalOperationError.invalid("The SVG image could not be converted to PNG.")
            }
            return try decode(png)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw LocalOperationError.invalid("This image is damaged or its format could not be opened.")
        }
        try ImageDownsampling.validateSourceDimensions(width: width, height: height)
        let type = CGImageSourceGetType(source).map { $0 as String }
        let isJPEG = type == UTType.jpeg.identifier
        let ext = isJPEG ? "jpeg" : "png"
        let outputType = isJPEG ? UTType.jpeg.identifier : UTType.png.identifier
        var dimension = min(2560, max(width, height))
        var encoded: Data?
        var preparedWidth = 0
        var preparedHeight = 0
        var workingSource = source
        var workingWidth = width
        var workingHeight = height
        while dimension > 0 {
            try Task.checkCancellation()
            let options = ImageDownsampling.options(maximumPixelSize: dimension, width: workingWidth, height: workingHeight)
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(workingSource, 0, options) else {
                throw LocalOperationError.invalid("This image could not be prepared for the message.")
            }
            let image = try padForModelAspectRatio(thumbnail)
            guard let output = encode(image, type: outputType) else {
                throw LocalOperationError.invalid("This image could not be prepared for the message.")
            }
            if output.count <= maximumOutputBytes {
                encoded = output
                preparedWidth = image.width
                preparedHeight = image.height
                break
            }
            if dimension <= 320 { break }
            // Retry and preview from the bounded rendition, not the original
            // panorama or screenshot. The expensive source is decoded once.
            guard let reducedSource = CGImageSourceCreateWithData(output as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
                throw LocalOperationError.invalid("The resized image could not be opened.")
            }
            workingSource = reducedSource
            workingWidth = image.width
            workingHeight = image.height
            dimension = dimension * 3 / 4
        }
        guard let encoded else { throw LocalOperationError.tooLarge(maximumOutputBytes) }
        let previewOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let previewSource = CGImageSourceCreateWithData(encoded as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let previewImage = CGImageSourceCreateThumbnailAtIndex(previewSource, 0, previewOptions as CFDictionary),
              let preview = encode(previewImage, type: UTType.png.identifier) else {
            throw LocalOperationError.invalid("This image preview could not be prepared.")
        }
        return .init(data: encoded, preview: preview, fileExtension: ext, width: preparedWidth, height: preparedHeight)
    }

    private static func padForModelAspectRatio(_ image: CGImage) throws -> CGImage {
        // Nova also limits aspect ratio to 20:1. Downsampling alone cannot
        // change it. Add a small neutral margin without cropping or stretching
        // long screenshots, preserving every pixel of the bounded rendition.
        let minimumEdge = Int(ceil(Double(max(image.width, image.height)) / 20))
        let width = max(image.width, minimumEdge)
        let height = max(image.height, minimumEdge)
        guard width != image.width || height != image.height else { return image }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw LocalOperationError.invalid("This image could not be fitted for the model.")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: (width - image.width) / 2, y: (height - image.height) / 2,
                                      width: image.width, height: image.height))
        guard let padded = context.makeImage() else {
            throw LocalOperationError.invalid("This image could not be fitted for the model.")
        }
        return padded
    }

    private static func encode(_ image: CGImage, type: String) -> Data? {
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, type as CFString, 1, nil) else { return nil }
        // Do not copy clipboard EXIF, location, or application metadata.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return result as Data
    }
}

struct PreparedRequestImage: Sendable {
    let base64: String
    let format: String
}

/// Old conversations and tool history can contain images prepared before the
/// current limits. Normalize only their outgoing copies, off the main actor.
/// Already-compatible PNG/JPEG bytes take a metadata-only path; conversions
/// are cached so subsequent turns and tool loops do not decode them again.
actor BedrockImageNormalizer {
    static let shared = BedrockImageNormalizer()
    private final class Cached: NSObject {
        let image: PreparedRequestImage
        init(_ image: PreparedRequestImage) { self.image = image }
    }
    private let cache: NSCache<NSString, Cached> = {
        let value = NSCache<NSString, Cached>()
        value.totalCostLimit = 16 * 1_024 * 1_024
        value.countLimit = 64
        return value
    }()

    func normalize(_ inputs: [String]) throws -> [PreparedRequestImage] {
        try inputs.map { encoded in
            try Task.checkCancellation()
            guard encoded.utf8.count <= (ClipboardImageProcessor.maximumInputBytes + 2) / 3 * 4,
                  let data = Data(base64Encoded: encoded) else {
                throw LocalOperationError.invalid("An image in this conversation could not be opened.")
            }
            if let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
               let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? Int,
               let height = properties[kCGImagePropertyPixelHeight] as? Int,
               width > 0, height > 0, max(width, height) <= 2560,
               Double(max(width, height)) / Double(min(width, height)) <= 20,
               data.count <= ClipboardImageProcessor.maximumOutputBytes,
               let type = CGImageSourceGetType(source) as String?,
               type == UTType.png.identifier || type == UTType.jpeg.identifier {
                return PreparedRequestImage(base64: encoded, format: type == UTType.png.identifier ? "png" : "jpeg")
            }
            let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() as NSString
            if let previous = cache.object(forKey: key) { return previous.image }
            let prepared = try ClipboardImageProcessor.decode(data)
            let result = PreparedRequestImage(base64: prepared.data.base64EncodedString(), format: prepared.fileExtension)
            cache.setObject(Cached(result), forKey: key, cost: result.base64.utf8.count * 2)
            return result
        }
    }
}

enum ImageDownsampling {
    static func validateSourceDimensions(width: Int, height: Int) throws {
        // These are decoder-resource bounds, not the model's image dimensions.
        // Long screenshots and large camera images are reduced before sending.
        guard width > 0, height > 0, width <= 131_072, height <= 131_072,
              width <= 256_000_000 / height else {
            throw LocalOperationError.invalid("This image exceeds the local decoder's 256-megapixel size limit.")
        }
    }

    static func options(maximumPixelSize: Int, width: Int, height: Int) -> CFDictionary {
        let factor = [8, 4, 2].first { max(width, height) / $0 >= maximumPixelSize }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if let factor { options[kCGImageSourceSubsampleFactor] = factor }
        return options as CFDictionary
    }
}

/// Browser selections often include SVGs with no raster pixel metadata.
/// Rasterize self-contained vectors into a bounded bitmap off the UI thread;
/// never route them through WebKit or allow external resources/entities.
private enum SVGClipboardRasterizer {
    static func isSVG(_ data: Data) -> Bool {
        let prefix = String(decoding: data.prefix(4096), as: UTF8.self)
        return prefix.range(of: #"<svg(?:\s|>)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func rasterize(_ data: Data, maximumPixelSize: Int) throws -> CGImage {
        guard data.count <= 2_000_000 else { throw LocalOperationError.tooLarge(2_000_000) }
        guard let text = String(data: data, encoding: .utf8),
              !text.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !text.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw LocalOperationError.invalid("SVG attachments must not contain document types or external entities.")
        }
        let validator = Validator()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = validator
        guard parser.parse(), validator.hasSVGRoot, validator.valid,
              let image = NSImage(data: data), image.size.width.isFinite, image.size.height.isFinite,
              image.size.width > 0, image.size.height > 0 else {
            throw LocalOperationError.invalid("This SVG is invalid or refers to external resources. Paste a PNG or JPEG instead.")
        }
        try Task.checkCancellation()
        let scale = min(1, CGFloat(maximumPixelSize) / max(image.size.width, image.size.height))
        let width = max(1, Int(ceil(image.size.width * scale)))
        let height = max(1, Int(ceil(image.size.height * scale)))
        guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                     bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw LocalOperationError.invalid("The SVG preview could not be allocated.")
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero,
                   operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        guard let output = bitmap.makeImage() else { throw LocalOperationError.invalid("The SVG could not be rendered.") }
        return output
    }

    private final class Validator: NSObject, XMLParserDelegate {
        var valid = true
        var hasSVGRoot = false
        private var depth = 0
        private var elements = 0
        private var styleDepth: Int?
        private var style = ""

        private func safeCSS(_ value: String) -> Bool {
            guard !value.contains("\\"), !value.contains("@"), !value.contains("/*") else { return false }
            let regex = try! NSRegularExpression(pattern: #"url\s*\((.*?)\)"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
            let source = value as NSString
            let matches = regex.matches(in: value, range: NSRange(location: 0, length: source.length))
            let remaining = regex.stringByReplacingMatches(in: value, range: NSRange(location: 0, length: source.length), withTemplate: "")
            guard !remaining.localizedCaseInsensitiveContains("url") else { return false }
            return matches.allSatisfy {
                let target = source.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
                return target.range(of: #"^#[A-Za-z_][A-Za-z0-9_.:-]*$"#, options: .regularExpression) != nil
            }
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            let tag = name.lowercased()
            if depth == 0 { hasSVGRoot = tag == "svg" }
            depth += 1
            elements += 1
            if depth > 128 || elements > 20_000 { valid = false }
            if ["script", "foreignobject", "iframe", "object", "embed", "animate", "set"].contains(tag) { valid = false }
            if tag == "style" { styleDepth = depth; style = "" }
            for (key, value) in attributes {
                let key = key.lowercased()
                if key.hasPrefix("on") || key == "xml:base" { valid = false }
                if key == "href" || key.hasSuffix(":href") {
                    if value.range(of: #"^#[A-Za-z_][A-Za-z0-9_.:-]*$"#, options: .regularExpression) == nil { valid = false }
                }
                if !safeCSS(value) { valid = false }
            }
            if !valid { parser.abortParsing() }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if styleDepth != nil { style += string }
        }
        func parser(_ parser: XMLParser, foundCDATA data: Data) {
            if styleDepth != nil { style += String(decoding: data, as: UTF8.self) }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if styleDepth == depth {
                valid = valid && safeCSS(style)
                styleDepth = nil
                if !valid { parser.abortParsing() }
            }
            depth -= 1
        }
        func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
            valid = false
            parser.abortParsing()
        }
    }
}

/// Chunked transfers bound memory before decoding, including after redirects.
/// A pasted web image never carries this app's AWS credentials or browser cookies.
private final class ClipboardImageDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var data = Data()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var finished = false
    private static let limit = 12_000_000

    static func fetch(_ url: URL) async throws -> Data {
        let download = ClipboardImageDownload()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in download.start(url, continuation: continuation) }
        } onCancel: { download.finish(.failure(CancellationError())) }
    }

    private func start(_ url: URL, continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        let task = session.dataTask(with: url)
        self.task = task
        lock.unlock()
        task.resume()
    }

    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = continuation
        self.continuation = nil
        let session = session
        self.session = nil
        task = nil
        data = Data()
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              response.expectedContentLength <= Self.limit,
              response.mimeType?.lowercased().hasPrefix("image/") == true else {
            completionHandler(.cancel)
            finish(.failure(LocalOperationError.invalid("The copied image URL did not return a supported image.")))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let value = request.url?.absoluteString, (try? LocalPath.validatedWebURL(value, allowedDomains: "")) != nil else {
            completionHandler(nil)
            finish(.failure(LocalOperationError.invalid("The image URL redirected to an unsupported address.")))
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        guard data.count + chunk.count <= Self.limit else {
            lock.unlock()
            finish(.failure(LocalOperationError.tooLarge(Self.limit)))
            return
        }
        data.append(chunk)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)); return }
        lock.lock()
        let output = data
        lock.unlock()
        finish(.success(output))
    }
}
