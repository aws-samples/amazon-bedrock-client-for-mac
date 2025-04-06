//
//  AppDelegate.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 6/29/24.
//

import Cocoa
import SwiftUI
import Foundation
import Combine
import Logging

class AppDelegate: NSObject, NSApplicationDelegate {
    // UI components
    var settingsWindow: NSWindow?
    var localhostServer: LocalhostServer?
    
    // Use a lazy property for UpdateManager to ensure it's only initialized when needed
    private lazy var updateManager: UpdateManager? = {
        Logger(label: "AppDelegate").info("Initializing UpdateManager lazily")
        return UpdateManager.shared
    }()
    
    private var logger = Logger(label: "AppDelegate")
    
    // Flag to control update check
    private var hasCheckedForUpdates = false

    @objc func newChat(_ sender: Any?) {
        // Trigger new chat creation through the coordinator
        AppCoordinator.shared.shouldCreateNewChat = true
    }
    
    @objc func deleteChat(_ sender: Any?) {
        // Set the flag in AppCoordinator to trigger deletion
        DispatchQueue.main.async {
            AppCoordinator.shared.shouldDeleteChat = true
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Application finished launching")
        
        // Disable automatic window tabbing
        NSWindow.allowsAutomaticWindowTabbing = false

        // Start the localhost server for local communication
        startLocalhostServer()
        
        // Schedule update check with a delay and only if not already checked
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, !self.hasCheckedForUpdates else { return }
            self.hasCheckedForUpdates = true
            
            self.logger.info("Starting update check after launch delay")
            // Access updateManager lazily here
            self.updateManager?.checkForUpdates()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Application will terminate")
        
        // Only access updateManager if it was previously initialized
        if let manager = updateManager {
            manager.cleanup()
        }
    }

    private func startLocalhostServer() {
        logger.info("Starting localhost server")
        
        DispatchQueue.global(qos: .background).async {
            do {
                self.localhostServer = try LocalhostServer()
                try self.localhostServer?.start()
                self.logger.info("Localhost server started successfully")
            } catch {
                self.logger.error("Could not start localhost server: \(error)")
                print("Could not start localhost server: \(error)")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Return false to keep app running when all windows are closed
        return false
    }

    @objc func openSettings(_ sender: Any?) {
        // Open the settings window using the singleton manager
        logger.info("Opening settings window")
        SettingsWindowManager.shared.openSettings(view: SettingsView())
    }
}
