import Foundation
import MCP
import Logging
import System

/// Own the process and all pipe endpoints for the entire MCP connection.
/// Draining stderr is essential: a full stderr pipe can otherwise stall a server.
@MainActor
final class MCPProcess {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let diagnostics = MCPProcessDiagnostics()
    private var stopped = false
    var pid: Int32 { process.processIdentifier }
    var diagnosticText: String { diagnostics.text }

    init(command: String, arguments: [String], environment: [String: String]?, directory: String?) throws {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        func expand(_ value: String) -> String { value.replacingOccurrences(of: "$HOME", with: homeDirectory) }
        let executable = (expand(command) as NSString).expandingTildeInPath
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "/usr/bin:/bin") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        for (key, value) in environment ?? [:] { env[key] = expand(value) }
        process.environment = env
        if let directory, !directory.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: (expand(directory) as NSString).expandingTildeInPath)
        }
        // /usr/bin/env resolves a command through PATH without sourcing a login
        // shell or interpreting quotes, substitutions and semicolons in arguments.
        if executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments.map(expand)
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments.map(expand)
        }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        let diagnostics = diagnostics
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { diagnostics.append(data) }
        }
        do { try process.run() }
        catch {
            errors.fileHandleForReading.readabilityHandler = nil
            throw error
        }
    }

    func transport(logger: Logger) -> StdioTransport {
        StdioTransport(input: FileDescriptor(rawValue: output.fileHandleForReading.fileDescriptor),
                       output: FileDescriptor(rawValue: input.fileHandleForWriting.fileDescriptor), logger: logger)
    }

    func stop() async {
        guard !stopped else { return }
        stopped = true
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        for _ in 0..<20 where process.isRunning { try? await Task.sleep(for: .milliseconds(25)) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        errors.fileHandleForReading.readabilityHandler = nil
        try? output.fileHandleForReading.close()
        try? errors.fileHandleForReading.close()
    }
}

private final class MCPProcessDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        bytes.append(data.suffix(8_192))
        if bytes.count > 8_192 { bytes.removeFirst(bytes.count - 8_192) }
    }
    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: bytes, as: UTF8.self)
    }
}
