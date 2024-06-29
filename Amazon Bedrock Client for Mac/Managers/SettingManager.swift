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
        didSet {
            saveSettings()
        }
    }
    @Published var selectedProfile: String {
        didSet {
            saveSettings()
        }
    }
    @Published var profiles: [String]
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
        self.checkForUpdates = UserDefaults.standard.object(forKey: "checkForUpdates") as? Bool ?? true
        self.profiles = Self.readAWSProfiles()
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
    
    static func readAWSProfiles() -> [String] {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let credentialsPath = homeDirectory.appendingPathComponent(".aws/credentials")
        
        do {
            let contents = try String(contentsOf: credentialsPath, encoding: .utf8)
            let lines = contents.components(separatedBy: .newlines)
            var profiles: [String] = []
            
            for line in lines {
                if line.starts(with: "[") && line.hasSuffix("]") {
                    let profile = String(line.dropFirst().dropLast())
                    profiles.append(profile)
                }
            }
            
            return profiles.isEmpty ? ["default"] : profiles
        } catch {
            print("Error reading AWS credentials file: \(error)")
            return ["default"]
        }
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
