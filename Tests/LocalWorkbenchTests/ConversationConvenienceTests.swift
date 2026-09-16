import XCTest
@testable import LocalWorkbench

final class ConversationConvenienceTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bedrock-convenience-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func fixture() -> ConversationHistory {
        let prompt = Message(id: UUID(), text: "Find the issue", role: .user, timestamp: Date(), isError: false,
                             imageBase64Strings: [Data("image fixture".utf8).base64EncodedString()],
                             documentBase64Strings: [Data("document".utf8).base64EncodedString()],
                             documentFormats: ["txt"], documentNames: ["example"],
                             pastedTexts: [.init(filename: "paste.txt", content: "literal ``` fence\n내용")])
        let call = Message.ToolUse(toolId: "read-1", toolName: "local_read_file", inputs: .object(["path": .string("/tmp/example")]),
                                   result: "line 1\nline 2", status: "success")
        let assistant = Message(id: UUID(), text: "Reading", role: .assistant, timestamp: Date(), isError: false, toolUses: [call])
        let result = Message(id: UUID(), text: "", role: .user, timestamp: Date(), isError: false, toolUses: [call])
        let answer = Message(id: UUID(), text: "Use café 😀 한국어 instead.", role: .assistant, timestamp: Date(), isError: false)
        return .init(chatId: "test-thread", modelId: "amazon.nova-2-lite-v1:0", messages: [prompt, assistant, result, answer],
                     systemPrompt: "Preserve this prompt.")
    }

    func testBranchIncludesHiddenToolResultsAndDoesNotChangeTheOriginal() throws {
        let original = fixture()
        let branch = try ConversationEditing.messages(in: original, through: original.messages[1].id)
        XCTAssertEqual(branch.map(\.id), Array(original.messages.prefix(3)).map(\.id))
        XCTAssertEqual(branch[2].toolUses?.first?.toolId, "read-1")
        XCTAssertEqual(original.messages.count, 4)
        XCTAssertEqual(original.systemPrompt, "Preserve this prompt.")
        XCTAssertThrowsError(try ConversationEditing.messages(in: original, through: UUID()))
    }

    func testRetryFindsTheActualUserPromptAndKeepsEveryAttachment() throws {
        let original = fixture()
        let prompt = try ConversationEditing.prompt(before: original.messages[3].id, in: original)
        XCTAssertEqual(prompt, original.messages[0])
        XCTAssertEqual(prompt.pastedTexts?.first?.content, "literal ``` fence\n내용")
        XCTAssertTrue(try ConversationEditing.messages(in: original, before: prompt.id).isEmpty)
        XCTAssertThrowsError(try ConversationEditing.prompt(before: UUID(), in: original))
    }

    func testMarkdownExportKeepsPastedTextDocumentsToolInputAndOutput() throws {
        let original = fixture()
        let markdown = try ConversationEditing.markdown(title: "Thread", modelName: "Nova", modelID: original.modelId, messages: original.messages)
        XCTAssertTrue(markdown.contains("````text\nliteral ``` fence\n내용\n````"))
        XCTAssertTrue(markdown.contains("Attachment: example"))
        XCTAssertTrue(markdown.contains("Image attachments: 1"))
        XCTAssertTrue(markdown.contains("\"path\" : \"/tmp/example\""))
        XCTAssertTrue(markdown.contains("line 1\nline 2"))
        XCTAssertEqual(markdown.components(separatedBy: "## You\n").count - 1, 1)
        XCTAssertEqual(markdown.components(separatedBy: "### Tool: local_read_file").count - 1, 1)
    }

    func testArchiveRoundTripPreservesOriginalMetadataAndRejectsMissingAttachmentMetadata() throws {
        let source = fixture()
        let archive = ConversationArchive(title: "Thread", modelID: source.modelId, modelName: "Nova", provider: "Amazon",
                                          messages: source.messages, systemPrompt: source.systemPrompt)
        let data = try ConversationArchiveCodec.encode(archive)
        let decoded = try JSONDecoder().decode(ConversationArchive.self, from: data)
        XCTAssertEqual(decoded.messages, source.messages)
        XCTAssertEqual(decoded.systemPrompt, source.systemPrompt)
        var broken = archive
        broken.messages[0].documentNames = []
        XCTAssertThrowsError(try ConversationArchiveCodec.encode(broken))
        broken = archive
        broken.messages[0].imageBase64Strings = ["img_../../outside"]
        XCTAssertThrowsError(try ConversationArchiveCodec.encode(broken))
        broken = archive
        broken.version = 99
        XCTAssertThrowsError(try ConversationArchiveCodec.encode(broken))
    }

    func testArchiveReaderRejectsOversizedFilesWithoutChangingThem() throws {
        let url = try directory().appendingPathComponent("oversized.json")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(ConversationArchiveCodec.maximumBytes + 1))
        try handle.close()
        XCTAssertThrowsError(try ConversationArchiveCodec.read(url))
        XCTAssertEqual(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, ConversationArchiveCodec.maximumBytes + 1)
    }

    func testImageReferencesRejectTraversalMissingFilesAndSymlinkEscapes() throws {
        let root = try directory()
        let images = root.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        XCTAssertThrowsError(try LocalImageReference.read("img_../outside", directory: images))
        XCTAssertThrowsError(try LocalImageReference.read("img_\(UUID())", directory: images))
        let secret = root.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: secret)
        let id = "img_\(UUID())"
        try FileManager.default.createSymbolicLink(at: images.appendingPathComponent(id + ".png"), withDestinationURL: secret)
        XCTAssertThrowsError(try LocalImageReference.read(id, directory: images))
        let direct = Data("valid bytes".utf8).base64EncodedString()
        XCTAssertEqual(try LocalImageReference.read(direct, directory: images), Data("valid bytes".utf8))
    }

    func testSearchFindsUnifiedAndLegacyUnicodeTextAndReportsCorruptFiles() async throws {
        let root = try directory()
        let history = fixture()
        let unified = root.appendingPathComponent("unified.json")
        try JSONEncoder().encode(history).write(to: unified)
        let legacy = root.appendingPathComponent("legacy.json")
        try JSONEncoder().encode([MessageData(text: "Old café 😀 한국어 text", user: "Assistant", sentTime: Date())]).write(to: legacy)
        let corrupt = root.appendingPathComponent("corrupt.json")
        try Data("{broken".utf8).write(to: corrupt)
        let inputs = [
            ConversationSearchInput(id: history.chatId, unifiedURL: unified, legacyURL: root.appendingPathComponent("missing")),
            ConversationSearchInput(id: "legacy-thread", unifiedURL: root.appendingPathComponent("missing"), legacyURL: legacy),
            ConversationSearchInput(id: "broken", unifiedURL: corrupt, legacyURL: legacy)
        ]
        let index = ConversationSearchIndex()
        let result = await index.search("CAFE 😀 한국어", inputs: inputs)
        XCTAssertEqual(result.hits.count, 2)
        XCTAssertEqual(result.hits[history.chatId]?.messageID, history.messages.last?.id)
        XCTAssertEqual(result.hits[history.chatId]?.snippet, "Use café 😀 한국어 instead.")
        XCTAssertEqual(result.unreadableCount, 1)
        XCTAssertEqual(try Data(contentsOf: corrupt), Data("{broken".utf8))
    }

    func testSearchInvalidatesChangedFilesAndHonorsCancellation() async throws {
        let root = try directory()
        let url = root.appendingPathComponent("history.json")
        var history = fixture()
        try JSONEncoder().encode(history).write(to: url)
        let inputs = [ConversationSearchInput(id: history.chatId, unifiedURL: url, legacyURL: root.appendingPathComponent("missing"))]
        let index = ConversationSearchIndex()
        let first = await index.search("instead", inputs: inputs)
        XCTAssertEqual(first.hits.count, 1)
        history.messages[3].text = "A different replacement"
        try JSONEncoder().encode(history).write(to: url)
        let second = await index.search("instead", inputs: inputs)
        XCTAssertTrue(second.hits.isEmpty)
        let third = await index.search("replacement", inputs: inputs)
        XCTAssertEqual(third.hits.count, 1)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await index.search("replacement", inputs: inputs)
        }
        let result = await cancelled.value
        XCTAssertTrue(result.hits.isEmpty)
    }

    func testQueuePreservesTextAttachmentsModelsAndFIFOAcrossDiskRoundTrip() throws {
        let root = try directory()
        let message = fixture().messages[0]
        let first = QueuedPrompt(message: .init(text: "First", user: "User", sentTime: Date(),
            imageBase64Strings: message.imageBase64Strings, documentBase64Strings: message.documentBase64Strings,
            documentFormats: message.documentFormats, documentNames: message.documentNames, pastedTexts: message.pastedTexts),
            modelID: "amazon.nova-2-lite-v1:0")
        let second = QueuedPrompt(message: .init(text: "Second", user: "User", sentTime: Date()), modelID: "openai.gpt-6-astra")
        var queue = ConversationOutbox()
        try queue.append(first)
        try queue.append(second)
        let url = try ConversationOutboxFile.url(threadID: "queue-test", directory: root)
        try ConversationOutboxFile.write(queue, to: url)
        let loaded = try ConversationOutboxFile.read(url)
        XCTAssertEqual(loaded.queued, [first, second])
        XCTAssertEqual(loaded.queued[0].attachmentCount, 3)
        XCTAssertEqual(loaded.queued[1].modelID, "openai.gpt-6-astra")
        XCTAssertThrowsError(try queue.append(first))
        queue.moveToFront(second.id)
        XCTAssertEqual(queue.queued.map(\.id), [second.id, first.id])
    }

    func testQueueRecoveryNeverResendsCheckpointedPromptsAndPausesUnsentWork() throws {
        let first = QueuedPrompt(message: .init(text: "Started", user: "User", sentTime: Date()), modelID: "nova")
        let second = QueuedPrompt(message: .init(text: "Waiting", user: "User", sentTime: Date()), modelID: "astra")
        var checkpointed = ConversationOutbox(queued: [second], inFlight: first)
        checkpointed.recover(sentMessageIDs: [first.id])
        XCTAssertEqual(checkpointed.queued, [second])
        XCTAssertNil(checkpointed.inFlight)
        XCTAssertNotNil(checkpointed.pauseReason)
        var notStarted = ConversationOutbox(queued: [second], inFlight: first)
        notStarted.recover(sentMessageIDs: [])
        XCTAssertEqual(notStarted.queued, [first, second])
        notStarted.recover(sentMessageIDs: [])
        XCTAssertEqual(notStarted.queued, [first, second])
    }

    func testQueueFullRecoveryKeepsEveryPromptAndProtectsFutureOrCorruptFiles() throws {
        var queue = ConversationOutbox()
        for index in 0..<20 {
            try queue.append(.init(message: .init(text: "\(index)", user: "User", sentTime: Date()), modelID: "nova"))
        }
        let interrupted = QueuedPrompt(message: .init(text: "Interrupted", user: "User", sentTime: Date()), modelID: "nova")
        XCTAssertThrowsError(try queue.append(interrupted))
        queue.inFlight = interrupted
        queue.recover(sentMessageIDs: [])
        XCTAssertEqual(queue.queued.count, 21)
        let url = try directory().appendingPathComponent("queue.json")
        try ConversationOutboxFile.write(queue, to: url)
        XCTAssertEqual(try ConversationOutboxFile.read(url).queued.count, 21)
        queue.version = 99
        let future = try JSONEncoder().encode(queue)
        try future.write(to: url)
        XCTAssertThrowsError(try ConversationOutboxFile.write(.init(), to: url))
        XCTAssertEqual(try Data(contentsOf: url), future)
        try Data("{broken".utf8).write(to: url)
        XCTAssertThrowsError(try ConversationOutboxFile.write(.init(), to: url))
        XCTAssertEqual(try Data(contentsOf: url), Data("{broken".utf8))
        XCTAssertThrowsError(try ConversationOutboxFile.url(threadID: "../escape", directory: url.deletingLastPathComponent()))
    }
}
