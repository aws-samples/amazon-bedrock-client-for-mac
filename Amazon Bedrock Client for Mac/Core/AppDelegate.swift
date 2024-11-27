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

class AppDelegate: NSObject, NSApplicationDelegate {
    var settingsWindow: NSWindow?
    var localhostServer: LocalhostServer?

    @objc func newChat(_ sender: Any?) {
        AppCoordinator.shared.shouldCreateNewChat = true
    }
    
    @objc func deleteChat(_ sender: Any?) {
        // Set the flag in AppCoordinator to trigger deletion
        DispatchQueue.main.async {
            AppCoordinator.shared.shouldDeleteChat = true
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable automatic window tabbing
        NSWindow.allowsAutomaticWindowTabbing = false

        // Start the localhost server
        startLocalhostServer()
    }

    private func startLocalhostServer() {
        DispatchQueue.global(qos: .background).async {
            do {
                self.localhostServer = try LocalhostServer()
                try self.localhostServer?.start()
            } catch {
                print("Could not start localhost server: \(error)")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Close the app when the window is closed
        return false
    }

    @objc func openSettings(_ sender: Any?) {
        // Open the settings window
        SettingsWindowManager.shared.openSettings(view: SettingsView())
        print("Open Settings action triggered")
    }
}
