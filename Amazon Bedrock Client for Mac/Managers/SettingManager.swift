//
//  SettingManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/08.
//

import Foundation
import Combine

class SettingManager {
    static let shared = SettingManager()
    
    // Publisher for AWS Region
    var awsRegionPublisher = PassthroughSubject<AWSRegion, Never>()
    
    private let awsRegionKey = "awsRegionKey"
    private let fontSizeKey = "fontSizeKey"
    
    init() {
        if let savedRegion = getAWSRegion() {
            awsRegionPublisher.send(savedRegion)
        }
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
    
    var fontSizePublisher = PassthroughSubject<CGFloat, Never>()
    
    func saveFontSize(_ size: CGFloat) {
        UserDefaults.standard.set(size, forKey: fontSizeKey)
        fontSizePublisher.send(size)
    }
    
    func getFontSize() -> CGFloat {
        return CGFloat(UserDefaults.standard.float(forKey: fontSizeKey))
    }
}

