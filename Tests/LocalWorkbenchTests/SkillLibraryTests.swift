import Foundation
import XCTest
@testable import LocalWorkbench

final class SkillLibraryTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bedrock-skills-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
    }
    private let source = "---\nname: Reference fixture\ndescription: Read references/example.txt.\n---\nUse the supplied fixture."

    func testLoadReportsBrokenOversizedAndLinkedSkillsWithoutLosingValidEntries() throws {
        let root = try temporaryDirectory()
        try write(source, to: root.appendingPathComponent("valid/SKILL.md"))
        try write("---\nname: broken", to: root.appendingPathComponent("broken/SKILL.md"))
        try write(String(repeating: "x", count: LocalSkillLibrary.instructionLimit + 1), to: root.appendingPathComponent("large/SKILL.md"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: root.appendingPathComponent("valid"))
        let result = try LocalSkillLibrary.load(root)
        XCTAssertEqual(result.skills.map(\.id), ["valid"])
        XCTAssertEqual(result.issues.count, 3)
        XCTAssertTrue(result.issues.contains { $0.hasPrefix("broken:") })
        XCTAssertTrue(result.issues.contains { $0.hasPrefix("large:") })
        XCTAssertTrue(result.issues.contains { $0.hasPrefix("linked:") })
    }

    func testDuplicateIdentifiersAreReportedAndOnlyOneIsLoaded() throws {
        let root = try temporaryDirectory()
        try write(source, to: root.appendingPathComponent("same.md"))
        try write(source, to: root.appendingPathComponent("same/SKILL.md"))
        let result = try LocalSkillLibrary.load(root)
        XCTAssertEqual(result.skills.map(\.id), ["same"])
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertTrue(result.issues[0].contains("Duplicate"))
    }

    func testImportExportPreservesReferencesBinaryBytesAndExecutablePermission() throws {
        let root = try temporaryDirectory()
        let original = root.appendingPathComponent("Original")
        try write(source, to: original.appendingPathComponent("SKILL.md"))
        try write("Reference 가나다 😀", to: original.appendingPathComponent("references/example.txt"))
        try write("#!/bin/sh\nprintf 'fixture\\n'\n", to: original.appendingPathComponent("scripts/example.sh"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: original.appendingPathComponent("scripts/example.sh").path)
        let binary = Data([0, 255, 127, 42])
        try binary.write(to: original.appendingPathComponent("references/binary.dat"))
        let library = root.appendingPathComponent("Library")
        let id = try LocalSkillLibrary.importPackage(from: original, into: library)
        XCTAssertEqual(id, "original")
        let skill = try XCTUnwrap(try LocalSkillLibrary.load(library).skills.first)
        XCTAssertEqual(try LocalSkillLibrary.references(for: skill).map(\.path).sorted(),
                       ["references/binary.dat", "references/example.txt", "scripts/example.sh"])
        let exported = root.appendingPathComponent("Exported")
        try LocalSkillLibrary.export(skill, to: exported)
        XCTAssertEqual(try Data(contentsOf: exported.appendingPathComponent("references/binary.dat")), binary)
        XCTAssertEqual(try String(contentsOf: exported.appendingPathComponent("SKILL.md"), encoding: .utf8), source)
        let mode = try FileManager.default.attributesOfItem(atPath: exported.appendingPathComponent("scripts/example.sh").path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o755)
        XCTAssertThrowsError(try LocalSkillLibrary.importPackage(from: original, into: library))
        XCTAssertThrowsError(try LocalSkillLibrary.export(skill, to: exported))
        XCTAssertEqual(try LocalSkillLibrary.load(library).skills.count, 1)
    }

    func testImportRejectsReferenceSymlinksAndLeavesNoPartialPackage() throws {
        let root = try temporaryDirectory()
        let sourceFolder = root.appendingPathComponent("linked-skill")
        try write(source, to: sourceFolder.appendingPathComponent("SKILL.md"))
        try write("Outside", to: root.appendingPathComponent("outside.txt"))
        try FileManager.default.createSymbolicLink(at: sourceFolder.appendingPathComponent("reference.txt"), withDestinationURL: root.appendingPathComponent("outside.txt"))
        let library = root.appendingPathComponent("Library")
        XCTAssertThrowsError(try LocalSkillLibrary.importPackage(from: sourceFolder, into: library))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.path), [])
    }

    func testSaveValidatesBeforeReplacingExistingInstructions() throws {
        let root = try temporaryDirectory()
        let url = root.appendingPathComponent("fixture/SKILL.md")
        try LocalSkillLibrary.save(id: "fixture", source: source, existingURL: nil, directory: root)
        XCTAssertThrowsError(try LocalSkillLibrary.save(id: "fixture", source: "---\nbroken", existingURL: url, directory: root))
        XCTAssertThrowsError(try LocalSkillLibrary.save(id: "../escape", source: source, existingURL: nil, directory: root))
        XCTAssertThrowsError(try LocalSkillLibrary.save(id: "fixture", source: source + "\nreplacement", existingURL: nil, directory: root))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), source)
    }

    func testAvailabilityAndAppliedContextUseTheSameSnapshot() throws {
        let root = try temporaryDirectory()
        try write("---\nname: Missing command\nrequires:\n  bins: [bedrock-test-command-that-does-not-exist]\n---\nUse command.",
                  to: root.appendingPathComponent("missing/SKILL.md"))
        let result = try LocalSkillLibrary.load(root)
        XCTAssertEqual(result.skills.count, 1)
        XCTAssertNotNil(result.unavailable["missing"])
        XCTAssertThrowsError(try LocalSkill.context(for: ["missing"], skills: result.skills, enabled: [:], unavailable: result.unavailable))
        XCTAssertFalse(try LocalSkill.context(for: ["missing"], skills: result.skills, enabled: [:], unavailable: [:]).isEmpty)
    }

    func testCancelledImportCannotPublishAPartialSkill() async throws {
        let root = try temporaryDirectory()
        let sourceFolder = root.appendingPathComponent("cancelled")
        try write(source, to: sourceFolder.appendingPathComponent("SKILL.md"))
        let library = root.appendingPathComponent("Library")
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try LocalSkillLibrary.importPackage(from: sourceFolder, into: library)
        }
        do { _ = try await task.value; XCTFail("Cancelled import should throw.") }
        catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.appendingPathComponent("cancelled").path))
    }
}
