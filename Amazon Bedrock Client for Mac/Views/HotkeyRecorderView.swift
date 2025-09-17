//
//  HotkeyRecorderView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Kiro on 2025/09/17.
//

import SwiftUI
import Carbon

struct HotkeyRecorderView: View {
    @Binding var modifiers: UInt32
    @Binding var keyCode: UInt32
    
    @State private var isRecording = false
    @State private var displayText = ""
    
    var body: some View {
        HStack {
            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                Text(isRecording ? "Press keys..." : displayText)
                    .frame(minWidth: 120)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isRecording ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            
            if !isRecording {
                Button("Reset") {
                    modifiers = UInt32(optionKey)
                    keyCode = 49 // Space
                    updateDisplayText()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .onAppear {
            updateDisplayText()
        }
    }
    
    private func startRecording() {
        isRecording = true
        
        // Create a local event monitor to capture key presses
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if isRecording {
                handleKeyEvent(event)
                return nil // Consume the event
            }
            return event
        }
    }
    
    private func stopRecording() {
        isRecording = false
        updateDisplayText()
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        let newModifiers = event.modifierFlags.carbonModifiers
        let newKeyCode = UInt32(event.keyCode)
        
        // Only accept combinations with modifier keys
        if newModifiers != 0 && event.type == .keyDown {
            modifiers = newModifiers
            keyCode = newKeyCode
            stopRecording()
        }
    }
    
    private func updateDisplayText() {
        displayText = hotkeyDisplayString(modifiers: modifiers, keyCode: keyCode)
    }
}

// MARK: - Helper Extensions

extension NSEvent.ModifierFlags {
    var carbonModifiers: UInt32 {
        var carbonMods: UInt32 = 0
        
        if contains(.command) {
            carbonMods |= UInt32(cmdKey)
        }
        if contains(.option) {
            carbonMods |= UInt32(optionKey)
        }
        if contains(.control) {
            carbonMods |= UInt32(controlKey)
        }
        if contains(.shift) {
            carbonMods |= UInt32(shiftKey)
        }
        
        return carbonMods
    }
}

// MARK: - Helper Functions

func hotkeyDisplayString(modifiers: UInt32, keyCode: UInt32) -> String {
    var parts: [String] = []
    
    if modifiers & UInt32(controlKey) != 0 {
        parts.append("⌃")
    }
    if modifiers & UInt32(optionKey) != 0 {
        parts.append("⌥")
    }
    if modifiers & UInt32(shiftKey) != 0 {
        parts.append("⇧")
    }
    if modifiers & UInt32(cmdKey) != 0 {
        parts.append("⌘")
    }
    
    // Add key name
    let keyName = keyCodeToString(keyCode)
    parts.append(keyName)
    
    return parts.joined()
}

func keyCodeToString(_ keyCode: UInt32) -> String {
    switch keyCode {
    case 49: return "Space"
    case 36: return "Return"
    case 48: return "Tab"
    case 51: return "Delete"
    case 53: return "Escape"
    case 123: return "←"
    case 124: return "→"
    case 125: return "↓"
    case 126: return "↑"
    case 116: return "Page Up"
    case 121: return "Page Down"
    case 115: return "Home"
    case 119: return "End"
    case 122: return "F1"
    case 120: return "F2"
    case 99: return "F3"
    case 118: return "F4"
    case 96: return "F5"
    case 97: return "F6"
    case 98: return "F7"
    case 100: return "F8"
    case 101: return "F9"
    case 109: return "F10"
    case 103: return "F11"
    case 111: return "F12"
    default:
        // For letter keys, try to get the actual character
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        
        if let data = layoutData {
            let keyboardLayout = unsafeBitCast(data, to: CFData.self)
            var chars = [UniChar](repeating: 0, count: 4)
            var actualStringLength = 0
            
            let status = UCKeyTranslate(
                CFDataGetBytePtr(keyboardLayout).assumingMemoryBound(to: UCKeyboardLayout.self),
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &actualStringLength,
                4,
                &actualStringLength,
                &chars
            )
            
            if status == noErr && actualStringLength > 0 {
                return String(utf16CodeUnits: chars, count: actualStringLength).uppercased()
            }
        }
        
        return "Key \(keyCode)"
    }
}