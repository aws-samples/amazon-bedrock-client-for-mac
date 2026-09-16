import XCTest
@testable import LocalWorkbench

final class LocalWorkbenchTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bedrock-core-test-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testStateRoundTripPreservesIndependentThreadDraftsAndSelections() throws {
        let root = try temporaryDirectory()
        let file = LocalJSONFile<WorkbenchState>(url: root.appendingPathComponent("state.json"))
        var state = WorkbenchState()
        let project = LocalProject(name: "Fixture", path: root.path)
        state.projects = [project]
        state.threads["one"] = ThreadWorkspace(draft: "안녕하세요", projectID: project.id, skillIDs: ["code-review"])
        state.threads["two"] = ThreadWorkspace(draft: "different draft", pinnedAt: Date(), archived: true)
        state.preferences.approvalMode = .askAlways
        try file.save(state)
        let loaded = try XCTUnwrap(file.load())
        XCTAssertEqual(loaded.threads, state.threads)
        XCTAssertEqual(loaded.preferences, state.preferences)
        XCTAssertEqual(loaded.projects, [project])
    }

    func testCorruptStateIsNotTreatedAsEmptyAndRemainsUntouched() throws {
        let root = try temporaryDirectory()
        let url = root.appendingPathComponent("state.json")
        let corrupt = Data("{not json".utf8)
        try corrupt.write(to: url)
        XCTAssertThrowsError(try LocalJSONFile<WorkbenchState>(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testSkillParsesMultilineDescriptionNestedRequirementsAndLists() throws {
        let source = """
        ---
        name: 'Local review'
        description: >-
          Review a project
          using real files.
        tags:
          - code
          - local
        requires:
          bins: [git, rg]
          anyBins: [python3, python]
          env: [DEMO_TOKEN]
        platforms: [darwin]
        enabled: false
        ---
        Read files before making claims.
        """
        let skill = try LocalSkill.parse(source, id: "review", url: URL(fileURLWithPath: "/tmp/SKILL.md"))
        XCTAssertEqual(skill.name, "Local review")
        XCTAssertEqual(skill.description, "Review a project using real files.")
        XCTAssertEqual(skill.tags, ["code", "local"])
        XCTAssertEqual(skill.requiredBinaries, ["git", "rg"])
        XCTAssertEqual(skill.anyBinaries, ["python3", "python"])
        XCTAssertEqual(skill.requiredEnvironment, ["DEMO_TOKEN"])
        XCTAssertFalse(skill.enabledByDefault)
        XCTAssertNil(skill.unavailableReason(environment: ["DEMO_TOKEN": "configured"], executableExists: { _ in true }))
        XCTAssertNotNil(skill.unavailableReason(environment: [:], executableExists: { _ in true }))
    }

    func testSkillLiteralBlockAndMalformedFrontmatter() throws {
        let skill = try LocalSkill.parse("---\nname: test\ndescription: |\n  First.\n  Second.\n---\nDo it.", id: "test", url: URL(fileURLWithPath: "/tmp/test.md"))
        XCTAssertEqual(skill.description, "First.\nSecond.")
        XCTAssertThrowsError(try LocalSkill.parse("---\nname: broken\nbody", id: "bad", url: skill.url))
        XCTAssertThrowsError(try LocalSkill.parse("---\nname: empty\n---\n", id: "bad", url: skill.url))
    }

    func testOnlySelectedEnabledSkillsEnterContextWithoutMutatingTheirFiles() throws {
        let skills = try LocalSkill.bundled.map { try LocalSkill.parse($0.source, id: $0.id, url: URL(fileURLWithPath: "/tmp/\($0.id)/SKILL.md")) }
        let context = try LocalSkill.context(for: ["code-review", "document-analysis"], skills: skills, enabled: ["document-analysis": false])
        XCTAssertTrue(context.contains("Local code review"))
        XCTAssertFalse(context.contains("Document analysis"))
        XCTAssertFalse(context.contains("Skill author"))
        XCTAssertThrowsError(try LocalSkill.context(for: ["code-review"], skills: skills, enabled: [:], limit: 10))
        XCTAssertTrue(skills.allSatisfy { $0.raw.contains("---") })
    }

    func testFileOperationsAndUnicodeSearchUseActualDiskFiles() throws {
        let root = try temporaryDirectory()
        _ = try LocalFileTools.write(root: root, path: "src/example.swift", content: "first\n안녕하세요 Bedrock\nlast")
        XCTAssertEqual(try LocalFileTools.list(root: root).map(\.path), ["src/example.swift"])
        XCTAssertEqual(try LocalFileTools.read(root: root, path: "src/example.swift", startLine: 2, lineCount: 1), "2: 안녕하세요 Bedrock")
        XCTAssertTrue(try LocalFileTools.search(root: root, query: "안녕").contains("src/example.swift:2:"))
        XCTAssertEqual(try LocalFileTools.search(root: root, query: "missing"), "No matches.")
    }

    func testPathTraversalAbsoluteSiblingAndSymlinksCannotEscapeProject() throws {
        let root = try temporaryDirectory()
        let outside = try temporaryDirectory()
        try Data("outside".utf8).write(to: outside.appendingPathComponent("private.txt"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        for path in ["../private.txt", outside.appendingPathComponent("private.txt").path, "escape/private.txt", "escape/new.txt"] {
            XCTAssertThrowsError(try LocalPath.resolve(path, in: root), path)
        }
        XCTAssertThrowsError(try LocalFileTools.write(root: root, path: "escape/new.txt", content: "bad"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("new.txt").path))
    }

    func testHiddenBuildAndBinaryFilesAreHandled() throws {
        let root = try temporaryDirectory()
        _ = try LocalFileTools.write(root: root, path: "node_modules/dependency.txt", content: "noise")
        _ = try LocalFileTools.write(root: root, path: ".hidden", content: "secret")
        try Data([0, 255, 1]).write(to: root.appendingPathComponent("binary"))
        XCTAssertEqual(try LocalFileTools.list(root: root).map(\.path), ["binary"])
        XCTAssertThrowsError(try LocalFileTools.read(root: root, path: "binary"))
        XCTAssertThrowsError(try LocalFileTools.read(root: root, path: ".hidden", maximumBytes: 2))
    }

    func testWebDomainsMatchBoundariesAndRejectCredentialsAndSchemes() throws {
        XCTAssertNoThrow(try LocalPath.validatedWebURL("https://docs.example.com/path", allowedDomains: "example.com"))
        for value in ["https://evil-example.com", "https://example.com.evil.test", "file:///tmp/test", "https://user:pass@example.com"] {
            XCTAssertThrowsError(try LocalPath.validatedWebURL(value, allowedDomains: "example.com"), value)
        }
    }

    func testProfileRemainsAnUpperBoundAndApprovalModes() {
        var preferences = WorkbenchPreferences()
        preferences.toolProfile = .chat
        preferences.customTools = [.runCommand]
        XCTAssertFalse(preferences.enabledTools.contains(.runCommand))
        preferences.toolProfile = .developer
        preferences.disabledTools = [.runCommand]
        XCTAssertFalse(preferences.enabledTools.contains(.runCommand))
        XCTAssertFalse(LocalApprovalMode.askForChanges.requiresApproval(tool: .readFile))
        XCTAssertTrue(LocalApprovalMode.askForChanges.requiresApproval(tool: .writeFile))
        XCTAssertTrue(LocalApprovalMode.askForChanges.requiresApproval(tool: nil))
        XCTAssertTrue(LocalApprovalMode.askAlways.requiresApproval(tool: .readFile))
    }

    func testContextBudgetKeepsCompleteToolCycles() throws {
        let sizes: [ContextMessageSize] = [
            .init(startsUserTurn: true, characters: 100),
            .init(startsUserTurn: false, characters: 300),
            .init(startsUserTurn: false, characters: 200),
            .init(startsUserTurn: true, characters: 100),
            .init(startsUserTurn: false, characters: 300),
            .init(startsUserTurn: false, characters: 200),
            .init(startsUserTurn: true, characters: 100)
        ]
        let result = try ContextBudget.select(sizes, budget: 700)
        XCTAssertEqual(result.startIndex, 3)
        XCTAssertEqual(result.omittedMessages, 3)
        XCTAssertEqual(result.retainedCharacters, 700)
        XCTAssertNotNil(result.notice)
        XCTAssertThrowsError(try ContextBudget.select(sizes, budget: 50))
    }

    func testMultipleInterleavedToolsAndConcurrentThreadsStayIndependent() throws {
        var first = ToolStreamAccumulator()
        var second = ToolStreamAccumulator()
        try first.begin(index: 1, id: "a", name: "read")
        try first.begin(index: 3, id: "b", name: "search")
        try second.begin(index: 1, id: "c", name: "status")
        try first.append(index: 1, json: "{\"path\":")
        try first.append(index: 3, json: "{\"query\":\"안녕\"}")
        try first.append(index: 1, json: "\"README.md\"}")
        try first.complete(index: 3)
        try second.complete(index: 1)
        XCTAssertThrowsError(try first.finish())
        try first.complete(index: 1)
        XCTAssertEqual(try first.finish().map(\.id), ["a", "b"])
        XCTAssertEqual(try second.finish().map(\.id), ["c"])
        XCTAssertEqual(try second.finish().first?.inputJSON, "{}")
        XCTAssertThrowsError(try first.begin(index: 4, id: "a", name: "duplicate"))
    }

    func testMalformedToolInputCannotExecuteAsAnEmptyObject() throws {
        var accumulator = ToolStreamAccumulator()
        try accumulator.begin(index: 0, id: "a", name: "write")
        try accumulator.append(index: 0, json: "{\"path\":")
        XCTAssertThrowsError(try accumulator.complete(index: 0))
    }

    func testPresetVariablesAreLiteralAndRequired() throws {
        let demo = DemoPreset(id: "custom", title: "test", summary: "", category: .text, prompt: "{{topic}} then {{topic}}")
        XCTAssertEqual(demo.variables, ["topic"])
        XCTAssertThrowsError(try demo.renderedPrompt(values: [:]))
        XCTAssertEqual(try demo.renderedPrompt(values: ["topic": #"$& \ hello"#]), #"$& \ hello then $& \ hello"#)
        let nested = DemoPreset(id: "nested", title: "test", summary: "", category: .text, prompt: "{{first}} then {{second}}")
        XCTAssertEqual(try nested.renderedPrompt(values: ["first": "{{second}}", "second": "value"]), "{{second}} then value")
    }

    func testModelIDsPreserveDottedVersionsAndOnlyRemoveKnownRegionPrefixes() {
        for base in ["deepseek.v3.2", "minimax.minimax-m2.5", "xai.grok-4.6", "openai.gpt-5.6-luna"] {
            XCTAssertEqual(BedrockModelID.base(base), base)
            XCTAssertEqual(BedrockModelID.base("global." + base), base)
            XCTAssertEqual(BedrockModelID.base("arn:aws:bedrock:us-east-1:123456789012:inference-profile/us." + base), base)
        }
        XCTAssertEqual(BedrockModelID.providerName("global.moonshotai.kimi-k2.5"), "Moonshot AI")
        XCTAssertEqual(BedrockModelID.base("us-gov.openai.gpt-6-astra"), "openai.gpt-6-astra")
        XCTAssertEqual(BedrockModelID.route("global.openai.gpt-6-astra"), .conversation)
        XCTAssertEqual(BedrockModelID.route("openai.gpt-5.5"), .responses)
        XCTAssertEqual(BedrockModelID.route("google.gemma-4-e2b"), .responses)
        XCTAssertEqual(BedrockModelID.route("xai.grok-4.3"), .responses)
        XCTAssertEqual(BedrockModelID.route("luma.ray-v2:0"), .video)
        XCTAssertEqual(BedrockModelID.route("cohere.embed-v4:0"), .embedding)
        XCTAssertEqual(BedrockModelID.route("amazon.nova-2-sonic-v1:0"), .speech)
    }

    func testLegacyFilteringKeepsActiveSuccessorsAndHandlesProfileMetadata() {
        for id in ["amazon.nova-reel-v1:1", "us.amazon.nova-canvas-v1:0", "global.anthropic.claude-sonnet-4-20250514-v1:0"] {
            XCTAssertTrue(BedrockModelID.isLegacy(id))
        }
        for id in ["amazon.nova-2-sonic-v1:0", "anthropic.claude-sonnet-4-6", "anthropic.claude-opus-4-8"] {
            XCTAssertFalse(BedrockModelID.isLegacy(id))
            XCTAssertTrue(BedrockModelID.isLegacy(id, lifecycle: "LEGACY"))
        }
    }

    func testProfileResolutionUsesMetadataAndKeepsExplicitRouting() {
        let registry = BedrockCapabilityRegistry()
        let base = BedrockModelDescriptor(id: "openai.gpt-6-astra", name: "GPT-6 Astra", provider: "OpenAI",
                                         inputModalities: ["TEXT", "IMAGE"], outputModalities: ["TEXT"],
                                         inferenceTypes: ["INFERENCE_PROFILE"], streaming: true)
        var us = base
        us.id = "us." + base.id
        us.foundationID = base.id
        us.isProfile = true
        var global = us
        global.id = "global." + base.id
        registry.replace(region: "us-east-1", descriptors: [base, global, us])
        XCTAssertEqual(registry.invocationID(base.id, region: "us-east-1"), us.id)
        XCTAssertEqual(registry.invocationID(global.id, region: "us-east-1"), global.id)
        XCTAssertEqual(registry.invocationID(base.id, region: "eu-west-1"), base.id)
        XCTAssertEqual(registry.foundationID(us.id, region: "us-east-1"), base.id)
    }

    func testModelPickerGroupsProfilesWithoutChangingAnExplicitSelection() throws {
        let base = BedrockModelDescriptor(id: "openai.gpt-5.6-luna", name: "GPT-5.6 Luna", provider: "OpenAI",
                                          inputModalities: ["TEXT", "IMAGE"], outputModalities: ["TEXT"],
                                          inferenceTypes: ["INFERENCE_PROFILE"], streaming: true)
        var us = base
        us.id = "us." + base.id
        us.isProfile = true
        us.foundationID = base.id
        var global = us
        global.id = "global." + base.id
        let rows = BedrockModelChoice.make(descriptors: [global, base, us], selectedID: global.id,
                                          favoriteIDs: [us.id], region: "us-east-1")
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(row.id, base.id)
        XCTAssertEqual(row.name, "GPT-5.6 Luna")
        XCTAssertEqual(row.preferredID, global.id)
        XCTAssertTrue(row.isFavorite)
        XCTAssertEqual(Set(row.variants.map(\.id)), Set([base.id, us.id, global.id]))
        XCTAssertTrue(row.matches("openai luna"))
        XCTAssertTrue(row.matches(global.id))
        XCTAssertFalse(row.matches("luna anthropic"))

        let automatic = BedrockModelChoice.make(descriptors: [global, base, us], selectedID: nil,
                                                favoriteIDs: [], region: "us-east-1")
        XCTAssertEqual(automatic.first?.preferredID, us.id)
        let reopened = BedrockModelChoice.make(descriptors: [us, global, base], selectedID: nil,
                                               favoriteIDs: [global.id], region: "us-east-1")
        XCTAssertEqual(reopened.first?.preferredID, global.id)
    }

    func testModelPickerRetainsUnknownProvidersAndFiltersUnusableModels() {
        let custom = BedrockModelDescriptor(id: "new-provider.future-model-1.2", name: "Future model", provider: "New Provider",
                                            inputModalities: ["TEXT"], outputModalities: ["TEXT"],
                                            inferenceTypes: ["ON_DEMAND"], streaming: true, origin: .custom)
        var retired = custom
        retired.id = "new-provider.retired"
        retired.lifecycle = "LEGACY"
        var provisioned = custom
        provisioned.id = "new-provider.provisioned"
        provisioned.inferenceTypes = ["PROVISIONED"]
        let rows = BedrockModelChoice.make(descriptors: [provisioned, retired, custom], selectedID: nil,
                                           favoriteIDs: [], region: "eu-west-1")
        XCTAssertEqual(rows.map(\.preferredID), [custom.id])
        XCTAssertEqual(rows.first?.provider, custom.provider)
    }

    func testChatOnlyProfileDoesNotAdvertiseStatusTools() {
        XCTAssertTrue(LocalToolProfile.chat.tools.isEmpty)
        XCTAssertFalse(LocalToolProfile.readOnly.tools.contains(.sessionStatus))
        XCTAssertFalse(LocalToolProfile.developer.tools.contains(.sessionStatus))
        var preferences = WorkbenchPreferences()
        preferences.toolProfile = .custom
        preferences.customTools = [.sessionStatus]
        XCTAssertEqual(preferences.enabledTools, [.sessionStatus])
    }

    func testMCPToolNamesAreStableBoundedAndSeparateServers() {
        let name = MCPToolIdentity.invocationName(server: "Local server", tool: "search")
        XCTAssertEqual(name, MCPToolIdentity.invocationName(server: "Local server", tool: "search"))
        XCTAssertNotEqual(name, MCPToolIdentity.invocationName(server: "Remote server", tool: "search"))
        XCTAssertNotEqual(name, MCPToolIdentity.invocationName(server: "Local server", tool: "Search"))
        let longName = MCPToolIdentity.invocationName(server: "검증 서버", tool: String(repeating: "한글.path/tool!", count: 30))
        XCTAssertLessThanOrEqual(longName.utf8.count, 64)
        XCTAssertNotNil(longName.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression))
        XCTAssertNotEqual(MCPToolIdentity.invocationName(server: "a", tool: "b.c"),
                          MCPToolIdentity.invocationName(server: "a.b", tool: "c"))
    }

    func testMCPArgumentQuotingRoundTripsEmptyUnicodeAndShellMetacharacters() async throws {
        let arguments = ["", "a b", "한글", "quote's", "$(touch unwanted)", "`pwd`", ";", "a\\b", "\"quoted\""]
        XCTAssertEqual(try LocalArguments.parse(LocalArguments.display(arguments)), arguments)
        XCTAssertEqual(try LocalArguments.parse(#"--name "a b" --flag 'literal $HOME'"#), ["--name", "a b", "--flag", "literal $HOME"])
        XCTAssertThrowsError(try LocalArguments.parse("\"unclosed"))
        XCTAssertThrowsError(try LocalArguments.parse("trailing\\"))
        let root = try temporaryDirectory()
        let result = try await LocalProcessRunner.run(executable: "/bin/zsh", arguments: ["-f", "-c", "printf '%s\\n' " + LocalArguments.display(arguments)], directory: root)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.output, arguments.joined(separator: "\n") + "\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("unwanted").path))
    }

    func testDataMigrationCopiesHistoryAndRejectsNonemptyOrNestedDestinations() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("original")
        let destination = root.appendingPathComponent("moved")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let data = Data("한글 draft".utf8)
        try data.write(to: source.appendingPathComponent("history.json"))
        try LocalDataMigration.copy(from: source, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("history.json")), data)
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("history.json")), data)
        XCTAssertThrowsError(try LocalDataMigration.copy(from: source, to: destination))
        XCTAssertThrowsError(try LocalDataMigration.copy(from: source, to: source.appendingPathComponent("nested")))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("history.json")), data)
    }

    func testScheduleCalculationsDoNotReplayMissedIntervals() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var automation = LocalAutomation(name: "Demo", prompt: "Hello", modelID: "model")
        automation.cadence = .interval
        automation.intervalMinutes = 15
        XCTAssertEqual(automation.nextDate(after: now), now.addingTimeInterval(900))
        automation.cadence = .once
        automation.scheduledAt = now.addingTimeInterval(-10)
        XCTAssertNil(automation.nextDate(after: now))
        automation.scheduledAt = now.addingTimeInterval(10)
        XCTAssertEqual(automation.nextDate(after: now), automation.scheduledAt)
        XCTAssertFalse(automation.enabled)
        automation.modelID = ""
        XCTAssertNotNil(automation.validationError)
    }

    func testDailyScheduleUsesCalendarAcrossDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let before = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23)))
        var automation = LocalAutomation(name: "Daily", prompt: "Hello", modelID: "model")
        automation.scheduledAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9, minute: 30)))
        let next = try XCTUnwrap(automation.nextDate(after: before, calendar: calendar))
        XCTAssertEqual(calendar.component(.hour, from: next), 9)
        XCTAssertEqual(calendar.component(.minute, from: next), 30)
        XCTAssertEqual(calendar.component(.day, from: next), 8)
    }

    func testSettingsAndDemosHaveUniqueStableDestinations() {
        XCTAssertEqual(Set(WorkbenchSetting.all.map(\.id)).count, WorkbenchSetting.all.count)
        XCTAssertEqual(Set(DemoPreset.builtIns.map(\.id)).count, DemoPreset.builtIns.count)
        XCTAssertEqual(Set(WorkbenchSetting.all.map(\.pane)), Set(WorkbenchSettingsPane.allCases))
        XCTAssertTrue(WorkbenchSetting.all.contains { $0.id == "approval" && $0.matches("permission") })
        for tool in LocalToolKind.allCases {
            XCTAssertTrue(WorkbenchSetting.all.contains { $0.id == tool.rawValue && $0.pane == .tools })
        }
    }

    func testShellCommandRunsInProjectWithBoundedUnicodeOutput() async throws {
        let root = try temporaryDirectory()
        let result = try await LocalProcessRunner.run(executable: "/bin/zsh", arguments: ["-f", "-c", "pwd; printf '안녕하세요'"], directory: root)
        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.output.contains(root.path))
        XCTAssertTrue(result.output.contains("안녕하세요"))
        let bounded = try await LocalProcessRunner.run(executable: "/usr/bin/yes", arguments: ["output"], directory: root, timeout: 0.1, outputLimit: 100)
        XCTAssertTrue(bounded.timedOut)
        XCTAssertTrue(bounded.truncated)
        XCTAssertLessThan(bounded.output.utf8.count, 200)
    }

    func testCancellingProcessAlsoStopsItsChild() async throws {
        let root = try temporaryDirectory()
        let task = Task {
            try await LocalProcessRunner.run(executable: "/bin/zsh", arguments: ["-f", "-c", "(sleep 1; touch should-not-exist) & wait"], directory: root, timeout: 10)
        }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        let result = try await task.value
        XCTAssertTrue(result.cancelled)
        XCTAssertLessThan(result.duration, 1)
        try await Task.sleep(for: .seconds(1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("should-not-exist").path))
    }
}
