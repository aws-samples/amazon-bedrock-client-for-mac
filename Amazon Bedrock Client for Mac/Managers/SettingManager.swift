//
//  SettingManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import Foundation
import Combine

class GlobalSettings: ObservableObject {
    @Published var showSettings: Bool = false
}

class SettingManager {
    static let shared = SettingManager()
    
    // Publisher for AWS Region
    var awsRegionPublisher = PassthroughSubject<AWSRegion, Never>()
    var settingsChangedPublisher = PassthroughSubject<Void, Never>()

    private let awsRegionKey = "awsRegionKey"
    private let awsEndpointKey = "awsEndpointKey"
    private let awsRuntimeEndpointKey = "awsRuntimeEndpointKey"
    private let fontSizeKey = "fontSizeKey"
    private let checkForUpdatesKey = "checkForUpdatesKey"

    init() {
        if let savedRegion = getAWSRegion() {
            awsRegionPublisher.send(savedRegion)
        }
    }
    
    // Save the update check setting
    func saveCheckForUpdates(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: checkForUpdatesKey)
    }
    
    // Get the update check setting with a default value of True
    func getCheckForUpdates() -> Bool {
        if UserDefaults.standard.object(forKey: checkForUpdatesKey) == nil {
            // Set the default value to True if it's not already set
            UserDefaults.standard.set(true, forKey: checkForUpdatesKey)
        }
        return UserDefaults.standard.bool(forKey: checkForUpdatesKey)
    }
    
    func saveAWSRegion(_ region: AWSRegion) {
        // Save the region to UserDefaults
        UserDefaults.standard.set(region.rawValue, forKey: awsRegionKey)
        
        // Notify subscribers that the region has changed
        awsRegionPublisher.send(region)
    }
    
    func getAWSRegion() -> AWSRegion? {
        // Retrieve the saved AWS region from UserDefaults
        if let savedRegion = UserDefaults.standard.string(forKey: awsRegionKey),
           let region = AWSRegion(rawValue: savedRegion) {
            return region
        }
        return nil
    }
    
    func saveEndpoint(_ endpoint: String) {
        UserDefaults.standard.set(endpoint, forKey: awsEndpointKey)
    }
    
    func getEndpoint() -> String? {
        return UserDefaults.standard.string(forKey: awsEndpointKey)
    }

    func saveRuntimeEndpoint(_ endpoint: String) {
        UserDefaults.standard.set(endpoint, forKey: awsRuntimeEndpointKey)
    }
    
    func getRuntimeEndpoint() -> String? {
        return UserDefaults.standard.string(forKey: awsRuntimeEndpointKey)
    }
    
    var fontSizePublisher = PassthroughSubject<CGFloat, Never>()
    
    func notifySettingsChanged() {
        settingsChangedPublisher.send()
    }
    
    func saveFontSize(_ size: CGFloat) {
        UserDefaults.standard.set(size, forKey: fontSizeKey)
        fontSizePublisher.send(size)
    }
    
    func getFontSize() -> CGFloat {
        return CGFloat(UserDefaults.standard.float(forKey: fontSizeKey))
    }
}

