import Foundation

struct DraftAttachment: Codable, Equatable, Sendable {
    var id: UUID
    var data: Data
    var filename: String
    var format: String
    var pastedText: String?
}

struct ConversationAttachmentDraft: Codable, Equatable, Sendable {
    var version = 1
    var images: [DraftAttachment] = []
    var documents: [DraftAttachment] = []
    var isEmpty: Bool { images.isEmpty && documents.isEmpty }
}

enum ConversationAttachmentDraftFile {
    static let maximumBytes = 128_000_000

    static func url(threadID: String, directory: URL) throws -> URL {
        guard threadID.range(of: #"^[a-zA-Z0-9_-]{1,128}$"#, options: .regularExpression) != nil else {
            throw LocalOperationError.invalid("This conversation identifier cannot be used for attachment storage.")
        }
        return directory.appendingPathComponent("drafts", isDirectory: true).appendingPathComponent(threadID + ".json")
    }

    static func validate(_ value: ConversationAttachmentDraft) throws {
        let attachments = value.images + value.documents
        guard value.version == 1, value.images.count <= 20, value.documents.count <= 25,
              Set(attachments.map(\.id)).count == attachments.count,
              attachments.allSatisfy({
                  !$0.data.isEmpty && $0.data.count <= 20_000_000 &&
                  !$0.filename.isEmpty && $0.filename.utf8.count <= 4_096 &&
                  !$0.format.isEmpty && $0.format.utf8.count <= 32
              }),
              value.images.allSatisfy({ $0.pastedText == nil }),
              value.documents.allSatisfy({ item in
                  item.data.count <= 4_500_000 &&
                  (item.pastedText.map { Data($0.utf8) == item.data } ?? true)
              }) else {
            throw LocalOperationError.invalid("These saved attachments cannot be opened by this app. The original draft was kept.")
        }
    }

    static func read(_ url: URL) throws -> ConversationAttachmentDraft {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        let properties = try FileManager.default.attributesOfItem(atPath: url.path)
        guard properties[.type] as? FileAttributeType == .typeRegular else {
            throw LocalOperationError.invalid("The attachment draft must be a regular file.")
        }
        guard (properties[.size] as? NSNumber)?.intValue ?? .max <= maximumBytes else {
            throw LocalOperationError.tooLarge(maximumBytes)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw LocalOperationError.tooLarge(maximumBytes) }
        let value = try JSONDecoder().decode(ConversationAttachmentDraft.self, from: data)
        try validate(value)
        return value
    }

    static func write(_ value: ConversationAttachmentDraft, to url: URL) throws {
        try validate(value)
        // Never erase a damaged or newer-format draft, even when clearing.
        _ = try read(url)
        if value.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximumBytes else { throw LocalOperationError.tooLarge(maximumBytes) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

/// Encoding and file I/O run on this actor, away from AppKit. A delayed save
/// cannot put an older attachment set back after Send or Remove cleared it.
actor ConversationAttachmentDraftWriter {
    private var lastRevision: UInt64 = 0
    func write(_ value: ConversationAttachmentDraft, to url: URL, revision: UInt64) throws {
        guard revision >= lastRevision else { return }
        try ConversationAttachmentDraftFile.write(value, to: url)
        lastRevision = revision
    }
}
