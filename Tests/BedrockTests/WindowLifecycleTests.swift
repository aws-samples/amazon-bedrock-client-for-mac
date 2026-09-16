import AppKit
import Combine
import SwiftUI
import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class WindowLifecycleTests: XCTestCase {
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
