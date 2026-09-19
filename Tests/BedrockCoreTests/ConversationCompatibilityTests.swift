import XCTest
@testable import BedrockCore

final class ConversationCompatibilityTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bedrock-migration-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func releasedHistory() -> Data {
        Data("""
        {"chatId":"old-chat","modelId":"us.amazon.nova-2-lite-v1:0","messages":[
          {"id":"77777777-7777-4777-8777-777777777777","text":"기존 대화","role":"user",
           "timestamp":790000000,"isError":false,"pastedTexts":[
             {"id":"88888888-8888-4888-8888-888888888888","filename":"memo.txt","content":"보존할 내용"}]}],
         "lastUpdated":790000001,"systemPrompt":"Keep my original instructions."}
        """.utf8)
    }

    func testReleasedUnifiedConversationLoadsWithoutNewFields() throws {
        let history = try ConversationFileStore.decode(releasedHistory(), chatID: "old-chat")
        XCTAssertNil(history.formatVersion)
        XCTAssertNil(history.messages[0].modelID)
        XCTAssertEqual(history.messages[0].timestamp, Date(timeIntervalSinceReferenceDate: 790000000))
        XCTAssertEqual(history.messages[0].pastedTexts?.first?.content, "보존할 내용")
        XCTAssertEqual(history.systemPrompt, "Keep my original instructions.")
    }

    func testColdReadPreservesUnifiedHistoryAndNeverFallsBackFromACorruptFile() async throws {
        let root = try directory()
        let unified = root.appendingPathComponent("unified.json")
        let legacy = root.appendingPathComponent("legacy.json")
        try releasedHistory().write(to: unified)
        try JSONEncoder().encode([MessageData(text: "A stale legacy copy", user: "User", sentTime: Date())]).write(to: legacy)
        let result = try await Task.detached {
            try ConversationFileStore.read(unifiedURL: unified, legacyURL: legacy, chatID: "old-chat")
        }.value
        guard case .unified(let history) = result else { return XCTFail("The unified history takes precedence.") }
        XCTAssertEqual(history.messages[0].text, "기존 대화")
        let corrupt = Data("{broken".utf8)
        try corrupt.write(to: unified)
        XCTAssertThrowsError(try ConversationFileStore.read(unifiedURL: unified, legacyURL: legacy, chatID: "old-chat"))
        XCTAssertEqual(try Data(contentsOf: unified), corrupt)
        try FileManager.default.removeItem(at: unified)
        guard case .legacy(let messages) = try ConversationFileStore.read(unifiedURL: unified, legacyURL: legacy, chatID: "old-chat") else {
            return XCTFail("Released legacy files must still open.")
        }
        XCTAssertEqual(messages[0].text, "A stale legacy copy")
    }

    func testColdReadRejectsOversizedOrCancelledReads() async throws {
        let root = try directory()
        let unified = root.appendingPathComponent("large.json")
        let legacy = root.appendingPathComponent("missing.json")
        FileManager.default.createFile(atPath: unified.path, contents: nil)
        let handle = try FileHandle(forWritingTo: unified)
        try handle.truncate(atOffset: 128_000_001)
        try handle.close()
        XCTAssertThrowsError(try ConversationFileStore.read(unifiedURL: unified, legacyURL: legacy, chatID: "old-chat"))
        let cancelled = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ConversationFileStore.read(unifiedURL: unified, legacyURL: legacy, chatID: "old-chat")
        }
        do { _ = try await cancelled.value; XCTFail("A cancelled read must stop.") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testFirstUpgradeBacksUpExactOriginalAndKeepsThatBackupOnLaterSaves() throws {
        let root = try directory()
        let url = root.appendingPathComponent("old-chat_unified_history.json")
        let original = releasedHistory()
        try original.write(to: url)
        var history = try ConversationFileStore.decode(original, chatID: "old-chat")
        history.switchModel(to: "us.openai.gpt-6-astra")
        var files = ConversationFileStore()
        let saved = try files.write(history, to: url)
        let backup = ConversationFileStore.backupURL(for: url)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(try ConversationFileStore.decode(Data(contentsOf: url), chatID: "old-chat"), saved)
        history.messages[0].text += "\nNext save"
        try files.write(history, to: url)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(saved.formatVersion, 2)
        XCTAssertEqual(saved.messages[0].modelID, "us.amazon.nova-2-lite-v1:0")
    }

    func testCorruptFutureAndWrongConversationFilesCannotBeOverwritten() throws {
        let root = try directory()
        let current = ConversationHistory(chatId: "old-chat", modelId: "us.openai.gpt-6-astra")
        var future = try XCTUnwrap(JSONSerialization.jsonObject(with: releasedHistory()) as? [String: Any])
        future["formatVersion"] = 99
        var wrongID = future
        wrongID["formatVersion"] = 1
        wrongID["chatId"] = "a-different-chat"
        let originals = [Data("{unreadable".utf8),
                         try JSONSerialization.data(withJSONObject: future),
                         try JSONSerialization.data(withJSONObject: wrongID)]
        for (index, original) in originals.enumerated() {
            let url = root.appendingPathComponent("\(index).json")
            try original.write(to: url)
            var files = ConversationFileStore()
            XCTAssertThrowsError(try files.write(current, to: url))
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: ConversationFileStore.backupURL(for: url).path))
        }
    }

    func testLegacyMessageFormatsKeepDatesOrderAndAttachments() throws {
        let firstID = UUID(), secondID = UUID()
        let raw: [[String: Any]] = [
            ["id": firstID.uuidString, "text": "Camel case", "user": "User", "sentTime": 1_789_444_800.0,
             "imageBase64Strings": ["aW1hZ2U="], "documentBase64Strings": ["cGRm"],
             "documentFormats": ["pdf"], "documentNames": ["original.pdf"]],
            ["id": secondID.uuidString, "text": "Snake case", "user": "Assistant",
             "sent_time": 790_000_000.0, "is_error": false, "thinking": "Saved thinking", "signature": "saved-signature"]
        ]
        let decoded = try LegacyConversationDecoder.decode(JSONSerialization.data(withJSONObject: raw))
        XCTAssertEqual(decoded.map(\.id), [firstID, secondID])
        XCTAssertEqual(decoded[0].sentTime, Date(timeIntervalSince1970: 1_789_444_800))
        XCTAssertEqual(decoded[1].sentTime, Date(timeIntervalSinceReferenceDate: 790_000_000))
        XCTAssertEqual(decoded[0].documentNames, ["original.pdf"])
        XCTAssertEqual(decoded[0].imageBase64Strings, ["aW1hZ2U="])
        XCTAssertEqual(try LegacyConversationDecoder.decode(JSONEncoder().encode(decoded)), decoded)
    }

    func testMalformedLegacyMessageDoesNotSilentlyDropPartOfConversation() throws {
        let original = Data("""
        [{"id":"77777777-7777-4777-8777-777777777777","text":"Keep me","user":"User","sentTime":1789444800},
         {"text":"Missing ID must be reported","user":"Assistant","sentTime":1789444801}]
        """.utf8)
        XCTAssertThrowsError(try LegacyConversationDecoder.decode(original))
    }

    func testSwitchingModelsKeepsEveryStoredFieldAndOriginalModelIdentity() throws {
        let tool = Message.ToolUse(toolId: "call_1", toolName: "echo", inputs: .object(["enabled": .bool(true)]),
                                   result: "MCP_OK", resultTimestamp: Date(timeIntervalSince1970: 100),
                                   status: "success", elapsedSeconds: 0.2, displayName: "Echo", serverName: "Local")
        let ui = MessageData(text: "Hello", thinking: "Keep this", thinkingSummary: "Summary", signature: "sig",
                             user: "Assistant", sentTime: Date(timeIntervalSince1970: 90),
                             imageBase64Strings: ["aW1hZ2U="], documentBase64Strings: ["cGRm"],
                             documentFormats: ["pdf"], documentNames: ["file.pdf"],
                             pastedTexts: [.init(filename: "pasted.txt", content: "Keep pasted text")],
                             videoUrl: URL(fileURLWithPath: "/tmp/local-video.mp4"), videoS3Uri: "s3://fixture/video",
                             toolUses: [tool])
        var history = ConversationHistory.fromMessages([ui], chatID: "old-chat",
                                                       modelID: "us.amazon.nova-2-lite-v1:0", systemPrompt: "Original")
        let originalMessages = history.messages
        history.switchModel(to: "us.openai.gpt-6-astra")
        history.switchModel(to: "global.anthropic.claude-sonnet-4-6")
        XCTAssertEqual(history.messages, originalMessages)
        XCTAssertEqual(history.systemPrompt, "Original")
        XCTAssertEqual(history.chatId, "old-chat")
        XCTAssertEqual(try JSONDecoder().decode(ConversationHistory.self, from: JSONEncoder().encode(history)), history)
    }

    func testCrossModelReplayKeepsContextWithoutForeignSignaturesOrToolProtocol() throws {
        let call = Message.ToolUse(toolId: "call_1", toolName: "echo", inputs: .object(["enabled": .bool(true)]),
                                   result: "MCP_OK", status: "success")
        let history = ConversationHistory(chatId: "one", modelId: "us.amazon.nova-2-lite-v1:0", messages: [
            .init(id: UUID(), text: "Look at this", role: .user, timestamp: Date(), isError: false,
                  imageBase64Strings: ["aW1hZ2U="], documentBase64Strings: [Data("READ_ME".utf8).base64EncodedString()],
                  documentFormats: ["txt"], documentNames: ["details.txt"]),
            .init(id: UUID(), text: "Checking", role: .assistant, timestamp: Date(), isError: false,
                  thinking: "Private model protocol", thinkingSignature: "nova-signature", toolUses: [call]),
            .init(id: UUID(), text: "", role: .user, timestamp: Date(), isError: false, toolUses: [call])
        ])
        let original = history
        let replay = ConversationReplay.prepare(history, targetModelID: "us.openai.gpt-6-astra",
                                                supportsReasoning: false, supportsTools: true,
                                                supportsImages: false, supportsDocuments: false)
        XCTAssertEqual(history, original)
        XCTAssertNil(replay.messages[1].thinkingSignature)
        XCTAssertNil(replay.messages[1].toolUses)
        XCTAssertNil(replay.messages[2].toolUses)
        XCTAssertTrue(replay.messages[2].text.contains("MCP_OK"))
        XCTAssertTrue(replay.messages[0].text.contains("READ_ME"))
        XCTAssertTrue(replay.messages[0].text.contains("saved locally"))
        XCTAssertNil(replay.messages[0].imageBase64Strings)
        XCTAssertNotNil(history.messages[0].imageBase64Strings)
    }

    func testSameFoundationAcrossRegionsPreservesPairedToolsAndSignedReasoning() {
        let call = Message.ToolUse(toolId: "call_1", toolName: "echo", inputs: .object([:]), result: "OK")
        let history = ConversationHistory(chatId: "one", modelId: "us.anthropic.claude-sonnet-4-6", messages: [
            .init(id: UUID(), text: "", role: .assistant, timestamp: Date(), isError: false,
                  thinking: "Saved", thinkingSignature: "signature", toolUses: [call]),
            .init(id: UUID(), text: "", role: .user, timestamp: Date(), isError: false, toolUses: [call])
        ])
        let replay = ConversationReplay.prepare(history, targetModelID: "global.anthropic.claude-sonnet-4-6",
                                                supportsReasoning: true, supportsTools: true,
                                                supportsImages: true, supportsDocuments: true)
        XCTAssertEqual(replay.messages, history.messages)
        let withoutTools = ConversationReplay.prepare(history, targetModelID: history.modelId,
                                                      supportsReasoning: true, supportsTools: false,
                                                      supportsImages: true, supportsDocuments: true)
        XCTAssertNil(withoutTools.messages[0].toolUses)
        XCTAssertNil(withoutTools.messages[0].thinkingSignature)
        XCTAssertTrue(withoutTools.messages[1].text.contains("OK"))
    }

    func testLegacyInferenceSettingsAndAstraProfileDefaultsRemainReadable() throws {
        let data = Data(#"{"maxTokens":2048,"temperature":0.4,"topP":0.8,"overrideDefault":true,"enableStreaming":false}"#.utf8)
        let config = try JSONDecoder().decode(ModelInferenceConfig.self, from: data)
        XCTAssertEqual(config.maxTokens, 2048)
        XCTAssertTrue(config.includeMaxTokens)
        XCTAssertFalse(config.enableStreaming)
        XCTAssertEqual(config.reasoningEffort, "medium")
        XCTAssertEqual(try JSONDecoder().decode(ModelInferenceConfig.self, from: JSONEncoder().encode(config)), config)
        for id in ["openai.gpt-6-astra", "us.openai.gpt-6-astra", "global.openai.gpt-6-astra"] {
            let defaults = ModelInferenceRange.getParameterDefaultsForModel(id)
            XCTAssertFalse(defaults.includeTemperature)
            XCTAssertFalse(defaults.includeTopP)
            XCTAssertEqual(ModelInferenceRange.getRangeForModel(id).defaultMaxTokens, 8192)
        }
    }

    func testAstraAlwaysUsesSavedReasoningEffortEvenWhenGlobalThinkingIsOff() {
        var config = ModelInferenceConfig()
        config.reasoningEffort = "xhigh"
        XCTAssertEqual(config.frontierReasoningEffort(modelID: "us.openai.gpt-6-astra", thinkingEnabled: false), "xhigh")
        XCTAssertEqual(config.frontierReasoningEffort(modelID: "global.openai.gpt-6-astra", thinkingEnabled: true), "xhigh")
        config.reasoningEffort = "none"
        XCTAssertEqual(config.frontierReasoningEffort(modelID: "openai.gpt-6-astra", thinkingEnabled: true), "medium")
        XCTAssertEqual(config.frontierReasoningEffort(modelID: "openai.gpt-5.6-luna", thinkingEnabled: false), "none")
    }

    func testNewModelDefaultsOmitSamplingWithoutChangingLegacyOverrides() throws {
        for id in ["future.new-model", "moonshotai.kimi-k99", "global.anthropic.claude-next",
                   "us.zai.new-model", "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.future.new-model"] {
            let defaults = ModelInferenceRange.getParameterDefaultsForModel(id)
            XCTAssertTrue(defaults.includeMaxTokens, "Keep a bounded output for \(id).")
            XCTAssertFalse(defaults.includeTemperature, id)
            XCTAssertFalse(defaults.includeTopP, id)
        }
        let legacy = try JSONDecoder().decode(ModelInferenceConfig.self, from:
            Data(#"{"temperature":0.4,"topP":0.8,"overrideDefault":true}"#.utf8))
        XCTAssertEqual(legacy.requestTemperature, 0.4)
        XCTAssertEqual(legacy.requestTopP, 0.8)
        XCTAssertTrue(legacy.overrideDefault)
        let known = ModelInferenceRange.getParameterDefaultsForModel("us.anthropic.claude-sonnet-4-6")
        XCTAssertTrue(known.includeTemperature)
        XCTAssertFalse(known.includeTopP)
    }

    func testKimiK3ReasoningOffIsExplicitAndSavedEffortIsValidated() {
        for effort in ["none", "low", "medium", "high", "xhigh", "max"] {
            let config = ModelInferenceConfig(reasoningEffort: effort)
            XCTAssertEqual(config.kimiK3ReasoningEffort(thinkingEnabled: true), effort)
            XCTAssertEqual(config.kimiK3ReasoningEffort(thinkingEnabled: false), "none")
            XCTAssertEqual(config.reasoningEffort, effort, "Turning thinking off must not erase the saved effort.")
        }
        for effort in ["", "bogus", "disabled"] {
            XCTAssertEqual(ModelInferenceConfig(reasoningEffort: effort).kimiK3ReasoningEffort(thinkingEnabled: true), "medium")
        }
        XCTAssertEqual(ModelInferenceConfig(reasoningEffort: " MAX ").kimiK3ReasoningEffort(thinkingEnabled: true), "max")
        for id in ["moonshotai.kimi-k3", "us.moonshotai.kimi-k3", "global.moonshotai.kimi-k3"] {
            let range = ModelInferenceRange.getRangeForModel(id)
            XCTAssertEqual(range.maxTokensRange, 1...128000)
            XCTAssertEqual(range.defaultMaxTokens, 8192)
            let defaults = ModelInferenceRange.getParameterDefaultsForModel(id)
            XCTAssertFalse(defaults.includeTemperature)
            XCTAssertFalse(defaults.includeTopP)
        }
    }

    func testSettingsBackupPreservesReleasedKeysWithoutCredentialsOrChangingPreferences() throws {
        let name = "bedrock-settings-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("light", forKey: "appearance")
        defaults.set("/tmp/my-existing-chats", forKey: "defaultDirector")
        defaults.set(Data([0, 1, 2]), forKey: "modelInferenceConfigs")
        defaults.set("test-only-secret", forKey: "bedrockApiKey")
        let url = try directory().appendingPathComponent("preferences.plist")
        try LegacyPreferencesBackup.preserve(defaults, at: url)
        let original = try Data(contentsOf: url)
        let snapshot = try XCTUnwrap(PropertyListSerialization.propertyList(from: original, format: nil) as? [String: Any])
        XCTAssertEqual(snapshot["appearance"] as? String, "light")
        XCTAssertEqual(snapshot["defaultDirector"] as? String, "/tmp/my-existing-chats")
        XCTAssertEqual(snapshot["modelInferenceConfigs"] as? Data, Data([0, 1, 2]))
        XCTAssertNil(snapshot["bedrockApiKey"])
        XCTAssertEqual(defaults.string(forKey: "bedrockApiKey"), "test-only-secret")
        defaults.set("dark", forKey: "appearance")
        try LegacyPreferencesBackup.preserve(defaults, at: url)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(defaults.string(forKey: "appearance"), "dark")
    }
}
