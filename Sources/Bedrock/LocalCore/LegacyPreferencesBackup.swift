import Foundation

enum LegacyPreferencesBackup {
    // Keep the released keys, including the historical defaultDirector spelling.
    // Credentials have their own Keychain migration and never enter this file.
    static let keys = [
        "appearance", "adjustedFontSize", "sidebarIconSize", "allowWallpaperTinting",
        "enableModelThinking", "showUsageInfo", "systemPrompt", "defaultDirector", "defaultModelId",
        "maxToolUseTurns", "enableQuickAccess", "hotkeyModifiers", "hotkeyKeyCode",
        "selectedRegion", "selectedProfile", "endpoint", "runtimeEndpoint", "favoriteModelIds",
        "modelInferenceConfigs", "novaCanvasConfig", "titanImageConfig", "stabilityAIConfig",
        "stabilityAIServicesConfig", "novaReelConfig", "allowImagePasting", "treatLargeTextAsFile",
        "checkForUpdates", "enableDebugLog", "mcpEnabled", "LastRunAppVersion"
    ]

    static func preserve(_ defaults: UserDefaults, at url: URL) throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: url.path) else { return }
        var values: [String: Any] = [:]
        for key in keys {
            if let value = defaults.object(forKey: key) { values[key] = value }
        }
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = url.deletingLastPathComponent().appendingPathComponent(".preferences-\(UUID()).tmp")
        defer { try? manager.removeItem(at: staging) }
        guard manager.createFile(atPath: staging.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw LocalWorkbenchError.unavailable("Could not preserve the previous app settings.")
        }
        try manager.moveItem(at: staging, to: url)
    }
}
