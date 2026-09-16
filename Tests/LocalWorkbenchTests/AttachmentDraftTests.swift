import XCTest
@testable import LocalWorkbench

final class AttachmentDraftTests: XCTestCase {
    private func url() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("draft-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try ConversationAttachmentDraftFile.url(threadID: "thread-1", directory: root)
    }

    private func draft() -> ConversationAttachmentDraft {
        .init(images: [.init(id: UUID(), data: Data([1, 2, 3]), filename: "사진.png", format: "png")],
              documents: [.init(id: UUID(), data: Data("문서\n공백  그대로\n".utf8), filename: "paste.txt", format: "txt",
                                pastedText: "문서\n공백  그대로\n")])
    }

    func testDraftRoundTripPreservesBinaryDataNamesIDsAndExactPastedText() throws {
        let file = try url()
        let original = draft()
        try ConversationAttachmentDraftFile.write(original, to: file)
        XCTAssertEqual(try ConversationAttachmentDraftFile.read(file), original)
        try ConversationAttachmentDraftFile.write(.init(), to: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(try ConversationAttachmentDraftFile.read(file).isEmpty)
    }

    func testFutureCorruptOrInconsistentDraftCannotBeOverwrittenOrCleared() throws {
        let file = try url()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        for data in [Data("{bad json".utf8), Data(#"{"version":999,"images":[],"documents":[]}"#.utf8)] {
            try data.write(to: file)
            XCTAssertThrowsError(try ConversationAttachmentDraftFile.write(draft(), to: file))
            XCTAssertThrowsError(try ConversationAttachmentDraftFile.write(.init(), to: file))
            XCTAssertEqual(try Data(contentsOf: file), data)
        }
        var value = draft()
        value.documents[0].pastedText = "Different bytes"
        XCTAssertThrowsError(try ConversationAttachmentDraftFile.validate(value))
        value = draft()
        value.documents[0].id = value.images[0].id
        XCTAssertThrowsError(try ConversationAttachmentDraftFile.validate(value))
        XCTAssertThrowsError(try ConversationAttachmentDraftFile.url(threadID: "../escape", directory: file.deletingLastPathComponent()))
    }

    func testLateSaveCannotResurrectAnAttachmentRemovedOrSentLater() async throws {
        let file = try url()
        let writer = ConversationAttachmentDraftWriter()
        let value = draft()
        try await writer.write(value, to: file, revision: 10)
        try await writer.write(.init(), to: file, revision: 12)
        try await writer.write(value, to: file, revision: 11)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        try await writer.write(value, to: file, revision: 13)
        XCTAssertEqual(try ConversationAttachmentDraftFile.read(file), value)
    }
}
