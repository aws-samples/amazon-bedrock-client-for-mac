import Foundation
import XCTest
@testable import BedrockCore

final class ToolOutputTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tool-output-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testFileReferencesResolveRelativeUnicodeAndFileURLsWithoutDuplicates() throws {
        let root = try directory()
        let file = root.appendingPathComponent("결과 report.txt")
        try Data("fixture".utf8).write(to: file)
        let input: JSONValue = .object(["path": .string("결과 report.txt")])
        let text = "Created `\(file.path)`\n[Report](\(file.path))\n\(file.absoluteString)"
        let files = try ToolOutputFiles.find(input: input, output: text, access: .init(workingDirectory: root.path))
        XCTAssertEqual(files, [try LocalPath.canonicalize(file)])
    }

    func testReferencesRespectRestrictionsIncludingSymlinksAndRemoteFileHosts() throws {
        let root = try directory()
        let allowed = root.appendingPathComponent("allowed")
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outside)
        let link = allowed.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let input: JSONValue = .object(["path": .string(link.path)])
        let text = "`\(outside.path)`\nfile://remote-host\(outside.path)\nfile://remote-host/etc/hosts"
        XCTAssertEqual(try ToolOutputFiles.find(input: input, output: text,
            access: .init(workingDirectory: allowed.path, allowedDirectories: [allowed.path])), [])
        XCTAssertEqual(try ToolOutputFiles.find(input: .null, output: "file://remote-host\(outside.path)",
            access: .init(workingDirectory: allowed.path)), [])
    }

    func testMissingReferencesAndCommandArgumentsAreNotOfferedAsFiles() throws {
        let root = try directory()
        let input: JSONValue = .object(["command": .string("/usr/bin/printf"),
                                       "path": .string("missing.txt")])
        XCTAssertEqual(try ToolOutputFiles.find(input: input, output: "No files were created.",
            access: .init(workingDirectory: root.path)), [])
    }

    func testMCPTextIncludesAllFailureBlocksResourcesAndStructuredValues() {
        let value: [String: Any] = [
            "status": "error",
            "content": [
                ["type": "text", "text": "First diagnostic"],
                ["type": "text", "text": "다음 diagnostic"],
                ["type": "resource", "resource": ["uri": "file:///tmp/report.txt", "text": "Resource body"]],
                ["type": "resource_link", "uri": "file:///tmp/image.png", "name": "Image"]
            ],
            "structuredContent": ["count": 42, "enabled": true]
        ]
        let text = MCPToolOutput.text(value)
        for expected in ["First diagnostic", "다음 diagnostic", "file:///tmp/report.txt", "Resource body", "Image: file:///tmp/image.png", "42", "true"] {
            XCTAssertTrue(text.contains(expected), "Missing tool output: \(expected)")
        }
        XCTAssertEqual(MCPToolOutput.text(["status": "error", "error": "Disconnected"]), "Disconnected")
        XCTAssertEqual(MCPToolOutput.text(["status": "success", "content": []]), "Tool completed without output.")
    }
}
