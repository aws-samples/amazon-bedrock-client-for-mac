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
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "tif", "tiff", "webp", "heic", "bmp"]
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
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 32_768, height <= 32_768,
              Int64(width) * Int64(height) <= 100_000_000 else {
            throw LocalOperationError.invalid("This image could not be decoded within the supported dimensions.")
        }
        let type = CGImageSourceGetType(source).map { $0 as String }
        let isJPEG = type == UTType.jpeg.identifier
        let ext = isJPEG ? "jpeg" : "png"
        let outputType = isJPEG ? UTType.jpeg.identifier : UTType.png.identifier
        var dimension = min(2560, max(width, height))
        var encoded: Data?
        var preparedWidth = 0
        var preparedHeight = 0
        while dimension > 0 {
            try Task.checkCancellation()
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: dimension,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let output = encode(image, type: outputType) else {
                throw LocalOperationError.invalid("This image could not be prepared for the message.")
            }
            if output.count <= maximumOutputBytes {
                encoded = output
                preparedWidth = image.width
                preparedHeight = image.height
                break
            }
            if dimension <= 320 { break }
            dimension = dimension * 3 / 4
        }
        guard let encoded else { throw LocalOperationError.tooLarge(maximumOutputBytes) }
        let previewOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let previewImage = CGImageSourceCreateThumbnailAtIndex(source, 0, previewOptions as CFDictionary),
              let preview = encode(previewImage, type: UTType.png.identifier) else {
            throw LocalOperationError.invalid("This image preview could not be prepared.")
        }
        return .init(data: encoded, preview: preview, fileExtension: ext, width: preparedWidth, height: preparedHeight)
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
