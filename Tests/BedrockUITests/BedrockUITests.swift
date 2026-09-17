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
    func testSidebarSectionsKeepTheirStateAndChatsRestoreCalendarDateGroups() throws {
        let (app, directory) = try launch()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for (title, days) in [("Today conversation", 0), ("Yesterday conversation", -1), ("Older conversation", -10)] {
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: days, to: today))
            let model = "us.amazon.nova-2-lite-v1:0"
            let file = directory.appendingPathComponent("\(days)-sidebar.json")
            try JSONSerialization.data(withJSONObject: [
                "version": 1, "title": title, "modelID": model, "modelName": "Nova 2 Lite",
                "provider": "Amazon", "messages": [
                    ["id": UUID().uuidString, "role": "user", "text": "An imported question.",
                     "modelID": model, "isError": false, "timestamp": date.timeIntervalSinceReferenceDate],
                    ["id": UUID().uuidString, "role": "assistant", "text": "The imported reply remains available.",
                     "modelID": model, "isError": false, "timestamp": date.timeIntervalSinceReferenceDate + 1]
                ]
            ]).write(to: file)
            importThread(file, in: app)
            XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 5))
        }
        let todayHeader = app.staticTexts["sidebar.date.Today"]
        let yesterdayHeader = app.staticTexts["sidebar.date.Yesterday"]
        XCTAssertTrue(todayHeader.waitForExistence(timeout: 3))
        XCTAssertTrue(yesterdayHeader.exists)
        let dateHeaders = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'sidebar.date.'"))
        XCTAssertEqual(dateHeaders.count, 3, "Imported chats must retain their original calendar dates.")
        XCTAssertLessThan(todayHeader.frame.minY, app.staticTexts["Today conversation"].firstMatch.frame.minY)
        XCTAssertLessThan(app.staticTexts["Today conversation"].firstMatch.frame.minY, yesterdayHeader.frame.minY)
        XCTAssertLessThan(yesterdayHeader.frame.minY, app.staticTexts["Yesterday conversation"].firstMatch.frame.minY)
        XCTAssertLessThanOrEqual(todayHeader.frame.minY - app.buttons["sidebar.chats.toggle"].frame.maxY, 16,
                                 "The first date belongs to Chats; it must not look like another separated section.")
        let todayRow = app.outlineRows.containing(.staticText, identifier: "Today conversation").firstMatch
        XCTAssertTrue(todayRow.exists)
        XCTAssertLessThanOrEqual(todayRow.frame.minY - todayHeader.frame.maxY, 12,
                                 "A date should stay attached to the conversation row's selection area.")
        XCTAssertEqual(todayHeader.frame.minX, app.staticTexts["Today conversation"].firstMatch.frame.minX, accuracy: 1,
                       "Date labels and conversation titles should share their text inset.")
        let dateLayout = XCTAttachment(screenshot: app.windows["MainWindow"].screenshot())
        dateLayout.name = "Sidebar – compact date hierarchy"
        dateLayout.lifetime = .keepAlways
        add(dateLayout)

        app.staticTexts["Today conversation"].firstMatch.rightClick()
        app.menuItems["Pin thread"].click()
        let pinned = app.buttons["sidebar.pinned.toggle"]
        XCTAssertTrue(pinned.waitForExistence(timeout: 3))
        let pinnedTitle = app.staticTexts.matching(NSPredicate(
            format: "label == %@ OR value == %@", "Today conversation", "Today conversation"))
        let movedToPinned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            pinnedTitle.count == 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [movedToPinned], timeout: 3), .completed)
        pinned.click()
        XCTAssertEqual(pinned.value as? String, "Collapsed")
        XCTAssertFalse(app.staticTexts["Today conversation"].exists)
        let library = app.buttons["sidebar.library.toggle"]
        let chats = app.buttons["sidebar.chats.toggle"]
        app.buttons["Activity"].click()
        library.click()
        XCTAssertEqual(library.value as? String, "Collapsed")
        XCTAssertFalse(app.buttons["Demo library"].exists)
        XCTAssertFalse(app.buttons["Automations"].exists)
        XCTAssertFalse(app.buttons["Activity"].exists)
        XCTAssertTrue(app.staticTexts["Activity"].exists, "Collapsing navigation must leave the active page open.")
        chats.click()
        XCTAssertEqual(chats.value as? String, "Collapsed")
        XCTAssertFalse(yesterdayHeader.exists)
        XCTAssertFalse(app.staticTexts["Older conversation"].exists)
        XCTAssertTrue(app.buttons["New chat"].exists)
        XCTAssertTrue(app.buttons["AWS connection and settings"].exists)

        let saved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("workbench/workspace.json")),
                  let state = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let preferences = state["preferences"] as? [String: Any],
                  let collapsed = preferences["collapsedSidebarSections"] as? [String] else { return false }
            return Set(collapsed) == ["library", "pinned", "chats"]
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 3), .completed)
        app.terminate()
        app.launch()
        app.activate()
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        for id in ["library", "pinned", "chats"] {
            XCTAssertEqual(app.buttons["sidebar.\(id).toggle"].value as? String, "Collapsed", id)
            app.buttons["sidebar.\(id).toggle"].click()
        }
        XCTAssertTrue(app.staticTexts["Today conversation"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(yesterdayHeader.exists)
        XCTAssertTrue(app.staticTexts["Older conversation"].exists)
        for destination in ["Demo library", "Automations", "Activity"] {
            app.buttons[destination].click()
            XCTAssertTrue(app.staticTexts[destination].firstMatch.waitForExistence(timeout: 3))
        }
        app.staticTexts["Older conversation"].firstMatch.click()
        _ = response("The imported reply remains available.", in: app)
        let screenshot = XCTAttachment(screenshot: app.windows["MainWindow"].screenshot())
        screenshot.name = "Sidebar – restored sections and dates"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testDarkSidebarLibraryDisclosureKeepsNavigationAvailable() throws {
        let (app, _) = try launch(appearance: "dark")
        let library = app.buttons["sidebar.library.toggle"]
        XCTAssertTrue(library.waitForExistence(timeout: 3))
        XCTAssertEqual(library.value as? String, "Expanded")
        library.click()
        XCTAssertFalse(app.buttons["Demo library"].exists)
        XCTAssertEqual(library.value as? String, "Collapsed")
        library.click()
        for destination in ["Demo library", "Automations", "Activity"] {
            let button = app.buttons[destination]
            XCTAssertTrue(button.waitForExistence(timeout: 3))
            button.click()
            XCTAssertTrue(app.staticTexts[destination].firstMatch.waitForExistence(timeout: 3))
        }
        let screenshot = XCTAttachment(screenshot: app.windows["MainWindow"].screenshot())
        screenshot.name = "Sidebar – dark Library hierarchy"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testNewChatDraftAndArchiveShortcutsPreservePreviousDraft() throws {
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
    func testArchiveMigratesLegacyTrashAndSupportsRestoreSearchAndPermanentDelete() throws {
        let (app, directory) = try launch()
        let model = "us.amazon.nova-2-lite-v1:0"
        for name in ["Legacy archive", "Legacy trash"] {
            let file = directory.appendingPathComponent("\(name).json")
            let messages: [[String: Any]] = [
                ["id": UUID().uuidString, "role": "user", "text": "\(name) question",
                 "modelID": model, "isError": false, "timestamp": Date().timeIntervalSinceReferenceDate],
                ["id": UUID().uuidString, "role": "assistant", "text": "\(name) preserved response",
                 "modelID": model, "isError": false, "timestamp": Date().timeIntervalSinceReferenceDate]
            ]
            try JSONSerialization.data(withJSONObject: [
                "version": 1, "title": name, "modelID": model, "modelName": "Nova 2 Lite",
                "provider": "Amazon", "messages": messages
            ]).write(to: file)
            importThread(file, in: app)
            _ = response("\(name) preserved response", in: app)
        }
        app.terminate()
        let workspaceURL = directory.appendingPathComponent("workbench/workspace.json")
        var workspace = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: workspaceURL)) as? [String: Any])
        var threads = try XCTUnwrap(workspace["threads"] as? [String: [String: Any]])
        var ids: [String: String] = [:]
        var originalHistory: [String: Data] = [:]
        let historyDirectory = directory.appendingPathComponent("history")
        for file in try FileManager.default.contentsOfDirectory(at: historyDirectory, includingPropertiesForKeys: nil)
            where file.lastPathComponent.hasSuffix("_unified_history.json") {
            let data = try Data(contentsOf: file)
            let history = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let messages = try XCTUnwrap(history["messages"] as? [[String: Any]])
            let question = try XCTUnwrap(messages.first?["text"] as? String)
            let name = question.replacingOccurrences(of: " question", with: "")
            let id = try XCTUnwrap(history["chatId"] as? String)
            guard ["Legacy archive", "Legacy trash"].contains(name) else { continue }
            ids[name] = id
            originalHistory[id] = data
            var metadata = try XCTUnwrap(threads[id])
            metadata["archived"] = name == "Legacy archive"
            if name == "Legacy trash" {
                metadata["deletedAt"] = Date().timeIntervalSinceReferenceDate
                metadata["draft"] = "Recovered unsent draft"
            }
            threads[id] = metadata
        }
        let archivedID = try XCTUnwrap(ids["Legacy archive"])
        let trashedID = try XCTUnwrap(ids["Legacy trash"])
        workspace["threads"] = threads
        try JSONSerialization.data(withJSONObject: workspace).write(to: workspaceURL, options: .atomic)
        app.launch()
        app.activate()
        XCTAssertTrue(app.staticTexts["How can I help?"].waitForExistence(timeout: 10),
                      "A legacy hidden last selection must not reopen itself on launch.")
        app.typeKey("k", modifierFlags: .command)
        let palette = app.descendants(matching: .any)["workbench.commandPalette"].firstMatch
        XCTAssertTrue(palette.waitForExistence(timeout: 3))
        let globalSearch = palette.textFields.firstMatch
        globalSearch.click()
        globalSearch.typeText("Legacy archive")
        XCTAssertTrue(palette.staticTexts["No results"].waitForExistence(timeout: 5),
                      "Archived conversations belong in Archive, not active global search.")
        app.typeKey(.escape, modifierFlags: [])

        func openArchive() -> XCUIElement {
            let window = settings(app)
            openPane("Data & history", in: window)
            window.buttons["Manage archived chats"].click()
            let history = app.descendants(matching: .any)["settings.chatHistory"].firstMatch
            XCTAssertTrue(history.waitForExistence(timeout: 5))
            return history
        }
        func row(_ id: String, in history: XCUIElement) -> XCUIElement {
            history.descendants(matching: .any)["archive.chat.\(id)"].firstMatch
        }
        let history = openArchive()
        XCTAssertTrue(row(archivedID, in: history).waitForExistence(timeout: 3))
        XCTAssertTrue(row(trashedID, in: history).exists)
        XCTAssertEqual(history.buttons.matching(identifier: "Restore").count, 2)
        XCTAssertFalse(history.buttons["Trash"].exists, "Recovery must use one list, not separate Archive and Trash tabs.")
        let search = history.textFields["Search archived chats"]
        search.click()
        search.typeText("Legacy archive")
        XCTAssertTrue(row(archivedID, in: history).exists)
        XCTAssertFalse(row(trashedID, in: history).exists)
        history.buttons["Clear search"].click()
        let firstTitle = row(trashedID, in: history).staticTexts["Legacy trash"]
        let list = history.outlines.firstMatch
        let fullyVisible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            firstTitle.exists && list.exists && firstTitle.isHittable
                && firstTitle.frame.minY >= list.frame.minY
                && firstTitle.frame.maxY <= list.frame.maxY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [fullyVisible], timeout: 5), .completed,
                       "Clearing the search must show the complete first row, not a clipped title.")
        let screenshot = XCTAttachment(screenshot: app.windows["Settings"].screenshot())
        screenshot.name = "Archive – former Archive and Trash in one list"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        row(archivedID, in: history).buttons["Restore"].click()
        XCTAssertFalse(row(archivedID, in: history).exists)
        row(trashedID, in: history).buttons["Actions for Legacy trash"].click()
        app.buttons["Restore and open"].click()
        XCTAssertTrue(response("Legacy trash preserved response", in: app).isHittable)
        XCTAssertEqual(composer(app).value as? String, "Recovered unsent draft")
        for (id, data) in originalHistory {
            XCTAssertEqual(try Data(contentsOf: historyDirectory.appendingPathComponent("\(id)_unified_history.json")), data)
        }

        app.typeKey("d", modifierFlags: .command)
        XCTAssertTrue(response("Legacy archive preserved response", in: app).isHittable)
        let reopened = openArchive()
        XCTAssertTrue(row(trashedID, in: reopened).waitForExistence(timeout: 3))
        row(trashedID, in: reopened).buttons["Actions for Legacy trash"].click()
        app.buttons["Delete permanently…"].click()
        // NSAlert is an AXDialog; the Touch Bar exposes duplicate actions.
        let cancel = app.dialogs.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        XCTAssertTrue(row(trashedID, in: reopened).exists)
        row(trashedID, in: reopened).buttons["Actions for Legacy trash"].click()
        app.buttons["Delete permanently…"].click()
        app.dialogs.buttons["Delete"].firstMatch.click()
        XCTAssertTrue(reopened.staticTexts["No archived chats"].waitForExistence(timeout: 3))
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyDirectory.appendingPathComponent("\(trashedID)_unified_history.json").path))
        app.terminate()
        app.launch()
        app.activate()
        XCTAssertTrue(response("Legacy archive preserved response", in: app).isHittable)
        XCTAssertTrue(openArchive().staticTexts["No archived chats"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testArchivingAStreamingChatPausesItsQueueAndPreservesTheDraftAcrossRestart() throws {
        let (app, _) = try launch(withRuntime: true)
        send("[stream] Archive this conversation while it runs.", in: app)
        _ = response("STREAM_BEGIN", in: app)
        send("[queue-one] Keep this queued message in the archive.", in: app)
        XCTAssertTrue(app.staticTexts["Up next"].waitForExistence(timeout: 5))
        composer(app).click()
        composer(app).typeText("Keep this archive draft")
        app.typeKey("d", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["How can I help?"].waitForExistence(timeout: 5))
        XCTAssertEqual(try XCTUnwrap(runtime).requests().count, 1)
        let window = settings(app)
        openPane("Data & history", in: window)
        window.buttons["Manage archived chats"].click()
        let history = app.descendants(matching: .any)["settings.chatHistory"].firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        history.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Actions for '")).firstMatch.click()
        app.buttons["Restore and open"].click()
        XCTAssertTrue(app.staticTexts["Queue paused"].waitForExistence(timeout: 8))
        XCTAssertEqual(composer(app).value as? String, "Keep this archive draft")
        XCTAssertEqual(try XCTUnwrap(runtime).requests().count, 1, "Restoring must not silently replay queued requests.")
        app.typeKey("q", modifierFlags: .command)
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.state == .notRunning }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 8), .completed)
        app.launch()
        XCTAssertTrue(app.staticTexts["Queue paused"].waitForExistence(timeout: 10))
        XCTAssertEqual(composer(app).value as? String, "Keep this archive draft")
        _ = response("STREAM_BEGIN", in: app)
        XCTAssertEqual(try XCTUnwrap(runtime).requests().count, 1)
        app.buttons["Resume"].click()
        _ = response("QUEUE_ONE_COMPLETE", in: app)
        XCTAssertEqual(try XCTUnwrap(runtime).requests().count, 2)
        XCTAssertEqual(composer(app).value as? String, "Keep this archive draft")
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
    func testLongMarkdownScrollsWithItsNeighborsAfterLoadResizeAndReopen() throws {
        try assertLongMarkdownScrollsWithItsNeighbors(appearance: "light")
    }

    @MainActor
    func testDarkLongMarkdownScrollsWithItsNeighborsAfterLoadResizeAndReopen() throws {
        try assertLongMarkdownScrollsWithItsNeighbors(appearance: "dark")
    }

    @MainActor
    private func assertLongMarkdownScrollsWithItsNeighbors(appearance: String) throws {
        let (app, directory) = try launch(appearance: appearance)
        let model = "us.amazon.nova-2-lite-v1:0"
        let longReply = "LONG_RESPONSE_START\n\n" + (0..<24).map { index in
            """
            ## Layout section \(index)

            A long response must remain inside its own message as the conversation scrolls.
            This paragraph wraps at different widths and includes **bold**, *italic*, `inline code`, and 한국어.

            - The first item belongs to this response.
            - The second item must not overlap the following message.

            """
        }.joined(separator: "\n") + "\nLONG_RESPONSE_END"
        var messages: [[String: Any]] = [
            ("user", "BEFORE_LONG_RESPONSE"), ("assistant", longReply),
            ("user", "AFTER_LONG_RESPONSE"), ("assistant", "FINAL_ASSISTANT_RESPONSE")
        ].map { role, text in
            ["id": UUID().uuidString, "role": role, "text": text, "modelID": model,
             "isError": false, "timestamp": Date().timeIntervalSinceReferenceDate]
        }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 480,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 640, height: 480).fill()
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        messages[2]["imageBase64Strings"] = [png.base64EncodedString()]
        messages[2]["pastedTexts"] = [
            ["id": UUID().uuidString, "filename": "layout.txt",
             "content": "A complete pasted text attachment beside an image."]
        ]
        let file = directory.appendingPathComponent("long-response-layout.json")
        try JSONSerialization.data(withJSONObject: [
            "version": 1, "title": "Long response layout regression", "modelID": model,
            "modelName": "Nova 2 Lite", "provider": "Amazon", "messages": messages
        ]).write(to: file)
        importThread(file, in: app)

        let window = app.windows["MainWindow"]
        let transcript = window.descendants(matching: .any)["conversation.transcript"].firstMatch
        let web = transcript.webViews.firstMatch
        let following = window.staticTexts["AFTER_LONG_RESPONSE"]
        let image = window.buttons["Open image attachment"]
        let attachment = window.buttons["Open attachment layout.txt"]
        XCTAssertTrue(web.waitForExistence(timeout: 10))

        func assertLayout() {
            let laidOut = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                web.exists && web.frame.height > 2_000 && following.exists
                    && web.frame.maxY <= following.frame.minY
                    && image.exists && attachment.exists
                    && web.frame.maxY <= min(image.frame.minY, attachment.frame.minY)
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [laidOut], timeout: 8), .completed,
                           "The asynchronously rendered body must move the next message down, not overlap it.")
        }

        func assertWheelMovesBothMessages() {
            assertLayout()
            if web.frame.intersection(transcript.frame).height < 40 {
                transcript.scroll(byDeltaX: 0, deltaY: 240)
            }
            let webBefore = web.frame
            let followingBefore = following.frame
            let editorBefore = composer(app).frame
            // Target the visible WebKit body, even when the following prompt's
            // attachments occupy the center of the conversation viewport.
            let visible = webBefore.intersection(transcript.frame)
            XCTAssertGreaterThan(visible.height, 30)
            let point = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: visible.midX - window.frame.minX, dy: visible.midY - window.frame.minY))
            point.scroll(byDeltaX: 0, deltaY: 240)
            let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                web.exists && following.exists && abs(following.frame.minY - followingBefore.minY) > 40
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed,
                           "Wheel input over the response must move the conversation.")
            XCTAssertEqual(web.frame.minY - webBefore.minY, following.frame.minY - followingBefore.minY,
                           accuracy: 2, "The response and its neighbor must share one scroll offset.")
            XCTAssertEqual(web.frame.height, webBefore.height, accuracy: 2)
            XCTAssertEqual(composer(app).frame.minY, editorBefore.minY, accuracy: 1)
            assertLayout()
            app.buttons["Scroll to latest message"].click()
            XCTAssertTrue(response("FINAL_ASSISTANT_RESPONSE", in: app).isHittable)
        }

        assertWheelMovesBothMessages()
        for _ in 0..<2 {
            app.typeKey("b", modifierFlags: .command)
            assertWheelMovesBothMessages()
        }
        let originalWidth = web.frame.width
        let initialFrame = window.frame
        // AppKit can restore the narrow size left by the preceding appearance
        // scenario. Always change the actual width; dragging 900 → 900 did not
        // exercise reflow and made this regression test dependent on run order.
        let availableWidth = CGDisplayBounds(CGMainDisplayID()).maxX - initialFrame.minX
        let targetWidth: CGFloat = initialFrame.width > 980 ? 900 : min(1120, availableWidth)
        XCTAssertGreaterThan(abs(targetWidth - initialFrame.width), 20,
                             "The resize gesture must change width within the display's reachable coordinates.")
        let origin = window.coordinate(withNormalizedOffset: .zero)
        let corner = origin.withOffset(CGVector(dx: initialFrame.width - 6, dy: initialFrame.height - 6))
        corner.press(forDuration: 0.1,
                     thenDragTo: origin.withOffset(CGVector(dx: targetWidth - 6, dy: min(initialFrame.height, 674) - 6)),
                     withVelocity: .slow, thenHoldForDuration: 0.1)
        let reflowed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(window.frame.width - targetWidth) < 2 && web.exists && abs(web.frame.width - originalWidth) > 20
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reflowed], timeout: 8), .completed,
                       "Exercise actual Markdown reflow, not only moving the sidebar at a capped text width.")
        assertWheelMovesBothMessages()
        image.click()
        XCTAssertTrue(app.buttons["Zoom in"].waitForExistence(timeout: 5))
        app.buttons["Close image preview"].click()
        assertLayout()
        window.buttons["Activity"].click()
        window.buttons["Back"].click()
        assertWheelMovesBothMessages()
        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = "\(appearance) – long response and following messages share one layout"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testStreamingNativeToWebMarkdownKeepsFollowingMessagesOutsideTheResponse() async throws {
        let (app, _) = try launch(withRuntime: true)
        let window = app.windows["MainWindow"]
        // Match the hosted display locally. Offscreen WebKit text is not a
        // reliable accessibility target while the reader is above the bottom.
        let initialFrame = window.frame
        let width = min(initialFrame.width, 1024)
        let height = min(initialFrame.height, 634)
        if initialFrame.width > width || initialFrame.height > height {
            let origin = window.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: initialFrame.width - 6, dy: initialFrame.height - 6))
                .press(forDuration: 0.1,
                       thenDragTo: origin.withOffset(CGVector(dx: width - 6, dy: height - 6)),
                       withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertLessThanOrEqual(window.frame.width, 1026)
        XCTAssertLessThanOrEqual(window.frame.height, 636)
        send("[layout-stream] Grow this reply past the native Markdown threshold.", in: app)
        _ = response("LAYOUT_STREAM_BEGIN", in: app)
        let transcript = window.descendants(matching: .any)["conversation.transcript"].firstMatch
        XCTAssertFalse(transcript.webViews.firstMatch.exists, "The short reply starts in the native text renderer.")
        try await XCTUnwrap(runtime).growStream()
        let web = transcript.webViews.firstMatch
        let grown = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            web.exists && web.frame.height > 2_000 && app.buttons["Stop response"].exists
        }, object: nil)
        await fulfillment(of: [grown], timeout: 12)
        let scrollBefore = web.frame.minY
        transcript.scroll(byDeltaX: 0, deltaY: 240)
        let scrolled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            web.exists && web.frame.minY - scrollBefore > 40
        }, object: nil)
        await fulfillment(of: [scrolled], timeout: 5)
        let readingY = web.frame.minY
        try await XCTUnwrap(runtime).releaseStream()
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.buttons["Stop response"].exists && web.exists && web.frame.height > 2_000
        }, object: nil)
        let finishResult = await XCTWaiter.fulfillment(of: [finished], timeout: 12)
        XCTAssertEqual(finishResult, .completed)
        guard finishResult == .completed else { return }
        XCTAssertEqual(web.frame.minY, readingY, accuracy: 2,
                       "Finalizing the response must retain the passage the user scrolled to.")
        app.buttons["Scroll to latest message"].click()
        let finalMarker = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            // WebKit also exposes numeric heading levels as StaticText AXValues.
            // An untyped `value CONTAINS` query throws an Objective-C exception.
            // Search backwards from the end and compare only actual strings.
            web.staticTexts.allElementsBoundByIndex.reversed().contains { element in
                (element.label.contains("LAYOUT_STREAM_COMPLETE")
                    || (element.value as? String)?.contains("LAYOUT_STREAM_COMPLETE") == true)
                    && element.isHittable
            }
        }, object: nil)
        let markerResult = await XCTWaiter.fulfillment(of: [finalMarker], timeout: 8)
        XCTAssertEqual(markerResult, .completed, "The full completed response must be visible after returning to the bottom.")
        guard markerResult == .completed else { return }
        chooseModel("GPT-6 Astra", in: app)
        send("[queue-one] AFTER_STREAMED_RESPONSE", in: app)
        let following = window.staticTexts["[queue-one] AFTER_STREAMED_RESPONSE"]
        _ = response("QUEUE_ONE_COMPLETE", in: app)
        let separated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            web.exists && following.exists && web.frame.maxY <= following.frame.minY
        }, object: nil)
        await fulfillment(of: [separated], timeout: 8)
        XCTAssertTrue(app.descendants(matching: .any)["conversation.modelSwitch"].firstMatch.exists)
        XCTAssertEqual(try XCTUnwrap(runtime).requests().count, 2)
        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = "Streamed long response, model switch and next message remain separate"
        screenshot.lifetime = .keepAlways
        add(screenshot)
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
        try await assertStreamFinishesWhileReading(appearance: "light")
    }

    @MainActor
    func testDarkConversationRemainsResponsiveAfterFinishingAStreamWhileReading() async throws {
        try await assertStreamFinishesWhileReading(appearance: "dark")
    }

    @MainActor
    private func assertStreamFinishesWhileReading(appearance: String) async throws {
        let (app, directory) = try launch(appearance: appearance, withRuntime: true)
        importThread(try longConversation(in: directory), in: app)
        XCTAssertTrue(app.descendants(matching: .any)["conversation.transcript"].firstMatch.waitForExistence(timeout: 10))
        send("[stream] Keep the previous passage readable while this finishes.", in: app)
        _ = response("STREAM_BEGIN", in: app)
        let window = app.windows["MainWindow"]
        let transcript = window.descendants(matching: .any)["conversation.transcript"].firstMatch
        // Read the preceding completed turn. Its richer Markdown fixture has
        // variable height; the behavior under test is preserving this passage.
        let anchor = window.staticTexts["Fixture question 499"]
        for _ in 0..<10 {
            transcript.scroll(byDeltaX: 0, deltaY: 300)
            if anchor.exists, anchor.frame.minY > window.frame.minY + 80,
               anchor.frame.maxY < composer(app).frame.minY - 40 { break }
        }
        XCTAssertTrue(anchor.isHittable, "The test must read an older visible passage, not stay at the bottom.")
        let before = anchor.frame.minY
        try await XCTUnwrap(runtime).releaseStream()
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            window.exists && self.composer(app).exists && !app.buttons["Stop response"].exists
        }, object: nil)
        await fulfillment(of: [completed], timeout: 12)
        let preserved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            anchor.exists && abs(anchor.frame.minY - before) < 2
        }, object: nil)
        await fulfillment(of: [preserved], timeout: 5)
        XCTAssertTrue(app.buttons["Scroll to latest message"].exists)
        app.buttons["Scroll to latest message"].click()
        XCTAssertTrue(response("STREAM_COMPLETE", in: app).isHittable)
        let draft = "Continue reading after the response finishes."
        composer(app).click()
        composer(app).typeText(draft)
        XCTAssertEqual(composer(app).value as? String, draft,
                       "The composer must accept input after the transcript and footer settle.")
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
    func testLegacyImageHistoryIsFittedOnTheWireWithoutChangingStoredAttachments() throws {
        let (app, directory) = try launch(withRuntime: true)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 400,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 400).fill()
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let original = png.base64EncodedString()
        let document = Data((String(repeating: "A complete earlier document. 한국어\n", count: 1_500)
                             + "LEGACY_DOCUMENT_LAST_LINE").utf8)
        let model = "us.amazon.nova-2-lite-v1:0"
        let file = directory.appendingPathComponent("legacy-image.json")
        try JSONSerialization.data(withJSONObject: [
            "version": 1, "title": "Legacy image normalization", "modelID": model,
            "modelName": "Nova 2 Lite", "provider": "Amazon", "messages": [
                ["id": UUID().uuidString, "role": "user", "text": "An earlier long screenshot.",
                 "modelID": model, "isError": false, "timestamp": Date().timeIntervalSinceReferenceDate,
                 "imageBase64Strings": [original], "documentBase64Strings": [document.base64EncodedString()],
                 "documentFormats": ["txt"], "documentNames": ["Earlier document"]],
                ["id": UUID().uuidString, "role": "assistant", "text": "Keep this image for the next turn.",
                 "modelID": model, "isError": false, "timestamp": Date().timeIntervalSinceReferenceDate]
            ]
        ]).write(to: file)
        importThread(file, in: app)
        send("[attachments] Continue with the earlier screenshot.", in: app)
        _ = response("ATTACHMENTS_RECEIVED", in: app)
        let request = try XCTUnwrap(try runtime?.requests().last)
        let body = try XCTUnwrap(request["body"] as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let images = messages.flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .compactMap { $0["image"] as? [String: Any] }
        XCTAssertEqual(images.count, 1, "The earlier image must reach the actual SDK request.")
        let source = try XCTUnwrap(images.first?["source"] as? [String: Any])
        let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(source["bytes"] as? String)))
        let fitted = try XCTUnwrap(NSBitmapImageRep(data: bytes))
        XCTAssertEqual(fitted.pixelsWide, 20)
        XCTAssertEqual(fitted.pixelsHigh, 400)
        let documents = messages.flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .compactMap { $0["document"] as? [String: Any] }
        XCTAssertEqual(documents.count, 1)
        let documentSource = try XCTUnwrap(documents.first?["source"] as? [String: Any])
        let documentBytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(documentSource["bytes"] as? String)))
        XCTAssertEqual(documentBytes, document, "Normalizing earlier images must keep every byte of the accompanying document.")
        let historyFiles = try FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent("history"), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix("_unified_history.json") }
        let stored = try historyFiles.flatMap { url -> [[String: Any]] in
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            return object["messages"] as? [[String: Any]] ?? []
        }.flatMap { $0["imageBase64Strings"] as? [String] ?? [] }
        XCTAssertEqual(stored, [original], "Resending old images must preserve their original stored bytes.")
    }

    @MainActor
    func testLunaDocumentHistoryUsesResponsesAndKeepsRealLocalToolsAndFollowups() throws {
        let (app, directory) = try launch(withRuntime: true)
        let localFile = directory.appendingPathComponent("responses-tool.txt")
        try Data("RESPONSES_FILE_MARKER".utf8).write(to: localFile)
        let document = Data((String(repeating: "An earlier document. 한국어\n", count: 1_000)
                             + "LUNA_DOCUMENT_LAST_LINE").utf8).base64EncodedString()
        let model = "us.openai.gpt-5.6-luna"
        let file = directory.appendingPathComponent("luna-history.json")
        try JSONSerialization.data(withJSONObject: [
            "version": 1, "title": "Luna document continuation", "modelID": model,
            "modelName": "GPT-5.6 Luna", "provider": "OpenAI", "messages": [
                ["id": UUID().uuidString, "role": "user", "text": "Keep the complete attached document.",
                 "modelID": model, "isError": false, "timestamp": Date().timeIntervalSinceReferenceDate,
                 "documentBase64Strings": [document], "documentFormats": ["txt"],
                 "documentNames": ["Earlier report"]],
                ["id": UUID().uuidString, "role": "assistant", "text": "Ready for the next request.",
                 "modelID": model, "isError": false, "timestamp": Date().timeIntervalSinceReferenceDate]
            ]
        ]).write(to: file)
        importThread(file, in: app)
        send("[responses-document-tool] " + localFile.path, in: app)
        _ = response("RESPONSES_DOCUMENT_TOOL_COMPLETE", in: app)
        send("Continue with the earlier document.", in: app)
        _ = response("RESPONSES_DOCUMENT_FOLLOWUP_COMPLETE", in: app)

        let requests = try XCTUnwrap(runtime).requests()
        XCTAssertEqual(requests.count, 3, "One local tool cycle followed by a separate user turn.")
        for request in requests {
            XCTAssertEqual(request["path"] as? String, "/openai/v1/responses")
            let body = try XCTUnwrap(request["body"] as? [String: Any])
            XCTAssertEqual(body["model"] as? String, model)
            XCTAssertEqual(body["store"] as? Bool, false)
            let input = try XCTUnwrap(body["input"] as? [[String: Any]])
            let documents = input.flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .filter { $0["type"] as? String == "input_file" }
            XCTAssertEqual(documents.count, 1)
            XCTAssertEqual(documents[0]["filename"] as? String, "Earlier report.txt")
            XCTAssertEqual(documents[0]["file_data"] as? String, "data:text/plain;base64," + document)
        }
        let continuation = try XCTUnwrap(requests[1]["body"] as? [String: Any])
        let input = try XCTUnwrap(continuation["input"] as? [[String: Any]])
        XCTAssertTrue(input.contains { $0["encrypted_content"] as? String == "FIXTURE_REASONING" },
                      "The stateless continuation must return the reasoning item without rendering it.")
        let result = try XCTUnwrap(input.first { $0["type"] as? String == "function_call_output" })
        XCTAssertEqual(result["call_id"] as? String, "responses-file-read")
        XCTAssertTrue((result["output"] as? String ?? "").contains("RESPONSES_FILE_MARKER"),
                      "The app must run the real local file tool rather than synthesizing its result.")

        let historyFiles = try FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent("history"), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix("_unified_history.json") }
        let stored = try historyFiles.flatMap { url -> [[String: Any]] in
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            return object["messages"] as? [[String: Any]] ?? []
        }
        XCTAssertEqual(stored.flatMap { $0["documentNames"] as? [String] ?? [] }, ["Earlier report"])
        XCTAssertEqual(stored.flatMap { $0["documentBase64Strings"] as? [String] ?? [] }, [document])
        XCTAssertFalse(stored.contains { $0["isError"] as? Bool == true })
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
