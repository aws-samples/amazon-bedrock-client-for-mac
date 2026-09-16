import AppKit
import XCTest

final class BedrockUITests: XCTestCase {
    @MainActor private var runtime: BedrockUITestFixture?

    @MainActor
    private func launch(appearance: String = "light", withRuntime: Bool = false) throws -> (XCUIApplication, URL) {
        continueAfterFailure = false
        // The signed runner's default temporaryDirectory is inside its app
        // container. Importing from there raises macOS cross-app privacy UI.
        // This explicitly entitled folder contains synthetic test data only.
        let directory = URL(fileURLWithPath: "/private/tmp/bedrock-ui-fixtures", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let app = XCUIApplication()
        app.launchEnvironment["BEDROCK_WORKBENCH_DATA_DIR"] = directory.path
        app.launchEnvironment["BEDROCK_TEST_OFFLINE"] = "1"
        app.launchArguments = ["-checkForUpdates", "NO", "-enableQuickAccess", "NO", "-mcpEnabled", "NO",
                               "-appearance", appearance, "-selectedRegion", "us-west-2",
                               "-selectedProfile", "default",
                               "-defaultModelId", "us.amazon.nova-2-lite-v1:0"]
        let fixture = try withRuntime ? BedrockUITestFixture(directory: directory) : nil
        runtime = fixture
        fixture?.configure(app)
        app.launch()
        XCTAssertTrue(app.staticTexts["How can I help?"].waitForExistence(timeout: 15))
        addTeardownBlock { @MainActor in
            app.terminate()
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
        app.typeKey("o", modifierFlags: [.command, .shift])
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
                        "## Fixture answer \(index)\n\n- First **item** with `inline code`.\n- Second item.\n\n> Synthetic content.\n\n```swift\nlet row = \(index)\n```"
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
        XCTAssertTrue(app.buttons["conversation.loadEarlier"].waitForExistence(timeout: 10))

        // Store clock measurements in the xcresult, using a bounded live
        // transcript rather than full accessibility-tree snapshots per key.
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
    func testPagingAndReturningToThreadKeepTheReadingPosition() throws {
        let (app, directory) = try launch()
        importThread(try longConversation(in: directory), in: app)
        let window = app.windows["MainWindow"]
        let earlier = app.buttons["conversation.loadEarlier"]
        XCTAssertTrue(earlier.waitForExistence(timeout: 10))
        let transcript = window.scrollViews.containing(.button, identifier: "conversation.loadEarlier").firstMatch
        for _ in 0..<8 {
            transcript.scroll(byDeltaX: 0, deltaY: 3_000)
            if earlier.isHittable { break }
        }
        XCTAssertTrue(earlier.isHittable)
        let anchor = window.staticTexts["Fixture question 484"]
        XCTAssertTrue(anchor.exists)
        let before = anchor.frame.minY
        earlier.click()
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            window.textViews.matching(NSPredicate(format: "label == 'Assistant response text'")).count == 32
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 8), .completed)
        let preserved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            anchor.exists && abs(anchor.frame.minY - before) < 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [preserved], timeout: 5), .completed)
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
        row.click()
        let open = app.buttons["Open details"]
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Copy tool input"].exists)
        XCTAssertTrue(app.buttons["Copy tool output"].exists)
        for _ in 0..<3 where !open.isHittable {
            app.windows["MainWindow"].scroll(byDeltaX: 0, deltaY: -240)
        }
        open.click()
        let detail = app.textViews["Tool detail text"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        XCTAssertEqual(detail.value as? String, output)
        app.buttons["Input"].click()
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
        XCTAssertTrue(app.buttons["conversation.loadEarlier"].waitForExistence(timeout: 10))
        send("[stream] Keep the previous passage readable while this finishes.", in: app)
        _ = response("STREAM_BEGIN", in: app)
        let window = app.windows["MainWindow"]
        let transcript = window.scrollViews.containing(.button, identifier: "conversation.loadEarlier").firstMatch
        let anchor = window.staticTexts["Fixture question 492"]
        for _ in 0..<10 {
            transcript.scroll(byDeltaX: 0, deltaY: 300)
            if anchor.exists, anchor.frame.minY > window.frame.minY + 80,
               anchor.frame.maxY < composer(app).frame.minY - 40 { break }
        }
        XCTAssertTrue(anchor.isHittable, "The test must read an older visible passage, not stay at the bottom.")
        let before = anchor.frame.minY
        try await XCTUnwrap(runtime).releaseStream()
        _ = response("STREAM_COMPLETE", in: app)
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
    func testModelSwitchUsesNewModelAndCarriesConversationContext() throws {
        let (app, _) = try launch(withRuntime: true)
        send("[remember] Remember BRIDGE_CI.", in: app)
        _ = response("CONTEXT_SAVED", in: app)
        chooseModel("GPT-6 Astra", in: app)
        send("[recall] Recall the code from this conversation.", in: app)
        _ = response("CONTEXT_RECALLED: BRIDGE_CI", in: app)
        let requests = try XCTUnwrap(runtime).requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue((requests[0]["model"] as? String)?.contains("nova-2-lite") == true)
        XCTAssertTrue((requests[1]["model"] as? String)?.contains("gpt-6-astra") == true)
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
        call.click()
        let open = app.buttons["Open details"]
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        for _ in 0..<3 where !open.isHittable {
            app.windows["MainWindow"].scroll(byDeltaX: 0, deltaY: -240)
        }
        open.click()
        let detail = app.textViews["Tool detail text"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        XCTAssertTrue((detail.value as? String)?.contains("EXEC_FROM_REAL_TOOL") == true)
        app.buttons["Done"].click()
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
    func testQuickAccessEscapeAndSubmissionReachTheMainConversation() throws {
        let (app, _) = try launch(withRuntime: true)
        app.typeKey("k", modifierFlags: [.command, .shift])
        let quick = app.dialogs["QuickAccessWindow"].textViews["composer.editor"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        quick.click()
        quick.typeText("A draft to dismiss")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(quick.exists)
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
        let error = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'fixture rejected'")).firstMatch
        // Errors are rendered using the same selectable native text surface.
        let errorText = app.textViews.matching(NSPredicate(format: "value CONTAINS 'fixture rejected'")).firstMatch
        let rejected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in error.exists || errorText.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rejected], timeout: 10), .completed)
        send("Continue after the failure.", in: app)
        _ = response("RESPONSE_COMPLETE", in: app)
        XCTAssertEqual(try XCTUnwrap(runtime).requests().count, 2)
        XCTAssertEqual(composer(app).value as? String, "")
    }
}
