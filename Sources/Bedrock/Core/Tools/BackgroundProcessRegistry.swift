import Foundation

struct BackgroundProcessSnapshot: Codable, Sendable {
    var id: UUID
    var command: String
    var directory: String
    var startedAt: Date
    var status: String
    var output: String
    var outputStart: Int
    var nextOffset: Int
    var outputTruncated: Bool
    var exitCode: Int32?
    var error: String?
}

/// Bounded process sessions, shared across tool turns but owned by one chat.
/// Only explicitly started processes enter this registry.
actor BackgroundProcessRegistry {
    static let shared = BackgroundProcessRegistry()

    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes = Data()
        private var total = 0
        private let limit: Int

        init(limit: Int) { self.limit = min(256_000, max(1_024, limit)) }

        func append(_ data: Data) {
            lock.lock()
            defer { lock.unlock() }
            total += data.count
            bytes.append(data)
            if bytes.count > limit { bytes.removeFirst(bytes.count - limit) }
        }

        func read(from offset: Int) -> (text: String, start: Int, end: Int, truncated: Bool) {
            lock.lock()
            defer { lock.unlock() }
            let available = total - bytes.count
            let start = min(total, max(available, max(0, offset)))
            return (String(decoding: bytes.dropFirst(start - available), as: UTF8.self),
                    start, total, offset < available)
        }
    }

    private struct Entry {
        var owner: String
        var command: String
        var directory: String
        var startedAt: Date
        var buffer: OutputBuffer
        var task: Task<Void, Never>?
        var result: LocalProcessResult?
        var error: String?
    }

    private var entries: [UUID: Entry] = [:]
    private let maximumRunning: Int
    private let maximumHistory: Int

    init(maximumRunning: Int = 4, maximumHistory: Int = 24) {
        self.maximumRunning = max(1, maximumRunning)
        self.maximumHistory = max(max(1, maximumRunning), maximumHistory)
    }

    func start(command: String, directory: URL, owner: String,
               timeout: TimeInterval = 600, outputLimit: Int = 32_000) throws -> BackgroundProcessSnapshot {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !command.contains("\0"), command.utf8.count <= 64_000 else {
            throw LocalOperationError.invalid("Enter a nonempty shell command of at most 64 KB.")
        }
        guard entries.values.filter({ $0.task != nil }).count < maximumRunning else {
            throw LocalOperationError.unavailable("At most \(maximumRunning) background commands can run at once. Stop one before starting another.")
        }
        if entries.count >= maximumHistory,
           let oldest = entries.filter({ $0.value.task == nil }).min(by: { $0.value.startedAt < $1.value.startedAt })?.key {
            entries.removeValue(forKey: oldest)
        }
        let id = UUID()
        let limit = min(256_000, max(1_024, outputLimit))
        let buffer = OutputBuffer(limit: limit)
        entries[id] = Entry(owner: owner, command: command, directory: directory.path,
                            startedAt: Date(), buffer: buffer)
        entries[id]?.task = Task {
            do {
                let result = try await LocalProcessRunner.run(
                    executable: "/bin/zsh", arguments: ["-f", "-c", command], directory: directory,
                    timeout: min(3_600, max(0.05, timeout)), outputLimit: limit,
                    onOutput: { buffer.append($0) }
                )
                finish(id, result: result, error: nil)
            } catch {
                finish(id, result: nil, error: error.localizedDescription)
            }
        }
        return try snapshot(id, owner: owner)
    }

    func snapshot(_ id: UUID, owner: String, from offset: Int = 0) throws -> BackgroundProcessSnapshot {
        guard let entry = entries[id], entry.owner == owner else {
            throw LocalOperationError.unavailable("This process is unavailable in the current chat. It may have ended before the app restarted.")
        }
        let output = entry.buffer.read(from: offset)
        let status: String
        if entry.task != nil { status = "running" }
        else if entry.result?.cancelled == true { status = "stopped" }
        else if entry.result?.timedOut == true { status = "timed_out" }
        else if entry.result?.succeeded == true { status = "completed" }
        else { status = "failed" }
        return .init(id: id, command: entry.command, directory: entry.directory, startedAt: entry.startedAt,
                     status: status, output: output.text, outputStart: output.start, nextOffset: output.end,
                     outputTruncated: output.truncated, exitCode: entry.result?.exitCode, error: entry.error)
    }

    func stop(_ id: UUID, owner: String) async throws -> BackgroundProcessSnapshot {
        _ = try snapshot(id, owner: owner)
        let task = entries[id]?.task
        task?.cancel()
        await task?.value
        return try snapshot(id, owner: owner)
    }

    func poll(_ id: UUID, owner: String, from offset: Int = 0,
              wait: TimeInterval = 1) async throws -> BackgroundProcessSnapshot {
        let deadline = Date().addingTimeInterval(min(10, max(0, wait)))
        var result = try snapshot(id, owner: owner, from: offset)
        while result.status == "running", result.nextOffset <= max(0, offset), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
            result = try snapshot(id, owner: owner, from: offset)
        }
        return result
    }

    func stopAll(owner: String? = nil) async {
        let tasks = entries.values.filter { owner == nil || $0.owner == owner }.compactMap(\.task)
        tasks.forEach { $0.cancel() }
        for task in tasks { await task.value }
    }

    private func finish(_ id: UUID, result: LocalProcessResult?, error: String?) {
        entries[id]?.result = result
        entries[id]?.error = error
        entries[id]?.task = nil
    }
}
