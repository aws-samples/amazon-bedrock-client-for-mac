import Foundation
import Darwin

struct LocalProcessResult: Equatable, Sendable {
    var output: String
    var exitCode: Int32
    var timedOut: Bool
    var cancelled: Bool
    var truncated: Bool
    var duration: TimeInterval
    var succeeded: Bool { exitCode == 0 && !timedOut && !cancelled }
}

/// Each command has its own process group, so cancelling it also stops descendants.
/// No shell is used by the caller unless it explicitly requests a shell command.
enum LocalProcessRunner {
    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false
        func cancel() { lock.lock(); stopped = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    }

    static func run(executable: String, arguments: [String], directory: URL,
                    timeout: TimeInterval = 30, outputLimit: Int = 32_000,
                    environment: [String: String]? = nil) async throws -> LocalProcessResult {
        let cancellation = Cancellation()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try execute(executable: executable, arguments: arguments, directory: directory,
                            timeout: timeout, outputLimit: outputLimit, environment: environment,
                            cancellation: cancellation)
            }.value
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func execute(executable: String, arguments: [String], directory: URL,
                                timeout: TimeInterval, outputLimit: Int,
                                environment: [String: String]?, cancellation: Cancellation) throws -> LocalProcessResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw LocalOperationError.unavailable("The command “\(executable)” is not installed or executable.")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LocalOperationError.unavailable("The working directory is unavailable.")
        }
        let started = Date()
        if cancellation.isCancelled {
            return .init(output: "", exitCode: -1, timedOut: false, cancelled: true, truncated: false, duration: 0)
        }
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else { throw POSIXError(.EMFILE) }
        defer { close(descriptors[0]) }

        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, descriptors[0])
        posix_spawn_file_actions_addclose(&actions, descriptors[1])
        let directoryResult = posix_spawn_file_actions_addchdir_np(&actions, directory.path)
        guard directoryResult == 0 else {
            close(descriptors[1])
            throw POSIXError(POSIXErrorCode(rawValue: directoryResult) ?? .EINVAL)
        }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)

        // Deliberately pass a small environment, not every application credential.
        let inherited = ProcessInfo.processInfo.environment
        let baseEnvironment = [
            "HOME": NSHomeDirectory(),
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": inherited["LANG"] ?? "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            "TMPDIR": NSTemporaryDirectory(),
            "TERM": "dumb",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_OPTIONAL_LOCKS": "0"
        ]
        let environmentValues = environment ?? baseEnvironment
        var argv = ([executable] + arguments).map { strdup($0) } + [nil]
        var envp = environmentValues.sorted(by: { $0.key < $1.key }).map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var pid: pid_t = 0
        let spawnResult = posix_spawn(&pid, executable, &actions, &attributes, &argv, &envp)
        close(descriptors[1])
        guard spawnResult == 0 else { throw POSIXError(POSIXErrorCode(rawValue: spawnResult) ?? .EIO) }
        _ = fcntl(descriptors[0], F_SETFL, O_NONBLOCK)

        var data = Data()
        let byteLimit = max(1, outputLimit)
        var buffer = [UInt8](repeating: 0, count: 8_192)
        var status: Int32 = 0
        var reaped = false
        var pipeEnded = false
        var timedOut = false
        var cancelled = false
        var truncated = false
        var stopAt: Date?
        while !reaped || !pipeEnded {
            while true {
                let count = read(descriptors[0], &buffer, buffer.count)
                if count > 0 {
                    let remaining = max(0, byteLimit - data.count)
                    data.append(contentsOf: buffer.prefix(min(count, remaining)))
                    if count > remaining { truncated = true }
                } else {
                    if count == 0 { pipeEnded = true }
                    break
                }
            }
            if !reaped {
                let result = waitpid(pid, &status, WNOHANG)
                reaped = result == pid || (result < 0 && errno == ECHILD)
            }
            let now = Date()
            if stopAt == nil && (cancellation.isCancelled || now.timeIntervalSince(started) >= max(0.05, timeout)) {
                cancelled = cancellation.isCancelled
                timedOut = !cancelled
                stopAt = now
                kill(-pid, SIGTERM)
            }
            if let stopAt, now.timeIntervalSince(stopAt) >= 0.25 {
                kill(-pid, SIGKILL)
                if reaped { break }
            }
            if reaped && pipeEnded { break }
            // A descendant that inherited stdout is still part of this command and is
            // bounded by the same timeout even after its immediate parent exits.
            var descriptor = pollfd(fd: descriptors[0], events: Int16(POLLIN), revents: 0)
            _ = poll(&descriptor, 1, 25)
        }
        if !reaped {
            kill(-pid, SIGKILL)
            while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
        }
        let signal = status & 0x7f
        let exitCode = signal == 0 ? (status >> 8) & 0xff : 128 + signal
        var text = String(decoding: data, as: UTF8.self)
        if truncated { text += "\n[Output truncated at \(byteLimit) bytes]" }
        return .init(output: text, exitCode: exitCode, timedOut: timedOut, cancelled: cancelled,
                     truncated: truncated, duration: Date().timeIntervalSince(started))
    }
}
