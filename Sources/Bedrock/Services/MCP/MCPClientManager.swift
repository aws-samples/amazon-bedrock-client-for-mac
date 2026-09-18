//
//  MCPClientManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 3/24/25.
//

import Foundation
import Combine
import MCP
import Logging
import System

struct MCPConversationContext {
    let id: UUID
    let tools: [MCPToolInfo]
    let onboarding: String
}

/**
 * Manages Model Context Protocol (MCP) integrations.
 * Handles server connections, tool discovery, and tool execution.
 * Uses mcp_config.json as the single source of truth for server configuration.
 */
@MainActor
class MCPClientManager: ObservableObject {
    static let shared = MCPClientManager()
    private var logger = Logger(label: "MCPClientManager")
    private let preferences: UserDefaults
    private let configurationDirectory: URL?
    private let automaticallyConnect: Bool
    private let oauth: MCPOAuthService
    private var connectionTasks: [String: Task<Void, Never>] = [:]
    private var connectionIDs: [String: UUID] = [:]
    private var contextLeases: [UUID: Set<String>] = [:]
    private var idleTasks: [String: Task<Void, Never>] = [:]
    private var inFlightCalls: [String: Int] = [:]
    var idleDisconnectDelay: TimeInterval = 30
    private var processes: [String: MCPProcess] = [:]
    var activeProcessIDs: [String: Int32] { processes.mapValues(\.pid) }
    var connectionTimeout: TimeInterval = 15
    var toolTimeout: TimeInterval = 300

    // Published properties
    @Published private(set) var activeClients: [String: Client] = [:]
    @Published private(set) var availableTools: [String: [Tool]] = [:]
    @Published private(set) var toolInfos: [MCPToolInfo] = []
    @Published private(set) var connectionStatus: [String: ConnectionStatus] = [:]

    // Server configuration - single source of truth from mcp_config.json
    @Published var servers: [MCPServerConfig] = [] {
        didSet {
            if !isLoadingConfig { saveConfigFile() }
        }
    }
    private var isLoadingConfig = false
    private var configLoadFailed = false

    // MCP enabled state
    @Published var mcpEnabled: Bool {
        didSet {
            guard mcpEnabled != oldValue else { return }
            preferences.set(mcpEnabled, forKey: "mcpEnabled")
            if mcpEnabled {
                // Reset crash protection when user manually enables
                resetCrashProtection()
                markMCPRunning(true)
                if automaticallyConnect { connectToAllServers() }
            } else {
                markMCPRunning(false)
                disconnectAllServers()
            }
        }
    }

    // Status tracking
    private var autoStartCompleted = false
    private var connecting: Set<String> = []

    /**
     * Represents the connection status of a server.
     */
    enum ConnectionStatus: Equatable {
        case notConnected, connecting, connected
        case failed(error: String)

        static func == (lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
            switch (lhs, rhs) {
            case (.notConnected, .notConnected), (.connecting, .connecting), (.connected, .connected):
                return true
            case (.failed(let lhsError), .failed(let rhsError)):
                return lhsError == rhsError
            default:
                return false
            }
        }
    }

    private var cancellables = Set<AnyCancellable>()

    // Crash detection keys
    private static let mcpRunningKey = "mcpWasRunning"
    private static let mcpCrashCountKey = "mcpCrashCount"
    private static let mcpDisabledDueToCrashKey = "mcpDisabledDueToCrash"

    init(configurationDirectory: URL? = nil, preferences: UserDefaults = .standard, autoStart: Bool = true,
         oauth: MCPOAuthService? = nil) {
        self.configurationDirectory = configurationDirectory
        self.preferences = preferences
        self.automaticallyConnect = autoStart
        self.oauth = oauth ?? .shared
        // Check for previous crash and disable MCP if needed
        let wasRunning = preferences.bool(forKey: Self.mcpRunningKey)
        var crashCount = preferences.integer(forKey: Self.mcpCrashCountKey)

        if wasRunning {
            // App crashed while MCP was running
            crashCount += 1
            preferences.set(crashCount, forKey: Self.mcpCrashCountKey)
            logger.warning("Detected crash while MCP was running. Crash count: \(crashCount)")

            if crashCount >= 1 {
                // Disable MCP after 1 crash
                logger.error("MCP disabled due to crash")
                preferences.set(false, forKey: "mcpEnabled")
                preferences.set(true, forKey: Self.mcpDisabledDueToCrashKey)
                preferences.set(false, forKey: Self.mcpRunningKey)
            }
        }

        // Load mcpEnabled from UserDefaults
        self.mcpEnabled = preferences.bool(forKey: "mcpEnabled")

        // Load servers from config file
        loadConfigFile()
        self.oauth.migrateLegacyTokens(for: servers)

        // Start servers if enabled
        if mcpEnabled && autoStart {
            startServersIfEnabled()
        }
    }

    /// Check if MCP was disabled due to crash
    var wasDisabledDueToCrash: Bool {
        preferences.bool(forKey: Self.mcpDisabledDueToCrashKey)
    }

    /// Reset crash count and re-enable MCP
    func resetCrashProtection() {
        preferences.set(0, forKey: Self.mcpCrashCountKey)
        preferences.set(false, forKey: Self.mcpDisabledDueToCrashKey)
        logger.info("MCP crash protection reset")
    }

    /// Mark MCP as running (call when MCP operations start)
    func markMCPRunning(_ running: Bool) {
        preferences.set(running, forKey: Self.mcpRunningKey)
    }

    // MARK: - Config File Management

    /**
     * Gets the path to the MCP config file.
     */
    func getConfigPath() -> String {
        if let configurationDirectory { return configurationDirectory.appendingPathComponent("mcp_config.json").path }
        let configDir = PreferencesStore.shared.defaultDirectory.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.path
            : PreferencesStore.shared.defaultDirectory

        return URL(fileURLWithPath: configDir)
            .appendingPathComponent("mcp_config.json")
            .path
    }

    /**
     * Loads server configuration from mcp_config.json.
     */
    func loadConfigFile() {
        isLoadingConfig = true
        defer { isLoadingConfig = false }
        let url = URL(fileURLWithPath: getConfigPath())
        guard FileManager.default.fileExists(atPath: url.path) else {
            servers = []
            configLoadFailed = false
            return
        }
        do {
            let loaded = try MCPConfiguration.decode(Data(contentsOf: url))
            servers = loaded
            configLoadFailed = false
        } catch {
            configLoadFailed = true
            logger.error("MCP config could not be loaded; original file preserved")
            DispatchQueue.main.async {
                AppStore.shared.errorMessage = "Could not read mcp_config.json. The original file was preserved. Correct it and reopen the app.\n\(error.localizedDescription)"
            }
        }
    }

    func saveConfigFile() {
        guard !isLoadingConfig, !configLoadFailed else { return }
        do {
            let data = try MCPConfiguration.encode(servers)
            let url = URL(fileURLWithPath: getConfigPath())
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Could not save MCP configuration")
            DispatchQueue.main.async {
                AppStore.shared.errorMessage = "Could not save MCP configuration: \(error.localizedDescription)"
            }
        }
    }

    /**
     * Adds a new server configuration.
     */
    func addServer(_ server: MCPServerConfig) {
        if !servers.contains(where: { $0.name == server.name }) {
            servers.append(server)
            if server.enabled && mcpEnabled && shouldStart(server) {
                connectToServer(server)
            }
        }
    }

    /**
     * Updates an existing server configuration.
     */
    func updateServer(_ server: MCPServerConfig) {
        if let index = servers.firstIndex(where: { $0.name == server.name }) {
            let wasEnabled = servers[index].enabled

            // Create a new array to ensure didSet is triggered
            var updatedServers = servers
            updatedServers[index] = server
            servers = updatedServers

            // Handle connection state changes
            if server.enabled && mcpEnabled && shouldStart(server) {
                // Reconnect to apply changes
                Task {
                    await disconnectServer(server.name)
                    connectToServer(server)
                }
            } else if wasEnabled {
                Task {
                    await disconnectServer(server.name)
                }
            }
        }
    }

    /**
     * Removes a server configuration.
     */
    func removeServer(named name: String) {
        if let server = servers.first(where: { $0.name == name }) { oauth.clearToken(for: server) }
        Task {
            await disconnectServer(name)
        }
        servers.removeAll { $0.name == name }
    }

    /**
     * Toggles a server's enabled state.
     */
    func toggleServer(named name: String, enabled: Bool) {
        if let index = servers.firstIndex(where: { $0.name == name }) {
            servers[index].enabled = enabled

            if enabled && mcpEnabled && shouldStart(servers[index]) {
                connectToServer(servers[index])
            } else if !enabled {
                Task {
                    await disconnectServer(name)
                }
            }
        }
    }

    /**
     * Starts MCP servers if enabled in settings.
     * Called once during app initialization.
     */
    func startServersIfEnabled() {
        if autoStartCompleted { return }

        autoStartCompleted = true
        if mcpEnabled {
            connectToAllServers()
        }
    }

    /**
     * Connects to all enabled MCP servers.
     */
    func connectToAllServers() {
        guard mcpEnabled else { return }

        for server in servers.filter({ $0.enabled && shouldStart($0) }) {
            if activeClients[server.name] == nil && !connecting.contains(server.name) {
                connectToServer(server)
            }
        }
    }

    private func shouldStart(_ server: MCPServerConfig) -> Bool {
        !server.loadsOnDemand || contextLeases.values.contains { $0.contains(server.name) }
    }

    /// A lease lasts through the entire model/tool cycle, not just its first request.
    func prepareContext(prompt: String) async throws -> MCPConversationContext {
        let id = UUID()
        guard mcpEnabled else { return .init(id: id, tools: [], onboarding: "") }
        let selected = servers.filter { $0.enabled && MCPContextPolicy.matches(prompt, keywords: $0.activationKeywords) }
        let names = Set(selected.map(\.name))
        contextLeases[id] = names
        for server in selected {
            idleTasks.removeValue(forKey: server.name)?.cancel()
            connectToServer(server)
        }
        do {
            while names.contains(where: { connecting.contains($0) }) {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(25))
            }
            try Task.checkCancellation()
            guard mcpEnabled else { releaseContext(id); return .init(id: id, tools: [], onboarding: "") }
            let tools = toolInfos.filter { names.contains($0.serverName) && activeClients[$0.serverName] != nil }
            let active = Set(tools.map(\.serverName))
            let documentation = selected.filter { active.contains($0.name) }.map { ($0.name, $0.onboardingMarkdown ?? "") }
            return .init(id: id, tools: tools, onboarding: MCPContextPolicy.onboarding(documentation))
        } catch {
            releaseContext(id)
            throw error
        }
    }

    func releaseContext(_ id: UUID) {
        let names = contextLeases.removeValue(forKey: id) ?? []
        for name in names { scheduleIdleDisconnect(name) }
    }

    private func scheduleIdleDisconnect(_ name: String) {
        guard servers.first(where: { $0.name == name })?.loadsOnDemand == true,
              !contextLeases.values.contains(where: { $0.contains(name) }),
              inFlightCalls[name, default: 0] == 0 else { return }
        idleTasks.removeValue(forKey: name)?.cancel()
        idleTasks[name] = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: .seconds(max(0, idleDisconnectDelay))) }
            catch { return }
            guard !contextLeases.values.contains(where: { $0.contains(name) }),
                  inFlightCalls[name, default: 0] == 0 else { return }
            idleTasks.removeValue(forKey: name)
            await disconnectServer(name)
        }
    }

    func connectToServer(_ server: MCPServerConfig) {
        guard mcpEnabled, !connecting.contains(server.name), activeClients[server.name] == nil else { return }
        let generation = UUID()
        connectionIDs[server.name] = generation
        connecting.insert(server.name)
        connectionStatus[server.name] = .connecting
        connectionTasks[server.name] = Task {
            let client = Client(name: "bedrock-client", version: "1.0")
            var process: MCPProcess?
            do {
                try MCPConfiguration.validate(server)
                let transport: any Transport
                switch server.transportType {
                case .stdio:
                    let child = try MCPProcess(command: server.command, arguments: server.args,
                                                       environment: server.env, directory: server.cwd)
                    process = child
                    transport = child.transport(logger: logger)
                case .http:
                    transport = try makeHTTPTransport(for: server)
                }
                let tools: [Tool] = try await Self.withTimeout(seconds: connectionTimeout,
                    paused: { @MainActor [oauth] in oauth.isAuthenticating(server.name) },
                    interrupt: { await client.disconnect() }) {
                    let initialized = try await client.connect(transport: transport)
                    guard initialized.capabilities.tools != nil else { return [] }
                    var result: [Tool] = []
                    var cursor: String?
                    var seen: Set<String> = []
                    repeat {
                        try Task.checkCancellation()
                        let page = try await client.listTools(cursor: cursor)
                        result.append(contentsOf: page.tools)
                        guard result.count <= 2_000 else { throw LocalOperationError.invalid("This MCP server returned too many tools.") }
                        cursor = page.nextCursor
                        if let cursor, !seen.insert(cursor).inserted {
                            throw LocalOperationError.invalid("This MCP server repeated a tool-list cursor.")
                        }
                    } while cursor != nil
                    return result
                }
                guard !Task.isCancelled, mcpEnabled, connectionIDs[server.name] == generation else { throw CancellationError() }
                activeClients[server.name] = client
                if let process { processes[server.name] = process }
                availableTools[server.name] = tools
                connectionStatus[server.name] = .connected
                connecting.remove(server.name)
                connectionTasks.removeValue(forKey: server.name)
                updateToolInfos()
                NotificationCenter.default.post(name: .mcpServerConnected, object: nil,
                    userInfo: ["serverName": server.name, "toolCount": toolInfos.count,
                               "serverCount": activeClients.count])
            } catch {
                await client.disconnect()
                await process?.stop()
                guard connectionIDs[server.name] == generation else { return }
                connecting.remove(server.name)
                connectionTasks.removeValue(forKey: server.name)
                if error is CancellationError || Task.isCancelled { connectionStatus[server.name] = .notConnected }
                else {
                    let detail = process?.diagnosticText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let message = error.localizedDescription + (detail.isEmpty ? "" : "\n" + detail)
                    connectionStatus[server.name] = .failed(error: MCPConfiguration.redactedDiagnostic(message, server: server))
                    logger.warning("MCP connection failed for \(server.name)")
                }
            }
        }
    }

    func makeHTTPTransport(for server: MCPServerConfig,
                           configuration: URLSessionConfiguration = .default) throws -> HTTPClientTransport {
        let endpoint = try LocalPath.validatedWebURL(server.url ?? "", allowedDomains: "")
        // Explicit headers continue to support API keys/PATs. OAuth credentials are
        // applied dynamically by the transport and never persisted in configuration.
        let hasAuthorization = server.headers?.keys.contains { $0.caseInsensitiveCompare("Authorization") == .orderedSame } == true
        let secureOAuth = endpoint.scheme == "https" || ["localhost", "127.0.0.1", "::1", "[::1]"].contains(endpoint.host ?? "")
        let authorizer = !hasAuthorization && secureOAuth ? oauth.makeAuthorizer(for: server) : nil
        return HTTPClientTransport(endpoint: endpoint, configuration: configuration, authorizer: authorizer,
                                   requestModifier: { @Sendable request in
            var request = request
            for (key, value) in server.headers ?? [:] { request.setValue(value, forHTTPHeaderField: key) }
            return request
        }, logger: logger)
    }

    /// Cancelling a Swift task alone does not resume the SDK's pending JSON-RPC
    /// continuations. Interrupt the request/connection before awaiting the group.
    nonisolated private static func withTimeout<T: Sendable>(seconds: TimeInterval,
        paused: @escaping @Sendable () async -> Bool = { false },
        interrupt: @escaping @Sendable () async -> Void,
        operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: T.self) { group in
                defer { group.cancelAll() }
                group.addTask { try Task.checkCancellation(); return try await operation() }
                group.addTask {
                    var remaining = max(0.1, seconds)
                    while remaining > 0 {
                        let interval = min(0.25, remaining)
                        try await Task.sleep(for: .seconds(interval))
                        if !(await paused()) { remaining -= interval }
                    }
                    await interrupt()
                    throw LocalOperationError.unavailable("The MCP request timed out. Reconnect the server and try again.")
                }
                guard let result = try await group.next() else { throw CancellationError() }
                try Task.checkCancellation()
                return result
            }
        } onCancel: { Task { await interrupt() } }
    }

    /**
     * Updates the consolidated list of available tools from all connected servers.
     */
    private func updateToolInfos() {
        var infos: [MCPToolInfo] = []
        for (serverName, tools) in availableTools {
            for tool in tools {
                infos.append(MCPToolInfo(serverName: serverName, tool: tool))
            }
        }
        self.toolInfos = infos.sorted {
            ($0.serverName, $0.toolName) < ($1.serverName, $1.toolName)
        }
        logger.info("Updated tool info list with \(infos.count) tools from \(availableTools.keys.count) servers")
    }

    /// Old histories can contain unqualified names. Resolve them only when a
    /// single server owns the name, so reconnect order cannot change execution.
    func toolInfo(named name: String) -> MCPToolInfo? {
        if let exact = toolInfos.first(where: { $0.invocationName == name }) { return exact }
        let matches = toolInfos.filter { $0.toolName == name }
        return matches.count == 1 ? matches[0] : nil
    }

    /**
     * Disconnects from all connected servers.
     */
    func disconnectAllServers() {
        Task { await shutdown() }
    }

    func shutdown() async {
        contextLeases.removeAll()
        for task in idleTasks.values { task.cancel() }
        idleTasks.removeAll()
        let names = Set(activeClients.keys).union(connectionTasks.keys).union(processes.keys)
        for name in names { await disconnectServer(name) }
        markMCPRunning(false)
    }

    func disconnectServer(_ serverName: String) async {
        idleTasks.removeValue(forKey: serverName)?.cancel()
        connectionIDs.removeValue(forKey: serverName)
        let connectingTask = connectionTasks.removeValue(forKey: serverName)
        connectingTask?.cancel()
        let client = activeClients.removeValue(forKey: serverName)
        let process = processes.removeValue(forKey: serverName)
        connecting.remove(serverName)
        availableTools.removeValue(forKey: serverName)
        connectionStatus[serverName] = .notConnected
        updateToolInfos()
        await client?.disconnect()
        await process?.stop()
        await connectingTask?.value
    }

    /**
     * Converts Any value to MCP Value format.
     *
     * @param value The value to convert
     * @return The converted Value for MCP protocol
     */
    private func convertToMCPValue(_ value: Any) -> Value {
        if let stringValue = value as? String {
            return .string(stringValue)
        } else if let number = value as? NSNumber {
            // Foundation bridges JSON booleans to NSNumber; checking Int first
            // silently turns true/false into 1/0 for MCP servers.
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            if ["f", "d"].contains(String(cString: number.objCType)) {
                return .double(number.doubleValue)
            }
            return .int(number.intValue)
        } else if let arrayValue = value as? [Any] {
            return .array(arrayValue.map { convertToMCPValue($0) })
        } else if let dictValue = value as? [String: Any] {
            return .object(dictValue.mapValues { convertToMCPValue($0) })
        } else if value is NSNull {
            return .null
        } else {
            // Fallback: convert to string representation
            return .string(String(describing: value))
        }
    }

    /**
     * Converts [String: Any] dictionary to [String: Value] for MCP compatibility.
     *
     * @param arguments The arguments dictionary to convert
     * @return The converted dictionary with Value types
     */
    private func convertArgumentsToMCPValues(_ arguments: [String: Any]) -> [String: Value] {
        return arguments.mapValues { convertToMCPValue($0) }
    }

    /**
     * Converts input to multi-modal arguments for MCP.
     *
     * @param input The input to convert (can be text, structured data, or multi-modal content)
     * @return MCP-compatible arguments dictionary
     */
    private func convertToMultiModalArguments(_ input: Any) throws -> [String: Value] {
        if let inputString = input as? String {
            // Handle plain string input
            if let data = inputString.data(using: .utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return convertArgumentsToMCPValues(jsonObject)
            } else {
                return ["text": .string(inputString)]
            }
        } else if let inputDict = input as? [String: Any] {
            // Tool arguments follow each server's schema. Keys like images,
            // text and content are ordinary keys and must not be reshaped.
            return convertArgumentsToMCPValues(inputDict)
        } else if let inputDict = input as? [String: String] {
            return convertArgumentsToMCPValues(inputDict)
        } else {
            return ["value": convertToMCPValue(input)]
        }
    }

    /// Let the SDK encode its wire format. Its content cases include annotations
    /// and metadata; treating an entire associated-value tuple as a String
    /// silently drops text. Image/audio data is already base64 encoded.
    nonisolated private static func encodeResult(_ result: CallTool.Result) throws -> Data {
        try Task.checkCancellation()
        let data = try JSONEncoder().encode(result)
        guard data.count <= 32_000_000 else { throw LocalOperationError.tooLarge(32_000_000) }
        try Task.checkCancellation()
        return data
    }

    /**
     * Executes a Bedrock tool through the MCP interface with multi-modal support.
     * Handles complex JSON structures, images, documents, audio, and tool execution.
     *
     * @param id The unique identifier for this tool execution
     * @param name The name of the tool to execute
     * @param input The input parameters (supports multi-modal content)
     * @return A dictionary containing the execution result
     */
    func executeBedrockTool(id: String, name: String, input: Any) async -> [String: Any] {
        do {
            try Task.checkCancellation()
            // Ensure we have a valid ID
            let toolId = id.isEmpty ? "tool_\(UUID().uuidString)" : id

            if let info = toolInfo(named: name), let client = activeClients[info.serverName] {
                idleTasks.removeValue(forKey: info.serverName)?.cancel()
                inFlightCalls[info.serverName, default: 0] += 1
                defer {
                    inFlightCalls[info.serverName, default: 1] -= 1
                    scheduleIdleDisconnect(info.serverName)
                }
                logger.debug("Executing tool '\(info.toolName)' on server '\(info.serverName)'")

                // Convert input to proper format for tool call with multi-modal support
                let arguments = try convertToMultiModalArguments(input)
                try Task.checkCancellation()
                let context: RequestContext<CallTool.Result> = try await client.callTool(name: info.toolName, arguments: arguments)
                let result = try await Self.withTimeout(seconds: toolTimeout, interrupt: {
                    try? await client.cancelRequest(context.requestID, reason: "Request stopped or timed out")
                }) { try await context.value }
                let worker = Task.detached(priority: .userInitiated) { try Self.encodeResult(result) }
                let data = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard var output = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw LocalOperationError.invalid("The MCP server returned an invalid tool result.")
                }
                output["id"] = toolId
                output["status"] = result.isError == true ? "error" : "success"
                return output
            } else {
                logger.warning("Tool '\(name)' not found in any connected server")
                return [
                    "id": toolId,
                    "status": "error",
                    "content": [["text": "Tool '\(name)' not found in any connected server"]]
                ]
            }
        } catch {
            logger.error("Tool execution error: \(error)")
            let detail = error is CancellationError ? "Tool stopped or timed out." : error.localizedDescription
            return [
                "id": id,
                "status": "error",
                "error": detail,
                "content": [["type": "text", "text": "Error executing tool:\n\(detail)"]]
            ]
        }
    }
}
