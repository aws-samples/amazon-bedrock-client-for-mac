import Foundation

struct ContextMessageSize: Sendable {
    var startsUserTurn: Bool
    var characters: Int
}

struct ContextSelection: Equatable, Sendable {
    var startIndex: Int
    var omittedMessages: Int
    var retainedCharacters: Int
    var notice: String? {
        omittedMessages > 0
            ? "\(omittedMessages) earlier messages were left out of this request to fit the context budget. The full conversation remains saved on this Mac."
            : nil
    }
}

enum ContextBudget {
    /// Keeps complete turns, including every tool-use/result pair. It never edits
    /// persisted history or silently clips the user's latest prompt.
    static func select(_ messages: [ContextMessageSize], budget: Int) throws -> ContextSelection {
        guard !messages.isEmpty else { return .init(startIndex: 0, omittedMessages: 0, retainedCharacters: 0) }
        var starts = messages.indices.filter { messages[$0].startsUserTurn }
        if starts.first != 0 { starts.insert(0, at: 0) }
        let total = messages.reduce(0) { $0 + max(0, $1.characters) }
        if total <= budget { return .init(startIndex: 0, omittedMessages: 0, retainedCharacters: total) }
        var used = 0
        var selectedStart = messages.count
        for position in starts.indices.reversed() {
            let start = starts[position]
            let end = position + 1 < starts.count ? starts[position + 1] : messages.count
            let size = messages[start..<end].reduce(0) { $0 + max(0, $1.characters) }
            if used + size > budget { break }
            used += size
            selectedStart = start
        }
        guard selectedStart < messages.count else {
            throw LocalWorkbenchError.invalid("The latest turn exceeds the context budget. Increase the budget in Models & context, shorten the prompt, or start a new thread.")
        }
        return .init(startIndex: selectedStart, omittedMessages: selectedStart, retainedCharacters: used)
    }
}
