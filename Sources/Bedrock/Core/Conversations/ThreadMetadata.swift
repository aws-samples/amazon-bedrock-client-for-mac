import Foundation

struct ThreadMetadata: Codable, Equatable, Sendable {
    var draft = ""
    var projectID: UUID?
    var workingDirectory: String?
    var skillIDs: [String] = []
    var systemPrompt = ""
    var pinnedAt: Date?
    var archived = false
    var parentThreadID: String?
    var contextNotice: String?
    var demoID: String?
    var hasQueuedMessages: Bool?
    var hasDraftAttachments: Bool?
    var isPinned: Bool { pinnedAt != nil }
    var hasUnsentWork: Bool { !draft.isEmpty || isPinned || !skillIDs.isEmpty || !systemPrompt.isEmpty || hasQueuedMessages == true || hasDraftAttachments == true }
}

extension ThreadMetadata {
    private enum CodingKeys: String, CodingKey {
        case draft, projectID, workingDirectory, skillIDs, systemPrompt, pinnedAt, archived
        case deletedAt // Read the old Trash state; new workspaces have only Archive.
        case parentThreadID, contextNotice, demoID, hasQueuedMessages, hasDraftAttachments
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        draft = try values.decodeIfPresent(String.self, forKey: .draft) ?? ""
        projectID = try values.decodeIfPresent(UUID.self, forKey: .projectID)
        workingDirectory = try values.decodeIfPresent(String.self, forKey: .workingDirectory)
        skillIDs = try values.decodeIfPresent([String].self, forKey: .skillIDs) ?? []
        systemPrompt = try values.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        pinnedAt = try values.decodeIfPresent(Date.self, forKey: .pinnedAt)
        archived = try values.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        if try values.decodeIfPresent(Date.self, forKey: .deletedAt) != nil { archived = true }
        parentThreadID = try values.decodeIfPresent(String.self, forKey: .parentThreadID)
        contextNotice = try values.decodeIfPresent(String.self, forKey: .contextNotice)
        demoID = try values.decodeIfPresent(String.self, forKey: .demoID)
        hasQueuedMessages = try values.decodeIfPresent(Bool.self, forKey: .hasQueuedMessages)
        hasDraftAttachments = try values.decodeIfPresent(Bool.self, forKey: .hasDraftAttachments)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(draft, forKey: .draft)
        try values.encodeIfPresent(projectID, forKey: .projectID)
        try values.encodeIfPresent(workingDirectory, forKey: .workingDirectory)
        try values.encode(skillIDs, forKey: .skillIDs)
        try values.encode(systemPrompt, forKey: .systemPrompt)
        try values.encodeIfPresent(pinnedAt, forKey: .pinnedAt)
        try values.encode(archived, forKey: .archived)
        try values.encodeIfPresent(parentThreadID, forKey: .parentThreadID)
        try values.encodeIfPresent(contextNotice, forKey: .contextNotice)
        try values.encodeIfPresent(demoID, forKey: .demoID)
        try values.encodeIfPresent(hasQueuedMessages, forKey: .hasQueuedMessages)
        try values.encodeIfPresent(hasDraftAttachments, forKey: .hasDraftAttachments)
    }
}
