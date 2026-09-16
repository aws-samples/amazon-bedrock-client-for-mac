import Foundation

enum RunStatus: String, CaseIterable, Codable, Sendable {
    case running, completed, failed, cancelled, timedOut
    var title: String {
        switch self {
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Stopped"
        case .timedOut: "Timed out"
        }
    }
}

struct RunRecord: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var threadID: String
    var modelID: String
    var title: String
    var startedAt = Date()
    var finishedAt: Date?
    var firstTokenAt: Date?
    var status: RunStatus = .running
    var inputTokens: Int?
    var outputTokens: Int?
    var cacheReadTokens: Int?
    var cacheWriteTokens: Int?
    var toolCalls = 0
    var error: String?
    var automationID: UUID?
    var stopReason: String?
    var canContinueResponse: Bool { status == .completed && stopReason == "max_tokens" }
    var completionNotice: String? {
        guard status == .completed else { return nil }
        switch stopReason {
        case "max_tokens": return "This response reached its output limit."
        case "model_context_window_exceeded": return "The conversation reached this model’s context limit."
        case "content_filtered": return "The model stopped because its content filter was triggered."
        case "guardrail_intervened": return "The configured Bedrock guardrail stopped this response."
        case "malformed_model_output", "malformed_tool_use": return "The model returned an incomplete response."
        default: return nil
        }
    }
    var duration: TimeInterval? { finishedAt.map { max(0, $0.timeIntervalSince(startedAt)) } }
    var timeToFirstToken: TimeInterval? { firstTokenAt.map { max(0, $0.timeIntervalSince(startedAt)) } }
    var tokensPerSecond: Double? {
        guard let outputTokens, let firstTokenAt, let finishedAt else { return nil }
        return Double(outputTokens) / max(0.001, finishedAt.timeIntervalSince(firstTokenAt))
    }
}
