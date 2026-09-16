import Foundation

struct ThreadMetadata: Codable, Equatable, Sendable {
    var draft = ""
    var projectID: UUID?
    var workingDirectory: String?
    var skillIDs: [String] = []
    var systemPrompt = ""
    var pinnedAt: Date?
    var archived = false
    var deletedAt: Date?
    var parentThreadID: String?
    var contextNotice: String?
    var demoID: String?
    var hasQueuedMessages: Bool?
    var hasDraftAttachments: Bool?
    var isPinned: Bool { pinnedAt != nil }
    var hasUnsentWork: Bool { !draft.isEmpty || isPinned || !skillIDs.isEmpty || !systemPrompt.isEmpty || hasQueuedMessages == true || hasDraftAttachments == true }
}
