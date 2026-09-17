import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class LocalToolIntegrationTests: XCTestCase {
    @MainActor
    private func withTools(_ operation: @MainActor () async throws -> Void) async throws {
        XCTAssertTrue(ValidationMode.isOffline, "Local tool tests require an isolated app data directory.")
        guard ValidationMode.isOffline else { return }
        let store = AppStore.shared
        let preferences = store.preferences
        let automations = store.state.automations
        store.preferences.toolProfile = .all
        store.preferences.disabledTools = []
        store.preferences.automationsEnabled = false
        defer {
            store.preferences = preferences
            store.state.automations = automations
            store.flush()
        }
        try await operation()
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    @MainActor
    func testFileToolUsesRequestedNumericLineRange() async throws {
        try await withTools {
            let directory = try temporaryDirectory()
            let file = directory.appendingPathComponent("lines.txt")
            try (1...60).map { "row-\($0)" }.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            AppStore.shared.preferences.restrictFileAccess = true
            AppStore.shared.preferences.allowedFileDirectories = [directory.path]
            let result = await LocalToolExecutor.execute(kind: .readFile, input: .object([
                "path": .string(file.path), "start_line": .number(42), "line_count": .number(2)
            ]), threadID: UUID().uuidString, modelID: "amazon.nova-2-lite-v1:0")
            XCTAssertEqual(result.status, "success", result.text)
            XCTAssertTrue(result.text.contains("row-42"))
            XCTAssertTrue(result.text.contains("row-43"))
            XCTAssertFalse(result.text.contains("row-41"))
            XCTAssertFalse(result.text.contains("row-44"))
        }
    }

    @MainActor
    func testImageToolReturnsDecodableBytesAndEnforcesConfiguredFileAccess() async throws {
        try await withTools {
            let directory = try temporaryDirectory()
            let file = directory.appendingPathComponent("image.png")
            let context = try XCTUnwrap(CGContext(data: nil, width: 48, height: 32, bitsPerComponent: 8,
                bytesPerRow: 48 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
            let image = try XCTUnwrap(context.makeImage())
            let target = try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(target, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(target))

            let store = AppStore.shared
            store.preferences.restrictFileAccess = true
            store.preferences.allowedFileDirectories = [directory.path]
            let input: JSONValue = .object(["path": .string(file.path)])
            let thread = UUID().uuidString
            let result = await LocalToolExecutor.execute(kind: .viewImage, input: input, threadID: thread, modelID: "amazon.nova-2-lite-v1:0")
            XCTAssertEqual(result.status, "success", result.text)
            let images = try XCTUnwrap(result.images)
            XCTAssertEqual(images.count, 1)
            let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(images.first).base64))
            let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(decoded.width, 48)
            XCTAssertEqual(decoded.height, 32)

            let allowed = directory.appendingPathComponent("allowed")
            try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
            store.preferences.allowedFileDirectories = [allowed.path]
            let denied = await LocalToolExecutor.execute(kind: .viewImage, input: input, threadID: thread, modelID: "amazon.nova-2-lite-v1:0")
            XCTAssertEqual(denied.status, "error")
            XCTAssertTrue(denied.images?.isEmpty != false)
            store.preferences.disabledTools.insert(.viewImage)
            let disabled = await LocalToolExecutor.execute(kind: .viewImage, input: input, threadID: thread, modelID: "amazon.nova-2-lite-v1:0")
            XCTAssertEqual(disabled.status, "error")
            XCTAssertFalse(LocalToolExecutor.availableTools(threadID: thread).contains(.viewImage))
        }
    }

    @MainActor
    func testAutomationToolsPersistPausedSchedulesAndPreserveIdentityOnUpdate() async throws {
        try await withTools {
            let store = AppStore.shared
            let thread = UUID().uuidString
            let model = "us.amazon.nova-2-lite-v1:0"
            let created = await LocalToolExecutor.execute(kind: .saveAutomation, input: .object([
                "name": .string("Tool integration schedule"), "prompt": .string("Summarize the sample."),
                "cadence": .string("daily"), "time_zone": .string("Asia/Seoul"),
                "weekdays": .array([.number(2), .number(6)])
            ]), threadID: thread, modelID: model)
            XCTAssertEqual(created.status, "success", created.text)
            let record = try XCTUnwrap(store.state.automations.last)
            XCTAssertFalse(record.enabled)
            XCTAssertEqual(record.modelID, model)
            XCTAssertEqual(record.weekdays, [2, 6])
            let updated = await LocalToolExecutor.execute(kind: .saveAutomation, input: .object([
                "id": .string(record.id.uuidString), "name": .string("Renamed schedule")
            ]), threadID: thread, modelID: "another-model")
            XCTAssertEqual(updated.status, "success", updated.text)
            let data = try Data(contentsOf: store.directory.appendingPathComponent("workspace.json"))
            let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let records = try XCTUnwrap(snapshot["automations"] as? [[String: Any]])
            let saved = try XCTUnwrap(records.first { $0["id"] as? String == record.id.uuidString })
            XCTAssertEqual(saved["name"] as? String, "Renamed schedule")
            XCTAssertEqual(saved["modelID"] as? String, model)
            XCTAssertEqual(saved["enabled"] as? Bool, false)
            let listed = await LocalToolExecutor.execute(kind: .listAutomations,
                input: .object(["offset": .number(Double(store.state.automations.count - 1))]), threadID: thread, modelID: model)
            XCTAssertEqual(listed.status, "success")
            XCTAssertTrue(listed.text.contains(record.id.uuidString))
            let rejected = await LocalToolExecutor.execute(kind: .saveAutomation, input: .object([
                "id": .string(record.id.uuidString), "model_id": .string("amazon.nova-2-pro-preview-20251202-v1:0")
            ]), threadID: thread, modelID: model)
            XCTAssertEqual(rejected.status, "error")
            XCTAssertEqual(store.state.automations.last?.modelID, model)
        }
    }
}
