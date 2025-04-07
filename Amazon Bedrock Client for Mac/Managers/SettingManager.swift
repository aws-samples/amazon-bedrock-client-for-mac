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
            saveMCPServers()
        }
    }
    @Published var favoriteModelIds: [String] = [] {
        didSet {
            saveFavoriteModels()
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
        let credentialsProfiles = readProfilesFromFile(
            path: "~/.aws/credentials", type: .credentials)
        profiles.append(contentsOf: credentialsProfiles)
        
        // Read profiles from ~/.aws/config including SSO and credential_process
        let configProfiles = readProfilesFromConfig(path: "~/.aws/config")
        profiles.append(contentsOf: configProfiles)
        
        // Return unique profiles
        return profiles.uniqued()
    }
    
    // Read profiles from a file (used for ~/.aws/credentials)
    static func readProfilesFromFile(path: String, type: ProfileInfo.ProfileType) -> [ProfileInfo] {
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
                profiles.append(ProfileInfo(name: profileName, type: type))
            }
        }
        
        return profiles
    }
    
    // Read all profiles from ~/.aws/config including SSO and credential_process
    static func readProfilesFromConfig(path: String) -> [ProfileInfo] {
        let expandedPath = NSString(string: path).expandingTildeInPath
        
        // Attempt to read the file contents
        guard let contents = try? String(contentsOfFile: expandedPath, encoding: .utf8) else {
            staticLogger.info("Error reading file: \(path)")
            return []
        }
        
        let lines = contents.components(separatedBy: .newlines)
        var profiles: [ProfileInfo] = []
        var currentProfile: String?
        var isSSO = false
        var hasCredentialProcess = false
        
        // Function to add the current profile with appropriate type
        func addCurrentProfile() {
            if let profile = currentProfile {
                if isSSO {
                    profiles.append(ProfileInfo(name: profile, type: .sso))
                } else if hasCredentialProcess {
                    profiles.append(ProfileInfo(name: profile, type: .credentialProcess))
                }
            }
        }
        
        // Parse each line to find profiles
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.starts(with: "[profile ") && trimmedLine.hasSuffix("]") {
                // If we've found a new profile, add the previous one if applicable
                addCurrentProfile()
                
                // Start tracking a new profile
                currentProfile = String(trimmedLine.dropFirst(9).dropLast())
                isSSO = false
                hasCredentialProcess = false
            } else if trimmedLine.starts(with: "sso_") {
                // If we find an SSO-related setting, mark this profile as SSO
                isSSO = true
            } else if trimmedLine.starts(with: "credential_process") {
                // If we find credential_process setting, mark this profile
                hasCredentialProcess = true
            }
        }
        
        // Add the last profile
        addCurrentProfile()
        
        return profiles
    }
    
    private func saveMCPServers() {
        if let encoded = try? JSONEncoder().encode(mcpServers) {
            UserDefaults.standard.set(encoded, forKey: "mcpServers")
        }
    }

    func loadMCPServers() {
        if let data = UserDefaults.standard.data(forKey: "mcpServers"),
           let decoded = try? JSONDecoder().decode([MCPServerConfig].self, from: data) {
            self.mcpServers = decoded
        }
    }

    // MCP 서버 구성 JSON 파일 경로 가져오기
    func getMCPConfigPath() -> String {
        return URL(fileURLWithPath: defaultDirectory)
            .appendingPathComponent("mcp_config.json")
            .path
    }

    // MCP 구성 파일 저장
    func saveMCPConfigFile() {
        let configDict: [String: [String: MCPServerInfo]] = [
            "mcpServers": Dictionary(uniqueKeysWithValues: mcpServers.compactMap { server in
                guard server.enabled else { return nil }
                return (server.name, MCPServerInfo(command: server.command, args: server.args))
            })
        ]
        
        struct MCPServerInfo: Codable {
            var command: String
            var args: [String]
        }
        
        if let jsonData = try? JSONEncoder().encode(configDict),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            do {
                try jsonString.write(
                    toFile: getMCPConfigPath(),
                    atomically: true,
                    encoding: .utf8
                )
            } catch {
                logger.error("Failed to save MCP config file: \(error)")
            }
        }
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
