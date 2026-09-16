import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class ClipboardRenderingTests: XCTestCase {
    @MainActor
    func testPastingSourceFileURLsUsesTheDocumentImporterWithoutReplacingDraftText() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let swift = directory.appendingPathComponent("한글 source.swift")
        let json = directory.appendingPathComponent("settings.json")
        try Data("let value = 42\n".utf8).write(to: swift)
        try Data("{\"value\":42}\n".utf8).write(to: json)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        XCTAssertTrue(board.writeObjects([swift as NSURL, json as NSURL]))

        let editor = MyTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 80))
        editor.string = "Keep this draft"
        var imported: [URL] = []
        editor.onPasteDocument = { imported.append($0) }
        XCTAssertTrue(editor.handlePasteboard(board))
        XCTAssertEqual(imported, [swift, json])
        XCTAssertEqual(editor.string, "Keep this draft")
    }

    private static func isOnMainThread() -> Bool { Thread.isMainThread }
    private func png(width: Int, height: Int) throws -> Data {
        let color = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: color,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @MainActor
    func testAttachmentDraftRestoresStableIDsAndKeepsNewlyPastedFiles() async throws {
        let original = SharedMediaDataSource()
        let prepared = try ClipboardImageProcessor.decode(png(width: 900, height: 700))
        XCTAssertTrue(original.addPreparedImage(prepared, filename: "원본.png"))
        original.addDocument(Data("document".utf8), fileExtension: "txt", filename: "memo.txt")
        original.addPastedText("  한글\n원문 그대로  ", filename: "paste.txt")
        let draft = try original.attachmentDraft()
        let restored = SharedMediaDataSource()
        restored.addPastedText("A new paste", filename: "new.txt")
        let newID = restored.documentIDs[0]
        try await restored.restoreAttachmentDraft(draft)
        XCTAssertEqual(restored.imageIDs, original.imageIDs)
        XCTAssertEqual(restored.imageFilenames, ["원본.png"])
        XCTAssertEqual(restored.documentIDs, [newID] + original.documentIDs)
        XCTAssertEqual(restored.textPreviews.last!, "  한글\n원문 그대로  ")
        let count = restored.documents.count
        try await restored.restoreAttachmentDraft(draft)
        XCTAssertEqual(restored.documents.count, count, "Restoring twice must not duplicate files.")
        XCTAssertFalse(restored.isImporting)
    }

    @MainActor
    func testCorruptDraftImageDoesNotConsumeExistingAttachments() async throws {
        let restored = SharedMediaDataSource()
        restored.addPastedText("Keep this", filename: "draft.txt")
        let id = restored.documentIDs[0]
        let invalid = ConversationAttachmentDraft(images: [
            .init(id: UUID(), data: Data("not an image".utf8), filename: "bad.png", format: "png")
        ])
        do {
            try await restored.restoreAttachmentDraft(invalid)
            XCTFail("Invalid image bytes were accepted.")
        } catch {
            XCTAssertEqual(restored.documentIDs, [id])
            XCTAssertEqual(restored.textPreviews[0], "Keep this")
            XCTAssertFalse(restored.isImporting)
        }
    }

    @MainActor
    func testComposerCommandsDoNotInterceptIMEComposition() {
        _ = NSApplication.shared
        let editor = MyTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 100))
        var commands: [String] = []
        var commits = 0
        editor.onCommit = { commits += 1 }
        editor.onComposerCommand = { key in
            switch key {
            case .up: commands.append("up")
            case .down: commands.append("down")
            case .accept: commands.append("accept")
            case .dismiss: commands.append("dismiss")
            }
            return true
        }
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(commands, ["down", "accept"])
        XCTAssertEqual(commits, 0)
        editor.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(commands, ["down", "accept"])
        XCTAssertEqual(commits, 0)
    }

    @MainActor
    func testQueuedAttachmentRemovalKeepsNewDraftAndPastedTextEditsKeepIdentity() throws {
        let media = SharedMediaDataSource()
        let image = try ClipboardImageProcessor.decode(png(width: 8, height: 6))
        XCTAssertTrue(media.addPreparedImage(image))
        media.addPastedText("Original", filename: "paste.txt")
        let images = Set(media.imageIDs)
        let documents = Set(media.documentIDs)
        XCTAssertTrue(media.addPreparedImage(image))
        media.addPastedText("New draft", filename: "next.txt")
        let nextID = try XCTUnwrap(media.documentIDs.last)
        media.remove(imageIDs: images, documentIDs: documents)
        XCTAssertEqual(media.images.count, 1)
        XCTAssertEqual(media.documents.count, 1)
        XCTAssertEqual(media.documentIDs[0], nextID)
        media.updatePastedText(id: nextID, text: "Edited 한글")
        XCTAssertEqual(media.documentIDs[0], nextID)
        XCTAssertEqual(media.textPreviews[0], "Edited 한글")
        XCTAssertEqual(media.documents[0], Data("Edited 한글".utf8))
    }

    @MainActor
    func testRetryAttachmentRestoreUsesPreparedImagesAndRetainsPastedText() async throws {
        let media = SharedMediaDataSource()
        let image = try png(width: 1200, height: 900)
        let original = MessageData(text: "Retry", user: "User", sentTime: Date(),
                                  imageBase64Strings: [image.base64EncodedString()],
                                  documentBase64Strings: [Data("document".utf8).base64EncodedString()],
                                  documentFormats: ["txt"], documentNames: ["example"],
                                  pastedTexts: [.init(filename: "paste.txt", content: "내용 그대로")])
        try await media.restore(original, imagesDirectory: FileManager.default.temporaryDirectory)
        XCTAssertEqual(media.images.count, 1)
        XCTAssertNotNil(media.imageEncodedData[0])
        XCTAssertEqual(media.documents.count, 2)
        XCTAssertEqual(media.documentFilenames, ["example", "paste.txt"])
        XCTAssertEqual(media.textPreviews[1], "내용 그대로")
        XCTAssertFalse(media.isImporting)
    }

    @MainActor
    func testRetryRestoreKeepsPasteAddedWhileImagesDecode() async throws {
        let media = SharedMediaDataSource()
        media.addPastedText("Replace this earlier draft", filename: "old.txt")
        let source = try png(width: 3200, height: 1800).base64EncodedString()
        let original = MessageData(text: "Original", user: "User", sentTime: Date(),
                                   imageBase64Strings: [source],
                                   pastedTexts: [.init(filename: "original.txt", content: "Original pasted content")])
        let restoring = Task { try await media.restore(original, imagesDirectory: FileManager.default.temporaryDirectory) }
        while !media.isImporting { await Task.yield() }
        media.addPastedText("New paste made during restore", filename: "new.txt")
        let newID = try XCTUnwrap(media.documentIDs.last)
        try await restoring.value
        XCTAssertEqual(media.images.count, 1)
        XCTAssertEqual(media.documentIDs.first, newID)
        XCTAssertEqual(media.documentFilenames, ["new.txt", "original.txt"])
        XCTAssertEqual(media.textPreviews.first!, "New paste made during restore")
    }

    func testImagePreparationHandlesSmallAndLargeImagesWithBoundedPreview() async throws {
        let data = try png(width: 3200, height: 1800)
        let (image, onMain) = try await Task.detached {
            (try await ClipboardImageProcessor.prepare(.data(data)), Self.isOnMainThread())
        }.value
        XCTAssertFalse(onMain)
        XCTAssertEqual(image.width, 2560)
        XCTAssertEqual(image.height, 1440)
        XCTAssertLessThanOrEqual(image.data.count, ClipboardImageProcessor.maximumOutputBytes)
        let preview = try XCTUnwrap(CGImageSourceCreateWithData(image.preview as CFData, nil))
        let metadata = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(preview, 0, nil) as? [CFString: Any])
        XCTAssertLessThanOrEqual(metadata[kCGImagePropertyPixelWidth] as? Int ?? .max, 480)
        let small = try ClipboardImageProcessor.decode(png(width: 4, height: 3))
        XCTAssertEqual(small.width, 4)
        XCTAssertEqual(small.height, 3)
        XCTAssertEqual(small.fileExtension, "png")
    }

    func testImageDecoderRejectsNonImagesAndOversizedInput() {
        XCTAssertThrowsError(try ClipboardImageProcessor.decode(Data("<html><script>alert(1)</script></html>".utf8)))
        XCTAssertThrowsError(try ClipboardImageProcessor.decode(Data(repeating: 0, count: ClipboardImageProcessor.maximumInputBytes + 1)))
    }

    @MainActor
    func testMixedHTMLTextAndMultipleImagesPasteWithoutHTMLImporter() async throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("bedrock-paste-test-\(UUID())"))
        defer { board.releaseGlobally() }
        let text = String(repeating: "Native paste 한글 👩🏽‍💻\n", count: 900)
        let first = NSPasteboardItem()
        first.setString(text, forType: .string)
        first.setString("<script>throw new Error('must not run')</script><img src='https://example.invalid/never.png'><p>Wrong HTML text</p>", forType: .html)
        let second = NSPasteboardItem()
        first.setData(try png(width: 30, height: 20), forType: .png)
        second.setData(try png(width: 40, height: 30), forType: .png)
        XCTAssertTrue(board.writeObjects([first, second]))
        let view = MyTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 120))
        view.isRichText = false
        let completed = expectation(description: "Mixed paste completed")
        var pastedText = ""
        var widths: [Int] = []
        var errors: [String] = []
        view.onPasteLargeText = { value, _ in pastedText = value }
        view.onPastePreparedImage = { widths.append($0.width) }
        view.onPasteError = { errors.append($0) }
        view.onPasteCompleted = { completed.fulfill() }
        XCTAssertTrue(view.handlePasteboard(board))
        XCTAssertEqual(pastedText, text) // Text does not wait for image work.
        await fulfillment(of: [completed], timeout: 10)
        XCTAssertEqual(widths, [30, 40])
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(view.string, "")
    }

    @MainActor
    func testHTMLOnlyPasteAndConsecutiveImagesPreserveOrder() async throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("bedrock-html-test-\(UUID())"))
        defer { board.releaseGlobally() }
        let view = MyTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 120))
        view.isRichText = false
        view.treatLargeTextAsFile = false
        let firstData = try png(width: 12, height: 8).base64EncodedString()
        let secondData = try png(width: 24, height: 16).base64EncodedString()
        board.setString("<p>안녕 &amp; &#128075;</p><img src='data:image/png;base64,\(firstData)'>", forType: .html)
        let completed = expectation(description: "Consecutive pastes completed")
        var widths: [Int] = []
        view.onPastePreparedImage = { widths.append($0.width) }
        view.onPasteCompleted = { completed.fulfill() }
        XCTAssertTrue(view.handlePasteboard(board))
        board.clearContents()
        board.setString("<p>Second</p><img src='data:image/png;base64,\(secondData)'>", forType: .html)
        XCTAssertTrue(view.handlePasteboard(board))
        await fulfillment(of: [completed], timeout: 10)
        XCTAssertEqual(widths, [12, 24])
        XCTAssertTrue(view.string.contains("안녕 & 👋"))
        XCTAssertTrue(view.string.hasSuffix("Second"))
    }

    @MainActor
    func testCancelPasteDoesNotAttachToAnotherConversation() async throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("bedrock-cancel-paste-\(UUID())"))
        defer { board.releaseGlobally() }
        board.setData(try png(width: 100, height: 80), forType: .png)
        let view = MyTextView(frame: .zero)
        var images = 0
        view.onPastePreparedImage = { _ in images += 1 }
        XCTAssertTrue(view.handlePasteboard(board))
        view.cancelPendingPastes()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(images, 0)
    }

    @MainActor
    func testComposerPreviewAndRequestBytesRemainSeparateWhenCopied() throws {
        let image = try ClipboardImageProcessor.decode(png(width: 1200, height: 900))
        let source = SharedMediaDataSource()
        XCTAssertTrue(source.addPreparedImage(image))
        source.addPastedText("Text attachment", filename: "text")
        let imageID = try XCTUnwrap(source.imageIDs.first)
        let documentID = try XCTUnwrap(source.documentIDs.first)
        let destination = SharedMediaDataSource()
        destination.copy(from: source)
        source.clear()
        XCTAssertEqual(destination.images.count, 1)
        XCTAssertEqual(destination.imageIDs, [imageID])
        XCTAssertEqual(destination.documentIDs, [documentID])
        XCTAssertEqual(destination.imageEncodedData.first!, image.data)
        XCTAssertEqual(destination.documentFilenames, ["text"])
        XCTAssertNotNil(destination.imagePreviewSource(at: 0))
        destination.removeImage(at: 0)
        XCTAssertTrue(destination.imageEncodedData.isEmpty)
        destination.removeImage(at: -1) // Invalid removal must not crash.
    }

    @MainActor
    func testFileImportPreservesOrderAndKeepsTheMainActorAvailable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bedrock-attachments-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.png"), second = root.appendingPathComponent("second.png")
        let document = root.appendingPathComponent("한국어 report.txt")
        try png(width: 2800, height: 1800).write(to: first)
        try png(width: 48, height: 30).write(to: second)
        try Data("DOCUMENT_IMPORTED".utf8).write(to: document)
        let source = SharedMediaDataSource()
        source.importFiles([first, document])
        source.importFiles([second])
        XCTAssertTrue(source.isImporting)
        // Work scheduled on the main actor must run while ImageIO prepares files.
        var heartbeat = false
        Task { @MainActor in heartbeat = true }
        for _ in 0..<500 {
            if !source.isImporting { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(heartbeat)
        XCTAssertFalse(source.isImporting)
        XCTAssertNil(source.importError)
        XCTAssertEqual(source.imageFilenames, ["first.png", "second.png"])
        XCTAssertEqual(source.documentFilenames, ["report"])
        XCTAssertEqual(source.documents, [Data("DOCUMENT_IMPORTED".utf8)])
        let secondID = source.imageIDs[1]
        source.removeImage(at: 0)
        XCTAssertEqual(source.imageIDs, [secondID])
        XCTAssertEqual(source.imageFilenames, ["second.png"])
    }

    @MainActor
    func testClearingAttachmentsCancelsPendingImportsAndRetainsNewImports() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bedrock-attachment-cancel-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("old.png"), next = root.appendingPathComponent("new.txt")
        try png(width: 1200, height: 900).write(to: old)
        try Data("NEW_IMPORT".utf8).write(to: next)
        let source = SharedMediaDataSource()
        source.importFiles([old, old])
        source.clear()
        source.importFiles([next])
        for _ in 0..<500 {
            if !source.isImporting { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(source.isImporting)
        XCTAssertTrue(source.images.isEmpty)
        XCTAssertEqual(source.documents, [Data("NEW_IMPORT".utf8)])
    }

    func testFileImportRejectsOversizedDocumentsAndDirectories() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bedrock-attachment-size-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("large.txt")
        try Data(repeating: 65, count: LocalAttachmentProcessor.maximumDocumentBytes + 1).write(to: file)
        for url in [file, root] {
            do { _ = try await LocalAttachmentProcessor.prepare(url); XCTFail("Unsupported attachment must be rejected.") }
            catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        }
    }

    func testSourceAttachmentsKeepExactUTF8AndUseSupportedBedrockTextFormat() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bedrock-source-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data("  // 한글 — preserve indentation\nlet value = \"hello\"\t\n".utf8)
        for ext in ["swift", "json", "py", "ts", "yaml", "rs"] {
            let file = root.appendingPathComponent("source.\(ext)")
            try bytes.write(to: file)
            guard case .document(let actual, let format, let name) = try await LocalAttachmentProcessor.prepare(file) else {
                XCTFail("Expected a text document for \(ext)")
                continue
            }
            XCTAssertEqual(actual, bytes)
            XCTAssertEqual(format, "txt")
            XCTAssertEqual(name, "source")
        }
    }

    func testSourceAttachmentsRejectBinaryAndOversizedInputs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bedrock-invalid-source-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source.swift")
        for data in [Data([0, 1, 65]), Data([0xFF, 0xFE, 0xFF]),
                     Data(repeating: 65, count: LocalAttachmentProcessor.maximumDocumentBytes + 1)] {
            try data.write(to: file)
            do {
                _ = try await LocalAttachmentProcessor.prepare(file)
                XCTFail("Invalid source bytes were accepted.")
            } catch {
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
        }
    }
}
