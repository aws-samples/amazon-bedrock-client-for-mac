import AppKit
import Combine
import SwiftUI
import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class WindowLifecycleTests: XCTestCase {
    @MainActor
    func testWindowChromeUpdatesPreserveTheEditorWithoutReassigningTheStyleMask() {
        final class ObservedWindow: NSWindow {
            var styleChanges = 0
            override var styleMask: NSWindow.StyleMask { didSet { styleChanges += 1 } }
        }
        let window = ObservedWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                                    styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let chrome = WindowChrome.ChromeView()
        window.contentView?.addSubview(chrome)
        chrome.applyStyle()
        let editor = NSTextView(frame: NSRect(x: 10, y: 10, width: 300, height: 80))
        window.contentView?.addSubview(editor)
        XCTAssertTrue(window.makeFirstResponder(editor))
        let changes = window.styleChanges
        for index in 0..<100 {
            editor.string = "Typing update \(index)"
            chrome.applyStyle()
        }
        XCTAssertEqual(window.styleChanges, changes)
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertEqual(editor.string, "Typing update 99")
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
    }

    @MainActor
    func testQuickAccessPanelDoesNotReplaceTheMainWindow() throws {
        // The hosted unit-test process need not own desktop keyboard focus.
        // Escape/typing/shortcut restoration is exercised by the UI suite.
        let previous = NSApp.mainWindow
        let controller = QuickAccessWindowController.shared
        controller.showWindow()
        defer { controller.hideWindow() }
        let panel = try XCTUnwrap(NSApp.windows.first {
            $0.identifier?.rawValue == "QuickAccessWindow" && $0.isVisible
        })
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.isReleasedWhenClosed)
        XCTAssertFalse(NSApp.mainWindow === panel)
        if let previous { XCTAssertTrue(NSApp.mainWindow === previous) }
        controller.hideWindow()
        XCTAssertFalse(panel.isVisible)
    }

    @MainActor
    func testDelayedQuickAccessFocusLossCannotCloseAReopenedPanel() async throws {
        let controller = QuickAccessWindowController.shared
        controller.showWindow()
        defer { controller.hideWindow() }
        let original = try XCTUnwrap(NSApp.windows.first {
            $0.identifier?.rawValue == "QuickAccessWindow" && $0.isVisible
        })
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: original))
        controller.hideWindow()
        controller.showWindow()
        let reopened = try XCTUnwrap(NSApp.windows.first {
            $0.identifier?.rawValue == "QuickAccessWindow" && $0.isVisible
        })
        XCTAssertFalse(original === reopened)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(reopened.isVisible, "A delayed callback from the old panel must not hide the new one.")
    }

    @MainActor
    func testTypingOnlyInvalidatesTheAffectedDraftIndicator() {
        let store = AppStore.shared
        let id = "draft-observation-\(UUID())"
        let otherID = "other-draft-\(UUID())"
        let indicator = store.draftIndicator(for: id)
        let other = store.draftIndicator(for: otherID)
        var workspaceChanges = 0
        var badgeChanges: [Bool] = []
        var otherChanges = 0
        let workspace = store.objectWillChange.sink { workspaceChanges += 1 }
        let badge = indicator.$hasText.dropFirst().sink { badgeChanges.append($0) }
        let unrelated = other.$hasText.dropFirst().sink { _ in otherChanges += 1 }
        defer {
            workspace.cancel()
            badge.cancel()
            unrelated.cancel()
            store.state.threads.removeValue(forKey: id)
        }

        store.updateDraft(id, text: "A")
        store.updateDraft(id, text: "A longer draft")
        store.updateDraft(id, text: "")
        XCTAssertEqual(workspaceChanges, 0, "The first and last character must not invalidate the entire app.")
        XCTAssertEqual(badgeChanges, [true, false])
        XCTAssertEqual(otherChanges, 0)
        XCTAssertEqual(store.thread(id).draft, "")

        store.updateThread(id) { $0.draft = "A restored draft" }
        XCTAssertTrue(indicator.hasText, "Importing/restoring a draft must also update its indicator.")
        XCTAssertEqual(store.thread(id).draft, "A restored draft")
    }

    @MainActor
    func testSettingsWindowCanCloseAndReopenWithoutAppKitReleasingSwiftOwnership() throws {
        _ = NSApplication.shared
        let manager = SettingsWindowController()

        for _ in 0..<6 {
            try autoreleasepool {
                manager.openSettings(view: Color.clear.frame(minWidth: 740, minHeight: 580))
                let window = try XCTUnwrap(NSApplication.shared.windows.first {
                    $0.title == "Settings" && $0.isVisible
                })
                XCTAssertFalse(window.isReleasedWhenClosed)
                XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
                XCTAssertTrue(window.titlebarAppearsTransparent)
                XCTAssertEqual(window.contentMinSize.width, 740)
                window.performClose(nil)
                XCTAssertFalse(window.isVisible)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }
}
