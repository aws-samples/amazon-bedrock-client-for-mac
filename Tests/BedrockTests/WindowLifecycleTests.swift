import AppKit
import Combine
import SwiftUI
import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class WindowLifecycleTests: XCTestCase {
    @MainActor
    func testLoadingPromptPresetsPreservesInstructionsWithoutPublishingUnchangedSettings() throws {
        let suite = "PromptLifecycle-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var prompt = "Keep the existing instructions."
        var applied: [String] = []
        func makeStore() -> PromptTemplateStore {
            PromptTemplateStore(defaults: defaults, currentSystemPrompt: { prompt },
                                updateSystemPrompt: { prompt = $0; applied.append($0) })
        }
        let store = makeStore()
        let initial = try XCTUnwrap(store.selectedTemplate)
        XCTAssertEqual(initial.content, prompt)
        XCTAssertTrue(applied.isEmpty, "Opening Models must not publish an unchanged setting during layout.")
        store.selectTemplate(initial)
        store.updateTemplate(initial)
        XCTAssertTrue(applied.isEmpty, "Reselecting or saving an unchanged preset must not invalidate the scene.")

        store.addTemplate(name: "Brief", content: "Answer in one sentence.")
        let selectedID = store.selectedTemplateId
        XCTAssertEqual(applied, ["Answer in one sentence."])
        let reopened = makeStore()
        XCTAssertEqual(reopened.selectedTemplateId, selectedID)
        XCTAssertEqual(reopened.selectedTemplate?.content, prompt)
        XCTAssertEqual(applied.count, 1, "Reloading a persisted selection must not rewrite the active prompt.")
        var edited = try XCTUnwrap(reopened.selectedTemplate)
        edited.content = "Answer with a short example."
        reopened.updateTemplate(edited)
        XCTAssertEqual(applied, ["Answer in one sentence.", "Answer with a short example."])
    }

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
    func testArchiveRestoreAndPermanentDeletePreserveHistoryDraftsAndNavigation() async throws {
        let store = AppStore.shared
        let chats = ConversationStore.shared
        let previousSelection = store.selectedThreadID
        let previousCompanion = store.companionThreadID
        let previousPreferences = store.preferences
        let model = "us.amazon.nova-2-lite-v1:0"
        let searchMarker = "ARCHIVE_SEARCH_\(UUID().uuidString)"
        let message = Message(id: UUID(), text: searchMarker, role: .user,
                              timestamp: Date(), isError: false, modelID: model)
        var created: [String] = []
        defer {
            for id in created {
                chats.setIsLoading(false, for: id)
                _ = chats.deleteChat(with: id)
                store.state.threads.removeValue(forKey: id)
            }
            store.selectedThreadID = previousSelection
            store.companionThreadID = previousCompanion
            store.preferences = previousPreferences
        }
        func create(_ title: String, hoursAhead: Double) async throws -> ChatModel {
            let chat = try await chats.createConversation(
                modelID: model, modelName: "Nova 2 Lite", provider: "Amazon", title: title,
                messages: [message], systemPrompt: "Preserved system prompt",
                lastMessageDate: Date().addingTimeInterval(hoursAhead * 3600))
            created.append(chat.chatId)
            return chat
        }
        let next = try await create("Most recent active conversation", hoursAhead: 1)
        let current = try await create("Conversation to archive", hoursAhead: 2)
        let alreadyArchived = try await create("A newer archived conversation", hoursAhead: 3)
        store.archive(alreadyArchived.chatId)
        store.selectThread(current.chatId)
        store.companionThreadID = current.chatId
        let metadata = ThreadMetadata(draft: "Unsent draft", skillIDs: ["code-review"],
                                      systemPrompt: "Preserved system prompt", pinnedAt: Date(),
                                      hasQueuedMessages: true, hasDraftAttachments: true)
        store.state.threads[current.chatId] = metadata
        let historyURL = URL(fileURLWithPath: PreferencesStore.shared.defaultDirectory)
            .appendingPathComponent("history/\(current.chatId)_unified_history.json")
        let queueURL = try ConversationOutboxFile.url(threadID: current.chatId, directory: store.directory)
        let draftURL = try ConversationAttachmentDraftFile.url(threadID: current.chatId, directory: store.directory)
        let queued = QueuedPrompt(message: MessageData(text: "Queued follow-up", user: "User", sentTime: Date()),
                                  modelID: model)
        try ConversationOutboxFile.write(ConversationOutbox(queued: [queued]), to: queueURL)
        let attachment = DraftAttachment(id: UUID(), data: Data("Draft attachment".utf8),
                                        filename: "draft.txt", format: "txt", pastedText: "Draft attachment")
        try ConversationAttachmentDraftFile.write(.init(documents: [attachment]), to: draftURL)
        let urls = [historyURL, queueURL, draftURL]
        let originalBytes = try urls.map { try Data(contentsOf: $0) }

        store.archive(current.chatId)
        XCTAssertTrue(store.thread(current.chatId).archived)
        XCTAssertEqual(store.selectedThreadID, next.chatId, "⌘D must choose the latest active chat, ignoring archived chats.")
        XCTAssertEqual(store.preferences.lastThreadID, next.chatId)
        XCTAssertNil(store.companionThreadID)
        XCTAssertEqual(try urls.map { try Data(contentsOf: $0) }, originalBytes)
        store.preferences.toolProfile = .all
        store.preferences.disabledTools.remove(.searchConversations)
        let hiddenSearch = await LocalToolExecutor.execute(
            kind: .searchConversations, input: .object(["query": .string(searchMarker)]),
            threadID: next.chatId, modelID: model)
        XCTAssertEqual(hiddenSearch.status, "success")
        XCTAssertTrue(hiddenSearch.text.contains(next.chatId))
        XCTAssertFalse(hiddenSearch.text.contains(current.chatId), "Tools must not expose archived conversation content.")
        XCTAssertFalse(hiddenSearch.text.contains(alreadyArchived.chatId))

        store.restore(current.chatId)
        XCTAssertEqual(store.thread(current.chatId), metadata)
        let restoredSearch = await LocalToolExecutor.execute(
            kind: .searchConversations, input: .object(["query": .string(searchMarker)]),
            threadID: next.chatId, modelID: model)
        XCTAssertTrue(restoredSearch.text.contains(current.chatId), "Restored conversations must return to normal search.")
        store.deletePermanently(current.chatId)
        XCTAssertNotNil(chats.getChatModel(for: current.chatId), "An active chat cannot be permanently deleted.")
        XCTAssertEqual(try urls.map { try Data(contentsOf: $0) }, originalBytes)

        store.archive(current.chatId)
        chats.setIsLoading(true, for: current.chatId)
        store.deletePermanently(current.chatId)
        XCTAssertNotNil(chats.getChatModel(for: current.chatId), "A running conversation must retain its files.")
        XCTAssertEqual(try urls.map { try Data(contentsOf: $0) }, originalBytes)
        chats.setIsLoading(false, for: current.chatId)
        store.deletePermanently(current.chatId)
        XCTAssertNil(chats.getChatModel(for: current.chatId))
        XCTAssertNil(store.state.threads[current.chatId])
        for url in urls { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)) }
        XCTAssertNotNil(chats.getChatModel(for: next.chatId))
        XCTAssertTrue(store.thread(alreadyArchived.chatId).archived)
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
