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

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // UI components
    var settingsWindow: NSWindow?
    var localhostServer: LocalhostServer?
    
    // Use a lazy property for UpdateManager to ensure it's only initialized when needed
    @MainActor
    private lazy var updateManager: UpdateManager? = {
        Logger(label: "AppDelegate").info("Initializing UpdateManager lazily")
        return UpdateManager.shared
    }()
    
    // Hotkey manager for quick access
    private var hotkeyManager: HotkeyManager?
    
    private var logger = Logger(label: "AppDelegate")
    
    // Track last update check time to prevent excessive checking
    private var lastUpdateCheckTime: Date?
    private let updateCheckInterval: TimeInterval = 3600 * 24 // 60 * 24 minutes minimum between checks
    
    // Flag to track if this is the first activation
    private var isFirstActivation = true

    @objc func newChat(_ sender: Any?) {
        // Trigger new chat creation through the coordinator
        Task { @MainActor in
            AppCoordinator.shared.shouldCreateNewChat = true
        }
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
        
        // Initialize hotkey manager for quick access
        Task { @MainActor in
            self.hotkeyManager = HotkeyManager.shared
            logger.info("Hotkey manager initialized")
        }
        
        // Register for app activation notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        
        // No update check here - only in applicationDidBecomeActive
        logger.info("App finished launching, update check will happen on first activation")
    }
    
    @objc func applicationDidBecomeActive(_ notification: Notification) {
        if isFirstActivation {
            // First activation after launch - do initial update check
            isFirstActivation = false
            logger.info("First activation - performing initial update check")
            performUpdateCheck()
        } else {
            // Regular activation - check if we should update based on time interval
            logger.info("App became active - checking if update check is needed")
            checkForUpdatesIfNeeded()
        }
    }
    
    private func checkForUpdatesIfNeeded() {
        let now = Date()
        
        // Check if enough time has passed since last update check
        if let lastCheck = lastUpdateCheckTime {
            let timeSinceLastCheck = now.timeIntervalSince(lastCheck)
            if timeSinceLastCheck < updateCheckInterval {
                logger.info("Skipping update check - only \(Int(timeSinceLastCheck)) seconds since last check")
                return
            }
        }
        
        performUpdateCheck()
    }
    
    private func performUpdateCheck() {
        lastUpdateCheckTime = Date()
        logger.info("Performing update check")
        Task { @MainActor in
            updateManager?.checkForUpdates()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Application will terminate")
        
        // Clean up temporary chats before terminating
        Task { @MainActor in
            ChatManager.shared.cleanupTemporaryChats()
        }
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
        
        // Only access updateManager if it was previously initialized
        Task { @MainActor in
            if let manager = self.updateManager {
                manager.cleanup()
            }
        }
    }

    private func startLocalhostServer() {
        Task { @MainActor in
            let settingsManager = SettingManager.shared
            
            guard settingsManager.enableLocalServer else {
                logger.info("Local server is disabled in settings")
                return
            }
            
            let serverPort = settingsManager.serverPort
            logger.info("Starting localhost server on port \(serverPort)")
            
            let defaultDirectory = settingsManager.defaultDirectory
            
            Task.detached { [weak self] in
                do {
                    let server = try await LocalhostServer(serverPort: serverPort, defaultDirectory: defaultDirectory)
                    try server.start()
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        self.localhostServer = server
                        self.logger.info("Localhost server started successfully on port \(serverPort)")
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.logger.error("Could not start localhost server: \(error)")
                    }
                    print("Could not start localhost server: \(error)")
                }
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
        Task { @MainActor in
            SettingsWindowManager.shared.openSettings(view: SettingsView())
        }
    }
}
