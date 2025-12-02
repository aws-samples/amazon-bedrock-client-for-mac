//
//  SettingManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import Combine
import Logging
import SwiftUI
import Carbon

extension Notification.Name {
    static let awsCredentialsChanged = Notification.Name("awsCredentialsChanged")
    static let mcpServerConnected = Notification.Name("mcpServerConnected")
}

@MainActor
class SettingManager: ObservableObject {
    static let shared = SettingManager()
    private var logger = Logger(label: "SettingManager")

    private var fileMonitors: [String: DispatchSourceFileSystemObject] = [:]
    private let monitoringQueue = DispatchQueue(
        label: "com.amazonbedrock.fileMonitoring", attributes: .concurrent)
    
    @AppStorage("checkForUpdates") var checkForUpdates: Bool = true
    @AppStorage("appearance") var appearance: String = "auto"
    @AppStorage("sidebarIconSize") var sidebarIconSize: String = "Medium"
    @AppStorage("allowWallpaperTinting") var allowWallpaperTinting: Bool = false
    @AppStorage("enableDebugLog") var enableDebugLog: Bool = true
    @AppStorage("enableModelThinking") var enableModelThinking: Bool = true
    @AppStorage("showUsageInfo") var showUsageInfo: Bool = true
    @AppStorage("systemPrompt") var systemPrompt: String = ""
    @AppStorage("defaultDirector") var defaultDirectory: String = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Amazon Bedrock Client"
    ).path
    @AppStorage("defaultModelId") var defaultModelId: String = ""
    @AppStorage("maxToolUseTurns") var maxToolUseTurns: Int = 10
    @AppStorage("serverPort") var serverPort: Int = 8080
    @AppStorage("enableLocalServer") var enableLocalServer: Bool = true
    
    // Quick Access Hotkey Settings
    @AppStorage("enableQuickAccess") var enableQuickAccess: Bool = true
    
    var hotkeyModifiers: UInt32 {
        get {
            let stored = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
            return stored == 0 ? UInt32(optionKey) : UInt32(stored) // Default to Option key
        }
        set {
            UserDefaults.standard.set(Int(newValue), forKey: "hotkeyModifiers")
        }
    }
    
    var hotkeyKeyCode: UInt32 {
        get {
            let stored = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
            return stored == 0 ? 49 : UInt32(stored) // Default to Space key (49)
        }
        set {
            UserDefaults.standard.set(Int(newValue), forKey: "hotkeyKeyCode")
        }
    }

    // TODO: these should be converted to AppStorage, but are used from BedrockClient with Combine, which does not support AppStorage.
    @Published var selectedRegion: AWSRegion { didSet { saveSettings() } }
    @Published var selectedProfile: String { didSet { saveSettings() } }
    @Published var endpoint: String { didSet { saveSettings() } }
    @Published var runtimeEndpoint: String { didSet { saveSettings() } }

    @Published var isSSOLoggedIn: Bool = false
    @Published var profiles: [ProfileInfo] = []
    //    @Published var ssoTokenInfo: SSOTokenInfo? {
    //        didSet {
    //            if let ssoTokenInfo = ssoTokenInfo {
    //                if let data = try? JSONEncoder().encode(ssoTokenInfo) {
    //                    UserDefaults.standard.set(data, forKey: "ssoTokenInfo")
    //                }
    //            } else {
    //                UserDefaults.standard.removeObject(forKey: "ssoTokenInfo")
    //            }
    //        }
    //    }
    @Published var virtualProfile: AWSProfile?
    @Published var availableModels: [ChatModel] = []
    @AppStorage("allowImagePasting") var allowImagePasting: Bool = true
    @AppStorage("treatLargeTextAsFile") var treatLargeTextAsFile: Bool = true
    @Published var favoriteModelIds: [String] = [] {
        didSet {
            saveFavoriteModels()
        }
    }
    @Published var modelInferenceConfigs: [String: ModelInferenceConfig] = [:] {
        didSet {
            saveModelInferenceConfigs()
        }
    }

    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        self.selectedRegion = UserDefaults.standard.string(forKey: "selectedRegion").flatMap {
            AWSRegion(rawValue: $0)
        } ?? .usEast1
        self.selectedProfile = UserDefaults.standard.string(forKey: "selectedProfile") ?? "default"
        self.endpoint = UserDefaults.standard.string(forKey: "endpoint") ?? ""
        self.runtimeEndpoint = UserDefaults.standard.string(forKey: "runtimeEndpoint") ?? ""
        
        // Set default hotkey values if not already set
        if UserDefaults.standard.object(forKey: "hotkeyModifiers") == nil {
            UserDefaults.standard.set(Int(optionKey), forKey: "hotkeyModifiers")
            logger.info("Set default hotkey modifiers: \(optionKey)")
        }
        if UserDefaults.standard.object(forKey: "hotkeyKeyCode") == nil {
            UserDefaults.standard.set(49, forKey: "hotkeyKeyCode") // Space key
            logger.info("Set default hotkey keyCode: 49 (Space)")
        }
        
        logger.info("Current hotkey settings - modifiers: \(hotkeyModifiers), keyCode: \(hotkeyKeyCode)")
        
        // Initialize HotkeyManager after setting defaults
        DispatchQueue.main.async {
            _ = HotkeyManager.shared
        }

        self.profiles = Self.readAWSProfiles()
        logger.info("Loaded \(self.profiles.count) AWS profiles: \(self.profiles.map { $0.name }.joined(separator: ", "))")
        
        //        if let data = UserDefaults.standard.data(forKey: "ssoTokenInfo"),
        //           let tokenInfo = try? JSONDecoder().decode(SSOTokenInfo.self, from: data) {
        //            self.ssoTokenInfo = tokenInfo
        //        } else {
        //            self.ssoTokenInfo = nil
        //        }
        //
        
        if let data = UserDefaults.standard.data(forKey: "favoriteModelIds"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.favoriteModelIds = decoded
        } else {
            self.favoriteModelIds = []
        }
        
        // Load model inference configs
        if let data = UserDefaults.standard.data(forKey: "modelInferenceConfigs"),
           let decoded = try? JSONDecoder().decode([String: ModelInferenceConfig].self, from: data) {
            self.modelInferenceConfigs = decoded
        } else {
            self.modelInferenceConfigs = [:]
        }
        setupFileMonitoring()
        logger.info("Settings loaded: \(selectedRegion.rawValue), \(selectedProfile)")
    }
    
     private func saveFavoriteModels() {
         if let encoded = try? JSONEncoder().encode(favoriteModelIds) {
             UserDefaults.standard.set(encoded, forKey: "favoriteModelIds")
         }
         logger.info("Saved favorite models: \(favoriteModelIds)")
     }
    
    private func saveSettings() {
        UserDefaults.standard.set(selectedRegion.rawValue, forKey: "selectedRegion")
        UserDefaults.standard.set(selectedProfile, forKey: "selectedProfile")
        UserDefaults.standard.set(endpoint, forKey: "endpoint")
        UserDefaults.standard.set(runtimeEndpoint, forKey: "runtimeEndpoint")
        
        logger.info("Settings saved: \(selectedRegion.rawValue), \(selectedProfile)")
    }
    
    func addModelToFavorites(_ modelId: String) {
        if !favoriteModelIds.contains(modelId) {
            favoriteModelIds.append(modelId)
        }
    }
    
    func removeModelFromFavorites(_ modelId: String) {
        favoriteModelIds.removeAll { $0 == modelId }
    }
    
    func isModelFavorite(_ modelId: String) -> Bool {
        return favoriteModelIds.contains(modelId)
    }
    
    func toggleFavoriteModel(_ modelId: String) {
        if isModelFavorite(modelId) {
            removeModelFromFavorites(modelId)
        } else {
            addModelToFavorites(modelId)
        }
    }
    
    private func setupFileMonitoring() {
        let credentialsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            ".aws/credentials")
        let configURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            ".aws/config")
        
        monitorFileChanges(at: credentialsURL)
        monitorFileChanges(at: configURL)
    }
    
    private func monitorFileChanges(at url: URL) {
        stopMonitoring(for: url)
        
        // Start monitoring on background queue
        Task.detached { [weak self] in
            await self?.startMonitoringAsync(for: url)
        }
    }
    
    nonisolated private func startMonitoringAsync(for url: URL) async {
        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            await MainActor.run {
                SettingManager.shared.logger.error("Failed to open file descriptor for \(url.path)")
            }
            return
        }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue(label: "com.aws.bedrock.filemonitor.\(url.lastPathComponent)")
        )
        
        // Capture url path as value type
        let urlPath = url.path
        let urlLastComponent = url.lastPathComponent
        
        source.setEventHandler {
            Task { @MainActor in
                let manager = SettingManager.shared
                manager.logger.info("File change detected at \(urlPath)")
                
                if urlLastComponent == "credentials" || urlLastComponent == "config" {
                    manager.refreshAWSProfiles()
                    NotificationCenter.default.post(name: .awsCredentialsChanged, object: nil)
                }
                
                // Re-establish monitoring for the changed file
                manager.monitorFileChanges(at: url)
            }
        }
        
        source.setCancelHandler {
            close(fileDescriptor)
        }
        
        source.resume()
        
        await MainActor.run {
            SettingManager.shared.fileMonitors[urlPath] = source
            SettingManager.shared.logger.info("File monitoring started for \(urlPath)")
        }
    }
    
    private func stopMonitoring(for url: URL) {
        if let existingSource = fileMonitors.removeValue(forKey: url.path) {
            existingSource.cancel()
            logger.info("File monitoring stopped for \(url.path)")
        }
    }
    
    
    private func refreshAWSProfiles() {
        // Read profiles on background thread, then update on main
        Task {
            let newProfiles = await Task.detached {
                Self.readAWSProfilesSync()
            }.value
            
            // Already on MainActor since SettingManager is @MainActor
            self.profiles = newProfiles
            self.logger.info("AWS profiles refreshed: \(newProfiles.count) profiles")
        }
    }
    
    /// Reads AWS profiles from ~/.aws/credentials and ~/.aws/config
    /// This is a simplified version that just reads profile names - AWS SDK handles the actual credential loading
    static func readAWSProfiles() -> [ProfileInfo] {
        return readAWSProfilesSync()
    }
    
    /// Non-isolated version for background thread access
    nonisolated static func readAWSProfilesSync() -> [ProfileInfo] {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        var profiles: [ProfileInfo] = []
        let logger = Logger(label: "SettingManager.readAWSProfilesSync")
        
        // Read from ~/.aws/credentials
        if let credentialsProfiles = parseProfilesFromFile("\(homePath)/.aws/credentials", isConfig: false) {
            logger.debug("Loaded \(credentialsProfiles.count) profiles from credentials file")
            for p in credentialsProfiles {
                logger.debug("  - \(p.name): \(p.type)")
            }
            profiles.append(contentsOf: credentialsProfiles)
        }
        
        // Read from ~/.aws/config
        if let configProfiles = parseProfilesFromFile("\(homePath)/.aws/config", isConfig: true) {
            logger.debug("Loaded \(configProfiles.count) profiles from config file")
            for p in configProfiles {
                logger.debug("  - \(p.name): \(p.type)")
            }
            profiles.append(contentsOf: configProfiles)
        }
        
        // Merge by name, preferring SSO/credential_process types from config
        let merged = profiles.mergedByName()
        logger.info("Final merged profiles: \(merged.map { "\($0.name)(\($0.type))" }.joined(separator: ", "))")
        return merged
    }
    
    /// Parse profile names from an AWS config/credentials file
    nonisolated private static func parseProfilesFromFile(_ path: String, isConfig: Bool) -> [ProfileInfo]? {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        
        var profiles: [ProfileInfo] = []
        var currentProfile: String?
        var currentType: ProfileInfo.ProfileType = .credentials
        
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check for profile header
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                // Save previous profile
                if let profile = currentProfile {
                    profiles.append(ProfileInfo(name: profile, type: currentType))
                }
                
                // Parse new profile name
                var profileName = String(trimmed.dropFirst().dropLast())
                
                // In config file, profiles are prefixed with "profile "
                if isConfig && profileName.hasPrefix("profile ") {
                    profileName = String(profileName.dropFirst(8))
                    currentType = .credentials // Default, will be updated below
                } else if isConfig && profileName == "default" {
                    // default profile in config doesn't have "profile " prefix
                    currentType = .credentials
                } else if !isConfig {
                    currentType = .credentials
                } else {
                    // Skip non-profile sections in config (like [sso-session ...])
                    currentProfile = nil
                    continue
                }
                
                currentProfile = profileName
                currentType = .credentials
            }
            // Detect profile type
            else if currentProfile != nil {
                if trimmed.hasPrefix("sso_") || trimmed.hasPrefix("sso_session") {
                    currentType = .sso
                } else if trimmed.hasPrefix("credential_process") {
                    currentType = .credentialProcess
                }
            }
        }
        
        // Don't forget the last profile
        if let profile = currentProfile {
            profiles.append(ProfileInfo(name: profile, type: currentType))
        }
        
        return profiles
    }
    
    // MARK: - Model Inference Configuration Methods
    
    func getInferenceConfig(for modelId: String) -> ModelInferenceConfig {
        // Return saved config if exists and override is enabled, otherwise return default
        if let savedConfig = modelInferenceConfigs[modelId], savedConfig.overrideDefault {
            return savedConfig
        } else {
            // Return default config based on model range
            let range = ModelInferenceRange.getRangeForModel(modelId)
            return ModelInferenceConfig(
                maxTokens: range.defaultMaxTokens,
                temperature: range.defaultTemperature,
                topP: range.defaultTopP,
                thinkingBudget: range.defaultThinkingBudget,
                reasoningEffort: range.defaultReasoningEffort,
                overrideDefault: false
            )
        }
    }
    
    func setInferenceConfig(_ config: ModelInferenceConfig, for modelId: String) {
        modelInferenceConfigs[modelId] = config
        logger.info("Updated inference config for model \(modelId): override=\(config.overrideDefault)")
    }
    
    func resetInferenceConfig(for modelId: String) {
        modelInferenceConfigs.removeValue(forKey: modelId)
        logger.info("Reset inference config for model \(modelId)")
    }
    
    private func saveModelInferenceConfigs() {
        if let encoded = try? JSONEncoder().encode(modelInferenceConfigs) {
            UserDefaults.standard.set(encoded, forKey: "modelInferenceConfigs")
        }
        logger.debug("Saved model inference configs")
    }

    deinit {
        for (_, monitor) in fileMonitors {
            monitor.cancel()
        }
    }
}

struct ProfileInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let type: ProfileType
    
    enum ProfileType {
        case credentials
        case sso
        case credentialProcess
    }
    
    // Hash and equality based on name only (for deduplication)
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    
    static func == (lhs: ProfileInfo, rhs: ProfileInfo) -> Bool {
        return lhs.name == rhs.name
    }
}

extension Array where Element == ProfileInfo {
    /// Merges profiles by name, preferring config file types (SSO, credential_process) over credentials
    func mergedByName() -> [ProfileInfo] {
        var profileMap: [String: ProfileInfo] = [:]
        
        for profile in self {
            if let existing = profileMap[profile.name] {
                // Prefer SSO or credentialProcess over plain credentials
                if existing.type == .credentials && profile.type != .credentials {
                    profileMap[profile.name] = profile
                }
                // Keep existing if it's already SSO or credentialProcess
            } else {
                profileMap[profile.name] = profile
            }
        }
        
        return Array(profileMap.values).sorted { $0.name < $1.name }
    }
}

struct AWSProfile {
    var name: String
    var ssoStartURL: String
    var ssoRegion: String
    var ssoAccountID: String
    var ssoRoleName: String
    var region: String
}
