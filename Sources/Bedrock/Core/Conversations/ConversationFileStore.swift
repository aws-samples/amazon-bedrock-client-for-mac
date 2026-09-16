import Foundation

/// Keeps the released JSON layout and backs up an older file before its first
/// upgrade. A file that cannot be decoded is never replaced with an empty chat.
struct ConversationFileStore {
    static let currentVersion = 2
    private var verifiedPaths: Set<String> = []

    enum ReadResult: Sendable {
        case unified(ConversationHistory)
        case legacy([MessageData])
    }

    static func read(unifiedURL: URL, legacyURL: URL, chatID: String) throws -> ReadResult {
        try Task.checkCancellation()
        let manager = FileManager.default
        let unified = manager.fileExists(atPath: unifiedURL.path)
        let url = unified ? unifiedURL : legacyURL
        guard manager.fileExists(atPath: url.path) else { return .legacy([]) }
        let limit = 128_000_000
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw LocalOperationError.invalid("The conversation must be a regular file.") }
        guard (values.fileSize ?? 0) <= limit else { throw LocalOperationError.tooLarge(limit) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw LocalOperationError.tooLarge(limit) }
        try Task.checkCancellation()
        if unified { return .unified(try decode(data, chatID: chatID)) }
        return .legacy(try LegacyConversationDecoder.decode(data))
    }

    static func decode(_ data: Data, chatID: String) throws -> ConversationHistory {
        let history = try JSONDecoder().decode(ConversationHistory.self, from: data)
        guard history.chatId == chatID else {
            throw LocalOperationError.invalid("The conversation ID does not match its file.")
        }
        guard (history.formatVersion ?? 1) <= currentVersion else {
            throw LocalOperationError.invalid("This conversation was saved by a newer app. Its original file has been preserved.")
        }
        return history
    }

    static func backupURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent("migration-backups", isDirectory: true)
            .appendingPathComponent(url.lastPathComponent)
    }

    @discardableResult
    mutating func write(_ history: ConversationHistory, to url: URL) throws -> ConversationHistory {
        guard (history.formatVersion ?? 1) <= Self.currentVersion else {
            throw LocalOperationError.invalid("This conversation requires a newer app.")
        }
        var upgraded = history
        upgraded.formatVersion = Self.currentVersion
        let data = try JSONEncoder().encode(upgraded)
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        if !verifiedPaths.contains(url.path), manager.fileExists(atPath: url.path) {
            let original = try Data(contentsOf: url)
            let previous = try Self.decode(original, chatID: history.chatId)
            if (previous.formatVersion ?? 1) < Self.currentVersion {
                let backup = Self.backupURL(for: url)
                try manager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !manager.fileExists(atPath: backup.path) {
                    // copyItem never replaces an earlier migration backup.
                    try manager.copyItem(at: url, to: backup)
                }
            }
        }
        try data.write(to: url, options: .atomic)
        verifiedPaths.insert(url.path)
        return upgraded
    }

    mutating func forget(_ url: URL) {
        verifiedPaths.remove(url.path)
    }
}
