//
//  QuickAccessWindowManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Kiro on 2025/09/17.
//

import Cocoa
import SwiftUI
import Logging

class QuickAccessWindowManager: ObservableObject {
    static let shared = QuickAccessWindowManager()
    
    private var window: NSWindow?
    private let logger = Logger(label: "QuickAccessWindowManager")
    
    private init() {}
    
    func showWindow() {
        if let existingWindow = window {
            // If window already exists, just show and focus it
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create new window
        let contentView = QuickAccessView { [weak self] in
            self?.hideWindow()
        }
        
        let hostingView = NSHostingView(rootView: contentView)
        
        // Calculate window position (center of screen)
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let windowWidth: CGFloat = 600
        let windowHeight: CGFloat = 400
        let windowRect = NSRect(
            x: screenFrame.midX - windowWidth / 2,
            y: screenFrame.midY - windowHeight / 2,
            width: windowWidth,
            height: windowHeight
        )
        
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        guard let window = window else { return }
        
        // Configure window
        window.contentView = hostingView
        window.title = "Quick Access - Amazon Bedrock"
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        // Set window delegate to handle close events
        window.delegate = self
        
        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        logger.info("Quick access window shown")
    }
    
    func hideWindow() {
        window?.close()
        window = nil
        logger.info("Quick access window hidden")
    }
    
    func toggleWindow() {
        if window?.isVisible == true {
            hideWindow()
        } else {
            showWindow()
        }
    }
}

// MARK: - NSWindowDelegate
extension QuickAccessWindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window = nil
        logger.info("Quick access window closed")
    }
    
    func windowDidResignKey(_ notification: Notification) {
        // Hide window when it loses focus (optional behavior)
        // Uncomment the line below if you want the window to auto-hide when focus is lost
        // hideWindow()
    }
}