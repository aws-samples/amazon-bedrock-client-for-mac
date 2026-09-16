//
//  PreferencesStore.swift
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
class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()
    private var logger = Logger(label: "PreferencesStore")

    private var fileMonitors: [String: DispatchSourceFileSystemObject] = [:]
    private let monitoringQueue = DispatchQueue(
        label: "com.amazonbedrock.fileMonitoring", attributes: .concurrent)
    
    @AppStorage("checkForUpdates") var checkForUpdates: Bool = true
    @AppStorage("appearance") var appearance: String = "auto" {
        didSet { applyAppearance() }
    }
    @AppStorage("sidebarIconSize") var sidebarIconSize: String = "Medium"
    @AppStorage("allowWallpaperTinting") var allowWallpaperTinting: Bool = false
    @AppStorage("enableDebugLog") var enableDebugLog: Bool = false
    @AppStorage("enableModelThinking") var enableModelThinking: Bool = true
    @AppStorage("showUsageInfo") var showUsageInfo: Bool = true
    @AppStorage("systemPrompt") var systemPrompt: String = ""
    @AppStorage("defaultDirector") private var savedDefaultDirectory: String = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Amazon Bedrock Client"
    ).path
    var defaultDirectory: String {
        get { ProcessInfo.processInfo.environment["BEDROCK_WORKBENCH_DATA_DIR"] ?? savedDefaultDirectory }
        set { savedDefaultDirectory = newValue }
    }
    @AppStorage("defaultModelId") var defaultModelId: String = ""
    @AppStorage("maxToolUseTurns") var maxToolUseTurns: Int = 10
    // Bedrock API key (Bearer token) for the bedrock-mantle Responses API (OpenAI GPT-5.5/5.4)
    @Published var bedrockApiKey: String = "" {
        didSet {
            guard !loadingCredential else { return }
            do {
                try SecureCredentialStore.save(bedrockApiKey)
                credentialError = nil
            } catch {
                bedrockApiKey = oldValue
                credentialError = "Could not save the API key in Keychain: \(error.localizedDescription)"
            }
        }
    }
    @Published var credentialError: String?
    private var loadingCredential = true
    
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
            guard UserDefaults.standard.object(forKey: "hotkeyKeyCode") != nil else { return 49 }
            return UInt32(UserDefaults.standard.integer(forKey: "hotkeyKeyCode"))
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
            if modelInferenceConfigs != oldValue { saveModelInferenceConfigs() }
        }
    }
    
    // Nova Canvas configuration
    @Published var novaCanvasConfig: NovaCanvasConfig = NovaCanvasConfig.defaultConfig {
        didSet {
            saveNovaCanvasConfig()
        }
    }
    
    // Titan Image configuration
    @Published var titanImageConfig: TitanImageConfig = TitanImageConfig.defaultConfig {
        didSet {
            saveTitanImageConfig()
        }
    }
    
    // Stability AI configuration
    @Published var stabilityAIConfig: StabilityAIConfig = StabilityAIConfig.defaultConfig {
        didSet {
            saveStabilityAIConfig()
        }
    }
    
    // Stability AI Image Services configuration
    @Published var stabilityAIServicesConfig: StabilityAIServicesConfig = StabilityAIServicesConfig.defaultConfig {
        didSet {
            saveStabilityAIServicesConfig()
        }
    }
    
    // Nova Reel video generation configuration
    @Published var novaReelConfig: NovaReelConfig = NovaReelConfig.defaultConfig {
        didSet {
            saveNovaReelConfig()
        }
    }
    @Published var lumaVideoConfig = LumaVideoConfiguration() {
        didSet {
            if let encoded = try? JSONEncoder().encode(lumaVideoConfig) {
                UserDefaults.standard.set(encoded, forKey: "lumaVideoConfig")
            }
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
        do {
            try LegacyPreferencesBackup.preserve(
                UserDefaults.standard,
                at: URL(fileURLWithPath: defaultDirectory).appendingPathComponent("workbench/migration-backups/preferences-v1.plist")
            )
        } catch {
            logger.error("Could not back up previous settings: \(error.localizedDescription)")
        }
        do {
            bedrockApiKey = try SecureCredentialStore.read()
            if let legacy = UserDefaults.standard.string(forKey: "bedrockApiKey"), !legacy.isEmpty {
                if bedrockApiKey.isEmpty {
                    try SecureCredentialStore.save(legacy)
                    bedrockApiKey = legacy
                }
                // Only remove plaintext after Keychain has accepted the credential.
                UserDefaults.standard.removeObject(forKey: "bedrockApiKey")
            }
        } catch {
            credentialError = "Could not access Keychain: \(error.localizedDescription)"
            bedrockApiKey = UserDefaults.standard.string(forKey: "bedrockApiKey") ?? ""
        }
        loadingCredential = false
        
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
        
        // Initialize GlobalHotkeyService after setting defaults
        DispatchQueue.main.async {
            _ = GlobalHotkeyService.shared
        }

        self.profiles = Self.readAWSProfiles()
        logger.info("Loaded \(self.profiles.count) AWS profiles")
        
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
        
        // Load Nova Canvas config
        if let data = UserDefaults.standard.data(forKey: "novaCanvasConfig"),
           let decoded = try? JSONDecoder().decode(NovaCanvasConfig.self, from: data) {
            self.novaCanvasConfig = decoded
        } else {
            self.novaCanvasConfig = NovaCanvasConfig.defaultConfig
        }
        
        // Load Titan Image config
        if let data = UserDefaults.standard.data(forKey: "titanImageConfig"),
           let decoded = try? JSONDecoder().decode(TitanImageConfig.self, from: data) {
            self.titanImageConfig = decoded
        } else {
            self.titanImageConfig = TitanImageConfig.defaultConfig
        }
        
        // Load Stability AI config
        if let data = UserDefaults.standard.data(forKey: "stabilityAIConfig"),
           let decoded = try? JSONDecoder().decode(StabilityAIConfig.self, from: data) {
            self.stabilityAIConfig = decoded
        } else {
            self.stabilityAIConfig = StabilityAIConfig.defaultConfig
        }
        
        // Load Stability AI Services config
        if let data = UserDefaults.standard.data(forKey: "stabilityAIServicesConfig"),
           let decoded = try? JSONDecoder().decode(StabilityAIServicesConfig.self, from: data) {
            self.stabilityAIServicesConfig = decoded
        } else {
            self.stabilityAIServicesConfig = StabilityAIServicesConfig.defaultConfig
        }
        
        // Load Nova Reel config
        if let data = UserDefaults.standard.data(forKey: "novaReelConfig"),
           let decoded = try? JSONDecoder().decode(NovaReelConfig.self, from: data) {
            self.novaReelConfig = decoded
        } else {
            self.novaReelConfig = NovaReelConfig.defaultConfig
        }
        
        if let data = UserDefaults.standard.data(forKey: "lumaVideoConfig"),
           let decoded = try? JSONDecoder().decode(LumaVideoConfiguration.self, from: data) {
            lumaVideoConfig = decoded
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
        let files = Self.configurationFileURLs()
        monitorFileChanges(at: files.credentials)
        monitorFileChanges(at: files.config)
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
                PreferencesStore.shared.logger.error("Failed to open file descriptor for \(url.path)")
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
        source.setEventHandler {
            Task { @MainActor in
                let manager = PreferencesStore.shared
                manager.logger.info("File change detected at \(urlPath)")
                
                // Environment overrides can use any filename.
                manager.refreshAWSProfiles()
                NotificationCenter.default.post(name: .awsCredentialsChanged, object: nil)
                
                // Re-establish monitoring for the changed file
                manager.monitorFileChanges(at: url)
            }
        }
        
        source.setCancelHandler {
            close(fileDescriptor)
        }
        
        source.resume()
        
        await MainActor.run {
            PreferencesStore.shared.fileMonitors[urlPath] = source
            PreferencesStore.shared.logger.info("File monitoring started for \(urlPath)")
        }
    }
    
    private func stopMonitoring(for url: URL) {
        if let existingSource = fileMonitors.removeValue(forKey: url.path) {
            existingSource.cancel()
            logger.info("File monitoring stopped for \(url.path)")
        }
    }
    
    
    func refreshAWSProfiles() {
        // Read profiles on background thread, then update on main
        Task {
            let newProfiles = await Task.detached {
                Self.readAWSProfilesSync()
            }.value
            
            // Already on MainActor since PreferencesStore is @MainActor
            self.profiles = newProfiles
            self.logger.info("AWS profiles refreshed: \(newProfiles.count) profiles")
        }
    }
    
    /// Match the SDK's AWS_SHARED_CREDENTIALS_FILE and AWS_CONFIG_FILE
    /// overrides. Isolated UI tests must never discover the user's profiles.
    nonisolated static func configurationFileURLs(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> (credentials: URL, config: URL) {
        let base: URL
        if ValidationMode.isOffline(environment: environment),
           let directory = environment["BEDROCK_WORKBENCH_DATA_DIR"] {
            base = URL(fileURLWithPath: directory).appendingPathComponent("aws", isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aws", isDirectory: true)
        }
        func file(_ key: String, fallback: String) -> URL {
            guard let path = environment[key], !path.isEmpty else {
                return base.appendingPathComponent(fallback)
            }
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return (file("AWS_SHARED_CREDENTIALS_FILE", fallback: "credentials"),
                file("AWS_CONFIG_FILE", fallback: "config"))
    }

    /// Only profile names and types are read here; the AWS SDK loads credentials.
    static func readAWSProfiles() -> [ProfileInfo] {
        return readAWSProfilesSync()
    }
    
    /// Non-isolated version for background thread access
    nonisolated static func readAWSProfilesSync(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [ProfileInfo] {
        let files = configurationFileURLs(environment: environment)
        var profiles: [ProfileInfo] = []
        
        if let credentialsProfiles = parseProfilesFromFile(files.credentials.path, isConfig: false) {
            profiles.append(contentsOf: credentialsProfiles)
        }
        
        if let configProfiles = parseProfilesFromFile(files.config.path, isConfig: true) {
            profiles.append(contentsOf: configProfiles)
        }
        
        // Merge by name, preferring SSO/credential_process types from config
        return profiles.mergedByName()
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

    func applyAppearance() {
        NSApp.appearance = appearance == "dark" ? NSAppearance(named: .darkAqua) :
            appearance == "light" ? NSAppearance(named: .aqua) : nil
    }
    
    func getInferenceConfig(for modelId: String) -> ModelInferenceConfig {
        // Return saved config if exists and override is enabled, otherwise return default
        let foundationID = BedrockCapabilityRegistry.shared.foundationID(modelId, region: selectedRegion.rawValue)
        let saved = modelInferenceConfigs[modelId] ?? modelInferenceConfigs[foundationID]
        if let savedConfig = saved, savedConfig.overrideDefault {
            return savedConfig
        } else {
            // Return default config based on model range
            let range = ModelInferenceRange.getRangeForModel(foundationID)
            let parameterDefaults = ModelInferenceRange.getParameterDefaultsForModel(foundationID)
            // Preserve saved reasoning effort even when override is off (for adaptive thinking models)
            let savedEffort = saved?.reasoningEffort
            return ModelInferenceConfig(
                maxTokens: range.defaultMaxTokens,
                temperature: range.defaultTemperature,
                topP: range.defaultTopP,
                includeMaxTokens: parameterDefaults.includeMaxTokens,
                includeTemperature: parameterDefaults.includeTemperature,
                includeTopP: parameterDefaults.includeTopP,
                thinkingBudget: range.defaultThinkingBudget,
                reasoningEffort: savedEffort ?? range.defaultReasoningEffort,
                overrideDefault: false,
                enableStreaming: saved?.enableStreaming ?? true
            )
        }
    }
    
    func setInferenceConfig(_ config: ModelInferenceConfig, for modelId: String) {
        var updated = modelInferenceConfigs
        updated[modelId] = config
        let foundationID = BedrockCapabilityRegistry.shared.foundationID(modelId, region: selectedRegion.rawValue)
        if foundationID != modelId { updated[foundationID] = config }
        guard updated != modelInferenceConfigs else { return }
        modelInferenceConfigs = updated
        logger.info("Updated inference config for model \(modelId): override=\(config.overrideDefault)")
    }
    
    func resetInferenceConfig(for modelId: String) {
        var updated = modelInferenceConfigs
        updated.removeValue(forKey: modelId)
        let foundationID = BedrockCapabilityRegistry.shared.foundationID(modelId, region: selectedRegion.rawValue)
        if foundationID != modelId { updated.removeValue(forKey: foundationID) }
        guard updated != modelInferenceConfigs else { return }
        modelInferenceConfigs = updated
        logger.info("Reset inference config for model \(modelId)")
    }
    
    private func saveModelInferenceConfigs() {
        if let encoded = try? JSONEncoder().encode(modelInferenceConfigs) {
            UserDefaults.standard.set(encoded, forKey: "modelInferenceConfigs")
        }
        logger.debug("Saved model inference configs")
    }
    
    private func saveNovaCanvasConfig() {
        if let encoded = try? JSONEncoder().encode(novaCanvasConfig) {
            UserDefaults.standard.set(encoded, forKey: "novaCanvasConfig")
        }
        logger.debug("Saved Nova Canvas config")
    }
    
    private func saveTitanImageConfig() {
        if let encoded = try? JSONEncoder().encode(titanImageConfig) {
            UserDefaults.standard.set(encoded, forKey: "titanImageConfig")
        }
        logger.debug("Saved Titan Image config")
    }
    
    private func saveStabilityAIConfig() {
        if let encoded = try? JSONEncoder().encode(stabilityAIConfig) {
            UserDefaults.standard.set(encoded, forKey: "stabilityAIConfig")
        }
        logger.debug("Saved Stability AI config")
    }
    
    private func saveStabilityAIServicesConfig() {
        if let encoded = try? JSONEncoder().encode(stabilityAIServicesConfig) {
            UserDefaults.standard.set(encoded, forKey: "stabilityAIServicesConfig")
        }
        logger.debug("Saved Stability AI Services config")
    }
    
    private func saveNovaReelConfig() {
        if let encoded = try? JSONEncoder().encode(novaReelConfig) {
            UserDefaults.standard.set(encoded, forKey: "novaReelConfig")
        }
        logger.debug("Saved Nova Reel config")
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
