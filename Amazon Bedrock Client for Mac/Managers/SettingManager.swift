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
}

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
    @AppStorage("systemPrompt") var systemPrompt: String = ""
    @AppStorage("defaultDirector") var defaultDirectory: String = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Amazon Bedrock Client"
    ).path
    @AppStorage("defaultModelId") var defaultModelId: String = ""

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
        setupFileMonitoring()
        logger.info("Settings loaded: \(selectedRegion.rawValue), \(selectedProfile)")
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(selectedRegion.rawValue, forKey: "selectedRegion")
        UserDefaults.standard.set(selectedProfile, forKey: "selectedProfile")
        UserDefaults.standard.set(endpoint, forKey: "endpoint")
        UserDefaults.standard.set(runtimeEndpoint, forKey: "runtimeEndpoint")
        
        logger.info("Settings saved: \(selectedRegion.rawValue), \(selectedProfile)")
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
        
        // Read SSO profiles from ~/.aws/config
        let configProfiles = readSSOProfilesFromConfig(path: "~/.aws/config")
        profiles.append(contentsOf: configProfiles)
        
        // Return unique profiles
        return profiles.uniqued()
    }
    
    // Read profiles from a file (used for ~/.aws/credentials)
    static func readProfilesFromFile(path: String, type: ProfileInfo.ProfileType) -> [ProfileInfo] {
        let expandedPath = NSString(string: path).expandingTildeInPath
        
        // Attempt to read the file contents
        guard let contents = try? String(contentsOfFile: expandedPath, encoding: .utf8) else {
            print("Error reading file: \(path)")
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
    
    // Read SSO profiles from ~/.aws/config
    static func readSSOProfilesFromConfig(path: String) -> [ProfileInfo] {
        let expandedPath = NSString(string: path).expandingTildeInPath
        
        // Attempt to read the file contents
        guard let contents = try? String(contentsOfFile: expandedPath, encoding: .utf8) else {
            print("Error reading file: \(path)")
            return []
        }
        
        let lines = contents.components(separatedBy: .newlines)
        var profiles: [ProfileInfo] = []
        var currentProfile: String?
        var isSSO = false
        
        // Function to add the current profile if it's SSO
        func addCurrentProfileIfSSO() {
            if let profile = currentProfile, isSSO {
                profiles.append(ProfileInfo(name: profile, type: .sso))
            }
        }
        
        // Parse each line to find SSO profiles
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.starts(with: "[profile ") && trimmedLine.hasSuffix("]") {
                // If we've found a new profile, add the previous one if it was SSO
                addCurrentProfileIfSSO()
                
                // Start tracking a new profile
                currentProfile = String(trimmedLine.dropFirst(9).dropLast())
                isSSO = false
            } else if trimmedLine.starts(with: "sso_") {
                // If we find an SSO-related setting, mark this profile as SSO
                isSSO = true
            }
        }
        
        // Add the last profile if it was SSO
        addCurrentProfileIfSSO()
        
        return profiles
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
