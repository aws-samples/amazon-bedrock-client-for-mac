import Foundation

enum WorkbenchDestination: String, CaseIterable, Identifiable, Codable, Sendable {
    case chats, demos, automations, activity
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chats: "Threads"
        case .demos: "Demo library"
        case .automations: "Automations"
        case .activity: "Activity"
        }
    }
    var symbol: String {
        switch self {
        case .chats: "bubble.left.and.bubble.right"
        case .demos: "square.grid.2x2"
        case .automations: "clock.arrow.circlepath"
        case .activity: "chart.bar.xaxis"
        }
    }
}

struct LocalProject: Codable, Identifiable, Equatable, Sendable {
    // Decode old workspaces without losing their data. No longer used for tool access.
    var id = UUID()
    var name: String
    var path: String
    var addedAt = Date()
    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

struct ThreadWorkspace: Codable, Equatable, Sendable {
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

enum LocalToolProfile: String, CaseIterable, Codable, Sendable {
    case all, chat, readOnly, developer, custom
    var title: String {
        switch self {
        case .all: "All tools"
        case .chat: "Chat only"
        case .readOnly: "Read only"
        case .developer: "Developer"
        case .custom: "Custom"
        }
    }
    var tools: Set<LocalToolKind> {
        switch self {
        case .all: Set(LocalToolKind.allCases)
        case .chat: []
        case .readOnly: [.listFiles, .readFile, .searchFiles, .gitStatus, .listSkills, .readSkill]
        case .developer: Set(LocalToolKind.allCases.filter { !$0.needsNetwork && $0 != .sessionStatus })
        case .custom: []
        }
    }
}

enum LocalToolKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case readFile = "local_read_file"
    case listFiles = "local_list_files"
    case searchFiles = "local_search_files"
    case writeFile = "local_write_file"
    case runCommand = "local_run_command"
    case gitStatus = "local_git"
    case fetchURL = "local_fetch_url"
    case openURL = "local_open_url"
    case sessionStatus = "local_session_status"
    case listSkills = "local_list_skills"
    case readSkill = "local_read_skill"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .readFile: "Read files"
        case .listFiles: "List files"
        case .searchFiles: "Search files"
        case .writeFile: "Write files"
        case .runCommand: "Run shell commands"
        case .gitStatus: "Inspect Git"
        case .fetchURL: "Fetch web pages"
        case .openURL: "Open URLs"
        case .sessionStatus: "Session status"
        case .listSkills: "List skills"
        case .readSkill: "Load skills"
        }
    }
    var symbol: String {
        switch self {
        case .readFile: "doc.text"
        case .listFiles: "folder"
        case .searchFiles: "doc.text.magnifyingglass"
        case .writeFile: "square.and.pencil"
        case .runCommand: "terminal"
        case .gitStatus: "point.3.connected.trianglepath.dotted"
        case .fetchURL: "globe"
        case .openURL: "arrow.up.forward.app"
        case .sessionStatus: "info.circle"
        case .listSkills, .readSkill: "sparkles"
        }
    }
    var needsNetwork: Bool { self == .fetchURL || self == .openURL }
    var changesState: Bool { self == .writeFile || self == .runCommand || self == .openURL }
    var description: String {
        switch self {
        case .readFile: "Read a local UTF-8 file. Accepts absolute paths, ~/ paths, or paths relative to the working directory."
        case .listFiles: "List a local directory. Hidden files and recursive listing are optional."
        case .searchFiles: "Search UTF-8 files in a local directory for a literal string and return matching lines."
        case .writeFile: "Create or replace a local UTF-8 file using an absolute, ~/, or relative path."
        case .runCommand: "Run a shell command on this Mac, with an optional working directory and a timeout."
        case .gitStatus: "Inspect local Git status, diff, or log. Does not modify the repository."
        case .fetchURL: "Fetch an HTTP(S) page directly from this Mac with a bounded response."
        case .openURL: "Open an HTTP(S) URL in the user's default browser."
        case .sessionStatus: "Report the current model, local time, working directory, and enabled tools when requested."
        case .listSkills: "List enabled local skills with their exact IDs, English names, and descriptions."
        case .readSkill: "Load an enabled local skill's instructions by ID. Use its reference directory for related files and scripts."
        }
    }
}

enum LocalApprovalMode: String, CaseIterable, Codable, Sendable {
    case askForChanges, askAlways, allowEnabled
    var title: String {
        switch self {
        case .askForChanges: "Ask before changes"
        case .askAlways: "Ask for every tool"
        case .allowEnabled: "Allow enabled tools"
        }
    }
    func requiresApproval(tool: LocalToolKind?) -> Bool {
        switch self {
        case .askAlways: true
        case .askForChanges: tool.map { $0.changesState || $0.needsNetwork } ?? true
        case .allowEnabled: false
        }
    }
}

struct WorkbenchPreferences: Codable, Equatable, Sendable {
    var compactSidebar = false
    var showTimestamps = false
    var restoreLastThread = true
    var sendWithCommandReturn = false
    var promptCaching = true
    var contextCharacterBudget = 180_000
    var automaticTitles = false
    var thinkingSummaries = false
    var toolProfile: LocalToolProfile = .all
    var customTools: Set<LocalToolKind> = []
    var disabledTools: Set<LocalToolKind> = []
    var approvalMode: LocalApprovalMode = .allowEnabled
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
    var enabledTools: Set<LocalToolKind> {
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

enum LocalRunStatus: String, CaseIterable, Codable, Sendable {
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

struct LocalRunRecord: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var threadID: String
    var modelID: String
    var title: String
    var startedAt = Date()
    var finishedAt: Date?
    var firstTokenAt: Date?
    var status: LocalRunStatus = .running
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

enum AutomationCadence: String, CaseIterable, Codable, Sendable {
    case once, interval, daily
    var title: String {
        switch self {
        case .once: "Once"
        case .interval: "Every interval"
        case .daily: "Daily"
        }
    }
}

struct LocalAutomation: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var prompt: String
    var modelID: String
    var projectID: UUID?
    var workingDirectory: String?
    var skillIDs: [String] = []
    var cadence: AutomationCadence = .daily
    var scheduledAt = Date().addingTimeInterval(3600)
    var intervalMinutes = 60
    var maximumRuntime = 300
    var enabled = false
    var nextRunAt: Date?
    var lastRunAt: Date?
    var lastThreadID: String?
    var lastStatus: LocalRunStatus?

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        switch cadence {
        case .once: return scheduledAt > date ? scheduledAt : nil
        case .interval: return date.addingTimeInterval(TimeInterval(max(1, intervalMinutes)) * 60)
        case .daily:
            let components = calendar.dateComponents([.hour, .minute], from: scheduledAt)
            return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
        }
    }
    var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give this automation a name." }
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a prompt to run." }
        if modelID.isEmpty { return "Choose a Bedrock model." }
        if !(1...43_200).contains(intervalMinutes) { return "Use an interval between 1 minute and 30 days." }
        if !(10...3_600).contains(maximumRuntime) { return "Use a runtime limit between 10 seconds and 1 hour." }
        return nil
    }
}

struct WorkbenchState: Codable, Sendable {
    var version = 1
    var projects: [LocalProject] = []
    var threads: [String: ThreadWorkspace] = [:]
    var preferences = WorkbenchPreferences()
    var skillEnabled: [String: Bool] = [:]
    var customDemos: [DemoPreset] = []
    var automations: [LocalAutomation] = []
    var runs: [LocalRunRecord] = []

    mutating func migrateLocalAccess() {
        preferences.migrateToolDefaults()
        // Retain old serialized project fields for rollback compatibility. Only
        // their working directory survives in active conversations and schedules.
        for id in Array(threads.keys) {
            if threads[id]?.workingDirectory == nil,
               let projectID = threads[id]?.projectID,
               let path = projects.first(where: { $0.id == projectID })?.path {
                threads[id]?.workingDirectory = path
            }
        }
        for index in automations.indices {
            if automations[index].workingDirectory == nil,
               let projectID = automations[index].projectID,
               let path = projects.first(where: { $0.id == projectID })?.path {
                automations[index].workingDirectory = path
            }
        }
    }
}

enum LocalWorkbenchError: LocalizedError, Equatable {
    case invalid(String)
    case outsideProject
    case tooLarge(Int)
    case unavailable(String)
    var errorDescription: String? {
        switch self {
        case .invalid(let message), .unavailable(let message): message
        case .outsideProject: "This path is outside the folders allowed in Settings → Tools & MCP."
        case .tooLarge(let limit): "This file exceeds the \(limit.formatted()) byte limit."
        }
    }
}

struct LocalJSONFile<Value: Codable> {
    let url: URL
    func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Value.self, from: data)
    }
    func save(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
