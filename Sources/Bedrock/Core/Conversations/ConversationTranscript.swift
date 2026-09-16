import Foundation

/// All user-facing messages, in conversation order. The native list reuses row
/// views; its data never excludes a message because it is outside the viewport.
enum ConversationTranscript {
    struct ModelTransition: Equatable {
        let fromModelID: String
        let toModelID: String
    }

    struct Row: Identifiable {
        let sourceIndex: Int
        let message: MessageData
        let modelTransition: ModelTransition?
        var id: UUID { message.id }
    }

    static func rows(in messages: [MessageData]) -> [Row] {
        var previousModelID: String?
        return messages.enumerated().compactMap { index, message in
            guard isVisible(message) else { return nil }
            let change = transition(from: previousModelID, to: message.modelID)
            if let modelID = message.modelID, !modelID.isEmpty { previousModelID = modelID }
            return Row(sourceIndex: index, message: message, modelTransition: change)
        }
    }

    /// An idle selection is shown at the end until the next message carries its
    /// model ID. There is then one persisted boundary, not a second event or an
    /// artificial message sent to the model.
    static func pendingTransition(after rows: [Row], to modelID: String) -> ModelTransition? {
        let previous = rows.reversed().lazy.compactMap(\.message.modelID).first { !$0.isEmpty }
        return transition(from: previous, to: modelID)
    }

    private static func transition(from previous: String?, to next: String?) -> ModelTransition? {
        guard let previous, let next, !previous.isEmpty, !next.isEmpty, previous != next,
              BedrockModelID.base(previous) != BedrockModelID.base(next) else { return nil }
        return ModelTransition(fromModelID: previous, toModelID: next)
    }

    static func isVisible(_ message: MessageData) -> Bool {
        message.user != "ToolResult" && !(message.user == "User" && message.toolUses != nil)
    }

    /// Prepare only likely first-paint Markdown. This bounds parsing work before
    /// opening a chat, independently of the complete list available to scroll.
    static func prewarmingTexts(in messages: [MessageData]) -> [String] {
        var texts: [String] = []
        var bytes = 0
        for message in messages.reversed() where isVisible(message) && message.user != "User" {
            guard !message.text.isEmpty else { continue }
            let size = message.text.utf8.count
            if !texts.isEmpty && (texts.count >= 16 || bytes + size > 96_000) { break }
            texts.append(message.text)
            bytes += size
        }
        return texts.reversed()
    }
}
