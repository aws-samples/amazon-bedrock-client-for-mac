//
//  SettingsWindowController.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 6/27/24.
//

import Foundation
import SwiftUI
import AppKit

@MainActor
class SettingsWindowController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var settingsWindow: NSWindow?

    func openSettings<V: View>(view: V) {
        if let existingWindow = settingsWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: view)
        hostingController.sizingOptions = [.minSize]

        // Create the titlebar in its final style before attaching SwiftUI.
        // Retrofitting fullSizeContentView after a hosting controller was
        // installed can leave its background above the native window controls.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 700),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Swift owns this window. AppKit's additional release on close would
        // race the delegate clearing settingsWindow and crash on Command-W.
        window.isReleasedWhenClosed = false
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = NSColor(DesignTokens.canvas)
        window.titleVisibility = .visible
        window.contentViewController = hostingController
        window.setContentSize(NSSize(width: 850, height: 700))
        window.contentMinSize = NSSize(width: 740, height: 580)
        window.setFrameAutosaveName("BedrockSettingsWindow")
        window.center()
        window.delegate = self

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        settingsWindow = nil
    }
}
