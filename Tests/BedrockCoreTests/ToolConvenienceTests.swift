import Foundation
import XCTest
@testable import BedrockCore

final class ToolConvenienceTests: XCTestCase {
    private let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9e8AAAAASUVORK5CYII="

    func testToolIntegerArgumentsPreserveOffsetsAndRejectInvalidTypes() throws {
        let input = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"start_line":42,"offset":256,"wait_seconds":0}"#.utf8))
        XCTAssertEqual(try input.integer("start_line", default: 1, in: 1...Int.max), 42)
        XCTAssertEqual(try input.integer("offset", default: 0, in: 0...Int.max), 256)
        XCTAssertEqual(try input.integer("wait_seconds", default: 1, in: 0...10), 0)
        XCTAssertEqual(try input.integer("line_count", default: 300, in: 1...5_000), 300)
        for value: JSONValue in [.number(1.5), .number(-1), .number(.infinity), .number(Double.greatestFiniteMagnitude), .bool(true), .string("5")] {
            XCTAssertThrowsError(try JSONValue.object(["offset": value]).integer("offset", default: 0, in: 0...Int.max))
        }
    }

    func testAutomationToolCreatesPausedAndUpdatesWithoutLosingHistory() throws {
        let input: JSONValue = .object(["name": .string("Weekly review"), "prompt": .string("Read the changelog"),
                                        "cadence": .string("daily"), "weekdays": .array([.number(2), .number(6)])])
        var created = try AutomationToolInput.apply(input, to: [], defaultModelID: "nova")
        XCTAssertFalse(created.enabled)
        XCTAssertEqual(created.modelID, "nova")
        XCTAssertEqual(created.weekdays, [2, 6])
        created.lastThreadID = "previous-thread"
        created.lastStatus = .completed
        let updated = try AutomationToolInput.apply(.object([
            "id": .string(created.id.uuidString), "enabled": .bool(true), "time_zone": .string("Asia/Seoul")
        ]), to: [created], defaultModelID: "different-model")
        XCTAssertEqual(updated.id, created.id)
        XCTAssertEqual(updated.modelID, "nova")
        XCTAssertEqual(updated.lastThreadID, "previous-thread")
        XCTAssertEqual(updated.lastStatus, .completed)
        XCTAssertTrue(updated.enabled)
        XCTAssertEqual(updated.timeZoneIdentifier, "Asia/Seoul")
        let description = try AutomationToolInput.describe([updated])
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(description.utf8)) as? [[String: Any]])
    }

    func testAutomationToolRejectsInvalidIDsTypesTimesAndUnexpectedFields() {
        let base: [String: JSONValue] = ["name": .string("Routine"), "prompt": .string("Hello")]
        let invalid: [[String: JSONValue]] = [
            ["id": .string(UUID().uuidString)], ["enabled": .string("true")],
            ["interval_minutes": .number(1.5)], ["interval_minutes": .number(Double.greatestFiniteMagnitude)],
            ["run_at": .string("tomorrow")], ["weekdays": .array([])],
            ["time_zone": .string("Not/AZone")], ["shell": .string("unexpected")],
            ["active_start": .string("25:00")], ["cadence": .string("monthly")]
        ]
        for patch in invalid {
            XCTAssertThrowsError(try AutomationToolInput.apply(.object(base.merging(patch) { _, value in value }),
                                                                to: [], defaultModelID: "nova"))
        }
    }

    func testNewReadToolsRespectReadOnlyProfileAndScheduleWritesNeedApprovalWhenConfigured() {
        for tool: BuiltInTool in [.viewImage, .searchConversations, .listAutomations] {
            XCTAssertTrue(ToolProfile.readOnly.tools.contains(tool))
            XCTAssertFalse(ToolApprovalMode.askForChanges.requiresApproval(tool: tool))
        }
        XCTAssertFalse(ToolProfile.readOnly.tools.contains(.saveAutomation))
        XCTAssertTrue(ToolApprovalMode.askForChanges.requiresApproval(tool: .saveAutomation))
        XCTAssertFalse(ToolApprovalMode.allowEnabled.requiresApproval(tool: .saveAutomation))
    }

    func testMCPImageExtractionBoundsAndRetainsStructuredText() {
        let result: [String: Any] = [
            "status": "success", "structuredContent": ["count": 1],
            "content": Array(repeating: ["type": "image", "mimeType": "image/png", "data": png], count: 8)
        ]
        XCTAssertEqual(MCPToolOutput.imageData(result).count, 4)
        XCTAssertEqual(MCPToolOutput.imageData(result).first, Data(base64Encoded: png))
        XCTAssertTrue(MCPToolOutput.text(result).contains("\"count\" : 1"))
        XCTAssertTrue(MCPToolOutput.imageData(["content": [["type": "image", "data": "/private/file.png"]]]).isEmpty)
    }

    func testToolImagesSurviveArchiveAndModelSwitchWithoutChangingOriginalHistory() throws {
        let image = ToolResultImage(base64: png, format: "png")
        let call = Message.ToolUse(toolId: "image", toolName: "local_view_image", inputs: .object(["path": .string("/tmp/image.png")]),
                                   result: "Image is ready.", status: "success", resultImages: [image])
        let prompt = Message(id: UUID(), text: "Inspect the image", role: .user, timestamp: Date(), isError: false)
        let assistant = Message(id: UUID(), text: "", role: .assistant, timestamp: Date(), isError: false, toolUses: [call])
        let result = Message(id: UUID(), text: "", role: .user, timestamp: Date(), isError: false, toolUses: [call])
        let history = ConversationHistory(chatId: "image-thread", modelId: "amazon.nova-2-lite-v1:0", messages: [prompt, assistant, result])
        let replay = ConversationReplay.prepare(history, targetModelID: "anthropic.claude-sonnet-4-6",
            supportsReasoning: false, supportsTools: true, supportsImages: true, supportsDocuments: true)
        XCTAssertEqual(replay.messages.last?.imageBase64Strings, [png])
        XCTAssertNil(replay.messages.last?.toolUses)
        XCTAssertEqual(history.messages.last?.toolUses?.first?.resultImages, [image])
        let archive = ConversationArchive(title: "Images", modelID: history.modelId, modelName: "Nova", provider: "Amazon", messages: history.messages)
        let decoded = try JSONDecoder().decode(ConversationArchive.self, from: ConversationArchiveCodec.encode(archive))
        XCTAssertEqual(decoded.messages.last?.toolUses?.first?.resultImages, [image])
        var invalid = archive
        invalid.messages[1].toolUses?[0].resultImages?[0].base64 = "file:///tmp/private.png"
        XCTAssertThrowsError(try ConversationArchiveCodec.encode(invalid))
    }

    func testConversationSearchIncludesPastedTextAndToolOutputWithDetailTargets() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pasted = PastedTextInfo(filename: "long.txt", content: "Keep ATTACHMENT_NEEDLE exact.")
        let user = Message(id: UUID(), text: "Please read", role: .user, timestamp: Date(), isError: false, pastedTexts: [pasted])
        let call = Message.ToolUse(toolId: "read", toolName: "local_read_file", inputs: .object([:]),
                                   result: "The value is TOOL_NEEDLE.", status: "success")
        let answer = Message(id: UUID(), text: "Done", role: .assistant, timestamp: Date(), isError: false, toolUses: [call])
        let history = ConversationHistory(chatId: "thread", modelId: "nova", messages: [user, answer])
        let file = root.appendingPathComponent("history.json")
        try JSONEncoder().encode(history).write(to: file)
        let index = ConversationSearchIndex()
        let input = ConversationSearchInput(id: "thread", unifiedURL: file, legacyURL: root.appendingPathComponent("absent.json"))
        let attachment = await index.search("attachment_needle", inputs: [input])
        XCTAssertEqual(attachment.hits["thread"]?.target, .pastedText(pasted.id))
        XCTAssertEqual(attachment.hits["thread"]?.messageID, user.id)
        let tool = await index.search("TOOL_NEEDLE", inputs: [input])
        XCTAssertEqual(tool.hits["thread"]?.target, .tool("read"))
        XCTAssertEqual(tool.hits["thread"]?.messageID, answer.id)
        try Data("{invalid".utf8).write(to: file, options: .atomic)
        let failed = await index.search("TOOL_NEEDLE", inputs: [input])
        XCTAssertTrue(failed.hits.isEmpty)
        XCTAssertEqual(failed.unreadableCount, 1)
    }
}
