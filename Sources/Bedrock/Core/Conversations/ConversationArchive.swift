import Foundation

struct ConversationArchive: Codable, Sendable {
    var version = 1
    var title: String
    var modelID: String
    var modelName: String
    var provider: String
    var messages: [Message]
    var systemPrompt: String?
}

enum ConversationArchiveCodec {
    static let maximumBytes = 50_000_000

    static func validate(_ archive: ConversationArchive) throws {
        guard archive.version == 1, !archive.modelID.isEmpty, archive.modelID.count <= 512,
              !archive.title.isEmpty, archive.title.count <= 500, archive.messages.count <= 20_000,
              Set(archive.messages.map(\.id)).count == archive.messages.count else {
            throw LocalOperationError.invalid("This is not a supported Bedrock conversation export.")
        }
        var total = 0
        for message in archive.messages {
            try Task.checkCancellation()
            for tool in (message.toolUses ?? []) + (message.toolUse.map { [$0] } ?? []) {
                guard (tool.resultImages?.count ?? 0) <= 4 else {
                    throw LocalOperationError.invalid("A tool result contains too many images.")
                }
                for image in tool.resultImages ?? [] {
                    total += image.base64.utf8.count
                    guard total <= maximumBytes else { throw LocalOperationError.tooLarge(maximumBytes) }
                    guard ["jpeg", "png"].contains(image.format),
                          image.base64.utf8.count <= 4_666_668,
                          Data(base64Encoded: image.base64) != nil else {
                        throw LocalOperationError.invalid("The tool image is invalid or exceeds its size limit.")
                    }
                }
            }
            let documents = message.documentBase64Strings?.count ?? 0
            guard message.documentFormats.map({ $0.count == documents }) ?? true,
                  message.documentNames.map({ $0.count == documents }) ?? true else {
                throw LocalOperationError.invalid("A document is missing its name or format. The original export was not changed.")
            }
            for value in (message.imageBase64Strings ?? []) + (message.documentBase64Strings ?? []) {
                total += value.utf8.count
                guard total <= maximumBytes else { throw LocalOperationError.tooLarge(maximumBytes) }
                guard Data(base64Encoded: value) != nil else {
                    throw LocalOperationError.invalid("Attachments must be embedded as base64 data, not paths to files on this Mac.")
                }
            }
        }
    }

    static func read(_ url: URL) throws -> ConversationArchive {
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard properties.isRegularFile == true else { throw LocalOperationError.invalid("Choose a regular JSON file.") }
        guard (properties.fileSize ?? 0) <= maximumBytes else { throw LocalOperationError.tooLarge(maximumBytes) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw LocalOperationError.tooLarge(maximumBytes) }
        try Task.checkCancellation()
        let archive = try JSONDecoder().decode(ConversationArchive.self, from: data)
        try validate(archive)
        return archive
    }

    static func encode(_ archive: ConversationArchive) throws -> Data {
        try validate(archive)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(archive)
        guard data.count <= maximumBytes else { throw LocalOperationError.tooLarge(maximumBytes) }
        return data
    }
}

enum LocalImageReference {
    static func read(_ reference: String, directory: URL) throws -> Data {
        if !reference.hasPrefix("img_") {
            guard let data = Data(base64Encoded: reference) else {
                throw LocalOperationError.invalid("The image attachment could not be decoded.")
            }
            return data
        }
        guard UUID(uuidString: String(reference.dropFirst(4))) != nil else {
            throw LocalOperationError.invalid("The stored image identifier is invalid.")
        }
        let url = try LocalPath.resolve(reference + ".png", in: directory)
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        let limit = 20_000_000
        guard properties.isRegularFile == true else { throw LocalOperationError.invalid("The image must be a regular file.") }
        guard (properties.fileSize ?? 0) <= limit else { throw LocalOperationError.tooLarge(limit) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw LocalOperationError.tooLarge(limit) }
        return data
    }
}
