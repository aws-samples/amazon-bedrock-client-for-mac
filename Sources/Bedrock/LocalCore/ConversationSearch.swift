import Foundation

struct ConversationSearchInput: Sendable {
    var id: String
    var unifiedURL: URL
    var legacyURL: URL
}

struct ConversationSearchHit: Equatable, Sendable {
    var messageID: UUID
    var snippet: String
}

struct ConversationSearchResults: Sendable {
    var hits: [String: ConversationSearchHit] = [:]
    var unreadableCount = 0
}

struct ConversationSearchRequest: Equatable {
    var id = UUID()
    var threadID: String
    var query: String
    var messageID: UUID
}

/// A bounded, local index. Large attachment payloads are discarded after decode;
/// repeated keystrokes reuse only the searchable text of unchanged files.
actor ConversationSearchIndex {
    static let shared = ConversationSearchIndex()
    private struct Entry {
        var modifiedAt: Date?
        var size: Int
        var fileID: UInt64?
        var textBytes: Int
        var messages: [(UUID, String)]
    }
    private var cache: [String: Entry] = [:]
    private var recency: [String] = []
    private let maximumCachedBytes = 6_000_000

    func search(_ query: String, inputs: [ConversationSearchInput], limit: Int = 40) -> ConversationSearchResults {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .init() }
        var results = ConversationSearchResults()
        for input in inputs {
            if Task.isCancelled { return results }
            do {
                let messages = try text(for: input)
                for (id, body) in messages {
                    try Task.checkCancellation()
                    guard let range = body.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
                    let start = body.index(range.lowerBound, offsetBy: -55, limitedBy: body.startIndex) ?? body.startIndex
                    let end = body.index(range.upperBound, offsetBy: 100, limitedBy: body.endIndex) ?? body.endIndex
                    let preview = body[start..<end].split(whereSeparator: \.isWhitespace).joined(separator: " ")
                    results.hits[input.id] = .init(messageID: id, snippet: "\(start == body.startIndex ? "" : "…")\(preview)\(end == body.endIndex ? "" : "…")")
                    break
                }
            } catch is CancellationError { return results }
            catch { results.unreadableCount += 1 }
            if results.hits.count >= max(1, limit) { break }
        }
        return results
    }

    private func text(for input: ConversationSearchInput) throws -> [(UUID, String)] {
        let manager = FileManager.default
        let url = manager.fileExists(atPath: input.unifiedURL.path) ? input.unifiedURL : input.legacyURL
        guard manager.fileExists(atPath: url.path) else { return [] }
        // URL resource values themselves can be cached. Stat the current file,
        // including its inode, so an atomic replacement with equal size/time
        // cannot keep a stale transcript in the search index.
        let properties = try manager.attributesOfItem(atPath: url.path)
        let modifiedAt = properties[.modificationDate] as? Date
        let size = (properties[.size] as? NSNumber)?.intValue ?? 0
        let fileID = (properties[.systemFileNumber] as? NSNumber)?.uint64Value
        if let entry = cache[url.path], entry.modifiedAt == modifiedAt, entry.size == size, entry.fileID == fileID {
            touch(url.path)
            return entry.messages
        }
        let messages: [(UUID, String)]
        switch try ConversationFileStore.read(unifiedURL: input.unifiedURL, legacyURL: input.legacyURL, chatID: input.id) {
        case .unified(let history):
            messages = history.messages.filter { $0.role != .user || ConversationEditing.isUserPrompt($0) }.map { ($0.id, $0.text) }
        case .legacy(let history):
            messages = history.filter { $0.user != "ToolResult" && !($0.user == "User" && $0.toolUses != nil) }.map { ($0.id, $0.text) }
        }
        let textBytes = messages.reduce(0) { $0 + $1.1.utf8.count }
        cache.removeValue(forKey: url.path)
        recency.removeAll { $0 == url.path }
        if textBytes <= maximumCachedBytes {
            cache[url.path] = Entry(modifiedAt: modifiedAt, size: size, fileID: fileID, textBytes: textBytes, messages: messages)
            touch(url.path)
            while cache.count > 24 || cache.values.reduce(0, { $0 + $1.textBytes }) > maximumCachedBytes {
                guard let first = recency.first else { break }
                cache.removeValue(forKey: first)
                recency.removeFirst()
            }
        }
        return messages
    }

    private func touch(_ path: String) {
        recency.removeAll { $0 == path }
        recency.append(path)
    }
}
