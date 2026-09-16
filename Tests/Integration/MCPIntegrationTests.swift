import Foundation
import XCTest
@testable import Amazon_Bedrock_Client_for_Mac

final class MCPIntegrationTests: XCTestCase {
    @MainActor
    private func makeManager() throws -> MCPManager {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bedrock-mcp-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "bedrock.mcp.tests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        preferences.set(true, forKey: "mcpEnabled")
        let manager = MCPManager(configurationDirectory: root, preferences: preferences, autoStart: false)
        manager.connectionTimeout = 4
        manager.toolTimeout = 4
        addTeardownBlock { @MainActor in
            await manager.shutdown()
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        return manager
    }

    private var fixture: URL {
        if let root = ProcessInfo.processInfo.environment["BEDROCK_TEST_FIXTURES"] {
            return URL(fileURLWithPath: root).appendingPathComponent("mcp_echo.py")
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Tests/Fixtures/mcp_echo.py")
    }

    private func server(_ name: String, flags: [String] = []) -> MCPServerConfig {
        .init(name: name, command: "/usr/bin/python3", args: [fixture.path, name] + flags)
    }

    @MainActor
    private func awaitConnection(_ manager: MCPManager, names: [String], timeout: TimeInterval = 6) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if names.allSatisfy({ manager.connectionStatus[$0] == .connected }) { return }
            for name in names {
                if case .failed(let error) = manager.connectionStatus[name] {
                    XCTFail("MCP \(name) connection failed: \(error)")
                    throw LocalWorkbenchError.unavailable(error)
                }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("MCP connection deadline exceeded")
        throw LocalWorkbenchError.unavailable("Connection deadline exceeded")
    }

    private var payload: [String: Any] {
        ["mode": "echo", "payload": ["enabled": true, "count": 42, "labels": ["가나다", "literal $(echo nope)"]]]
    }

    @MainActor
    func testDuplicateToolNamesRoundTripNestedArgumentsAndReconnectIndependently() async throws {
        let manager = try makeManager()
        manager.connectToServer(server("first"))
        manager.connectToServer(server("second"))
        try await awaitConnection(manager, names: ["first", "second"])
        XCTAssertEqual(manager.toolInfos.count, 2)
        XCTAssertNil(manager.toolInfo(named: "echo_payload"))
        let first = try XCTUnwrap(manager.toolInfos.first { $0.serverName == "first" })
        let secondPID = manager.activeProcessIDs["second"]
        let result = await manager.executeBedrockTool(id: "call", name: first.invocationName, input: payload)
        XCTAssertEqual(result["status"] as? String, "success")
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        let output = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(output["server"] as? String, "first")
        let received = try XCTUnwrap(output["received"] as? [String: Any])
        let nested = try XCTUnwrap(received["payload"] as? [String: Any])
        XCTAssertEqual(CFGetTypeID(try XCTUnwrap(nested["enabled"] as? NSNumber)), CFBooleanGetTypeID())
        XCTAssertEqual(nested["count"] as? Int, 42)
        XCTAssertEqual(nested["labels"] as? [String], ["가나다", "literal $(echo nope)"])
        let oldPID = try XCTUnwrap(manager.activeProcessIDs["first"])
        await manager.disconnectServer("first")
        XCTAssertNil(manager.activeClients["first"])
        XCTAssertEqual(manager.activeProcessIDs["second"], secondPID)
        XCTAssertEqual(manager.toolInfo(named: "echo_payload")?.serverName, "second")
        XCTAssertEqual(kill(oldPID, 0), -1, "Disconnected MCP subprocess must exit.")
        manager.connectToServer(server("first"))
        try await awaitConnection(manager, names: ["first", "second"])
        XCTAssertEqual(manager.toolInfos.first { $0.serverName == "first" }?.invocationName, first.invocationName)
        XCTAssertEqual(manager.activeProcessIDs["second"], secondPID)
    }

    @MainActor
    func testStderrFloodDoesNotBlockConnectionAndArgumentsRemainLiteral() async throws {
        let manager = try makeManager()
        let label = "literal ' $() ; fixture"
        manager.connectToServer(server(label, flags: ["--stderr"]))
        try await awaitConnection(manager, names: [label])
        let tool = try XCTUnwrap(manager.toolInfos.first)
        let result = await manager.executeBedrockTool(id: "literal", name: tool.invocationName, input: payload)
        XCTAssertEqual(result["status"] as? String, "success")
        let text = try XCTUnwrap((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(text.contains(label))
    }

    @MainActor
    func testContentPreservesTextMetadataResourcesAndAlreadyEncodedMedia() async throws {
        let manager = try makeManager()
        manager.connectToServer(server("content"))
        try await awaitConnection(manager, names: ["content"])
        let name = try XCTUnwrap(manager.toolInfos.first?.invocationName)
        var arguments = payload
        arguments["mode"] = "multimodal"
        let result = await manager.executeBedrockTool(id: "content", name: name, input: arguments)
        XCTAssertEqual(result["status"] as? String, "success")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(result))
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 5)
        XCTAssertEqual(content[0]["text"] as? String, "TEXT_OK")
        XCTAssertEqual((content[0]["_meta"] as? [String: Any])?["fixture"] as? Bool, true)
        XCTAssertEqual(content[1]["data"] as? String, Data("image".utf8).base64EncodedString())
        XCTAssertEqual(content[2]["data"] as? String, Data("audio".utf8).base64EncodedString())
        XCTAssertEqual((content[3]["resource"] as? [String: Any])?["text"] as? String, "RESOURCE_OK")
        let text = MCPToolOutput.text(result)
        XCTAssertTrue(text.contains("TEXT_OK"))
        XCTAssertTrue(text.contains("RESOURCE_OK"))
        XCTAssertTrue(text.contains("STRUCTURED_OK"))
        XCTAssertTrue(text.contains("file:///tmp/mcp-fixture.txt"))
    }

    @MainActor
    func testToolErrorsAreNotReportedAsSuccessAndTimedOutCallsCanBeRetried() async throws {
        let manager = try makeManager()
        manager.connectToServer(server("error"))
        try await awaitConnection(manager, names: ["error"])
        let name = try XCTUnwrap(manager.toolInfos.first?.invocationName)
        var arguments = payload
        arguments["mode"] = "error"
        let error = await manager.executeBedrockTool(id: "failed", name: name, input: arguments)
        XCTAssertEqual(error["status"] as? String, "error")
        XCTAssertTrue(MCPToolOutput.text(error).contains("MCP_OK"), "Do not lose a failed tool's actual diagnostic output.")
        manager.toolTimeout = 0.2
        arguments["mode"] = "wait"
        let start = Date()
        let timedOut = await manager.executeBedrockTool(id: "timeout", name: name, input: arguments)
        XCTAssertEqual(timedOut["status"] as? String, "error")
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        let recovered = await manager.executeBedrockTool(id: "recovered", name: name, input: payload)
        XCTAssertEqual(recovered["status"] as? String, "success")
    }

    @MainActor
    func testCancelledCallStopsPromptlyWithoutDisconnectingHealthyServer() async throws {
        let manager = try makeManager()
        manager.connectToServer(server("cancel"))
        try await awaitConnection(manager, names: ["cancel"])
        let name = try XCTUnwrap(manager.toolInfos.first?.invocationName)
        let task = Task { @MainActor in
            var arguments = self.payload
            arguments["mode"] = "wait"
            let result = await manager.executeBedrockTool(id: "cancelled", name: name, input: arguments)
            return result["status"] as? String
        }
        try await Task.sleep(for: .milliseconds(40))
        let start = Date()
        task.cancel()
        let status = await task.value
        XCTAssertEqual(status, "error")
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertEqual(manager.connectionStatus["cancel"], .connected)
        let result = await manager.executeBedrockTool(id: "next", name: name, input: payload)
        XCTAssertEqual(result["status"] as? String, "success")
    }

    @MainActor
    func testRapidCancellationDoesNotLeavePendingCallsOrLoseNextResponse() async throws {
        let manager = try makeManager()
        manager.connectToServer(server("rapid-cancel"))
        try await awaitConnection(manager, names: ["rapid-cancel"])
        let name = try XCTUnwrap(manager.toolInfos.first?.invocationName)
        for delay in [0, 1, 10] {
            let request = Task { @MainActor in
                var arguments = self.payload
                arguments["mode"] = "wait"
                return await manager.executeBedrockTool(id: "cancel-\(delay)", name: name, input: arguments)["status"] as? String
            }
            if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
            request.cancel()
            let status = await request.value
            XCTAssertEqual(status, "error")
            let next = await manager.executeBedrockTool(id: "after-\(delay)", name: name, input: payload)
            XCTAssertEqual(next["status"] as? String, "success")
            XCTAssertTrue(MCPToolOutput.text(next).contains("MCP_OK"))
        }
    }

    @MainActor
    func testUnresponsiveHandshakeTimesOutAndDisconnectDuringConnectCannotReappear() async throws {
        let manager = try makeManager()
        manager.connectionTimeout = 0.2
        manager.connectToServer(server("hang", flags: ["--hang-initialize"]))
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, manager.connectionStatus["hang"] == .connecting {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard case .failed = manager.connectionStatus["hang"] else { return XCTFail("Handshake must time out.") }
        XCTAssertNil(manager.activeClients["hang"])
        XCTAssertNil(manager.activeProcessIDs["hang"])
        manager.connectToServer(server("stop", flags: ["--hang-initialize"]))
        await manager.disconnectServer("stop")
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(manager.connectionStatus["stop"], .notConnected)
        XCTAssertNil(manager.activeClients["stop"])
    }
}
