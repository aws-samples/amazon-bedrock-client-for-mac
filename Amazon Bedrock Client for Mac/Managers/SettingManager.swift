//
//  SettingManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import Combine
import Logging
import SwiftUI

extension Notification.Name {
    static let awsCredentialsChanged = Notification.Name("awsCredentialsChanged")
    static let mcpEnabledChanged = Notification.Name("mcpEnabledChanged")  // 추가
}

class SettingManager: ObservableObject {
    static let shared = SettingManager()
    private var logger = Logger(label: "SettingManager")
    private static let staticLogger = Logger(label: "SettingManager.Static")

    private var fileMonitors: [String: DispatchSourceFileSystemObject] = [:]
    private let monitoringQueue = DispatchQueue(
        label: "com.amazonbedrock.fileMonitoring", attributes: .concurrent)
    
    @AppStorage("checkForUpdates") var checkForUpdates: Bool = true
    @AppStorage("appearance") var appearance: String = "auto"
    @AppStorage("sidebarIconSize") var sidebarIconSize: String = "Medium"
    @AppStorage("allowWallpaperTinting") var allowWallpaperTinting: Bool = false
    @AppStorage("enableDebugLog") var enableDebugLog: Bool = true
    @AppStorage("enableModelThinking") var enableModelThinking: Bool = true
    @AppStorage("systemPrompt") var systemPrompt: String = ""
    @AppStorage("defaultDirector") var defaultDirectory: String = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Amazon Bedrock Client"
    ).path
    @AppStorage("defaultModelId") var defaultModelId: String = ""
    @AppStorage("maxToolUseTurns") var maxToolUseTurns: Int = 10

    var mcpEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "mcpEnabled")
        }
        set {
            let oldValue = UserDefaults.standard.bool(forKey: "mcpEnabled")
            if oldValue != newValue {
                UserDefaults.standard.set(newValue, forKey: "mcpEnabled")
                // 값이 변경되었을 때만 커스텀 알림 전송
                logger.info("MCP enabled changed: \(oldValue) -> \(newValue)")
                NotificationCenter.default.post(name: .mcpEnabledChanged, object: nil)
            }
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
    @Published var allowImagePasting: Bool = true
    @Published var mcpServers: [MCPServerConfig] = [] {
        didSet {
            // Save the complete list to UserDefaults
            saveMCPServerList()
            // Save only enabled servers to the config file
            saveMCPConfigFile()
        }
    }
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

        self.profiles = Self.readAWSProfiles()
        
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
        startMonitoring(for: url)
    }
    
    private func startMonitoring(for url: URL) {
        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            logger.error("Failed to open file descriptor for \(url.path)")
            return
        }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor, eventMask: [.write, .delete, .rename],
            queue: monitoringQueue)
        source.setEventHandler { [weak self] in
            self?.handleFileChange(at: url)
        }
        source.setCancelHandler {
            close(fileDescriptor)
        }
        source.resume()
        
        fileMonitors[url.path] = source
        logger.info("File monitoring started for \(url.path)")
    }
    
    private func stopMonitoring(for url: URL) {
        if let existingSource = fileMonitors.removeValue(forKey: url.path) {
            existingSource.cancel()
            logger.info("File monitoring stopped for \(url.path)")
        }
    }
    
    private func handleFileChange(at url: URL) {
        logger.info("File change detected at \(url.path)")
        DispatchQueue.main.async { [weak self] in
            if url.lastPathComponent == "credentials" || url.lastPathComponent == "config" {
                self?.refreshAWSProfiles()
                NotificationCenter.default.post(name: .awsCredentialsChanged, object: nil)
            }
            
            // Re-establish monitoring for the changed file
            self?.monitorFileChanges(at: url)
        }
    }
    
    private func refreshAWSProfiles() {
        self.profiles = Self.readAWSProfiles()
        logger.info("AWS profiles refreshed")
    }
    
    static func readAWSProfiles() -> [ProfileInfo] {
        var profiles: [ProfileInfo] = []
        
        // Read regular profiles from ~/.aws/credentials
        let credentialsProfiles = readProfilesFromFile(path: "~/.aws/credentials")
        profiles.append(contentsOf: credentialsProfiles)
        
        // Read profiles from ~/.aws/config including SSO and credential_process
        let configProfiles = readProfilesFromConfig(path: "~/.aws/config")
        profiles.append(contentsOf: configProfiles)
        
        // Return unique profiles
        return profiles.uniqued()
    }
    
    // Read profiles from a file (used for ~/.aws/credentials)
    static func readProfilesFromFile(path: String) -> [ProfileInfo] {
        let expandedPath = NSString(string: path).expandingTildeInPath
        
        // Attempt to read the file contents
        guard let contents = try? String(contentsOfFile: expandedPath, encoding: .utf8) else {
            staticLogger.info("Error reading file: \(path)")
            return []
        }
        
        let lines = contents.components(separatedBy: .newlines)
        var profiles: [ProfileInfo] = []
        
        // Parse each line to find profile names
        for line in lines {
            if line.starts(with: "[") && line.hasSuffix("]") {
                let profileName = String(line.dropFirst().dropLast())
                profiles.append(ProfileInfo(name: profileName))
            }
        }
        
        return profiles
    }
    
    // Read all profiles from ~/.aws/config including SSO and credential_process
    static func readProfilesFromConfig(path: String) -> [ProfileInfo] {
        // Attempt to read the file contents
        let expandedPath = NSString(string: path).expandingTildeInPath
        guard let contents = try? String(contentsOfFile: expandedPath, encoding: .utf8) else {
            staticLogger.info("Error reading file: \(path)")
            return []
        }
        
        // Parse each line to find profiles
        let lines = contents.components(separatedBy: .newlines)
        var profiles: [ProfileInfo] = []
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.starts(with: "[profile ") && trimmedLine.hasSuffix("]") {
                profiles.append(ProfileInfo(name: String(trimmedLine.dropFirst(9).dropLast())))
            }
        }
        
        return profiles
    }
    
    // Load both sources and reconcile differences
    func loadMCPServers() {
        // Step 1: Load the complete list from UserDefaults
        let savedServers = loadSavedMCPServerList()
        
        // Step 2: Load the enabled servers from the config file
        let configServers = loadMCPServersFromConfigFile()
        
        // Step 3: Reconcile the differences
        var mergedServers = savedServers
        
        // Add any servers in the config file that aren't in our saved list
        for configServer in configServers {
            if !mergedServers.contains(where: { $0.name == configServer.name }) {
                // New server found in config file - add it as enabled
                var newServer = configServer
                newServer.enabled = true
                mergedServers.append(newServer)
            } else {
                // Update existing server if it's in the config file (should be enabled)
                for i in 0..<mergedServers.count {
                    if mergedServers[i].name == configServer.name {
                        // Update details from config file but preserve enabled state
                        var updatedServer = configServer
                        updatedServer.enabled = true  // If it's in the config file, it should be enabled
                        mergedServers[i] = updatedServer
                        break
                    }
                }
            }
        }
        
        // Update the server list without triggering didSet (to avoid immediate saving)
        self.mcpServers = mergedServers
    }
    
    // Load server list from UserDefaults
    private func loadSavedMCPServerList() -> [MCPServerConfig] {
        if let data = UserDefaults.standard.data(forKey: "mcpServers"),
           let decoded = try? JSONDecoder().decode([MCPServerConfig].self, from: data) {
            return decoded
        }
        return []
    }

    // Save complete server list to UserDefaults
    private func saveMCPServerList() {
        if let encoded = try? JSONEncoder().encode(mcpServers) {
            UserDefaults.standard.set(encoded, forKey: "mcpServers")
        }
    }

    // Load servers from config file
    private func loadMCPServersFromConfigFile() -> [MCPServerConfig] {
        let configPath = getMCPConfigPath()
        var loadedServers: [MCPServerConfig] = []
        
        if FileManager.default.fileExists(atPath: configPath) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]],
                   let servers = json["mcpServers"] as? [String: [String: Any]] {
                    
                    for (name, serverInfo) in servers {
                        // Extract server details directly from dictionary
                        if let command = serverInfo["command"] as? String,
                           let argsArray = serverInfo["args"] as? [String] {
                            
                            var server = MCPServerConfig(
                                name: name,
                                command: command,
                                args: argsArray,
                                enabled: true  // Servers in config are considered enabled
                            )
                            
                            // Add optional fields if present
                            if let env = serverInfo["env"] as? [String: String] {
                                server.env = env
                            }
                            
                            if let cwd = serverInfo["cwd"] as? String {
                                server.cwd = cwd
                            }
                            
                            loadedServers.append(server)
                        }
                    }
                    
                    logger.info("Loaded \(loadedServers.count) MCP servers from config file")
                }
            } catch {
                logger.error("Error reading MCP config file: \(error)")
            }
        }
        
        return loadedServers
    }

    // Define MCPServerInfo for JSON parsing
    private struct MCPServerInfo: Codable {
        var command: String
        var args: [String]
        var env: [String: String]?
        var cwd: String?
    }

    // Helper function to get the MCP config file path
    func getMCPConfigPath() -> String {
        let configDir = defaultDirectory.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.path
            : defaultDirectory
        
        return URL(fileURLWithPath: configDir)
            .appendingPathComponent("mcp_config.json")
            .path
    }

    // Save only enabled servers to the MCP config file
    func saveMCPConfigFile() {
        // Get only enabled servers
        let enabledServers = mcpServers.filter { $0.enabled }
        
        // Only proceed if we have servers to save
        guard !enabledServers.isEmpty else {
            // If no enabled servers, create an empty config
            try? "{ \"mcpServers\": {} }".write(
                toFile: getMCPConfigPath(),
                atomically: true,
                encoding: .utf8
            )
            return
        }
        
        // Build a dictionary representation first
        var serversDict: [String: [String: Any]] = [:]
        
        for server in enabledServers {
            var serverInfo: [String: Any] = [
                "command": server.command,
                "args": server.args
            ]
            
            if let env = server.env, !env.isEmpty {
                serverInfo["env"] = env
            }
            
            if let cwd = server.cwd, !cwd.isEmpty {
                serverInfo["cwd"] = cwd
            }
            
            serversDict[server.name] = serverInfo
        }
        
        let configDict: [String: Any] = ["mcpServers": serversDict]
        
        // Use JSONSerialization instead of Codable to have more control over escaping
        if let jsonData = try? JSONSerialization.data(
            withJSONObject: configDict,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        ) {
            do {
                // Ensure directory exists
                let configPath = getMCPConfigPath()
                let directoryURL = URL(fileURLWithPath: configPath).deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                
                // Write the config file
                try jsonData.write(to: URL(fileURLWithPath: configPath))
                logger.debug("Saved MCP config file with pretty formatting")
            } catch {
                logger.error("Failed to save MCP config file: \(error)")
            }
        }
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
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
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
