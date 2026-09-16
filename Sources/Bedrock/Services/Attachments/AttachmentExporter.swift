import Foundation

struct ImageExportItem: Sendable {
    var filename: String
    var source: ImagePreviewSource
}

struct ImageExportResult: Sendable {
    var files: [URL] = []
    var failures: [String] = []
}

/// Image decoding and file writes stay off the main actor. Each file keeps its
/// original bytes and real format, and existing destination files are preserved.
actor AttachmentExporter {
    static let shared = AttachmentExporter()

    func save(_ items: [ImageExportItem], to directory: URL) async throws -> ImageExportResult {
        var isDirectory: ObjCBool = false
        guard directory.isFileURL,
              FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw LocalOperationError.invalid("Choose an existing folder for the images.")
        }
        var result = ImageExportResult()
        for item in items {
            try Task.checkCancellation()
            do {
                let image = try await ImagePreviewLoader.shared.load(item.source, maximumPixelSize: 64)
                try Task.checkCancellation()
                let stem = Self.filenameStem(item.filename)
                let temporary = directory.appendingPathComponent(".bedrock-export-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: temporary) }
                try image.original.write(to: temporary, options: [.atomic])
                var suffix = 1
                while true {
                    try Task.checkCancellation()
                    let name = stem + (suffix == 1 ? "" : " \(suffix)") + "." + image.fileExtension
                    let destination = directory.appendingPathComponent(name)
                    do {
                        // moveItem refuses an existing destination, including
                        // a file created after we chose the name.
                        try FileManager.default.moveItem(at: temporary, to: destination)
                        result.files.append(destination)
                        break
                    } catch let error as CocoaError where error.code == .fileWriteFileExists {
                        suffix += 1
                        if suffix > 10_000 { throw LocalOperationError.invalid("Too many images share the filename \(stem).") }
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                result.failures.append("\(item.filename): \(error.localizedDescription)")
            }
        }
        return result
    }

    private static func filenameStem(_ name: String) -> String {
        let component = (name.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
        let raw = (component as NSString).deletingPathExtension
        var stem = ""
        for character in raw {
            let part = String(character)
            guard !part.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { continue }
            if stem.utf8.count + part.utf8.count > 180 { break }
            stem += part
        }
        stem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        return stem.isEmpty || stem == "." || stem == ".." ? "Image" : stem
    }
}
