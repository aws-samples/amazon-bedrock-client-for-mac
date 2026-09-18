import Foundation

struct AppPreferences: Codable, Equatable, Sendable {
    var compactSidebar = false
    var showTimestamps = false
    var restoreLastThread = true
    var sendWithCommandReturn = false
    var promptCaching = true
    var contextCharacterBudget = 180_000
    var automaticTitles = false
    // nil retains automatic selection when loading preferences from older versions.
    var titleGenerationModelID: String?
    var thinkingSummaries = false
    var toolProfile: ToolProfile = .all
    var customTools: Set<BuiltInTool> = []
    var disabledTools: Set<BuiltInTool> = []
    var approvalMode: ToolApprovalMode = .allowEnabled
    var toolDefaultsVersion: Int? = 1
    var workingDirectory: String?
    var restrictFileAccess: Bool?
    var allowedFileDirectories: [String]?
    var commandTimeout = 30
    var toolOutputLimit = 32_000
    var allowedWebDomains = ""
    var automationsEnabled = true
    var notificationsEnabled = false
    var notificationSound = false
    var notifyInBackgroundOnly = true
    var showMenuBarItem = false
    var defaultProjectID: UUID?
    var lastThreadID: String?
    // Optional so workspaces from earlier versions keep every section open.
    var collapsedSidebarSections: Set<String>?
    func isSidebarSectionExpanded(_ section: String) -> Bool {
        collapsedSidebarSections?.contains(section) != true
    }
    mutating func setSidebarSection(_ section: String, expanded: Bool) {
        var collapsed = collapsedSidebarSections ?? []
        if expanded { collapsed.remove(section) } else { collapsed.insert(section) }
        collapsedSidebarSections = collapsed.isEmpty ? nil : collapsed
    }
    var enabledTools: Set<BuiltInTool> {
        (toolProfile == .custom ? customTools : toolProfile.tools).subtracting(disabledTools)
    }
    var validContextBudget: Int { min(1_000_000, max(8_000, contextCharacterBudget)) }
    var validCommandTimeout: Int { min(600, max(1, commandTimeout)) }
    var validToolOutputLimit: Int { min(256_000, max(1_024, toolOutputLimit)) }

    mutating func migrateToolDefaults() {
        guard toolDefaultsVersion == nil else { return }
        // Replace the old untouched default, retaining deliberately configured profiles.
        if toolProfile == .chat && customTools.isEmpty && disabledTools.isEmpty && approvalMode == .askForChanges {
            toolProfile = .all
            approvalMode = .allowEnabled
        }
        toolDefaultsVersion = 1
    }
}
