import AppKit
import AWSBedrockRuntime
import Combine
import Foundation
import Smithy

struct PendingToolApproval: Identifiable {
    let id: UUID
    let threadID: String
    let name: String
    let input: String
    let workingDirectory: String?
}

@MainActor
final class ToolApprovalCenter: ObservableObject {
    static let shared = ToolApprovalCenter()
    @Published private(set) var pending: [PendingToolApproval] = []
    private var continuations: [UUID: CheckedContinuation<Bool, Never>] = [:]

    func request(threadID: String, name: String, input: String, workingDirectory: String?) async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: false); return }
                continuations[id] = continuation
                pending.append(.init(id: id, threadID: threadID, name: name, input: input, workingDirectory: workingDirectory))
            }
        } onCancel: {
            Task { @MainActor in self.resolve(id, allow: false) }
        }
    }
    func resolve(_ id: UUID, allow: Bool) {
        pending.removeAll { $0.id == id }
        continuations.removeValue(forKey: id)?.resume(returning: allow)
    }
    func cancel(threadID: String) {
        for request in pending where request.threadID == threadID { resolve(request.id, allow: false) }
    }
}

@MainActor
enum LocalToolExecutor {
    static func availableTools(threadID: String) -> [BuiltInTool] {
        let enabled = AppStore.shared.preferences.enabledTools
        return BuiltInTool.allCases.filter { enabled.contains($0) }
    }

    static func specifications(threadID: String) -> [BedrockRuntimeClientTypes.Tool] {
        availableTools(threadID: threadID).compactMap { kind in
            var properties: [String: Any] = [:]
            var required: [String] = []
            func string(_ key: String, _ description: String, required isRequired: Bool = true) {
                properties[key] = ["type": "string", "description": description]
                if isRequired { required.append(key) }
            }
            switch kind {
            case .readFile:
                string("path", "Absolute, ~/, or working-directory-relative file path.")
                properties["start_line"] = ["type": "integer", "minimum": 1, "description": "First line to return, starting at 1."]
                properties["line_count"] = ["type": "integer", "minimum": 1, "maximum": 5000]
            case .listFiles:
                string("directory", "Absolute, ~/, or relative directory; defaults to the working directory.", required: false)
                properties["recursive"] = ["type": "boolean", "description": "Include nested files; false by default."]
                properties["include_hidden"] = ["type": "boolean", "description": "Include hidden entries; false by default."]
            case .searchFiles:
                string("query", "Literal text to search for.")
                string("directory", "Directory to search recursively; defaults to the working directory.", required: false)
            case .writeFile:
                string("path", "Absolute, ~/, or working-directory-relative file path.")
                string("content", "Complete UTF-8 file content.")
            case .runCommand:
                string("command", "Shell command to run on this Mac.")
                string("directory", "Working directory for the command. Accepts absolute, ~/, and working-directory-relative paths.", required: false)
            case .gitStatus:
                properties["action"] = ["type": "string", "enum": ["status", "diff", "log"]]
                required = ["action"]
                string("directory", "Local repository directory. Accepts absolute, ~/, and working-directory-relative paths.", required: false)
            case .fetchURL, .openURL: string("url", "HTTP or HTTPS URL without embedded credentials.")
            case .readSkill: string("id", "Exact skill ID returned by local_list_skills.")
            case .sessionStatus, .listSkills: break
            }
            do {
                let document = try Document.make(from: ["type": "object", "properties": properties, "required": required, "additionalProperties": false] as [String: Any])
                return .toolspec(.init(description: kind.description, inputSchema: .json(document), name: kind.rawValue))
            } catch { return nil }
        }
    }

    static func authorize(name: String, input: JSONValue, threadID: String) async -> Bool {
        let store = AppStore.shared
        let kind = BuiltInTool(rawValue: name)
        if let kind, !availableTools(threadID: threadID).contains(kind) { return false }
        guard store.preferences.approvalMode.requiresApproval(tool: kind) else { return !Task.isCancelled }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let text = (try? encoder.encode(input)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let tool = MCPClientManager.shared.toolInfo(named: name)
        let title = tool.map { "\($0.toolName) · \($0.serverName)" } ?? name
        return await ToolApprovalCenter.shared.request(
            threadID: threadID, name: kind?.title ?? title,
            input: text, workingDirectory: store.thread(threadID).workingDirectory ?? store.preferences.workingDirectory
        )
    }

    static func execute(kind: BuiltInTool, input: JSONValue, threadID: String, modelID: String) async -> ChatViewModel.SendableToolResult {
        let store = AppStore.shared
        guard availableTools(threadID: threadID).contains(kind) else {
            return .init(status: "error", text: "This tool is disabled in Settings → Tools & MCP.", error: "Tool unavailable")
        }
        let values = input.asDictionary ?? [:]
        let preferences = store.preferences
        let access = preferences.fileAccess(workingDirectory: store.thread(threadID).workingDirectory)
        func string(_ key: String) throws -> String {
            guard let value = values[key] as? String, !value.isEmpty else {
                throw LocalOperationError.invalid("Missing required tool input: \(key).")
            }
            return value
        }
        do {
            try Task.checkCancellation()
            let output: String
            switch kind {
            case .readFile:
                let path = try string("path")
                let start = values["start_line"] as? Int ?? 1
                let count = values["line_count"] as? Int ?? 300
                output = try await fileWork {
                    let location = try access.resolve(path, allowRoot: false)
                    return try LocalFileTools.read(root: location.root, path: location.url.path, startLine: start, lineCount: count)
                }
            case .listFiles:
                let directory = values["directory"] as? String ?? "."
                let recursive = values["recursive"] as? Bool ?? false
                let includeHidden = values["include_hidden"] as? Bool ?? false
                output = try await fileWork {
                    let location = try access.resolve(directory)
                    let files = try LocalFileTools.list(root: location.url, recursive: recursive, includeHidden: includeHidden)
                    let entries = files.map { $0.isDirectory ? "\($0.path)/" : "\($0.path) (\($0.bytes) bytes)" }
                    return "Directory: \(location.url.path)\n" + (entries.isEmpty ? "No entries." : entries.joined(separator: "\n"))
                }
            case .searchFiles:
                let query = try string("query")
                let directory = values["directory"] as? String ?? "."
                output = try await fileWork {
                    let location = try access.resolve(directory)
                    return "Directory: \(location.url.path)\n" + (try LocalFileTools.search(root: location.url, query: query))
                }
            case .writeFile:
                let path = try string("path")
                guard let content = values["content"] as? String else { throw LocalOperationError.invalid("Missing file content.") }
                output = try await fileWork {
                    let location = try access.resolve(path, allowRoot: false)
                    return try LocalFileTools.write(root: location.root, path: location.url.path, content: content)
                }
            case .runCommand, .gitStatus:
                // The optional file allowlist governs file tools, not a shell sandbox.
                let directory = values["directory"] as? String ?? "."
                let root = try LocalFileAccess(workingDirectory: access.workingDirectory).resolve(directory).url
                let executable: String
                let arguments: [String]
                if kind == .runCommand {
                    executable = "/bin/zsh"
                    arguments = ["-f", "-c", try string("command")]
                } else {
                    executable = "/usr/bin/git"
                    let prefix = ["--no-pager", "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false"]
                    switch try string("action") {
                    case "status": arguments = prefix + ["status", "--short", "--branch"]
                    case "diff": arguments = prefix + ["diff", "--no-ext-diff", "--no-textconv", "--", "."]
                    case "log": arguments = prefix + ["log", "-12", "--oneline"]
                    default: throw LocalOperationError.invalid("Git action must be status, diff, or log.")
                    }
                }
                let result = try await LocalProcessRunner.run(executable: executable, arguments: arguments, directory: root,
                                                              timeout: Double(preferences.validCommandTimeout), outputLimit: preferences.validToolOutputLimit)
                let suffix = result.timedOut ? "\n[Command timed out]" : result.cancelled ? "\n[Command stopped]" : "\n[Exit code: \(result.exitCode)]"
                return .init(status: result.succeeded ? "success" : "error",
                             text: result.output + suffix, error: result.succeeded ? nil : suffix)
            case .fetchURL:
                let url = try LocalPath.validatedWebURL(try string("url"), allowedDomains: preferences.allowedWebDomains)
                output = try await DirectWebFetcher.fetch(url: url, allowedDomains: preferences.allowedWebDomains,
                                                         limit: preferences.validToolOutputLimit, timeout: preferences.validCommandTimeout)
            case .openURL:
                let url = try LocalPath.validatedWebURL(try string("url"), allowedDomains: preferences.allowedWebDomains)
                guard NSWorkspace.shared.open(url) else { throw LocalOperationError.unavailable("macOS could not open this URL.") }
                output = "Opened \(url.absoluteString) in the default browser."
            case .sessionStatus:
                let lines = [
                    "Model: \(modelID)",
                    "Local time: \(Date().formatted(date: .abbreviated, time: .standard)) (\(TimeZone.current.identifier))",
                    "Working directory: \(try access.directory.path)",
                    "Tools: \(availableTools(threadID: threadID).map(\.rawValue).joined(separator: ", "))"
                ]
                output = lines.joined(separator: "\n")
            case .listSkills:
                await store.waitForSkills()
                let enabled = store.skills.filter { store.isSkillEnabled($0) }
                let skills = try await fileWork { enabled.filter { $0.unavailableReason() == nil } }
                output = skills.isEmpty ? "No enabled local skills. Manage skills in Settings → Skills." :
                    skills.map { "ID: \($0.id)\nName: \($0.name)\nDescription: \($0.description)" }.joined(separator: "\n\n")
            case .readSkill:
                await store.waitForSkills()
                let id = try string("id")
                guard let skill = store.skills.first(where: { $0.id == id }), store.isSkillEnabled(skill) else {
                    throw LocalOperationError.unavailable("This skill is not enabled. Use local_list_skills for available IDs.")
                }
                if let reason = try await fileWork({ skill.unavailableReason() }) { throw LocalOperationError.unavailable(reason) }
                output = "Skill: \(skill.name)\nID: \(skill.id)\nReference directory: \(skill.url.deletingLastPathComponent().path)\n\n\(skill.raw)"
            }
            return .init(status: "success", text: LocalFileTools.bounded(output, limit: preferences.validToolOutputLimit), error: nil)
        } catch {
            return .init(status: "error", text: error is CancellationError ? "Tool stopped." : error.localizedDescription, error: error.localizedDescription)
        }
    }
    private static func fileWork<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority: .userInitiated, operation: operation)
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}

private final class DirectWebFetcher: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let allowedDomains: String
    init(allowedDomains: String) { self.allowedDomains = allowedDomains }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let value = request.url?.absoluteString,
              (try? LocalPath.validatedWebURL(value, allowedDomains: allowedDomains)) != nil else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
    static func fetch(url: URL, allowedDomains: String, limit: Int, timeout: Int) async throws -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Double(timeout)
        configuration.timeoutIntervalForResource = Double(timeout)
        configuration.httpShouldSetCookies = false
        let delegate = DirectWebFetcher(allowedDomains: allowedDomains)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LocalOperationError.unavailable("The web request returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0).")
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            data.append(byte)
            if data.count >= min(1_048_576, limit * 4) { break }
        }
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
            throw LocalOperationError.invalid("This URL returned binary content rather than UTF-8 text.")
        }
        return LocalFileTools.bounded(text, limit: limit)
    }
}
