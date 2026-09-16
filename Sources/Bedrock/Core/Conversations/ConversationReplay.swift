import Foundation

/// Adapts a request copy when a conversation moves between model families.
/// Local history, attachments, reasoning and tool details remain intact.
enum ConversationReplay {
    static func prepare(
        _ history: ConversationHistory, targetModelID: String,
        supportsReasoning: Bool, supportsTools: Bool, supportsImages: Bool, supportsDocuments: Bool,
        foundationID: (String) -> String = BedrockModelID.base
    ) -> ConversationHistory {
        let target = foundationID(targetModelID)
        var prepared = history
        let calls = Set(history.messages.filter { $0.role == .assistant }.flatMap { tools(in: $0).map(\.toolId) })
        let results = Set(history.messages.filter { $0.role == .user }.flatMap { tools(in: $0).map(\.toolId) })
        let pairedIDs = calls.intersection(results)

        prepared.messages = history.messages.map { original in
            var message = original
            let sameModel = foundationID(message.modelID ?? history.modelId) == target
            if !sameModel || !supportsReasoning {
                message.thinking = nil
                message.thinkingSummary = nil
                message.thinkingSignature = nil
            }
            let tools = tools(in: message)
            if !tools.isEmpty && (!sameModel || !supportsTools || !tools.allSatisfy({ pairedIDs.contains($0.toolId) })) {
                for tool in tools {
                    let name = tool.displayName ?? tool.toolName
                    if message.role == .assistant {
                        let input = (try? JSONEncoder().encode(tool.inputs)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                        append("[Previous tool call: \(name)]\nInput: \(input)", to: &message.text)
                        // Older versions sometimes stored the result only on the
                        // assistant message. Preserve that information too.
                        if !results.contains(tool.toolId), let result = tool.result {
                            append("[Previous tool result: \(name)]\n\(result)", to: &message.text)
                        }
                    } else {
                        append("[Previous tool result: \(name)]\n\(tool.result ?? "The tool did not complete.")", to: &message.text)
                    }
                }
                message.toolUse = nil
                message.toolUses = nil
                message.thinking = nil
                message.thinkingSignature = nil
            }
            if !supportsImages || message.role == .assistant,
               let images = message.imageBase64Strings, !images.isEmpty {
                append("[\(images.count) earlier image attachment(s) remain saved locally. Image contents are unavailable to this model in this request.]", to: &message.text)
                message.imageBase64Strings = nil
            }
            if !supportsDocuments, let documents = message.documentBase64Strings, !documents.isEmpty {
                for (index, document) in documents.enumerated() {
                    let name = message.documentNames.flatMap { index < $0.count ? $0[index] : nil } ?? "Document"
                    let format = message.documentFormats.flatMap { index < $0.count ? $0[index].lowercased() : nil } ?? ""
                    if ["txt", "md", "csv", "html"].contains(format),
                       let data = Data(base64Encoded: document), let text = String(data: data, encoding: .utf8) {
                        append("[Earlier attachment: \(name)]\n\(text)", to: &message.text)
                    } else {
                        append("[Earlier attachment: \(name) remains saved locally. Its contents are unavailable to this model in this request.]", to: &message.text)
                    }
                }
                message.documentBase64Strings = nil
                message.documentFormats = nil
                message.documentNames = nil
            }
            return message
        }
        return prepared
    }

    private static func tools(in message: Message) -> [Message.ToolUse] {
        if let tools = message.toolUses, !tools.isEmpty { return tools }
        return message.toolUse.map { [$0] } ?? []
    }

    private static func append(_ text: String, to destination: inout String) {
        if !destination.isEmpty { destination += "\n\n" }
        destination += text
    }
}
