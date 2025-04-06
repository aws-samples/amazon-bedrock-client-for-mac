//
//  UpdateManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2024/01/04.
//

import Foundation
import AppKit
import Combine
import Logging

class UpdateManager {
    // Singleton instance
    static let shared: UpdateManager = {
        let instance = UpdateManager()
        return instance
    }()
    
    private let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0" 
    private let updateCheckURL = URL(string: "https://api.github.com/repos/aws-samples/amazon-bedrock-client-for-mac/releases/latest")!
    
    // The name used for display purposes
    private let appDisplayName = "Amazon Bedrock Client for Mac"
    // The actual name of the .app file (important for the update process)
    private let appFileName = "Amazon Bedrock"
    
    private var cancellables = Set<AnyCancellable>()
    private var logger: Logger
    
    // Strong references to prevent premature deallocation
    private var updateTask: URLSessionTask?
    private var downloadTask: URLSessionDownloadTask?
    private var progressWindow: NSWindow?
    
    // Private initializer for singleton
    private init() {
        logger = Logger(label: "UpdateManager")
        logger.info("UpdateManager initialized with current version: \(self.currentVersion)")
    }
    
    func cleanup() {
        updateTask?.cancel()
        downloadTask?.cancel()
        
        DispatchQueue.main.async {
            self.progressWindow?.close()
            self.progressWindow = nil
        }
    }
    
    func checkForUpdates() {
        guard SettingManager.shared.checkForUpdates else {
            logger.debug("Auto-update is disabled in settings")
            return
        }
        
        logger.info("Checking for updates. Current version: \(currentVersion)")
        
        // Cancel existing task if any
        updateTask?.cancel()
        
        let request = URLRequest(url: updateCheckURL, timeoutInterval: 30)
        updateTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("Update check failed: \(error.localizedDescription)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                self.logger.error("Invalid response from update server")
                return
            }
            
            guard let data = data else {
                self.logger.error("No data received from update server")
                return
            }
            
            self.processReleaseData(data)
        }
        
        updateTask?.resume()
    }
    
    private func processReleaseData(_ data: Data) {
        do {
            let decoder = JSONDecoder()
            let releaseInfo = try decoder.decode(ReleaseInfo.self, from: data)
            
            guard let tagName = releaseInfo.tagName, !tagName.isEmpty else {
                logger.error("Invalid release info - missing tag name")
                return
            }
            
            guard let assets = releaseInfo.assets, !assets.isEmpty else {
                logger.error("No assets found in release")
                return
            }
            
            // Find DMG asset
            for asset in assets {
                if asset.name.hasSuffix(".dmg"), let downloadURL = asset.browserDownloadURL {
                    logger.info("Found update: \(tagName), download: \(downloadURL)")
                    
                    let updateAvailable = isNewVersionAvailable(
                        currentVersion: self.currentVersion,
                        latestVersion: tagName
                    )
                    
                    if updateAvailable {
                        DispatchQueue.main.async {
                            self.showUpdateAlert(latestVersion: tagName, downloadURL: downloadURL)
                        }
                    }
                    
                    break
                }
            }
        } catch {
            logger.error("Failed to parse release data: \(error.localizedDescription)")
        }
    }
    
    private func isNewVersionAvailable(currentVersion: String, latestVersion: String) -> Bool {
        let cleanedLatestVersion = latestVersion.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        return currentVersion.compare(cleanedLatestVersion, options: .numeric) == .orderedAscending
    }
    
    private func showUpdateAlert(latestVersion: String, downloadURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "A new version (\(latestVersion)) is available. Would you like to update now?"
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Disable Auto Updates")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // User chose "Update Now"
            downloadAndInstallUpdate(latestVersion: latestVersion, downloadURL: downloadURL)
        case .alertThirdButtonReturn:
            // User chose "Disable Auto Updates"
            SettingManager.shared.checkForUpdates = false
            
            let disabledAlert = NSAlert()
            disabledAlert.messageText = "Auto Updates Disabled"
            disabledAlert.informativeText = "Automatic updates have been disabled. You can re-enable them in the application settings."
            disabledAlert.addButton(withTitle: "OK")
            disabledAlert.runModal()
        default:
            // User chose "Later"
            logger.debug("Update deferred by user")
        }
    }
    
    private func downloadAndInstallUpdate(latestVersion: String, downloadURL: URL) {
        logger.info("Starting download for version \(latestVersion)")
        
        // Create updates directory
        let defaultDirPath = SettingManager.shared.defaultDirectory
        let updatesDir = URL(fileURLWithPath: defaultDirPath).appendingPathComponent("Updates")
        
        do {
            if !FileManager.default.fileExists(atPath: updatesDir.path) {
                try FileManager.default.createDirectory(at: updatesDir, withIntermediateDirectories: true, attributes: nil)
            }
        } catch {
            logger.error("Failed to create updates directory: \(error.localizedDescription)")
            showError(message: "Failed to create updates directory")
            return
        }
        
        let dmgPath = updatesDir.appendingPathComponent("AmazonBedrockClientUpdate.dmg")
        
        // Create progress window
        progressWindow = createProgressWindow()
        
        // Download DMG file
        downloadTask = URLSession.shared.downloadTask(with: downloadURL) { [weak self] localURL, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.progressWindow?.close()
                self.progressWindow = nil
                
                if let error = error {
                    self.logger.error("Download failed: \(error.localizedDescription)")
                    self.showError(message: "Download failed. Please try again later.")
                    return
                }
                
                guard let localURL = localURL else {
                    self.logger.error("Download failed: No file returned")
                    self.showError(message: "Download failed. No file was received.")
                    return
                }
                
                do {
                    // Remove existing file if it exists
                    if FileManager.default.fileExists(atPath: dmgPath.path) {
                        try FileManager.default.removeItem(at: dmgPath)
                    }
                    
                    // Move downloaded file to updates directory
                    try FileManager.default.moveItem(at: localURL, to: dmgPath)
                    
                    self.installUpdate(dmgPath: dmgPath)
                    
                } catch {
                    self.logger.error("Failed to prepare update: \(error.localizedDescription)")
                    self.showError(message: "Failed to prepare update")
                }
            }
        }
        
        downloadTask?.resume()
    }
    
    private func createProgressWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Downloading Update"
        window.center()
        window.isReleasedWhenClosed = false
        
        let progressIndicator = NSProgressIndicator(frame: NSRect(x: 50, y: 50, width: 200, height: 20))
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = true
        progressIndicator.startAnimation(nil)
        
        let label = NSTextField(labelWithString: "Downloading the latest version...")
        label.frame = NSRect(x: 50, y: 30, width: 200, height: 20)
        label.alignment = .center
        
        window.contentView?.addSubview(progressIndicator)
        window.contentView?.addSubview(label)
        
        window.makeKeyAndOrderFront(nil)
        
        return window
    }
    
    private func installUpdate(dmgPath: URL) {
        logger.info("Preparing installation script")
        
        // Create script in the updates directory
        let defaultDirPath = SettingManager.shared.defaultDirectory
        let scriptDir = URL(fileURLWithPath: defaultDirPath).appendingPathComponent("Updates")
        let installScriptPath = scriptDir.appendingPathComponent("install_update.sh")
        
        // Simplified script with cleaner quoting
        let scriptContent = """
        #!/bin/bash
        
        # Log file for debugging
        LOG_FILE="\(scriptDir.path)/update_log.txt"
        
        # Make sure the log directory exists and is writable
        mkdir -p "\(scriptDir.path)"
        touch "$LOG_FILE"
        
        # Redirect both stdout and stderr to the log file
        exec > "$LOG_FILE" 2>&1
        
        echo "Starting update process at $(date)"
        
        # Define expected volume name and app name
        EXPECTED_VOLUME_NAME="Amazon Bedrock Client for Mac"
        EXPECTED_APP_NAME="Amazon Bedrock.app"
        
        echo "DMG path: \(dmgPath.path)"
        echo "Expected volume: $EXPECTED_VOLUME_NAME"
        echo "Expected app: $EXPECTED_APP_NAME"
        
        # Mount DMG using a simple approach
        echo "Mounting DMG..."
        hdiutil attach "\(dmgPath.path)"
        
        # Wait for mounting to complete
        sleep 3
        
        # Check if our expected volume exists
        if [ -d "/Volumes/$EXPECTED_VOLUME_NAME" ]; then
            echo "Found expected volume: /Volumes/$EXPECTED_VOLUME_NAME"
            VOLUME_PATH="/Volumes/$EXPECTED_VOLUME_NAME"
        else
            echo "Expected volume not found, looking for recently mounted volumes..."
            RECENT_VOLUMES=$(ls -td /Volumes/* | head -3)
            echo "Recent volumes: $RECENT_VOLUMES"
            
            # Take the first one as a best guess
            VOLUME_PATH=$(echo "$RECENT_VOLUMES" | head -1)
            echo "Using volume: $VOLUME_PATH"
        fi
        
        # Verify the volume exists
        if [ ! -d "$VOLUME_PATH" ]; then
            echo "Error: Could not locate a valid mounted volume"
            osascript -e 'display dialog "Failed to locate the update volume." buttons {"OK"} default button "OK" with title "Update Error"'
            exit 1
        fi
        
        # Check for the app in the volume - first try the expected name
        if [ -d "$VOLUME_PATH/$EXPECTED_APP_NAME" ]; then
            echo "Found expected app: $VOLUME_PATH/$EXPECTED_APP_NAME"
            APP_PATH="$VOLUME_PATH/$EXPECTED_APP_NAME"
        else
            echo "Expected app not found, searching for any .app file..."
            # Find any .app in the volume
            FOUND_APP=$(find "$VOLUME_PATH" -maxdepth 1 -name "*.app" | head -1)
            
            if [ -n "$FOUND_APP" ]; then
                APP_PATH="$FOUND_APP"
                echo "Found app: $APP_PATH"
            else
                echo "Error: No application found in the mounted volume"
                osascript -e 'display dialog "No application found in the update package." buttons {"OK"} default button "OK" with title "Update Error"'
                # Try to unmount
                diskutil unmount "$VOLUME_PATH" > /dev/null 2>&1 || true
                exit 1
            fi
        fi
        
        # Extract just the app name from the path
        APP_NAME=$(basename "$APP_PATH")
        echo "App name: $APP_NAME"
        
        # Destination in Applications folder
        DEST_PATH="/Applications/$APP_NAME"
        echo "Will install to: $DEST_PATH"
        
        # Close app if running
        echo "Checking if app is running..."
        pkill -f "$APP_NAME" > /dev/null 2>&1 || true
        sleep 2
        
        # Copy to Applications folder with simplified admin privileges approach
        echo "Installing to Applications folder..."
        
        # Remove old app if it exists
        if [ -d "$DEST_PATH" ]; then
            echo "Removing previous version..."
            rm -rf "$DEST_PATH"
            
            # If removal failed, use admin privileges via a simpler approach
            if [ -d "$DEST_PATH" ]; then
                echo "Using admin privileges to remove old app..."
                osascript -e "do shell script \\\"rm -rf $DEST_PATH\\\" with administrator privileges"
            fi
        fi
        
        # Copy new version
        echo "Copying new version..."
        cp -R "$APP_PATH" "/Applications/"
        
        # If copy failed, use admin privileges
        if [ ! -d "$DEST_PATH" ]; then
            echo "Using admin privileges to copy new app..."
            osascript -e "do shell script \\\"cp -R \\\\\\\"$APP_PATH\\\\\\\" /Applications/\\\" with administrator privileges"
        fi
        
        # Verify installation succeeded
        if [ ! -d "$DEST_PATH" ]; then
            echo "Error: Failed to install app to Applications folder"
            osascript -e 'display dialog "Failed to install the update." buttons {"OK"} default button "OK" with title "Update Error"'
            diskutil unmount "$VOLUME_PATH" > /dev/null 2>&1 || true
            exit 1
        fi
        
        echo "App installed successfully"
        
        # Remove quarantine attribute
        echo "Removing quarantine attribute..."
        xattr -d com.apple.quarantine "$DEST_PATH" > /dev/null 2>&1 || true
        
        # Unmount the volume
        echo "Unmounting update volume..."
        diskutil unmount "$VOLUME_PATH" > /dev/null 2>&1 || hdiutil detach "$VOLUME_PATH" -force > /dev/null 2>&1 || true
        
        # Clean up
        echo "Cleaning up..."
        rm -f "\(dmgPath.path)" > /dev/null 2>&1 || true
        
        # Show success notification
        echo "Update completed successfully"
        osascript -e 'display notification "Update installed successfully!" with title "Update Complete"'
        
        # Launch the updated app
        echo "Launching updated application..."
        open "$DEST_PATH"
        
        echo "Update process completed at $(date)"
        """
        
        do {
            // Create scripts directory if needed
            if !FileManager.default.fileExists(atPath: scriptDir.path) {
                try FileManager.default.createDirectory(at: scriptDir, withIntermediateDirectories: true, attributes: nil)
            }
            
            // Write script
            try scriptContent.write(to: installScriptPath, atomically: true, encoding: .utf8)
            
            // Make script executable
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installScriptPath.path)
            
            // Create a simpler launcher script (avoiding complex escaping)
            let launcherScriptPath = scriptDir.appendingPathComponent("launch_update.sh")
            let launcherScript = """
            #!/bin/bash
            
            # Simple delay to allow the app to quit
            sleep 2
            
            # Run the install script and ensure it runs in the background
            bash "\(installScriptPath.path)" &
            
            # Exit launcher
            exit 0
            """
            
            try launcherScript.write(to: launcherScriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherScriptPath.path)
            
            // Show user notification before updating
            let alert = NSAlert()
            alert.messageText = "Ready to Update"
            alert.informativeText = "The application will now restart to install the update."
            alert.addButton(withTitle: "Install")
            
            if alert.runModal() == .alertFirstButtonReturn {
                // Use NSTask for more reliable script execution
                let task = Process()
                task.launchPath = "/bin/bash"
                task.arguments = [launcherScriptPath.path]
                
                do {
                    try task.run()
                    
                    // Give the script time to start before quitting
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // Terminate app gracefully
                        NSApplication.shared.terminate(nil)
                    }
                } catch {
                    self.logger.error("Failed to launch update script: \(error.localizedDescription)")
                    self.showError(message: "Failed to start the update process")
                }
            }
        } catch {
            logger.error("Failed to prepare update script: \(error.localizedDescription)")
            showError(message: "Failed to prepare update script")
        }
    }
    
    
    private func showError(message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Update Error"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

// Improved Codable structs for parsing GitHub API response
struct Asset: Codable {
    let name: String
    let browserDownloadURL: URL?
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

struct ReleaseInfo: Codable {
    let tagName: String?
    let assets: [Asset]?
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}
