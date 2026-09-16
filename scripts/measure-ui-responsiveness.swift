// Compile: swiftc -O scripts/measure-ui-responsiveness.swift -o /tmp/bedrock-ui-probe
// Run against an isolated, already-open fixture:
//   /tmp/bedrock-ui-probe PID idle|scroll|typing SCREEN_X SCREEN_Y
//
// Uses public Accessibility/CoreGraphics APIs. These are event/AX round-trip
// measurements, not frame times. No recursive transcript snapshots or inference.
import AppKit
import ApplicationServices
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

let arguments = CommandLine.arguments
guard arguments.count == 5, let pid = pid_t(arguments[1]),
      ["idle", "scroll", "typing"].contains(arguments[2]),
      let x = Double(arguments[3]), let y = Double(arguments[4]) else {
    fail("Usage: bedrock-ui-probe PID idle|scroll|typing SCREEN_X SCREEN_Y")
}
let mode = arguments[2]
let application = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(application, 1)

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func string(_ element: AXUIElement, _ name: String) -> String? {
    attribute(element, name) as? String
}
func foreground() -> Bool { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
func now() -> Double { ProcessInfo.processInfo.systemUptime }

// Find the editor once. Skip transcript scroll areas: asking for thousands of
// accessibility labels can itself cause the hang a probe is trying to measure.
func composer() -> AXUIElement? {
    var visited = 0
    func find(_ element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        visited += 1
        guard visited < 500, depth < 25 else { return nil }
        let role = string(element, kAXRoleAttribute)
        if role == kAXScrollAreaRole, let raw = attribute(element, kAXSizeAttribute),
           CFGetTypeID(raw) == AXValueGetTypeID() {
            var size = CGSize.zero
            if AXValueGetValue(raw as! AXValue, .cgSize, &size), size.width > 400, size.height > 110 { return nil }
        }
        if role == kAXTextAreaRole { return element }
        for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).reversed() {
            if let result = find(child, depth: depth + 1) { return result }
        }
        return nil
    }
    for window in attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
        if string(window, kAXIdentifierAttribute) == "MainWindow" { return find(window) }
    }
    return nil
}

guard foreground() else { fail("Bring the target app to the foreground before measuring.") }
let point = CGPoint(x: x, y: y)
var samples: [Double] = []
var failures = 0
var eventsSent = 0
let started = now()

if mode == "typing" {
    guard let editor = composer(), (string(editor, kAXValueAttribute) ?? "").isEmpty else {
        fail("Typing requires an empty composer in an isolated test conversation.")
    }
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    for type: CGEventType in [.leftMouseDown, .leftMouseUp] {
        let event = CGEvent(mouseEventSource: nil, mouseType: type,
                            mouseCursorPosition: point, mouseButton: .left)!
        event.flags = []
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.025)
    }
    Thread.sleep(forTimeInterval: 0.2)
    let text = "PERF62 typing latency: abcdefghijklmnopqrstuvwxyz 0123456789."
    var expected = ""
    defer {
        // Never erase text the user entered while a probe was running.
        if let current = string(editor, kAXValueAttribute), current == expected {
            _ = AXUIElementSetAttributeValue(editor, kAXValueAttribute as CFString, "" as CFString)
        }
    }
    for character in text {
        guard foreground() else { failures += 1; break }
        let sent = now()
        var units = Array(String(character).utf16)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
            event.flags = []
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            event.post(tap: .cghidEventTap)
        }
        eventsSent += 1
        expected.append(character)
        while string(editor, kAXValueAttribute) != expected, now() - sent < 2 {
            Thread.sleep(forTimeInterval: 0.002)
        }
        let elapsed = now() - sent
        samples.append(elapsed * 1000)
        if string(editor, kAXValueAttribute) != expected { failures += 1; break }
        if elapsed < 0.035 { Thread.sleep(forTimeInterval: 0.035 - elapsed) }
    }
} else {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    for index in 0..<360 {
        guard foreground(), now() - started < 20 else { failures += 1; break }
        let due = started + Double(index) / 60
        if due > now() { Thread.sleep(forTimeInterval: due - now()) }
        if mode == "scroll" {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                wheel1: index < 180 ? 18 : -18, wheel2: 0, wheel3: 0)!
            event.location = point
            event.post(tap: .cghidEventTap)
            eventsSent += 1
        }
        if index % 6 == 0 {
            let sent = now()
            var windows: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windows)
            samples.append((now() - sent) * 1000)
            if status != .success { failures += 1 }
        }
    }
}
let sorted = samples.sorted()
func percentile(_ fraction: Double) -> Double {
    sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * fraction))]
}
let result: [String: Any] = [
    "mode": mode, "samples_ms": samples, "events_sent": eventsSent, "failures": failures,
    "duration_s": now() - started, "p50_ms": percentile(0.5),
    "p95_ms": percentile(0.95), "max_ms": sorted.last ?? 0
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
exit(failures == 0 ? 0 : 1)
