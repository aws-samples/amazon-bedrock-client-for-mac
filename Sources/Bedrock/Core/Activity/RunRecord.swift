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
    var duration: TimeInterval? { finishedAt.map { max(0, $0.timeIntervalSince(startedAt)) } }
    var timeToFirstToken: TimeInterval? { firstTokenAt.map { max(0, $0.timeIntervalSince(startedAt)) } }
    var tokensPerSecond: Double? {
        guard let outputTokens, let firstTokenAt, let finishedAt else { return nil }
        return Double(outputTokens) / max(0.001, finishedAt.timeIntervalSince(firstTokenAt))
    }
}
