import AppKit
import Carbon
import XCTest

final class BedrockUITests: XCTestCase {
    @MainActor private var runtime: BedrockUITestFixture?

    @MainActor
    private func launch(appearance: String = "light", withRuntime: Bool = false,
                        scrollbars: String? = nil) throws -> (XCUIApplication, URL) {
        continueAfterFailure = false
        // The signed runner's default temporaryDirectory is inside its app
        // container. Importing from there raises macOS cross-app privacy UI.
        // This explicitly entitled folder contains synthetic test data only.
        let directory = URL(fileURLWithPath: "/private/tmp/bedrock-ui-fixtures", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        // XCTest's character-based Shift shortcuts are layout dependent. Use
        // an ASCII keyboard for synthetic keystrokes, then restore the user's
        // input method after the app terminates. IME behavior has native tests.
        let previousInput = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let keyboard = TISCopyCurrentASCIICapableKeyboardInputSource().takeRetainedValue()
        addTeardownBlock { @MainActor in
            if CFEqual(TISCopyCurrentKeyboardInputSource().takeRetainedValue(), keyboard) {
                TISSelectInputSource(previousInput)
            }
        }
        let app = XCUIApplication()
        app.launchEnvironment["BEDROCK_WORKBENCH_DATA_DIR"] = directory.path
        app.launchEnvironment["BEDROCK_TEST_OFFLINE"] = "1"
        app.launchArguments = ["-checkForUpdates", "NO", "-enableQuickAccess", "NO", "-mcpEnabled", "NO",
                               "-appearance", appearance, "-selectedRegion", "us-west-2",
                                "-selectedProfile", "default",
                                "-defaultModelId", "us.amazon.nova-2-lite-v1:0"]
        // AppKit saves window geometry outside the isolated conversation data.
        // Ignore a previous scenario's resized frame so a fresh launch exercises
        // the app's real default size, rather than inheriting that test's size.
        app.launchArguments += ["-NSWindow Frame MainWindow", ""]
        if let scrollbars {
            app.launchArguments += ["-AppleShowScrollBars", scrollbars]
        }
        let fixture = try withRuntime ? BedrockUITestFixture(directory: directory) : nil
        runtime = fixture
        fixture?.configure(app)
        // Register cleanup before any launch assertion. A failed setup must
        // not leave an app or fixture process behind for the next scenario.
        addTeardownBlock { @MainActor in
            if app.state != .notRunning { app.terminate() }
            if let fixture {
                if let data = try? Data(contentsOf: fixture.requestsURL) {
                    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.plain-text")
                    attachment.name = "Actual SDK requests to loopback fixture"
                    attachment.lifetime = .keepAlways
                    self.add(attachment)
                }
                fixture.stop()
            }
        }
        app.launch()
        app.activate()
        XCTAssertEqual(TISSelectInputSource(keyboard), noErr)
        XCTAssertEqual(app.state, .runningForeground, "UI input requires the test app to own keyboard focus.")
        XCTAssertTrue(app.staticTexts["How can I help?"].waitForExistence(timeout: 15))
        // XCTest window captures can fail on a secondary display with negative
        // coordinates. Move only the test window, retaining its default size.
        let window = app.windows["MainWindow"]
        let display = CGDisplayBounds(CGMainDisplayID())
        let frame = window.frame
        if !display.contains(frame) {
            let titlebar = window.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.width / 2, dy: 14))
            let destination = titlebar.withOffset(CGVector(dx: display.midX - frame.midX,
                                                          dy: display.midY - frame.midY))
            titlebar.press(forDuration: 0.1, thenDragTo: destination,
                           withVelocity: .fast, thenHoldForDuration: 0.1)
            XCTAssertTrue(display.insetBy(dx: -1, dy: -1).contains(window.frame),
                          "The initial window \(window.frame) must fit the main display \(display).")
        }
        return (app, directory)
    }

    @MainActor
    private func composer(_ app: XCUIApplication) -> XCUIElement {
        app.textViews.matching(identifier: "composer.editor").firstMatch
    }

    @MainActor
    private func response(_ marker: String, in app: XCUIApplication, timeout: TimeInterval = 12) -> XCUIElement {
        let result = app.textViews.matching(NSPredicate(format: "label == 'Assistant response text' AND value CONTAINS %@", marker)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: timeout), "Missing response marker: \(marker)")
        return result
    }

    @MainActor
    private func send(_ text: String, in app: XCUIApplication) {
        let editor = composer(app)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText(text)
        app.typeKey(.return, modifierFlags: [])
    }

    @MainActor
    private func chooseModel(_ name: String, in app: XCUIApplication) {
        app.buttons["modelPicker.button"].click()
        let search = app.textFields["modelPicker.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click()
        search.typeText(name)
        let choice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Select \(name)")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.click()
    }

    @MainActor
    private func preserveClipboard() {
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        addTeardownBlock { @MainActor in board.clearContents(); board.writeObjects(saved) }
    }

    @MainActor
    private func settings(_ app: XCUIApplication) -> XCUIElement {
        app.typeKey(",", modifierFlags: .command)
        let window = app.windows["Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        return window
    }

    @MainActor
    private func openPane(_ name: String, in window: XCUIElement) {
        let row = window.outlineRows.matching(NSPredicate(format: "label == %@", name)).firstMatch
        if row.exists { row.click() }
        else { window.staticTexts[name].firstMatch.click() }
    }

    @MainActor
    private func importThread(_ file: URL, in app: XCUIApplication) {
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["Import Thread…"].click()
        // The system also exposes an Import button in its virtual Touch Bar.
        // Target the actual file panel, not every button in the application.
        let button = app.windows.buttons["Import thread"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.windows.textFields["PathTextField"].firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 4))
        path.click()
        app.typeKey("a", modifierFlags: .command)
        path.typeText(file.path)
        app.typeKey(.return, modifierFlags: [])
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            button.exists && button.isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 4), .completed)
        button.click()
    }

    private func longConversation(in directory: URL) throws -> URL {
        let model = "us.amazon.nova-2-lite-v1:0"
        var messages: [[String: Any]] = []
        for index in 0..<500 {
            for role in ["user", "assistant"] {
                messages.append([
                    "id": UUID().uuidString, "role": role, "modelID": model, "isError": false,
                    "timestamp": Date().timeIntervalSinceReferenceDate,
                    "text": role == "user" ? "Fixture question \(index)" :
                        """
                        ## Fixture answer \(index)

                        - First **item** with `inline code`.
                        - Second item with [a safe link](https://example.com).
                          - Nested item in 한국어 and English.

                        > Synthetic content with enough layout variation to exercise cold search results.

                        ```swift
                        let row = \(index)
                        print("ROW_" + String(row))
                        ```

                        | Column | Value |
                        | --- | --- |
                        | Row | \(index) |
                        | Status | fixture |
                        """
                ])
            }
        }
        let archive: [String: Any] = [
            "version": 1, "title": "Typing and scroll performance fixture",
            "modelID": model, "modelName": "Nova 2 Lite", "provider": "Amazon", "messages": messages
        ]
        let file = directory.appendingPathComponent("performance.json")
        try JSONSerialization.data(withJSONObject: archive).write(to: file)
        return file
    }

    @MainActor
    func testNewChatDraftAndTrashShortcutsPreservePreviousDraft() throws {
        let (app, _) = try launch()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'New chat'")).count, 1)
        app.typeKey("n", modifierFlags: .command)
        let editor = composer(app)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText("DRAFT_RETAINED_BY_COMMAND_N")
        app.typeKey("n", modifierFlags: .command)
        XCTAssertEqual(composer(app).value as? String, "")
        app.typeKey("d", modifierFlags: .command)
        XCTAssertTrue(composer(app).waitForExistence(timeout: 3))
        XCTAssertEqual(composer(app).value as? String, "DRAFT_RETAINED_BY_COMMAND_N")
        app.typeKey("b", modifierFlags: .command)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.buttons["New chat"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed)
        app.typeKey("b", modifierFlags: .command)
        XCTAssertTrue(app.buttons["New chat"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAllSettingsPanesAndLightDarkSystemControls() throws {
        let (app, _) = try launch()
        let window = settings(app)
        for pane in ["General", "Appearance", "AWS connection", "Models", "Skills", "Tools & MCP", "Keyboard", "Data & history", "Advanced"] {
            openPane(pane, in: window)
            let heading = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                window.staticTexts.matching(identifier: pane).allElementsBoundByIndex.contains {
                    $0.frame.minX > window.frame.minX + 200 && $0.isHittable
                }
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [heading], timeout: 4), .completed,
                           "The detail pane must open; its sidebar label alone is not sufficient: \(pane)")
            if pane == "Keyboard" {
                XCTAssertEqual(window.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reset'")).count, 1)
                let reset = window.buttons["quickAccess.resetShortcut"]
                XCTAssertTrue(reset.exists)
                reset.click()
                XCTAssertEqual(window.buttons["quickAccess.shortcutRecorder"].value as? String, "⌥Space")
            }
            let image = XCTAttachment(screenshot: window.screenshot())
            image.name = "Settings – \(pane)"
            image.lifetime = .keepAlways
            add(image)
        }
        openPane("Appearance", in: window)
        for theme in ["Dark", "Light", "System"] {
            let choice = window.buttons[theme]
            XCTAssertTrue(choice.exists)
            choice.click()
            XCTAssertTrue(choice.isSelected)
            let image = XCTAttachment(screenshot: window.screenshot())
            image.name = "Appearance – \(theme)"
            image.lifetime = .keepAlways
            add(image)
        }
        for _ in 0..<4 {
            window.typeKey("w", modifierFlags: .command)
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !window.exists }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 3), .completed)
            XCTAssertNotEqual(app.state, .notRunning, "Closing Settings must not terminate the app.")
            XCTAssertTrue(app.windows["MainWindow"].exists)
            _ = settings(app)
        }
    }

    @MainActor
    func testCenteredSearchDismissesOutsideAndWithEscapeWithoutLosingDraft() throws {
        let (app, _) = try launch()
        app.typeKey("n", modifierFlags: .command)
        composer(app).click()
        composer(app).typeText("SEARCH_MUST_KEEP_THIS_DRAFT")
        let window = app.windows["MainWindow"]
        let search = app.buttons["Search"]
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Search'")).count, 1)
        XCTAssertLessThanOrEqual(search.frame.width, 44)
        XCTAssertGreaterThan(search.frame.midX, window.frame.midX)
        search.click()
        // SwiftUI exposes the containing accessibility element as a Group on
        // macOS. Its stable identifier is independent of that platform role.
        let panel = app.descendants(matching: .any).matching(identifier: "workbench.commandPalette").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        XCTAssertEqual(panel.frame.midX, window.frame.midX, accuracy: 3)
        XCTAssertLessThan(abs(panel.frame.midY - window.frame.midY), 32)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.7)).click()
        XCTAssertFalse(panel.exists)
        XCTAssertEqual(composer(app).value as? String, "SEARCH_MUST_KEEP_THIS_DRAFT")
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(panel.exists)
        XCTAssertEqual(composer(app).value as? String, "SEARCH_MUST_KEEP_THIS_DRAFT")
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.textFields["Find in chat"].waitForExistence(timeout: 3))
        XCTAssertFalse(panel.exists)
    }

    @MainActor
    func testTitlebarHasOneCompactSidebarControlAndAdjacentBackButton() throws {
        let (app, _) = try launch()
        let window = app.windows["MainWindow"]
        let sidebar = app.buttons["toolbar.toggleSidebar"]
        let back = app.buttons["toolbar.back"]
        XCTAssertEqual(sidebar.label, "Hide sidebar")
        XCTAssertEqual(back.label, "Back")
        XCTAssertFalse(back.isEnabled)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Hide sidebar'")).count, 1)
        // The glyph remains 14pt. Native toolbar groups supply up to a 44pt
        // transparent hit target without an always-visible button background.
        XCTAssertLessThanOrEqual(sidebar.frame.width, 44)
        XCTAssertLessThanOrEqual(sidebar.frame.height, 44)
        XCTAssertEqual(sidebar.frame.width, back.frame.width, accuracy: 1)
        XCTAssertEqual(sidebar.frame.height, back.frame.height, accuracy: 1)
        XCTAssertGreaterThan(back.frame.minX, sidebar.frame.minX)
        XCTAssertLessThan(back.frame.minX - sidebar.frame.maxX, 8)
        XCTAssertLessThan(back.frame.maxX, window.frame.minX + 240)
        XCTAssertGreaterThanOrEqual(app.buttons["New chat"].frame.width, 200)
        let availableWidth = NSScreen.main?.visibleFrame.width ?? 1050
        XCTAssertGreaterThanOrEqual(window.frame.width, min(1050, availableWidth))
        let searchX = window.buttons["Search"].frame.minX
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(composer(app).waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["toolbar.back"].label, "Back")
        XCTAssertEqual(app.buttons["toolbar.search"].label, "Search")
        XCTAssertEqual(window.buttons["Search"].frame.minX, searchX, accuracy: 1)
        XCTAssertLessThanOrEqual(window.buttons["Search"].frame.maxX, window.frame.maxX)
        window.buttons["Demo library"].click()
        XCTAssertEqual(window.buttons["Search"].frame.minX, searchX, accuracy: 1)
        window.buttons["Back"].click()
        XCTAssertTrue(composer(app).waitForExistence(timeout: 3))
        XCTAssertEqual(window.buttons["Search"].frame.minX, searchX, accuracy: 1)
        let settingsWindow = settings(app)
        settingsWindow.typeKey("w", modifierFlags: .command)
        app.buttons["toolbar.chatOptions"].click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(app.buttons["toolbar.search"].label, "Search")
        XCTAssertEqual(app.buttons["toolbar.chatOptions"].label, "Chat options")
        app.typeKey("b", modifierFlags: .command)
        XCTAssertEqual(app.buttons["toolbar.toggleSidebar"].label, "Show sidebar")
        XCTAssertEqual(app.buttons["toolbar.back"].label, "Back")
        app.typeKey("b", modifierFlags: .command)
        XCTAssertEqual(app.buttons["toolbar.toggleSidebar"].label, "Hide sidebar")
        XCTAssertEqual(app.buttons["toolbar.back"].label, "Back")
    }

    @MainActor
    func testModelPickerIsInComposerAndPreservesDraftWhileSwitching() throws {
        let (app, _) = try launch()
        app.typeKey("n", modifierFlags: .command)
        composer(app).click()
        composer(app).typeText("MODEL_SWITCH_DRAFT")
        let modelButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Model:'")).firstMatch
        XCTAssertTrue(modelButton.exists)
        let composerFrame = composer(app).frame
        XCTAssertGreaterThan(modelButton.frame.minY, composerFrame.minY)
        modelButton.click()
        XCTAssertFalse(app.buttons["All providers"].exists)
        let search = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'Search'")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click()
        search.typeText("Nova 2 Pro Preview")
        XCTAssertTrue(app.staticTexts["No models found"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Select Nova 2 Pro Preview"].exists)
        search.typeKey("a", modifierFlags: .command)
        search.typeText("GPT-6 Astra")
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS 'GPT-6 Astra'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        result.click()
        XCTAssertEqual(composer(app).value as? String, "MODEL_SWITCH_DRAFT")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Model: GPT-6 Astra'")).firstMatch.exists)
    }

    @MainActor
    func testSlashSkillSelectionAndRemovalDoNotSendAPrompt() throws {
        let (app, _) = try launch()
        app.typeKey("n", modifierFlags: .command)
        composer(app).click()
        composer(app).typeText("/code")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS '/code-review'")).firstMatch.waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["Remove skill code-review"].waitForExistence(timeout: 3))
        XCTAssertEqual(composer(app).value as? String, "")
        XCTAssertFalse(app.buttons["Send message"].isEnabled)
        app.buttons["Remove skill code-review"].click()
        XCTAssertFalse(app.buttons["Remove skill code-review"].exists)
    }

    @MainActor
    func testLongPastedTextBecomesAnAttachmentAndSurvivesGracefulRelaunch() throws {
        try verifyLongDraftRestoration(createThread: true)
    }

    @MainActor
    func testWelcomeAttachmentsRestoreBeforeSendBecomesAvailable() throws {
        try verifyLongDraftRestoration(createThread: false)
    }

    @MainActor
    private func verifyLongDraftRestoration(createThread: Bool) throws {
        let (app, directory) = try launch(appearance: "dark")
        if createThread { app.typeKey("n", modifierFlags: .command) }
        let pasteboard = NSPasteboard.general
        let preserved = (pasteboard.pasteboardItems ?? []).map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        defer { pasteboard.clearContents(); pasteboard.writeObjects(preserved) }
        let text = String(repeating: "Long pasted text 가나다 with exact whitespace.\n", count: 1500) + "PASTE_END_UI"
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        composer(app).click()
        app.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["PASTED"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(composer(app).value as? String, "")
        app.typeKey("q", modifierFlags: .command)
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.state == .notRunning }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 8), .completed)
        let draftDirectory = directory.appendingPathComponent("workbench/drafts")
        let files = try FileManager.default.contentsOfDirectory(at: draftDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.filter { $0.pathExtension == "json" }.count, 1)
        app.launch()
        XCTAssertTrue(app.staticTexts["PASTED"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Send message"].isEnabled)
        app.buttons["Edit pasted text"].click()
        let editor = app.textViews["pastedText.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, text)
        app.buttons["Save changes"].click()
    }

    @MainActor
    func testLongConversationTypingAndScrollPerformanceKeepsCommandsWorking() throws {
        let (app, directory) = try launch()
        let file = try longConversation(in: directory)
        importThread(file, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["conversation.transcript"].firstMatch.waitForExistence(timeout: 10))
        _ = response("Fixture answer 499", in: app)

        // Store clock measurements in the xcresult, using a bounded live
        // row set rather than full accessibility-tree snapshots per key.
        let editor = composer(app)
        let text = "Typing must not rebuild the application scene."
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric()], options: options) {
            editor.click()
            app.typeKey("a", modifierFlags: .command)
            app.typeKey(.delete, modifierFlags: [])
            editor.typeText(text)
            XCTAssertEqual(editor.value as? String, text)
        }
        let window = app.windows["MainWindow"]
        for _ in 0..<3 {
            window.scroll(byDeltaX: 0, deltaY: 500)
            window.scroll(byDeltaX: 0, deltaY: -500)
        }
        app.typeKey("b", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Show sidebar"].waitForExistence(timeout: 3))
        app.typeKey("b", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Hide sidebar"].waitForExistence(timeout: 3))
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.textFields["Find in chat"].waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("n", modifierFlags: .command)
        XCTAssertEqual(composer(app).value as? String, "")
        app.typeKey("d", modifierFlags: .command)
        XCTAssertEqual(composer(app).value as? String, text)
        XCTAssertNotEqual(app.state, .notRunning)
    }

    @MainActor
    func testFullConversationScrollSearchAndReturnKeepTheReadingPosition() throws {
        let (app, directory) = try launch(scrollbars: "Always")
        let window = app.windows["MainWindow"]
        // Match the small hosted display locally too. Use the actual native
        // resize gesture so the test exercises the same safe areas and layout.
        let initialFrame = window.frame
        let width = min(initialFrame.width, 1_024)
        let height = min(initialFrame.height, 674)
        if initialFrame.width > width || initialFrame.height > height {
            let origin = window.coordinate(withNormalizedOffset: .zero)
            let corner = origin.withOffset(CGVector(dx: initialFrame.width - 6, dy: initialFrame.height - 6))
            corner.press(forDuration: 0.1,
                         thenDragTo: origin.withOffset(CGVector(dx: width - 6, dy: height - 6)),
                         withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertLessThanOrEqual(window.frame.width, 1_026)
        XCTAssertLessThanOrEqual(window.frame.height, 676)
        importThread(try longConversation(in: directory), in: app)
        let transcript = window.descendants(matching: .any)["conversation.transcript"].firstMatch
        XCTAssertTrue(transcript.waitForExistence(timeout: 10))
        XCTAssertTrue(response("Fixture answer 499", in: app).isHittable)
        let first = window.staticTexts["Fixture question 0"]
        // Move the native scroll thumb across the complete 1,000-message
        // transcript. A million-pixel wheel event takes minutes to synthesize.
        transcript.scroll(byDeltaX: 0, deltaY: 300)
        let scrollbar = transcript.scrollBars.firstMatch
        XCTAssertTrue(scrollbar.waitForExistence(timeout: 3))
        let thumb = scrollbar.descendants(matching: .valueIndicator).firstMatch
        XCTAssertTrue(thumb.waitForExistence(timeout: 3))
        // AppKit exposes a scroll thumb's frame but not an AXPress action.
        // Drive one real drag instead of treating the scroller as a button.
        let origin = window.coordinate(withNormalizedOffset: .zero)
        let frame = thumb.frame
        let start = origin.withOffset(CGVector(dx: frame.midX - window.frame.minX,
                                               dy: frame.midY - window.frame.minY))
        // Drag past the slot's top, not four points into it. The minimum
        // thumb size and Retina scale otherwise leave a small nonzero offset
        // that can hide the first prompt in a very long conversation.
        let end = origin.withOffset(CGVector(dx: frame.midX - window.frame.minX,
                                             dy: scrollbar.frame.minY - 10 - window.frame.minY))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        let image = XCTAttachment(screenshot: window.screenshot())
        image.name = "First message of the complete transcript after one thumb drag"
        image.lifetime = .keepAlways
        add(image)
        XCTAssertTrue(first.isHittable, "The first message must be reachable by scrolling, without loading a page.")
        app.buttons["Scroll to latest message"].click()
        XCTAssertTrue(response("Fixture answer 499", in: app).isHittable)

        app.typeKey("f", modifierFlags: .command)
        let find = app.textFields["Find in chat"]
        XCTAssertTrue(find.waitForExistence(timeout: 3))
        find.typeText("Fixture question 250")
        XCTAssertEqual(find.value as? String, "Fixture question 250")
        let anchor = window.staticTexts["Fixture question 250"]
        let found = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in anchor.isHittable }, object: nil)
        let foundResult = XCTWaiter.wait(for: [found], timeout: 8)
        let searchImage = XCTAttachment(screenshot: window.screenshot())
        searchImage.name = "Full transcript search position"
        searchImage.lifetime = .keepAlways
        add(searchImage)
        XCTAssertEqual(foundResult, .completed)
        app.typeKey(.escape, modifierFlags: [])
        let before = anchor.frame.minY
        window.buttons["Activity"].click()
        window.buttons["Back"].click()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            anchor.exists && abs(anchor.frame.minY - before) < 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 8), .completed)
    }

    @MainActor
    func testToolDisclosureKeepsDistinctActionsAndOpensOriginalOutput() throws {
        let (app, directory) = try launch()
        let model = "us.amazon.nova-2-lite-v1:0"
        let output = "ID: fixture-code-review\nEXACT_TOOL_OUTPUT"
        let call: [String: Any] = [
            "toolId": "fixture-skill-list", "toolName": "local_list_skills",
            "inputs": [:] as [String: Any], "status": "success", "result": output,
            "elapsedSeconds": 0.01
        ]
        let messages: [[String: Any]] = [
            ("user", "List the available skills.", false),
            ("assistant", "", true),
            ("user", "", true),
            ("assistant", "The skill is available.", false)
        ].map { role, text, hasTool in
            var message: [String: Any] = [
                "id": UUID().uuidString, "role": role, "text": text, "modelID": model,
                "isError": false, "timestamp": Date().timeIntervalSinceReferenceDate
            ]
            if hasTool { message["toolUses"] = [call] }
            return message
        }
        let archive: [String: Any] = [
            "version": 1, "title": "Tool detail fixture", "modelID": model,
            "modelName": "Nova 2 Lite", "provider": "Amazon", "messages": messages
        ]
        let file = directory.appendingPathComponent("tool-details.json")
        try JSONSerialization.data(withJSONObject: archive).write(to: file)
        importThread(file, in: app)
        let row = app.descendants(matching: .any)
            .matching(identifier: "toolCall.fixture-skill-list").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "List skills")
        XCTAssertGreaterThanOrEqual(row.frame.height, 32, "The entire disclosure row must be clickable.")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).click()
        let open = app.buttons["Open details"]
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Copy tool input"].exists)
        XCTAssertTrue(app.buttons["Copy tool output"].exists)
        let inputPreview = try XCTUnwrap(app.textViews["Tool input preview"].value as? String)
        let previewObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(inputPreview.utf8)) as? [String: Any])
        XCTAssertTrue(previewObject.isEmpty)
        XCTAssertEqual(app.textViews["Tool output preview"].value as? String, output)
        XCTAssertLessThan(app.textViews["Tool input preview"].frame.minX - row.frame.minX, 24)
        for _ in 0..<3 where !open.isHittable {
            app.textViews["Tool input preview"].scroll(byDeltaX: 0, deltaY: -240)
        }
        open.click()
        let detail = app.textViews["Tool detail text"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        XCTAssertEqual(detail.value as? String, output)
        app.buttons["Input"].click()
        XCTAssertEqual(detail.value as? String, inputPreview)
        let input = try XCTUnwrap((detail.value as? String)?.data(using: .utf8))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: input) as? [String: Any])
        XCTAssertTrue(object.isEmpty)
        app.buttons["Output"].click()
        XCTAssertEqual(detail.value as? String, output)
        app.buttons["Done"].click()
        XCTAssertFalse(detail.exists)
    }

    @MainActor
    func testGeneratedImageCanOpenZoomCopyCloseAndReopen() throws {
        let (app, directory) = try launch()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4096, pixelsHigh: 3072,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 4096, height: 3072).fill()
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let model = "stability.stable-image-ultra-v1:1"
        let archive: [String: Any] = [
            "version": 1, "title": "Image preview UI regression",
            "modelID": model, "modelName": "Stable Image Ultra", "provider": "Stability AI",
            "messages": [
                ["id": UUID().uuidString, "text": "Synthetic image fixture.", "role": "user",
                 "timestamp": Date().timeIntervalSinceReferenceDate, "isError": false, "modelID": model],
                ["id": UUID().uuidString, "text": "4K preview fixture.", "role": "assistant",
                 "timestamp": Date().timeIntervalSinceReferenceDate, "isError": false, "modelID": model,
                 "imageBase64Strings": [png.base64EncodedString()]]
            ]
        ]
        let file = directory.appendingPathComponent("image-preview.json")
        try JSONSerialization.data(withJSONObject: archive).write(to: file)
        importThread(file, in: app)
        let open = app.buttons["Open generated image"]
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        let board = NSPasteboard.general
        let preserved = (board.pasteboardItems ?? []).map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        defer { board.clearContents(); board.writeObjects(preserved) }
        for iteration in 0..<3 {
            open.click()
            XCTAssertTrue(app.buttons["Zoom in"].waitForExistence(timeout: 5))
            app.buttons["Zoom in"].click()
            XCTAssertTrue(app.staticTexts["125%"].waitForExistence(timeout: 3))
            app.buttons["Fit image"].click()
            XCTAssertTrue(app.staticTexts["100%"].waitForExistence(timeout: 3))
            if iteration == 0 {
                app.buttons["Copy image"].click()
                XCTAssertTrue(app.buttons["Image copied"].waitForExistence(timeout: 5))
                XCTAssertEqual(board.data(forType: .png), png)
            }
            app.buttons["Close image preview"].click()
            XCTAssertFalse(app.buttons["Zoom in"].exists)
        }
    }

    @MainActor
    func testStreamingQueueRunsInOrderAndPreservesTheNextDraft() async throws {
        let (app, _) = try launch(withRuntime: true)
        send("[stream] Start a controlled streaming response.", in: app)
        _ = response("STREAM_BEGIN", in: app)
        send("[queue-one] First queued message.", in: app)
        XCTAssertTrue(app.staticTexts["Up next"].waitForExistence(timeout: 5))
        send("[queue-two] Second queued message.", in: app)
        let queued = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Edit queued message:'"))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in queued.count == 2 }, object: nil)
        await fulfillment(of: [ready], timeout: 5)
        composer(app).click()
        composer(app).typeText("Keep this unsent draft")
        try await XCTUnwrap(runtime).releaseStream()
        _ = response("QUEUE_TWO_COMPLETE", in: app)
        XCTAssertEqual(composer(app).value as? String, "Keep this unsent draft")
        let requests = try XCTUnwrap(runtime).requests()
        XCTAssertEqual(requests.count, 3)
        let bodies = try requests.map { try XCTUnwrap($0["body"] as? [String: Any]) }
        let lastPrompts = try bodies.map { body in
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            return try XCTUnwrap(messages.last?["content"] as? [[String: Any]]).compactMap { $0["text"] as? String }.joined()
        }
        XCTAssertTrue(lastPrompts[0].contains("[stream]"))
        XCTAssertTrue(lastPrompts[1].contains("[queue-one]"))
        XCTAssertTrue(lastPrompts[2].contains("[queue-two]"))
        XCTAssertFalse(lastPrompts.joined().contains("Keep this unsent draft"))
    }

    @MainActor
    func testFinishingAStreamDoesNotMoveThePassageBeingRead() async throws {
        let (app, directory) = try launch(withRuntime: true)
        importThread(try longConversation(in: directory), in: app)
        XCTAssertTrue(app.descendants(matching: .any)["conversation.transcript"].firstMatch.waitForExistence(timeout: 10))
        send("[stream] Keep the previous passage readable while this finishes.", in: app)
        _ = response("STREAM_BEGIN", in: app)
        let window = app.windows["MainWindow"]
        let transcript = window.descendants(matching: .any)["conversation.transcript"].firstMatch
        let anchor = window.staticTexts["Fixture question 492"]
        for _ in 0..<10 {
            transcript.scroll(byDeltaX: 0, deltaY: 300)
            if anchor.exists, anchor.frame.minY > window.frame.minY + 80,
               anchor.frame.maxY < composer(app).frame.minY - 40 { break }
        }
        XCTAssertTrue(anchor.isHittable, "The test must read an older visible passage, not stay at the bottom.")
        let before = anchor.frame.minY
        try await XCTUnwrap(runtime).releaseStream()
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.buttons["Stop response"].exists
        }, object: nil)
        await fulfillment(of: [completed], timeout: 12)
        let preserved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            anchor.exists && abs(anchor.frame.minY - before) < 2
        }, object: nil)
        await fulfillment(of: [preserved], timeout: 5)
        XCTAssertTrue(app.buttons["Scroll to latest message"].exists)
        app.buttons["Scroll to latest message"].click()
        XCTAssertTrue(response("STREAM_COMPLETE", in: app).isHittable)
    }

    @MainActor
    func testStopPausesQueuedMessagesAndResumeKeepsPartialOutput() throws {
        let (app, directory) = try launch(withRuntime: true)
        send("[stream] This response will be stopped.", in: app)
        _ = response("STREAM_BEGIN", in: app)
        send("[queue-one] Survive stop and restart.", in: app)
        XCTAssertTrue(app.staticTexts["Up next"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Queue paused"].waitForExistence(timeout: 8))
        XCTAssertEqual(try XCTUnwrap(runtime).requests().count, 1)
        app.typeKey("q", modifierFlags: .command)
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.state == .notRunning }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 8), .completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        app.launch()
        XCTAssertTrue(app.staticTexts["Queue paused"].waitForExistence(timeout: 10))
        _ = response("STREAM_BEGIN", in: app)
        XCTAssertEqual(try XCTUnwrap(runtime).requests().count, 1, "Restart must not silently replay a request.")
        app.buttons["Resume"].click()
        _ = response("QUEUE_ONE_COMPLETE", in: app)
        XCTAssertEqual(try XCTUnwrap(runtime).requests().count, 2)
    }

    @MainActor
    func testRenderedSelectionCopiesRichHTMLWhileCopyResponseKeepsMarkdown() throws {
        preserveClipboard()
        let (app, directory) = try launch()
        let model = "amazon.nova-2-lite-v1:0"
        let source = """
        **Bold welcome** and *italic detail*.

        - First item
        - 두 번째 item

        [Documentation](https://example.com)
        """
        let file = directory.appendingPathComponent("rich-copy.json")
        let fixture: [String: Any] = [
            "version": 1, "title": "Formatted response", "modelID": model,
            "modelName": "Nova 2 Lite", "provider": "Amazon",
            "messages": [
                ["id": UUID().uuidString, "role": "assistant", "text": source,
                 "timestamp": Date().timeIntervalSinceReferenceDate, "isError": false, "modelID": model]
            ]
        ]
        try JSONSerialization.data(withJSONObject: fixture).write(to: file, options: .atomic)
        importThread(file, in: app)
        let answer = response("Bold welcome", in: app)
        answer.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("c", modifierFlags: .command)
        let board = NSPasteboard.general
        let htmlReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            board.string(forType: .html)?.contains("<strong>Bold welcome</strong>") == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [htmlReady], timeout: 3), .completed)
        let html = try XCTUnwrap(board.string(forType: .html))
        XCTAssertTrue(html.contains("<em>italic detail</em>"))
        XCTAssertTrue(html.contains("<ul><li>"))
        XCTAssertTrue(html.contains("두 번째 item"))
        XCTAssertTrue(html.contains("href=\"https://example.com\""))
        XCTAssertFalse(html.contains("•"))

        answer.rightClick()
        let copies = app.menuItems.matching(identifier: "Copy")
        XCTAssertTrue(copies.firstMatch.waitForExistence(timeout: 3))
        // The Edit menu also exposes Copy while the text's context menu is open.
        let copySelection = try XCTUnwrap(copies.allElementsBoundByIndex.first(where: \.isHittable))
        copySelection.click()
        XCTAssertNotNil(board.string(forType: .html))

        let copyResponse = app.buttons["Copy response"]
        XCTAssertLessThanOrEqual(copyResponse.frame.minY - answer.frame.maxY, 20)
        copyResponse.click()
        XCTAssertEqual(board.string(forType: .string), source)
        XCTAssertNil(board.data(forType: .html), "Copy response remains the original Markdown.")
    }

    @MainActor
    func testModelSwitchUsesNewModelAndCarriesConversationContext() throws {
        let (app, _) = try launch(withRuntime: true)
        send("[remember] Remember BRIDGE_CI.", in: app)
        _ = response("CONTEXT_SAVED", in: app)
        XCTAssertFalse(app.buttons["conversation.loadEarlier"].exists)
        XCTAssertFalse(app.buttons["conversation.loadNewer"].exists)
        chooseModel("GPT-6 Astra", in: app)
        let switches = app.descendants(matching: .any).matching(identifier: "conversation.modelSwitch")
        XCTAssertTrue(switches.firstMatch.waitForExistence(timeout: 3))
        // macOS exposes a static text's displayed content as AXValue.
        let transition = switches.firstMatch
        XCTAssertEqual((transition.value as? String) ?? transition.label, "Switched to GPT-6 Astra")
        XCTAssertEqual(switches.count, 1)
        send("[recall] Recall the code from this conversation.", in: app)
        _ = response("CONTEXT_RECALLED: BRIDGE_CI", in: app)
        XCTAssertEqual(switches.count, 1, "Sending must not duplicate the pending switch indicator.")
        XCTAssertFalse(app.buttons["conversation.loadEarlier"].exists)
        XCTAssertFalse(app.buttons["conversation.loadNewer"].exists)
        let requests = try XCTUnwrap(runtime).requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue((requests[0]["model"] as? String)?.contains("nova-2-lite") == true)
        XCTAssertTrue((requests[1]["model"] as? String)?.contains("gpt-6-astra") == true)
        let wire = String(decoding: try JSONSerialization.data(withJSONObject: requests), as: UTF8.self)
        XCTAssertFalse(wire.contains("Switched to"), "A visual boundary must not become model context.")
        app.typeKey("n", modifierFlags: .command)
        app.windows["MainWindow"].buttons["Back"].click()
        _ = response("CONTEXT_RECALLED: BRIDGE_CI", in: app)
        XCTAssertEqual(switches.count, 1, "Reopening the conversation must retain one model boundary.")
        XCTAssertEqual((switches.firstMatch.value as? String) ?? switches.firstMatch.label, "Switched to GPT-6 Astra")
        XCTAssertEqual(try XCTUnwrap(runtime).requests().count, 2, "Reopening must not invoke the model again.")
    }

    @MainActor
    func testSkillsAndShellRunThroughTheActualToolLoop() throws {
        let (app, _) = try launch(withRuntime: true)
        send("[tools] List skills, load code-review, then run the fixture command.", in: app)
        _ = response("TOOLS_COMPLETE: code-review · EXEC_FROM_REAL_TOOL", in: app, timeout: 20)
        let requests = try XCTUnwrap(runtime).requests()
        XCTAssertEqual(requests.count, 4)
        let last = try XCTUnwrap(requests.last?["body"] as? [String: Any])
        let messages = try XCTUnwrap(last["messages"] as? [[String: Any]])
        let results = messages.flatMap { $0["content"] as? [[String: Any]] ?? [] }.compactMap { $0["toolResult"] as? [String: Any] }
        XCTAssertEqual(results.count, 3)
        let wire = String(decoding: try JSONSerialization.data(withJSONObject: results), as: UTF8.self)
        XCTAssertTrue(wire.contains("code-review"))
        XCTAssertTrue(wire.contains("EXEC_FROM_REAL_TOOL"))
        XCTAssertTrue(wire.contains("Exit code: 0"))
        let call = app.descendants(matching: .any).matching(identifier: "toolCall.fixture-exec").firstMatch
        XCTAssertTrue(call.exists)
        let headerY = call.frame.minY
        call.click()
        let open = app.buttons["Open details"]
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        XCTAssertEqual(call.frame.minY, headerY, accuracy: 2,
                       "Inspecting a tool must preserve its position instead of following the expanded document to the bottom.")
        for _ in 0..<3 where !open.isHittable {
            app.textViews["Tool input preview"].scroll(byDeltaX: 0, deltaY: -240)
        }
        open.click()
        let detail = app.textViews["Tool detail text"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        XCTAssertTrue((detail.value as? String)?.contains("EXEC_FROM_REAL_TOOL") == true)
        app.buttons["Done"].click()
    }

    @MainActor
    func testExpandedToolRemainsResponsiveAcrossChatAndImageModelChanges() throws {
        let (app, _) = try launch(withRuntime: true)
        chooseModel("GPT-6 Astra", in: app)
        send("[tools] List skills, load code-review, then run the fixture command.", in: app)
        _ = response("TOOLS_COMPLETE: code-review · EXEC_FROM_REAL_TOOL", in: app, timeout: 20)
        let row = app.buttons["toolCall.fixture-exec"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        let open = app.buttons["Open details"]
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        for _ in 0..<3 where !open.isHittable {
            app.textViews["Tool input preview"].scroll(byDeltaX: 0, deltaY: -240)
        }
        open.click()
        let detail = app.textViews["Tool detail text"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        XCTAssertTrue((detail.value as? String)?.contains("EXEC_FROM_REAL_TOOL") == true)
        app.buttons["Input"].click()
        app.buttons["Done"].click()

        let draft = "Keep this unsent draft while changing the model."
        composer(app).click()
        composer(app).typeText(draft)
        for _ in 0..<3 {
            for model in ["Stable Image Ultra 1.0", "GPT-6 Astra"] {
                chooseModel(model, in: app)
                XCTAssertEqual(app.buttons["modelPicker.button"].label, "Model: \(model)")
                XCTAssertEqual(composer(app).value as? String, draft)
                XCTAssertTrue(row.exists)
                XCTAssertEqual(row.value as? String, "Expanded")
                XCTAssertFalse(app.textFields["modelPicker.search"].exists)
            }
        }
        XCTAssertEqual(try XCTUnwrap(runtime).requests().count, 4,
                       "Changing a model must not send the draft or rerun the tools.")
        let image = XCTAttachment(screenshot: app.windows["MainWindow"].screenshot())
        image.name = "Expanded tool after repeated chat and image model changes"
        image.lifetime = .keepAlways
        add(image)
    }

    @MainActor
    func testLocalImageSearchAndAutomationToolsReturnTheirActualResults() throws {
        let (app, directory) = try launch(withRuntime: true)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 48,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 180, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let file = directory.appendingPathComponent("local-tool-image.png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
        send("[remember] Save the synthetic bridge code for another conversation.", in: app)
        _ = response("CONTEXT_SAVED: BRIDGE_CI", in: app)
        app.typeKey("n", modifierFlags: .command)
        send("[local-tools] \(file.path)", in: app)
        _ = response("LOCAL_TOOLS_COMPLETE: image · saved conversation · paused automation", in: app, timeout: 20)

        let requests = try XCTUnwrap(runtime).requests()
        XCTAssertEqual(requests.count, 6)
        let body = try XCTUnwrap(requests.last?["body"] as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let results = messages.flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .compactMap { $0["toolResult"] as? [String: Any] }
        XCTAssertEqual(results.count, 4)
        XCTAssertTrue(results.allSatisfy { $0["status"] as? String == "success" })
        let imageResult = try XCTUnwrap(results.first { $0["toolUseId"] as? String == "local-image" })
        let content = try XCTUnwrap(imageResult["content"] as? [[String: Any]])
        let wireImage = try XCTUnwrap(content.compactMap { $0["image"] as? [String: Any] }.first)
        let source = try XCTUnwrap(wireImage["source"] as? [String: Any])
        let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(source["bytes"] as? String)))
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: bytes))
        XCTAssertEqual(decoded.pixelsWide, 64)
        XCTAssertEqual(decoded.pixelsHigh, 48)
        let wire = String(decoding: try JSONSerialization.data(withJSONObject: results), as: UTF8.self)
        XCTAssertTrue(wire.contains("CONTEXT_SAVED: BRIDGE_CI"), "Search must find the saved earlier conversation.")
        XCTAssertTrue(wire.contains("Local workflow automation"))
        let state = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: directory.appendingPathComponent("workbench/workspace.json"))) as? [String: Any])
        let schedule = try XCTUnwrap((state["automations"] as? [[String: Any]])?.first)
        XCTAssertEqual(schedule["name"] as? String, "Local workflow automation")
        XCTAssertEqual(schedule["enabled"] as? Bool, false)
        XCTAssertEqual(schedule["timeZoneIdentifier"] as? String, "Asia/Seoul")
        XCTAssertEqual(Set(schedule["weekdays"] as? [Int] ?? []), [2, 6])
        app.buttons["Automations"].click()
        XCTAssertTrue(app.staticTexts["Local workflow automation"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSourceFilePasteSendsExactDocumentBytesAndKeepsDraft() throws {
        let (app, directory) = try launch(withRuntime: true)
        preserveClipboard()
        let bytes = Data("// 한글\nlet value = 42\n".utf8)
        let file = directory.appendingPathComponent("Example.swift")
        try bytes.write(to: file)
        let editor = composer(app)
        editor.click()
        editor.typeText("[attachments] Read this source file.")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(file.absoluteString, forType: .fileURL)
        XCTAssertNotNil(NSPasteboard.general.data(forType: .fileURL))
        app.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Example"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(editor.value as? String, "[attachments] Read this source file.")
        app.buttons["Send message"].click()
        _ = response("ATTACHMENTS_RECEIVED: 1 documents, 0 images", in: app)
        let request = try XCTUnwrap(runtime).requests().first
        let body = try XCTUnwrap(request?["body"] as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        let document = try XCTUnwrap(content.compactMap { $0["document"] as? [String: Any] }.first)
        XCTAssertEqual(document["format"] as? String, "txt")
        let source = try XCTUnwrap(document["source"] as? [String: Any])
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(source["bytes"] as? String)), bytes)
    }

    @MainActor
    func testImageOnlyThenMixedLongTextPasteSendsAllImagesAndExactText() throws {
        let (app, _) = try launch(withRuntime: true)
        preserveClipboard()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3200, pixelsHigh: 1800,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 3200, height: 1800).fill()
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(png, forType: .png)
        XCTAssertNil(board.string(forType: .string))
        composer(app).click()
        app.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Attachments (1)"].waitForExistence(timeout: 8),
                      "An image-only clipboard must work through Command-V.")

        let longText = String(repeating: "Mixed paste 한글 with exact whitespace.\n", count: 1500) + "EXACT_PASTE_END_CI"
        let text = NSPasteboardItem()
        text.setString(longText, forType: .string)
        text.setString("<script>wrong content</script><p>Prefer the supplied plain text</p>", forType: .html)
        let images = (0..<2).map { _ -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            return item
        }
        board.clearContents()
        board.writeObjects([text] + images)
        XCTAssertEqual(board.string(forType: .string), longText)
        app.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Attachments (4)"].waitForExistence(timeout: 12))
        XCTAssertEqual(composer(app).value as? String, "")
        send("[attachments] Inspect the pasted content.", in: app)
        _ = response("ATTACHMENTS_RECEIVED: 0 documents, 3 images", in: app)
        let request = try XCTUnwrap(runtime).requests().first
        let body = try XCTUnwrap(request?["body"] as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        let actual = content.compactMap { $0["text"] as? String }.joined()
        XCTAssertTrue(actual.contains(longText))
        XCTAssertFalse(actual.contains("<script>wrong content</script>"))
        XCTAssertEqual(content.filter { $0["image"] != nil }.count, 3)
    }

    @MainActor
    func testAutomationUsesGroupedProviderModelPickerAndPersistsTheSelectedRoute() throws {
        let (app, directory) = try launch()
        app.buttons["Automations"].click()
        app.buttons["automations.new"].click()
        let name = app.textFields["automation.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeText("Provider-aware schedule")
        let prompt = app.textViews["automation.prompt"]
        prompt.click()
        prompt.typeText("Describe the weather in three fictional words.")
        let picker = try XCTUnwrap(app.buttons.matching(identifier: "modelPicker.button")
            .allElementsBoundByIndex.first(where: \.isHittable))
        picker.click()
        let search = app.textFields["modelPicker.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click()
        search.typeText("Anthropic Fable")
        XCTAssertEqual(search.value as? String, "Anthropic Fable")
        let rows = app.buttons.matching(NSPredicate(format: "label == 'Select Claude Fable 5.1'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1, "Regional and global routes must share one model row.")
        XCTAssertTrue((rows.firstMatch.value as? String ?? "").contains("Anthropic"))
        let screenshot = XCTAttachment(screenshot: app.windows["MainWindow"].screenshot())
        screenshot.name = "Automation – shared provider model picker"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        rows.firstMatch.click()
        let details = app.staticTexts["automation.modelDetails"]
        // Selectable SwiftUI Text exposes AXValue on macOS, unlike labels.
        let description = (details.value as? String) ?? details.label
        XCTAssertTrue(description.contains("Anthropic"), description)
        XCTAssertTrue(description.contains("anthropic.claude-fable-5-1"), description)
        let selected = description.components(separatedBy: " · ").last
        app.buttons["automation.save"].click()
        XCTAssertTrue(app.staticTexts["Provider-aware schedule"].waitForExistence(timeout: 5))
        let data = try Data(contentsOf: directory.appendingPathComponent("workbench/workspace.json"))
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let saved = try XCTUnwrap((state["automations"] as? [[String: Any]])?.first)
        XCTAssertEqual(saved["modelID"] as? String, selected)
        XCTAssertEqual(saved["enabled"] as? Bool, false)

        let id = try XCTUnwrap(saved["id"] as? String)
        app.terminate()
        app.launch()
        app.activate()
        XCTAssertTrue(app.buttons["Automations"].waitForExistence(timeout: 10))
        app.buttons["Automations"].click()
        let options = app.buttons["automation.options.\(id)"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.click()
        app.buttons["Edit"].click()
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertEqual((details.value as? String) ?? details.label, description)
        app.buttons["automation.save"].click()
        XCTAssertTrue(app.staticTexts["Provider-aware schedule"].waitForExistence(timeout: 5))
        let updated = try JSONSerialization.jsonObject(
            with: Data(contentsOf: directory.appendingPathComponent("workbench/workspace.json"))) as? [String: Any]
        XCTAssertEqual((updated?["automations"] as? [[String: Any]])?.first?["modelID"] as? String, selected,
                       "Opening and saving an existing automation must preserve its selected inference route.")
    }

    @MainActor
    func testQuickAccessEscapeAndSubmissionReachTheMainConversation() throws {
        let (app, _) = try launch(withRuntime: true)
        let mainEditor = composer(app)
        mainEditor.click()
        mainEditor.typeText("MAIN_DRAFT")
        app.menuBars.menuBarItems["Amazon Bedrock"].click()
        app.menuItems["Show Quick Access"].click()
        // NSPanel is exposed as a Dialog on hosted macOS and as a Window on
        // some local versions. Use its stable identifier across both roles.
        let quick = app.descendants(matching: .any).matching(identifier: "QuickAccessWindow")
            .firstMatch.textViews["composer.editor"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        quick.click()
        quick.typeText("A draft to dismiss")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(quick.exists)
        app.typeText("_RESTORED")
        XCTAssertEqual(mainEditor.value as? String, "MAIN_DRAFT_RESTORED",
                       "Escape must return keyboard input to the previous editor without another click.")
        app.typeKey("k", modifierFlags: [.command, .shift])
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        quick.click()
        app.typeKey("a", modifierFlags: .command)
        quick.typeText("[quick] Submit through Quick Access.")
        app.typeKey(.return, modifierFlags: [])
        _ = response("QUICK_ACCESS_COMPLETE", in: app)
        XCTAssertFalse(quick.exists)
        XCTAssertEqual(try XCTUnwrap(runtime).requests().count, 1)
    }

    @MainActor
    func testBackgroundCommandsCanStartPollAndStopAcrossRealToolTurns() throws {
        let (app, _) = try launch(withRuntime: true)
        send("[background] Start the fixture command, read its output, then stop it.", in: app)
        _ = response("BACKGROUND_TOOLS_COMPLETE", in: app, timeout: 20)
        let requests = try XCTUnwrap(runtime).requests()
        XCTAssertEqual(requests.count, 4)
        let body = try XCTUnwrap(requests.last?["body"] as? [String: Any])
        let history = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let historyText = String(decoding: try JSONSerialization.data(withJSONObject: history), as: UTF8.self)
        for name in ["local_start_process", "local_poll_process", "local_stop_process"] {
            XCTAssertTrue(historyText.contains(name))
        }
        XCTAssertTrue(historyText.contains("BACKGROUND_READY"))
        XCTAssertTrue(historyText.contains("stopped"))
    }

    @MainActor
    func testOutputLimitContinuationKeepsUnsentDraftAndConversationContext() throws {
        let (app, _) = try launch(withRuntime: true)
        send("[truncated] Write a response that reaches the output limit.", in: app)
        _ = response("PARTIAL_RESPONSE", in: app)
        let button = app.buttons["chat.continueResponse"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        composer(app).click()
        composer(app).typeText("UNSENT_DRAFT_AFTER_PARTIAL")
        button.click()
        _ = response("RESPONSE_COMPLETE", in: app)
        XCTAssertEqual(composer(app).value as? String, "UNSENT_DRAFT_AFTER_PARTIAL")
        XCTAssertFalse(button.exists)
        let requests = try XCTUnwrap(runtime).requests()
        XCTAssertEqual(requests.count, 2)
        let body = try XCTUnwrap(requests.last?["body"] as? [String: Any])
        let history = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let historyText = String(decoding: try JSONSerialization.data(withJSONObject: history), as: UTF8.self)
        XCTAssertTrue(historyText.contains("PARTIAL_RESPONSE"))
        XCTAssertTrue(historyText.contains("Continue the previous response"))
        XCTAssertFalse(historyText.contains("UNSENT_DRAFT_AFTER_PARTIAL"))
    }

    @MainActor
    func testFailedRequestLeavesConversationUsableForTheNextMessage() throws {
        let (app, _) = try launch(withRuntime: true)
        send("[failure] Reject this synthetic request.", in: app)
        let error = app.staticTexts["requestError.message"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        // SwiftUI exposes selectable Text through AXValue on some macOS
        // versions. Verify the actual message using its stable identity.
        XCTAssertTrue((error.label + (error.value as? String ?? "")).contains("fixture rejected"))
        send("Continue after the failure.", in: app)
        _ = response("RESPONSE_COMPLETE", in: app)
        XCTAssertEqual(try XCTUnwrap(runtime).requests().count, 2)
        XCTAssertEqual(composer(app).value as? String, "")
    }
}
