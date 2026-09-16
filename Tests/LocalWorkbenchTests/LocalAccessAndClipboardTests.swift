import XCTest
import Darwin
@testable import LocalWorkbench

final class LocalAccessAndClipboardTests: XCTestCase {
    func testMarkdownLinksCannotLaunchLocalFilesOrApplicationCommands() throws {
        for value in ["https://example.com/a?q=1#heading", "http://localhost:8080", "mailto:demo@example.com"] {
            XCTAssertTrue(MarkdownLinkPolicy.allowsExternalLink(try XCTUnwrap(URL(string: value))))
        }
        for value in ["file:///tmp/private.txt", "javascript:alert(1)", "data:text/html,hello",
                      "x-apple.systempreferences:com.apple.preference.security", "https://user:password@example.com"] {
            XCTAssertFalse(MarkdownLinkPolicy.allowsExternalLink(try XCTUnwrap(URL(string: value))))
        }
    }

    func testBundledSkillUpgradePreservesUserEdits() throws {
        let original = """
        ---
        name: Local code review
        description: Inspect a local project and report actionable findings.
        tags: [code, review, local]
        ---
        Inspect the selected project with the available read, list, search, and Git tools. Read relevant source before drawing conclusions. Prioritize bugs, data loss, incorrect behavior, and missing validation. For each finding, name the file and line, explain a concrete trigger, and suggest the smallest appropriate fix. Do not modify files unless the user requests it. If no project is selected, ask the user to select a folder.
        """
        let upgraded = try XCTUnwrap(LocalSkill.bundledUpgrade(id: "code-review", source: original))
        XCTAssertTrue(upgraded.contains("Absolute and ~/ paths"))
        XCTAssertFalse(upgraded.contains("ask the user to select a folder"))
        XCTAssertNil(LocalSkill.bundledUpgrade(id: "code-review", source: original + "\nMy custom rule."))
        XCTAssertNil(LocalSkill.bundledUpgrade(id: "my-review", source: original))
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bedrock-access-test-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let resolved = try XCTUnwrap(realpath(url.path, nil))
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    func testNewPreferencesPermitAllToolsAndLocalPathsWithoutApproval() throws {
        let preferences = WorkbenchPreferences()
        XCTAssertEqual(preferences.enabledTools, Set(LocalToolKind.allCases))
        for tool in LocalToolKind.allCases { XCTAssertFalse(preferences.approvalMode.requiresApproval(tool: tool)) }
        XCTAssertFalse(preferences.approvalMode.requiresApproval(tool: nil)) // Enabled MCP tools.
        XCTAssertNil(preferences.fileAccess().allowedDirectories)
        XCTAssertEqual(try preferences.fileAccess().resolve("~/").url, FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath())
    }

    func testOldDefaultMigratesWhileConfiguredRestrictionsAndDraftsRemain() throws {
        var state = WorkbenchState()
        state.preferences.toolDefaultsVersion = nil
        state.preferences.toolProfile = .chat
        state.preferences.approvalMode = .askForChanges
        let folder = LocalProject(name: "Legacy", path: "/tmp/legacy")
        state.projects = [folder]
        state.threads["one"] = .init(draft: "안녕 👋", projectID: folder.id, skillIDs: ["code-review"])
        state.automations = [.init(name: "Saved", prompt: "Read README.md", modelID: "model", projectID: folder.id)]
        var migrated = try JSONDecoder().decode(WorkbenchState.self, from: JSONEncoder().encode(state))
        migrated.migrateLocalAccess()
        XCTAssertEqual(migrated.preferences.toolProfile, .all)
        XCTAssertEqual(migrated.preferences.approvalMode, .allowEnabled)
        XCTAssertEqual(migrated.threads["one"]?.draft, "안녕 👋")
        XCTAssertEqual(migrated.threads["one"]?.workingDirectory, folder.path)
        XCTAssertEqual(migrated.automations.first?.workingDirectory, folder.path)
        XCTAssertEqual(migrated.projects, state.projects)
        XCTAssertEqual(migrated.threads["one"]?.projectID, folder.id)
        var restricted = WorkbenchPreferences()
        restricted.toolDefaultsVersion = nil
        restricted.toolProfile = .readOnly
        restricted.approvalMode = .askAlways
        restricted.migrateToolDefaults()
        XCTAssertEqual(restricted.toolProfile, .readOnly)
        XCTAssertEqual(restricted.approvalMode, .askAlways)
    }

    func testAbsoluteRelativeTildeAndRootPathsWithoutProjects() throws {
        let root = try directory()
        let other = try directory()
        let access = LocalFileAccess(workingDirectory: root.path)
        XCTAssertEqual(try access.resolve("new.txt").url, root.appendingPathComponent("new.txt"))
        let location = try access.resolve(other.appendingPathComponent("outside.txt").path, allowRoot: false)
        _ = try LocalFileTools.write(root: location.root, path: location.url.path, content: "PERMISSIVE_OK")
        XCTAssertEqual(try LocalFileTools.read(root: location.root, path: location.url.path), "1: PERMISSIVE_OK")
        XCTAssertEqual(try LocalPath.resolve(other.path, in: URL(fileURLWithPath: "/")), other)
        XCTAssertEqual(try access.resolve("/").url.path, "/")
        XCTAssertThrowsError(try access.resolve("/", allowRoot: false))
        XCTAssertThrowsError(try access.resolve("bad\0path"))
    }

    func testOptionalScopeChecksSiblingPrefixesSymlinksAndMissingDestinations() throws {
        let root = try directory()
        let outside = try directory()
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        let restricted = LocalFileAccess(workingDirectory: root.path, allowedDirectories: [root.path])
        XCTAssertEqual(try restricted.resolve("src/new.swift").url, root.appendingPathComponent("src/new.swift"))
        for path in ["escape/new.txt", "../outside.txt", root.path + "-other/file", outside.path] {
            XCTAssertThrowsError(try restricted.resolve(path), path)
        }
        XCTAssertThrowsError(try LocalFileAccess(allowedDirectories: []).resolve("~"))
        let open = LocalFileAccess(workingDirectory: root.path)
        XCTAssertEqual(try open.resolve("escape/new.txt").url, outside.appendingPathComponent("new.txt"))
    }

    func testShallowListingDoesNotRecursivelyScanHomeSizedTrees() throws {
        let root = try directory()
        _ = try LocalFileTools.write(root: root, path: "nested/deep/file.txt", content: "inner")
        _ = try LocalFileTools.write(root: root, path: "top.txt", content: "top")
        _ = try LocalFileTools.write(root: root, path: ".hidden", content: "hidden")
        let entries = try LocalFileTools.list(root: root, recursive: false)
        XCTAssertEqual(entries.map(\.path), ["nested", "top.txt"])
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertTrue(try LocalFileTools.list(root: root, recursive: false, includeHidden: true).contains { $0.path == ".hidden" })
    }

    func testHTMLClipboardExtractsTextAndImagesWithoutInterpretingActiveContent() throws {
        let html = """
        <head><style>ignored</style><img src="https://bad.test/head.png"></head>
        <p>Hello <b>안녕하세요</b> &amp; &#x1F44B;</p>
        <script>window.location = 'file:///etc/passwd';</script>
        <p>Next&nbsp;line</p><img alt='a > b' SRC=https://example.com/one.png>
        <img src="https://example.com/two.png?a=1&amp;b=2">
        <img src="https://example.com/one.png">
        """
        let parsed = try ClipboardHTMLParser.parse(html)
        XCTAssertTrue(parsed.text.contains("Hello 안녕하세요 & 👋"))
        XCTAssertTrue(parsed.text.contains("Next line"))
        XCTAssertFalse(parsed.text.contains("window.location"))
        XCTAssertFalse(parsed.text.contains("ignored"))
        XCTAssertEqual(parsed.imageSources, ["https://example.com/one.png", "https://example.com/two.png?a=1&b=2"])
        XCTAssertEqual(try ClipboardHTMLParser.parse(html, includeText: false).text, "")
    }

    func testClipboardCannotReadLocalFilesOrUseActiveImageSchemesFromHTML() throws {
        let sources = ["file:///etc/passwd", "javascript:alert(1)", "data:image/svg+xml;base64,PHN2Zz4=",
                       "https://user:secret@example.com/image.png", "/private/file.png", "blob:https://example.com/id"]
        for source in sources { XCTAssertFalse(ClipboardHTMLParser.isImageSourceAllowed(source), source) }
        XCTAssertTrue(ClipboardHTMLParser.isImageSourceAllowed("data:image/png;base64,aGVsbG8="))
        let html = sources.map { "<img src='\($0)'>" }.joined()
        XCTAssertTrue(try ClipboardHTMLParser.parse(html).imageSources.isEmpty)
    }

    func testClipboardMalformedMarkupAndLargeMixedTextStayBounded() throws {
        let text = String(repeating: "<p>한글 &lt;code&gt; &amp; café 👩🏽‍💻</p>", count: 4_000)
        let parsed = try ClipboardHTMLParser.parse(text + "<img src='unterminated")
        XCTAssertTrue(parsed.text.contains("한글 <code> & café 👩🏽‍💻"))
        XCTAssertTrue(parsed.text.hasSuffix("<img src='unterminated"))
        let images = (0..<50).map { "<img src='https://example.com/\($0).png'>" }.joined()
        XCTAssertEqual(try ClipboardHTMLParser.parse(images).imageSources.count, ClipboardHTMLParser.maximumImages)
        XCTAssertThrowsError(try ClipboardHTMLParser.parse(String(repeating: "x", count: ClipboardHTMLParser.maximumHTMLBytes + 1)))
    }
}
