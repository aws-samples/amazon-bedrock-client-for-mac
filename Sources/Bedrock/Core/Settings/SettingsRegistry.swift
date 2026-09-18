import Foundation

enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general, appearance, connection, models, skills, tools, shortcuts, storage, advanced
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .connection: "AWS connection"
        case .models: "Models"
        case .skills: "Skills"
        case .tools: "Tools & MCP"
        case .shortcuts: "Keyboard"
        case .storage: "Data & history"
        case .advanced: "Advanced"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .connection: "network"
        case .models: "cpu"
        case .skills: "sparkles"
        case .tools: "wrench.and.screwdriver"
        case .shortcuts: "keyboard"
        case .storage: "internaldrive"
        case .advanced: "slider.horizontal.3"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Startup, menu bar, and notifications."
        case .appearance: "Make your conversations comfortable to read."
        case .connection: "Connect directly with your AWS credentials."
        case .models: "Choose a default model and response preferences."
        case .skills: "Reusable instructions, stored on this Mac."
        case .tools: "Connect tools and control when they can run."
        case .shortcuts: "Shortcuts, dictation, and message input."
        case .storage: "Manage local conversations and storage."
        case .advanced: "Diagnostics and additional options."
        }
    }
}

struct SettingsItem: Identifiable, Sendable {
    var id: String
    var pane: SettingsPane
    var title: String
    var detail: String
    var keywords: String
    func matches(_ query: String) -> Bool {
        "\(title) \(detail) \(keywords) \(pane.title)".localizedStandardContains(query)
    }

    static let all: [SettingsItem] = [
        .init(id: "updates", pane: .general, title: "Check for updates", detail: "Check GitHub for new app releases.", keywords: "version release"),
        .init(id: "login", pane: .general, title: "Launch at login", detail: "Open Bedrock when you sign in to this Mac.", keywords: "startup"),
        .init(id: "menubar", pane: .general, title: "Show menu bar item", detail: "Keep Quick Access and your threads within reach.", keywords: "status"),
        .init(id: "restore", pane: .general, title: "Restore last thread", detail: "Reopen the thread you were using.", keywords: "startup session"),
        .init(id: "automations", pane: .general, title: "Run local automations", detail: "Scheduled prompts run while this app is open.", keywords: "schedule pause heartbeat cron"),
        .init(id: "appearance", pane: .appearance, title: "Appearance", detail: "Follow macOS or choose light or dark.", keywords: "theme system"),
        .init(id: "textSize", pane: .appearance, title: "Text size", detail: "Adjust conversation text.", keywords: "font zoom"),
        .init(id: "compact", pane: .appearance, title: "Compact sidebar", detail: "Use smaller spacing in the thread list.", keywords: "density"),
        .init(id: "timestamps", pane: .appearance, title: "Show timestamps", detail: "Display when messages were sent.", keywords: "time date"),
        .init(id: "usage", pane: .appearance, title: "Show usage information", detail: "Show actual tokens and response timing.", keywords: "performance cache"),
        .init(id: "region", pane: .connection, title: "AWS region", detail: "Region used for direct Bedrock requests.", keywords: "endpoint location"),
        .init(id: "profile", pane: .connection, title: "AWS profile", detail: "Use credentials or SSO from your local AWS configuration.", keywords: "credentials login sso"),
        .init(id: "apiKey", pane: .connection, title: "Bedrock API key", detail: "Optional Mantle API key stored in macOS Keychain.", keywords: "bearer token password"),
        .init(id: "endpoint", pane: .connection, title: "Bedrock endpoint", detail: "Optional custom control-plane endpoint.", keywords: "url proxy"),
        .init(id: "runtimeEndpoint", pane: .connection, title: "Runtime endpoint", detail: "Optional custom inference endpoint.", keywords: "url proxy"),
        .init(id: "connectionTest", pane: .connection, title: "Test connection", detail: "Refresh the model catalog using this connection.", keywords: "refresh models credentials"),
        .init(id: "defaultModel", pane: .models, title: "Default model", detail: "Model selected for new threads.", keywords: "provider claude nova favorite"),
        .init(id: "inferenceProfiles", pane: .models, title: "Inference profiles", detail: "Add a profile directly when your account cannot list all models. Profiles are saved for this AWS connection.", keywords: "application arn billing cost access model"),
        .init(id: "systemPrompt", pane: .models, title: "System prompt", detail: "Instructions applied to model requests.", keywords: "template persona saved"),
        .init(id: "thinking", pane: .models, title: "Model thinking", detail: "Enable reasoning for compatible models.", keywords: "effort budget reasoning"),
        .init(id: "caching", pane: .models, title: "Prompt caching", detail: "Reuse eligible prompt prefixes on supported Bedrock models.", keywords: "tokens cost performance"),
        .init(id: "context", pane: .models, title: "Context budget", detail: "Limit request history while keeping the full thread on disk.", keywords: "compaction tokens length"),
        .init(id: "titles", pane: .models, title: "Generate thread titles", detail: "Use an additional model request for automatic titles.", keywords: "rename inference"),
        .init(id: "summaries", pane: .models, title: "Summarize thinking", detail: "Use additional model requests for reasoning summaries.", keywords: "inference"),
        .init(id: "toolProfile", pane: .tools, title: "Local tools", detail: "All tools are available by default. Choose a preset or adjust individual tools below.", keywords: "profile all read developer custom"),
        .init(id: "approval", pane: .tools, title: "Tool approval", detail: "Choose when a tool call needs your confirmation.", keywords: "permission safety allow"),
        .init(id: "fileAccess", pane: .tools, title: "File access", detail: "Applies to built-in file tools. Shell commands and MCP servers use their own access settings.", keywords: "permissions local paths allow restrict folders"),
        .init(id: "workingDirectory", pane: .tools, title: "Working directory", detail: "Starting folder for relative paths and shell commands. Defaults to your home folder.", keywords: "path home local cwd"),
        .init(id: "turns", pane: .tools, title: "Maximum tool turns", detail: "Stop after this many tool cycles.", keywords: "limit agent"),
        .init(id: "timeout", pane: .tools, title: "Command timeout", detail: "Stop shell commands after this many seconds.", keywords: "process runtime"),
        .init(id: "output", pane: .tools, title: "Tool output limit", detail: "Bound the text returned to the model.", keywords: "bytes characters performance"),
        .init(id: "domains", pane: .tools, title: "Allowed web domains", detail: "Optional comma-separated domain allowlist for web tools.", keywords: "browser network fetch internet"),
        .init(id: "mcp", pane: .tools, title: "Model Context Protocol", detail: "Manage your directly connected local or HTTP MCP servers.", keywords: "stdio oauth tools integrations"),
        .init(id: "quickAccess", pane: .shortcuts, title: "Quick Access", detail: "Open the small assistant window from any app.", keywords: "hotkey option space"),
        .init(id: "hotkey", pane: .shortcuts, title: "Quick Access shortcut", detail: "Record a system-wide keyboard shortcut.", keywords: "rebind keybinding"),
        .init(id: "send", pane: .shortcuts, title: "Send message with", detail: "Choose Return or Command+Return.", keywords: "enter newline composer"),
        .init(id: "pasteImages", pane: .shortcuts, title: "Paste images", detail: "Attach images from the clipboard.", keywords: "clipboard attachments"),
        .init(id: "pasteText", pane: .shortcuts, title: "Attach large pasted text", detail: "Keep long clipboard text out of the composer.", keywords: "clipboard file"),
        .init(id: "shortcutReference", pane: .shortcuts, title: "Keyboard shortcuts", detail: "All app commands in one place.", keywords: "palette find navigation"),
        .init(id: "notifications", pane: .general, title: "Desktop notifications", detail: "Notify when a response completes or fails.", keywords: "alerts"),
        .init(id: "sound", pane: .general, title: "Notification sound", detail: "Play the system notification sound.", keywords: "audio"),
        .init(id: "background", pane: .general, title: "Only when in background", detail: "Avoid notifications while using the app.", keywords: "focus quiet"),
        .init(id: "notificationTest", pane: .general, title: "Test notification", detail: "Send a sample desktop notification.", keywords: "permission"),
        .init(id: "dataDirectory", pane: .storage, title: "Data folder", detail: "Conversations and workbench data stay on this Mac.", keywords: "storage reveal finder"),
        .init(id: "skills", pane: .skills, title: "Skills", detail: "Import, edit, enable, and apply local SKILL.md files.", keywords: "plugins extensions instructions"),
        .init(id: "history", pane: .storage, title: "Archive", detail: "Restore or permanently delete archived chats.", keywords: "history archive trash recover restore delete undo"),
        .init(id: "logging", pane: .advanced, title: "Debug logging", detail: "Write diagnostic logs locally. Takes effect on next launch.", keywords: "console debug"),
        .init(id: "logs", pane: .advanced, title: "Open logs folder", detail: "Inspect local diagnostic output.", keywords: "finder console"),
        .init(id: "diagnostics", pane: .advanced, title: "Export diagnostics", detail: "Export app configuration and run counts without credentials or prompts.", keywords: "report debug"),
        .init(id: "about", pane: .advanced, title: "About Bedrock", detail: "Native Swift app. Local storage. Direct AWS connection.", keywords: "version privacy")
    ] + BuiltInTool.allCases.map {
        .init(id: $0.rawValue, pane: .tools, title: $0.title, detail: $0.description, keywords: "tool enable disable")
    }
}
