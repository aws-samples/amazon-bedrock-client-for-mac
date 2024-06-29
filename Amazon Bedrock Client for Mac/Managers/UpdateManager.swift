//
//  UpdateManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2024/01/04.
//

import Foundation
import AppKit
import Combine

class UpdateManager {
    private let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    private let updateCheckURL = URL(string: "https://api.github.com/repos/aws-samples/amazon-bedrock-client-for-mac/releases/latest")!
    
    private var cancellables = Set<AnyCancellable>()
    
    func checkForUpdates() {
        guard SettingManager.shared.checkForUpdates else { return }
        
        URLSession.shared.dataTask(with: updateCheckURL) { data, response, error in
            guard let data = data,
                  let releaseInfo = try? JSONDecoder().decode(ReleaseInfo.self, from: data),
                  let latestVersion = releaseInfo.tagName else {
                return
            }
            
            let updateAvailable = self.isNewVersionAvailable(currentVersion: self.currentVersion, latestVersion: latestVersion)
            let downloadURL = "https://github.com/aws-samples/amazon-bedrock-client-for-mac/releases/latest/download/Amazon.Bedrock.Client.for.Mac.dmg"
            
            if updateAvailable {
                DispatchQueue.main.async {
                    self.showUpdateAlert(downloadURL: downloadURL)
                }
            }
        }.resume()
    }
    
    private func isNewVersionAvailable(currentVersion: String, latestVersion: String) -> Bool {
        let cleanedLatestVersion = latestVersion.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        return currentVersion.compare(cleanedLatestVersion, options: .numeric) == .orderedAscending
    }
    
    private func showUpdateAlert(downloadURL: String) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "A new version is available. Would you like to download it?"
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: downloadURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

struct ReleaseInfo: Codable {
    var tagName: String?
    
    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}
