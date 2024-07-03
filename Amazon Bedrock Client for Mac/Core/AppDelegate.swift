//
//  AppDelegate.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 6/29/24.
//

import SwiftUI
import Foundation
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var settingsWindow: NSWindow?
    var localhostServer: LocalhostServer?
    
    @objc func newTab() {
    }

    @objc func newWindow() {
    }

    func newChat() {
        AppCoordinator.shared.shouldCreateNewChat = true
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApplication.shared.windows.forEach { window in
            window.delegate = self
            restoreWindowSize(window: window, id: window.windowNumber)
        }
        
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
    
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        if window == settingsWindow {
            settingsWindow = nil
        }
        saveWindowSize(window: window, id: window.windowNumber)
    }
    
    func restoreWindowSize(window: NSWindow, id: Int) {
        if let sizeData = UserDefaults.standard.data(forKey: "windowSize_\(id)") {
            do {
                if let sizeDict = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSDictionary.self, from: sizeData) as? [String: CGFloat],
                   let width = sizeDict["width"],
                   let height = sizeDict["height"] {
                    window.setContentSize(NSSize(width: width, height: height))
                }
            } catch {
                print("Error unarchiving window size: \(error)")
            }
        }
    }

    func saveWindowSize(window: NSWindow, id: Int) {
        let size = window.frame.size
        let sizeDict: [String: CGFloat] = ["width": size.width, "height": size.height]
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: sizeDict, requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: "windowSize_\(id)")
        } catch {
            print("Error archiving window size: \(error)")
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApplication.shared.windows.forEach { $0.makeKeyAndOrderFront(self) }
        }
        return true
    }
    
    @objc func openSettings() {
        SettingsWindowManager.shared.openSettings(view: SettingsView())
    }
}
