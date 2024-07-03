//
//  SettingManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import SwiftUI
import Combine
import Logging

class SettingManager: ObservableObject {
    static let shared = SettingManager()
    private var logger = Logger(label: "SettingManager")
    
    @Published var selectedRegion: AWSRegion {
        didSet { saveSettings() }
    }
    @Published var selectedProfile: String {
        didSet { saveSettings() }
    }
    @Published var profiles: [ProfileInfo] {
        didSet { saveSettings() }
    }
    @Published var checkForUpdates: Bool {
        didSet {
            saveSettings()
        }
    }
    @Published var appearance: String {
        didSet {
            saveSettings()
        }
    }
    @Published var accentColor: NSColor {
        didSet {
            saveSettings()
        }
    }
    @Published var sidebarIconSize: String {
        didSet {
            saveSettings()
        }
    }
    @Published var allowWallpaperTinting: Bool {
        didSet {
            saveSettings()
        }
    }
    @Published var endpoint: String {
        didSet {
            saveSettings()
        }
    }
    @Published var runtimeEndpoint: String {
        didSet {
            saveSettings()
        }
    }
    @Published var enableDebugLog: Bool {
        didSet {
            saveSettings()
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        self.selectedRegion = UserDefaults.standard.string(forKey: "selectedRegion").flatMap { AWSRegion(rawValue: $0) } ?? .usEast1
        self.selectedProfile = UserDefaults.standard.string(forKey: "selectedProfile") ?? "default"
        self.profiles = Self.readAWSProfiles()
        self.checkForUpdates = UserDefaults.standard.object(forKey: "checkForUpdates") as? Bool ?? true
        self.appearance = UserDefaults.standard.string(forKey: "appearance") ?? "auto"
        self.accentColor = UserDefaults.standard.color(forKey: "accentColor") ?? .systemBlue
        self.sidebarIconSize = UserDefaults.standard.string(forKey: "sidebarIconSize") ?? "Medium"
        self.allowWallpaperTinting = UserDefaults.standard.bool(forKey: "allowWallpaperTinting")
        self.endpoint = UserDefaults.standard.string(forKey: "endpoint") ?? ""
        self.runtimeEndpoint = UserDefaults.standard.string(forKey: "runtimeEndpoint") ?? ""
        self.enableDebugLog = UserDefaults.standard.object(forKey: "enableDebugLog") as? Bool ?? true
        
        logger.info("Settings loaded: \(selectedRegion.rawValue), \(selectedProfile)")
    }
    
    private func saveSettings() {
        logger.info("Settings saved: \(selectedRegion.rawValue), \(selectedProfile)")
        
        UserDefaults.standard.set(selectedRegion.rawValue, forKey: "selectedRegion")
        UserDefaults.standard.set(selectedProfile, forKey: "selectedProfile")
        UserDefaults.standard.set(checkForUpdates, forKey: "checkForUpdates")
        UserDefaults.standard.set(appearance, forKey: "appearance")
        UserDefaults.standard.set(accentColor, forKey: "accentColor")
        UserDefaults.standard.set(sidebarIconSize, forKey: "sidebarIconSize")
        UserDefaults.standard.set(allowWallpaperTinting, forKey: "allowWallpaperTinting")
        UserDefaults.standard.set(endpoint, forKey: "endpoint")
        UserDefaults.standard.set(runtimeEndpoint, forKey: "runtimeEndpoint")
        UserDefaults.standard.set(enableDebugLog, forKey: "enableDebugLog")
    }
    
    static func readAWSProfiles() -> [ProfileInfo] {
        var profiles: [ProfileInfo] = []
        
        // Read regular profiles from ~/.aws/credentials
        let credentialsProfiles = readProfilesFromFile(path: "~/.aws/credentials", type: .credentials)
        profiles.append(contentsOf: credentialsProfiles)
        
        // Read SSO profiles from ~/.aws/config
        let configProfiles = readSSOProfilesFromConfig(path: "~/.aws/config")
        profiles.append(contentsOf: configProfiles)
        
        // Return unique profiles
        return profiles.uniqued()
    }
    
    // Read profiles from a file (used for ~/.aws/credentials)
    static func readProfilesFromFile(path: String, type: ProfileInfo.ProfileType) -> [ProfileInfo] {
        let fileManager = FileManager.default
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
        let fileManager = FileManager.default
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
        
        // Parse each line to find SSO profiles
        for line in lines {
            if line.starts(with: "[profile ") && line.hasSuffix("]") {
                // If we've found a new profile, add the previous one if it was SSO
                if let profile = currentProfile, isSSO {
                    profiles.append(ProfileInfo(name: profile, type: .sso))
                }
                // Start tracking a new profile
                currentProfile = String(line.dropFirst(9).dropLast())
                isSSO = false
            } else if line.trimmingCharacters(in: .whitespaces).starts(with: "sso_") {
                // If we find an SSO-related setting, mark this profile as SSO
                isSSO = true
            }
        }
        
        // Add the last profile if it was SSO
        if let profile = currentProfile, isSSO {
            profiles.append(ProfileInfo(name: profile, type: .sso))
        }
        
        return profiles
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

extension UserDefaults {
    func color(forKey key: String) -> NSColor? {
        guard let colorData = data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData)
    }
    
    func set(_ color: NSColor, forKey key: String) {
        let colorData = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false)
        set(colorData, forKey: key)
    }
}
