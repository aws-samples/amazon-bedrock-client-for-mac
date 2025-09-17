//
//  HotkeyManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Kiro on 2025/09/17.
//

import Cocoa
import Carbon
import SwiftUI
import Logging

class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let logger = Logger(label: "HotkeyManager")
    private let settingManager = SettingManager.shared
    
    // Hotkey settings from SettingManager
    @Published var hotkeyModifiers: UInt32 = UInt32(optionKey)
    @Published var hotkeyKeyCode: UInt32 = 49 // Space key
    
    private init() {
        // Load settings
        hotkeyModifiers = settingManager.hotkeyModifiers
        hotkeyKeyCode = settingManager.hotkeyKeyCode
        
        setupEventHandler()
        
        if settingManager.enableQuickAccess {
            registerHotkey()
        }
        
        // Listen for settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }
    
    @objc private func settingsChanged() {
        DispatchQueue.main.async {
            let newModifiers = self.settingManager.hotkeyModifiers
            let newKeyCode = self.settingManager.hotkeyKeyCode
            let enabled = self.settingManager.enableQuickAccess
            
            if newModifiers != self.hotkeyModifiers || newKeyCode != self.hotkeyKeyCode {
                self.hotkeyModifiers = newModifiers
                self.hotkeyKeyCode = newKeyCode
                
                if enabled {
                    self.registerHotkey()
                }
            }
            
            if enabled && self.hotKeyRef == nil {
                self.registerHotkey()
            } else if !enabled && self.hotKeyRef != nil {
                self.unregisterHotkey()
            }
        }
    }
    
    deinit {
        unregisterHotkey()
        removeEventHandler()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupEventHandler() {
        let eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        
        let callback: EventHandlerProcPtr = { (nextHandler, theEvent, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handleHotkeyPressed()
            return noErr
        }
        
        let userDataPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            userDataPtr,
            &eventHandler
        )
    }
    
    private func removeEventHandler() {
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
    
    func registerHotkey() {
        unregisterHotkey() // Unregister existing hotkey first
        
        let hotkeyID = EventHotKeyID(signature: OSType(fourCharCodeFrom: "BEDR"), id: 1)
        
        let status = RegisterEventHotKey(
            hotkeyKeyCode,
            hotkeyModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            logger.info("Hotkey registered successfully")
        } else {
            logger.error("Failed to register hotkey with status: \(status)")
        }
    }
    
    func unregisterHotkey() {
        if let hotkey = hotKeyRef {
            UnregisterEventHotKey(hotkey)
            hotKeyRef = nil
            logger.info("Hotkey unregistered")
        }
    }
    
    private func handleHotkeyPressed() {
        logger.info("Hotkey pressed - showing quick access window")
        DispatchQueue.main.async {
            QuickAccessWindowManager.shared.showWindow()
        }
    }
    
    func updateHotkey(modifiers: UInt32, keyCode: UInt32) {
        hotkeyModifiers = modifiers
        hotkeyKeyCode = keyCode
        
        // Update settings
        settingManager.hotkeyModifiers = modifiers
        settingManager.hotkeyKeyCode = keyCode
        
        registerHotkey()
    }
}

// Helper function to convert string to FourCharCode
private func fourCharCodeFrom(_ string: String) -> FourCharCode {
    let utf8 = string.utf8
    var result: FourCharCode = 0
    for (i, byte) in utf8.enumerated() {
        if i >= 4 { break }
        result = result << 8 + FourCharCode(byte)
    }
    return result
}