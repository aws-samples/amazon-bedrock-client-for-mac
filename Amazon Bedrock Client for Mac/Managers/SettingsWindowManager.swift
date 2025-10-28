//
//  SettingsWindowManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 6/27/24.
//

import Foundation
import SwiftUI
import AppKit

@MainActor
class SettingsWindowManager: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = SettingsWindowManager()
    private var settingsWindow: NSWindow?
    
    func openSettings<V: View>(view: V) {
        if let existingWindow = settingsWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        let hostingController = NSHostingController(rootView: view)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 600, height: 400))
        window.center()
        window.delegate = self
        
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }
    
    func windowWillClose(_ notification: Notification) {
        settingsWindow = nil
    }
}

