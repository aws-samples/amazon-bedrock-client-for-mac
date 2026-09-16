import XCTest
@testable import BedrockCore

final class BackgroundProcessTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bedrock-process-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func wait(_ registry: BackgroundProcessRegistry, id: UUID, owner: String,
                      offset: Int = 0, until predicate: (BackgroundProcessSnapshot) -> Bool) async throws -> BackgroundProcessSnapshot {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let result = try await registry.snapshot(id, owner: owner, from: offset)
            if predicate(result) { return result }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw LocalOperationError.unavailable("The fixture process did not reach its expected state.")
    }

    func testOutputCanBePolledAcrossTurnsWithoutRepeatingConsumedBytes() async throws {
        let root = try directory()
        let registry = BackgroundProcessRegistry()
        addTeardownBlock { await registry.stopAll() }
        let started = try await registry.start(
            command: "printf READY; while [ ! -e release ]; do sleep 0.02; done; printf DONE",
            directory: root, owner: "chat", timeout: 10)
        let first = try await wait(registry, id: started.id, owner: "chat") { $0.output == "READY" }
        XCTAssertEqual(first.status, "running")
        try Data().write(to: root.appendingPathComponent("release"))
        let final = try await wait(registry, id: started.id, owner: "chat", offset: first.nextOffset) { $0.status == "completed" }
        XCTAssertEqual(final.output, "DONE")
        XCTAssertEqual(final.outputStart, first.nextOffset)
        XCTAssertEqual(final.nextOffset, 9)
        XCTAssertEqual(final.exitCode, 0)
        let consumed = try await registry.snapshot(started.id, owner: "chat", from: final.nextOffset)
        XCTAssertEqual(consumed.output, "")
    }

    func testOutputTailRemainsBoundedAndReportsDroppedBytes() async throws {
        let registry = BackgroundProcessRegistry()
        addTeardownBlock { await registry.stopAll() }
        let started = try await registry.start(command: "/usr/bin/yes x | /usr/bin/head -c 6000; printf TAIL",
                                               directory: directory(), owner: "chat", outputLimit: 1024)
        let final = try await wait(registry, id: started.id, owner: "chat") { $0.status == "completed" }
        XCTAssertLessThanOrEqual(final.output.utf8.count, 1024)
        XCTAssertTrue(final.output.hasSuffix("TAIL"))
        XCTAssertEqual(final.nextOffset, 6004)
        XCTAssertTrue(final.outputTruncated)
        XCTAssertGreaterThan(final.outputStart, 0)
    }

    func testStopKillsDescendantsAndRejectsAnotherChatsProcessID() async throws {
        let root = try directory()
        let registry = BackgroundProcessRegistry()
        addTeardownBlock { await registry.stopAll() }
        let started = try await registry.start(command: "(sleep 1; touch unexpected) & printf READY; wait",
                                               directory: root, owner: "owner", timeout: 10)
        _ = try await wait(registry, id: started.id, owner: "owner") { $0.output == "READY" }
        do {
            _ = try await registry.stop(started.id, owner: "other")
            XCTFail("A different chat must not stop this process.")
        } catch {}
        let stopped = try await registry.stop(started.id, owner: "owner")
        XCTAssertEqual(stopped.status, "stopped")
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("unexpected").path))
    }

    func testCapacityAndScopedShutdownKeepOtherChatsIndependent() async throws {
        let registry = BackgroundProcessRegistry(maximumRunning: 2, maximumHistory: 2)
        addTeardownBlock { await registry.stopAll() }
        let root = try directory()
        let first = try await registry.start(command: "sleep 10", directory: root, owner: "one")
        let second = try await registry.start(command: "sleep 10", directory: root, owner: "two")
        do {
            _ = try await registry.start(command: "sleep 10", directory: root, owner: "three")
            XCTFail("The running-process bound must be enforced.")
        } catch {}
        await registry.stopAll(owner: "one")
        let firstState = try await registry.snapshot(first.id, owner: "one")
        let secondState = try await registry.snapshot(second.id, owner: "two")
        XCTAssertEqual(firstState.status, "stopped")
        XCTAssertEqual(secondState.status, "running")
        await registry.stopAll()
        let ended = try await registry.snapshot(second.id, owner: "two")
        XCTAssertEqual(ended.status, "stopped")
    }

    func testContinuousOutputStillHonorsTimeout() async throws {
        let registry = BackgroundProcessRegistry()
        addTeardownBlock { await registry.stopAll() }
        let started = try await registry.start(command: "/usr/bin/yes OUTPUT", directory: directory(),
                                               owner: "chat", timeout: 0.1, outputLimit: 1024)
        let final = try await wait(registry, id: started.id, owner: "chat") { $0.status != "running" }
        XCTAssertEqual(final.status, "timed_out")
        XCTAssertTrue(final.outputTruncated)
        XCTAssertLessThanOrEqual(final.output.utf8.count, 1024)
    }

    func testCancellingAPollDoesNotTerminateTheBackgroundCommand() async throws {
        let registry = BackgroundProcessRegistry()
        addTeardownBlock { await registry.stopAll() }
        let started = try await registry.start(command: "sleep 10", directory: directory(), owner: "chat")
        let polling = Task { try await registry.poll(started.id, owner: "chat", wait: 10) }
        try await Task.sleep(for: .milliseconds(60))
        polling.cancel()
        do {
            _ = try await polling.value
            XCTFail("A cancelled wait must return promptly.")
        } catch is CancellationError {}
        let stillRunning = try await registry.snapshot(started.id, owner: "chat")
        XCTAssertEqual(stillRunning.status, "running")
    }
}
