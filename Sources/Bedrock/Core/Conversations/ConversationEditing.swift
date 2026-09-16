import Foundation

/// Message actions operate on a copy. The original history and its draft remain
/// untouched, and a branch never ends between a tool call and its result.
enum ConversationEditing {
    static func isUserPrompt(_ message: Message) -> Bool {
        message.role == .user && message.toolUse == nil && message.toolUses?.isEmpty != false
    }

    static func prompt(before responseID: UUID, in history: ConversationHistory) throws -> Message {
        guard let index = history.messages.firstIndex(where: { $0.id == responseID }),
              let prompt = history.messages.prefix(index + 1).last(where: isUserPrompt) else {
            throw LocalOperationError.invalid("The original prompt for this response could not be found.")
        }
        return prompt
    }

    static func messages(in history: ConversationHistory, before id: UUID) throws -> [Message] {
        guard let index = history.messages.firstIndex(where: { $0.id == id }) else {
            throw LocalOperationError.invalid("This message is no longer in the conversation.")
        }
        return Array(history.messages.prefix(index))
    }

    static func messages(in history: ConversationHistory, through id: UUID) throws -> [Message] {
        guard let index = history.messages.firstIndex(where: { $0.id == id }) else {
            throw LocalOperationError.invalid("This message is no longer in the conversation.")
        }
        var end = index + 1
        // Tool results are hidden in the transcript but belong to the preceding
        // assistant message. Include every consecutive result in this cycle.
        while end < history.messages.count {
            let next = history.messages[end]
            guard next.role == .user && !isUserPrompt(next) else { break }
            end += 1
        }
        return Array(history.messages.prefix(end))
    }

    static func markdown(title: String, modelName: String, modelID: String, messages: [Message]) throws -> String {
        var parts = ["# \(title)", "Model: \(modelName) (`\(modelID)`)"]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        for message in messages {
            if message.role == .user && !isUserPrompt(message) { continue }
            parts.append("## \(message.role == .user ? "You" : "Assistant")\n\n\(message.text)")
            for pasted in message.pastedTexts ?? [] {
                parts.append("### \(pasted.filename)\n\n\(fenced(pasted.content, language: "text"))")
            }
            for (index, _) in (message.documentBase64Strings ?? []).enumerated() {
                let name = message.documentNames.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? "Document \(index + 1)"
                parts.append("Attachment: \(name)")
            }
            if let images = message.imageBase64Strings, !images.isEmpty {
                parts.append("Image attachments: \(images.count) (included in JSON export)")
            }
            let tools = message.toolUses ?? message.toolUse.map { [$0] } ?? []
            for tool in tools {
                let input = String(decoding: try encoder.encode(tool.inputs), as: UTF8.self)
                parts.append("### Tool: \(tool.toolName)\n\nStatus: \(tool.status ?? "pending")\n\nInput:\n\n\(fenced(input, language: "json"))")
                if let output = tool.result { parts.append("Output:\n\n\(fenced(output, language: "text"))") }
            }
            if let s3 = message.videoS3Uri { parts.append("Generated video: \(s3)") }
        }
        return parts.joined(separator: "\n\n") + "\n"
    }

    private static func fenced(_ content: String, language: String) -> String {
        var run = 0
        var longest = 0
        for character in content {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return "\(fence)\(language)\n\(content)\n\(fence)"
    }
}
