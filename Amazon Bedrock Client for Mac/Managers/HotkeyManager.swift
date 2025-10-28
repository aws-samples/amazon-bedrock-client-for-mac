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

@MainActor
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
        
        if settingManager.enableQuickAccess {
            setupEventHandler()
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
            
            // 핫키 설정이 변경되었거나 활성화 상태가 변경된 경우
            if newModifiers != self.hotkeyModifiers || newKeyCode != self.hotkeyKeyCode || 
               (enabled && self.hotKeyRef == nil) || (!enabled && self.hotKeyRef != nil) {
                
                self.hotkeyModifiers = newModifiers
                self.hotkeyKeyCode = newKeyCode
                
                // 기존 핫키 해제
                self.unregisterHotkey()
                self.removeEventHandler()
                
                // 활성화된 경우에만 새로 등록
                if enabled {
                    self.setupEventHandler()
                    self.registerHotkey()
                }
            }
        }
    }
    
    deinit {
        // Note: Cannot safely call async methods in deinit
        // Cleanup will happen when the object is deallocated
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupEventHandler() {
        // 기존 핸들러가 있으면 제거
        removeEventHandler()
        
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), 
            eventKind: OSType(kEventHotKeyPressed)
        )
        
        let callback: EventHandlerProcPtr = { (nextHandler, theEvent, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handleHotkeyPressed()
            return noErr
        }
        
        let userDataPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            userDataPtr,
            &eventHandler
        )
        
        if status != noErr {
            logger.error("Failed to install event handler with status: \(status)")
        }
    }
    
    private func removeEventHandler() {
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
    
    func registerHotkey() {
        unregisterHotkey() // 기존 핫키 해제
        
        let hotkeyID = EventHotKeyID(signature: OSType(fourCharCodeFrom("QKAC")), id: 1)
        
        let status = RegisterEventHotKey(
            hotkeyKeyCode,
            hotkeyModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            logger.info("Hotkey registered successfully: modifiers=\(hotkeyModifiers), keyCode=\(hotkeyKeyCode)")
        } else {
            logger.error("Failed to register hotkey with status: \(status)")
        }
    }
    
    func unregisterHotkey() {
        if let hotkey = hotKeyRef {
            let status = UnregisterEventHotKey(hotkey)
            hotKeyRef = nil
            if status == noErr {
                logger.info("Hotkey unregistered successfully")
            } else {
                logger.error("Failed to unregister hotkey with status: \(status)")
            }
        }
    }
    
    private func handleHotkeyPressed() {
        logger.info("Hotkey pressed - showing quick access window")
        DispatchQueue.main.async {
            QuickAccessWindowManager.shared.toggleWindow()
        }
    }
    
    func updateHotkey(modifiers: UInt32, keyCode: UInt32) {
        logger.info("Updating hotkey: modifiers=\(modifiers), keyCode=\(keyCode)")
        
        hotkeyModifiers = modifiers
        hotkeyKeyCode = keyCode
        
        // Update settings
        settingManager.hotkeyModifiers = modifiers
        settingManager.hotkeyKeyCode = keyCode
        
        // Re-register with new settings if enabled
        if settingManager.enableQuickAccess {
            unregisterHotkey()
            removeEventHandler()
            setupEventHandler()
            registerHotkey()
        }
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