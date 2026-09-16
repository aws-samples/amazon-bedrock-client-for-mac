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
    
    // Use a lazy property for UpdateService to ensure it's only initialized when needed
    @MainActor
    private lazy var updateManager: UpdateService? = {
        Logger(label: "AppDelegate").info("Initializing UpdateService lazily")
        return UpdateService.shared
    }()
    
    // Hotkey manager for quick access
    private var hotkeyManager: GlobalHotkeyService?
    
    private var logger = Logger(label: "AppDelegate")
    
    // Track last update check time to prevent excessive checking
    private var lastUpdateCheckTime: Date?
    private let updateCheckInterval: TimeInterval = 3600 * 24 // 60 * 24 minutes minimum between checks
    
    // Flag to track if this is the first activation
    private var isFirstActivation = true
    private var isPreparingToQuit = false

    @objc func newChat(_ sender: Any?) {
        AppWindows.showMain()
        if let newThread = AppWindows.newThread { newThread() }
        else { AppCoordinator.shared.shouldCreateNewChat = true }
        AppWindows.focusComposer()
    }
    
    @objc func deleteChat(_ sender: Any?) {
        guard AppWindows.isMainWindowKey,
              AppStore.shared.destination == .chats,
              let id = AppStore.shared.selectedThreadID else { return }
        AppStore.shared.trash(id)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Application finished launching")
        
        // Disable automatic window tabbing
        NSWindow.allowsAutomaticWindowTabbing = false
        
        // Initialize hotkey manager for quick access
        if !ValidationMode.isOffline {
            Task { @MainActor in
                self.hotkeyManager = GlobalHotkeyService.shared
                logger.info("Hotkey manager initialized")
            }
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
        guard !ValidationMode.isOffline else { return }
        lastUpdateCheckTime = Date()
        logger.info("Performing update check")
        Task { @MainActor in
            updateManager?.checkForUpdates()
        }
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isPreparingToQuit else { return .terminateLater }
        isPreparingToQuit = true
        Task {
            let savedSessions = await ChatSessionPool.shared.prepareToTerminate()
            let savedWelcome = await ComposerDraft.welcome.flush()
            let saved = savedSessions && savedWelcome
            if !saved { ChatSessionPool.shared.resumeAfterCancelledQuit() }
            if saved {
                await BackgroundProcessRegistry.shared.stopAll()
                await MCPClientManager.shared.shutdown()
            }
            AppStore.shared.flush()
            isPreparingToQuit = false
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Application will terminate")
        MCPClientManager.shared.markMCPRunning(false)
        AppStore.shared.flush()
        
        // Clean up temporary chats before terminating
        Task { @MainActor in
            ConversationStore.shared.cleanupTemporaryChats()
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Return false to keep app running when all windows are closed
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppWindows.showMain() }
        return true
    }

    @objc func openSettings(_ sender: Any?) {
        // Open the settings window using the singleton manager
        logger.info("Opening settings window")
        Task { @MainActor in
            SettingsWindowController.shared.openSettings(view: SettingsView())
        }
    }
}
