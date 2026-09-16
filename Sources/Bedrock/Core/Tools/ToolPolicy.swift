import Foundation

enum ToolProfile: String, CaseIterable, Codable, Sendable {
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
    var tools: Set<BuiltInTool> {
        switch self {
        case .all: Set(BuiltInTool.allCases)
        case .chat: []
        case .readOnly: [.listFiles, .readFile, .searchFiles, .gitStatus, .listSkills, .readSkill, .pollProcess]
        case .developer: Set(BuiltInTool.allCases.filter { !$0.needsNetwork && $0 != .sessionStatus })
        case .custom: []
        }
    }
}

enum BuiltInTool: String, CaseIterable, Codable, Identifiable, Sendable {
    case readFile = "local_read_file"
    case listFiles = "local_list_files"
    case searchFiles = "local_search_files"
    case writeFile = "local_write_file"
    case runCommand = "local_run_command"
    case startProcess = "local_start_process"
    case pollProcess = "local_poll_process"
    case stopProcess = "local_stop_process"
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
        case .startProcess: "Start background commands"
        case .pollProcess: "Read background output"
        case .stopProcess: "Stop background commands"
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
        case .runCommand, .startProcess, .pollProcess, .stopProcess: "terminal"
        case .gitStatus: "point.3.connected.trianglepath.dotted"
        case .fetchURL: "globe"
        case .openURL: "arrow.up.forward.app"
        case .sessionStatus: "info.circle"
        case .listSkills, .readSkill: "sparkles"
        }
    }
    var needsNetwork: Bool { self == .fetchURL || self == .openURL }
    var changesState: Bool {
        [.writeFile, .runCommand, .startProcess, .stopProcess, .openURL].contains(self)
    }
    var description: String {
        switch self {
        case .readFile: "Read a local UTF-8 file. Accepts absolute paths, ~/ paths, or paths relative to the working directory."
        case .listFiles: "List a local directory. Hidden files and recursive listing are optional."
        case .searchFiles: "Search UTF-8 files in a local directory for a literal string and return matching lines."
        case .writeFile: "Create or replace a local UTF-8 file using an absolute, ~/, or relative path."
        case .runCommand: "Run a shell command on this Mac, with an optional working directory and a timeout."
        case .startProcess: "Start a shell command without waiting for completion. Returns a process ID for local_poll_process and local_stop_process. The Settings command timeout still applies; processes stop when the user stops the response or quits the app."
        case .pollProcess: "Read incremental output and status for a background command started in this chat. Pass the previous nextOffset as offset to avoid repeated output."
        case .stopProcess: "Stop a background command and its child processes by ID. Only processes started in this chat are eligible."
        case .gitStatus: "Inspect local Git status, diff, or log. Does not modify the repository."
        case .fetchURL: "Fetch an HTTP(S) page directly from this Mac with a bounded response."
        case .openURL: "Open an HTTP(S) URL in the user's default browser."
        case .sessionStatus: "Report the current model, local time, working directory, and enabled tools when requested."
        case .listSkills: "List enabled local skills with their exact IDs, English names, and descriptions."
        case .readSkill: "Load an enabled local skill's instructions by ID. Use its reference directory for related files and scripts."
        }
    }
}

enum ToolApprovalMode: String, CaseIterable, Codable, Sendable {
    case askForChanges, askAlways, allowEnabled
    var title: String {
        switch self {
        case .askForChanges: "Ask before changes"
        case .askAlways: "Ask for every tool"
        case .allowEnabled: "Allow enabled tools"
        }
    }
    func requiresApproval(tool: BuiltInTool?) -> Bool {
        switch self {
        case .askAlways: true
        case .askForChanges: tool.map { $0.changesState || $0.needsNetwork } ?? true
        case .allowEnabled: false
        }
    }
}
