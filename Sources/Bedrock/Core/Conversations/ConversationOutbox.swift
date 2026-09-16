import Foundation

struct QueuedPrompt: Codable, Identifiable, Equatable, Sendable {
    var message: MessageData
    var modelID: String
    var id: UUID { message.id }
    var attachmentCount: Int {
        (message.imageBase64Strings?.count ?? 0) + (message.documentBase64Strings?.count ?? 0) + (message.pastedTexts?.count ?? 0)
    }
}

struct ConversationOutbox: Codable, Equatable, Sendable {
    var version = 1
    var queued: [QueuedPrompt] = []
    var inFlight: QueuedPrompt?
    var pauseReason: String?

    /// A restart must neither silently send paid requests nor send a prompt
    /// twice if it was already checkpointed in conversation history.
    mutating func recover(sentMessageIDs: Set<UUID>) {
        if let previous = inFlight, !sentMessageIDs.contains(previous.id),
           !queued.contains(where: { $0.id == previous.id }) {
            queued.insert(previous, at: 0)
        }
        inFlight = nil
        if !queued.isEmpty { pauseReason = "Saved messages are ready. Resume when you’re ready to send them." }
    }

    mutating func append(_ prompt: QueuedPrompt) throws {
        guard queued.count < 20 else { throw LocalOperationError.invalid("The queue holds up to 20 messages. Send or remove one before adding another.") }
        guard !queued.contains(where: { $0.id == prompt.id }), inFlight?.id != prompt.id else {
            throw LocalOperationError.invalid("This message is already in the queue.")
        }
        queued.append(prompt)
    }

    mutating func moveToFront(_ id: UUID) {
        guard let index = queued.firstIndex(where: { $0.id == id }) else { return }
        queued.insert(queued.remove(at: index), at: 0)
    }
}

enum ConversationOutboxFile {
    static let maximumBytes = 128_000_000

    static func url(threadID: String, directory: URL) throws -> URL {
        guard threadID.range(of: #"^[a-zA-Z0-9_-]{1,128}$"#, options: .regularExpression) != nil else {
            throw LocalOperationError.invalid("This conversation identifier cannot be used for draft storage.")
        }
        return directory.appendingPathComponent("outbox", isDirectory: true).appendingPathComponent(threadID + ".json")
    }

    static func read(_ url: URL) throws -> ConversationOutbox {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard properties.isRegularFile == true else { throw LocalOperationError.invalid("The message queue must be a regular file.") }
        guard (properties.fileSize ?? 0) <= maximumBytes else { throw LocalOperationError.tooLarge(maximumBytes) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw LocalOperationError.tooLarge(maximumBytes) }
        let value = try JSONDecoder().decode(ConversationOutbox.self, from: data)
        try validate(value)
        return value
    }

    static func write(_ value: ConversationOutbox, to url: URL) throws {
        try validate(value)
        // A corrupt or future-version queue remains available for recovery.
        _ = try read(url)
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximumBytes else { throw LocalOperationError.tooLarge(maximumBytes) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func validate(_ value: ConversationOutbox) throws {
        let prompts = value.queued + (value.inFlight.map { [$0] } ?? [])
        // Recovery can put one interrupted in-flight item ahead of a full queue.
        guard value.version == 1, value.queued.count <= 21,
              Set(prompts.map(\.id)).count == prompts.count,
              prompts.allSatisfy({ !$0.modelID.isEmpty && $0.modelID.count <= 512 && $0.message.user == "User" }) else {
            throw LocalOperationError.invalid("This saved message queue cannot be opened by this app. Its original file was kept.")
        }
    }
}
