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
    @State private var eventMonitor: Any?
    
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
            print("DEBUG: HotkeyRecorderView onAppear - modifiers: \(modifiers), keyCode: \(keyCode)")
        }
        .onChange(of: modifiers) { _, newValue in
            updateDisplayText()
            print("DEBUG: Modifiers changed to: \(newValue)")
        }
        .onChange(of: keyCode) { _, newValue in
            updateDisplayText()
            print("DEBUG: KeyCode changed to: \(newValue)")
        }
        .onDisappear {
            stopRecording()
        }
    }
    
    private func startRecording() {
        // Remove existing monitor first
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        isRecording = true
        
        // Create local event monitor
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if self.isRecording {
                return self.handleKeyEvent(event) ? nil : event
            }
            return event
        }
    }
    
    private func stopRecording() {
        isRecording = false
        
        // Remove the event monitor
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        updateDisplayText()
    }
    
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Skip if not recording
        guard isRecording else { return false }
        
        let newModifiers = event.modifierFlags.carbonModifiers
        let newKeyCode = UInt32(event.keyCode)
        
        // Only accept key down events with modifier keys
        if event.type == .keyDown && newModifiers != 0 {
            // Validate that it's a reasonable key combination
            if isValidHotkeyCombo(modifiers: newModifiers, keyCode: newKeyCode) {
                DispatchQueue.main.async {
                    self.modifiers = newModifiers
                    self.keyCode = newKeyCode
                    self.stopRecording()
                }
                return true // Consume the event
            }
        }
        
        return false // Don't consume the event
    }
    
    private func isValidHotkeyCombo(modifiers: UInt32, keyCode: UInt32) -> Bool {
        // Must have at least one modifier
        guard modifiers != 0 else { return false }
        
        // Avoid system reserved combinations
        let hasCmd = (modifiers & UInt32(cmdKey)) != 0
        let hasOpt = (modifiers & UInt32(optionKey)) != 0
        let hasCtrl = (modifiers & UInt32(controlKey)) != 0
        let _ = (modifiers & UInt32(shiftKey)) != 0  // hasShift - reserved for future use
        
        // Avoid common system shortcuts
        if hasCmd && !hasOpt && !hasCtrl {
            // Avoid Cmd+common keys
            switch keyCode {
            case 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11: // A-Z except some
                return false
            case 12, 13, 14, 15, 16, 17: // Q, W, E, R, Y, T
                return false
            default:
                break
            }
        }
        
        return true
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
        // Simple key mapping for common keys
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 50: return "`"
        default: return "Key \(keyCode)"
        }
    }
}