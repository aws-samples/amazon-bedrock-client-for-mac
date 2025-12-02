//
//  MCPManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 3/24/25.
//

import Foundation
import Combine
import MCP
import Logging
import System

/**
 * Manages Model Context Protocol (MCP) integrations.
 * Handles server connections, tool discovery, and tool execution.
 * Uses mcp_config.json as the single source of truth for server configuration.
 */
@MainActor
class MCPManager: ObservableObject {
    static let shared = MCPManager()
    private var logger = Logger(label: "MCPManager")
    
    // Published properties
    @Published private(set) var activeClients: [String: Client] = [:]
    @Published private(set) var availableTools: [String: [Tool]] = [:]
    @Published private(set) var toolInfos: [MCPToolInfo] = []
    @Published private(set) var connectionStatus: [String: ConnectionStatus] = [:]
    
    // Server configuration - single source of truth from mcp_config.json
    @Published var servers: [MCPServerConfig] = [] {
        didSet {
            saveConfigFile()
        }
    }
    
    // MCP enabled state
    @Published var mcpEnabled: Bool {
        didSet {
            UserDefaults.standard.set(mcpEnabled, forKey: "mcpEnabled")
            if mcpEnabled {
                // Reset crash protection when user manually enables
                resetCrashProtection()
                markMCPRunning(true)
                connectToAllServers()
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
    
    private init() {
        // Check for previous crash and disable MCP if needed
        let wasRunning = UserDefaults.standard.bool(forKey: Self.mcpRunningKey)
        var crashCount = UserDefaults.standard.integer(forKey: Self.mcpCrashCountKey)
        
        if wasRunning {
            // App crashed while MCP was running
            crashCount += 1
            UserDefaults.standard.set(crashCount, forKey: Self.mcpCrashCountKey)
            logger.warning("Detected crash while MCP was running. Crash count: \(crashCount)")
            
            if crashCount >= 1 {
                // Disable MCP after 1 crash
                logger.error("MCP disabled due to crash")
                UserDefaults.standard.set(false, forKey: "mcpEnabled")
                UserDefaults.standard.set(true, forKey: Self.mcpDisabledDueToCrashKey)
                UserDefaults.standard.set(false, forKey: Self.mcpRunningKey)
            }
        }
        
        // Load mcpEnabled from UserDefaults
        self.mcpEnabled = UserDefaults.standard.bool(forKey: "mcpEnabled")
        
        // Load servers from config file
        loadConfigFile()
        
        // Start servers if enabled
        if mcpEnabled {
            startServersIfEnabled()
        }
    }
    
    /// Check if MCP was disabled due to crash
    var wasDisabledDueToCrash: Bool {
        UserDefaults.standard.bool(forKey: Self.mcpDisabledDueToCrashKey)
    }
    
    /// Reset crash count and re-enable MCP
    func resetCrashProtection() {
        UserDefaults.standard.set(0, forKey: Self.mcpCrashCountKey)
        UserDefaults.standard.set(false, forKey: Self.mcpDisabledDueToCrashKey)
        logger.info("MCP crash protection reset")
    }
    
    /// Mark MCP as running (call when MCP operations start)
    func markMCPRunning(_ running: Bool) {
        UserDefaults.standard.set(running, forKey: Self.mcpRunningKey)
    }
    
    // MARK: - Config File Management
    
    /**
     * Gets the path to the MCP config file.
     */
    func getConfigPath() -> String {
        let configDir = SettingManager.shared.defaultDirectory.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.path
            : SettingManager.shared.defaultDirectory
        
        return URL(fileURLWithPath: configDir)
            .appendingPathComponent("mcp_config.json")
            .path
    }
    
    /**
     * Loads server configuration from mcp_config.json.
     */
    func loadConfigFile() {
        let configPath = getConfigPath()
        var loadedServers: [MCPServerConfig] = []
        
        if FileManager.default.fileExists(atPath: configPath) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let serversJson = json["mcpServers"] as? [String: [String: Any]] {
                    
                    for (name, serverInfo) in serversJson {
                        // Support both "type" (Claude Code style) and "transportType" (legacy)
                        let transportTypeStr = serverInfo["type"] as? String
                            ?? serverInfo["transportType"] as? String
                            ?? "stdio"
                        let transportType = MCPTransportType(rawValue: transportTypeStr) ?? .stdio
                        let enabled = serverInfo["enabled"] as? Bool ?? true
                        
                        var server: MCPServerConfig
                        
                        if transportType == .http {
                            guard let url = serverInfo["url"] as? String else {
                                logger.warning("Skipping HTTP server '\(name)': missing URL")
                                continue
                            }
                            
                            server = MCPServerConfig(
                                name: name,
                                transportType: .http,
                                url: url,
                                headers: serverInfo["headers"] as? [String: String],
                                enabled: enabled
                            )
                        } else {
                            guard let command = serverInfo["command"] as? String,
                                  let argsArray = serverInfo["args"] as? [String] else {
                                logger.warning("Skipping stdio server '\(name)': missing command or args")
                                continue
                            }
                            
                            server = MCPServerConfig(
                                name: name,
                                transportType: .stdio,
                                command: command,
                                args: argsArray,
                                env: serverInfo["env"] as? [String: String],
                                cwd: serverInfo["cwd"] as? String,
                                enabled: enabled
                            )
                        }
                        
                        loadedServers.append(server)
                    }
                    
                    logger.info("Loaded \(loadedServers.count) MCP servers from config file")
                }
            } catch {
                logger.error("Error reading MCP config file: \(error)")
            }
        }
        
        // Update without triggering didSet save
        self.servers = loadedServers
    }
    
    /**
     * Saves server configuration to mcp_config.json.
     */
    func saveConfigFile() {
        var serversDict: [String: [String: Any]] = [:]
        
        for server in servers {
            var serverInfo: [String: Any] = [:]
            
            serverInfo["type"] = server.transportType.rawValue
            serverInfo["enabled"] = server.enabled
            
            if server.transportType == .http {
                if let url = server.url {
                    serverInfo["url"] = url
                }
                if let headers = server.headers, !headers.isEmpty {
                    serverInfo["headers"] = headers
                }
            } else {
                serverInfo["command"] = server.command
                serverInfo["args"] = server.args
                
                if let env = server.env, !env.isEmpty {
                    serverInfo["env"] = env
                }
                if let cwd = server.cwd, !cwd.isEmpty {
                    serverInfo["cwd"] = cwd
                }
            }
            
            serversDict[server.name] = serverInfo
        }
        
        let configDict: [String: Any] = ["mcpServers": serversDict]
        
        if let jsonData = try? JSONSerialization.data(
            withJSONObject: configDict,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        ) {
            do {
                let configPath = getConfigPath()
                let directoryURL = URL(fileURLWithPath: configPath).deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                try jsonData.write(to: URL(fileURLWithPath: configPath))
                logger.debug("Saved MCP config file")
            } catch {
                logger.error("Failed to save MCP config file: \(error)")
            }
        }
    }
    
    /**
     * Adds a new server configuration.
     */
    func addServer(_ server: MCPServerConfig) {
        if !servers.contains(where: { $0.name == server.name }) {
            servers.append(server)
            if server.enabled && mcpEnabled {
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
            servers[index] = server
            
            // Handle connection state changes
            if server.enabled && !wasEnabled && mcpEnabled {
                connectToServer(server)
            } else if !server.enabled && wasEnabled {
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
            
            if enabled && mcpEnabled {
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
        
        for server in servers.filter({ $0.enabled }) {
            if activeClients[server.name] == nil && !connecting.contains(server.name) {
                connectToServer(server)
            }
        }
    }
    
    /**
     * Detects the user's default shell.
     *
     * @return The path to the user's shell
     */
    private func getUserShell() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"] {
            return shell
        }
        
        // Fallback: try to get from passwd
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        process.arguments = [".", "-read", "/Users/\(NSUserName())", "UserShell"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let lines = output.components(separatedBy: .newlines)
                    for line in lines {
                        if line.contains("UserShell:") {
                            let shell = line.replacingOccurrences(of: "UserShell:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            return shell
                        }
                    }
                }
            }
        } catch {
            logger.warning("Failed to detect user shell: \(error)")
        }
        
        // Final fallback
        return "/bin/zsh"
    }
    
    /**
     * Creates a shell command string that properly sources shell configuration.
     *
     * @param command The command to execute
     * @param args The command arguments
     * @param workingDirectory Optional working directory
     * @return Shell command string
     */
    private func createShellCommand(command: String, args: [String], workingDirectory: String?) -> String {
        let shell = getUserShell()
        let shellName = URL(fileURLWithPath: shell).lastPathComponent
        
        var shellCommand = ""
        
        // Source appropriate shell configuration files
        if shellName.contains("zsh") {
            shellCommand += "source ~/.zshrc 2>/dev/null || true; "
        } else if shellName.contains("bash") {
            shellCommand += "source ~/.bashrc 2>/dev/null || true; source ~/.bash_profile 2>/dev/null || true; "
        }
        
        // Change directory if specified - don't quote to allow ~ expansion
        if let cwd = workingDirectory {
            // Replace ~ with $HOME for proper expansion
            let expandedCwd = cwd.replacingOccurrences(of: "~", with: "$HOME")
            shellCommand += "cd \(expandedCwd) && "
        }
        
        // Add the actual command - only quote args that need it
        let quotedArgs = args.map { arg in
            // Only quote if contains spaces or special characters
            if arg.contains(" ") || arg.contains("'") || arg.contains("$") {
                return "'\(arg.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
            } else {
                return arg
            }
        }.joined(separator: " ")
        
        // Don't quote the command itself if it's a simple command
        if command.contains(" ") || command.contains("'") {
            shellCommand += "'\(command.replacingOccurrences(of: "'", with: "'\"'\"'"))' \(quotedArgs)"
        } else {
            shellCommand += "\(command) \(quotedArgs)"
        }
        
        return shellCommand
    }
    
    /**
     * Connects to a specific MCP server.
     * Supports both stdio (local process) and HTTP (remote server) transports.
     *
     * @param server The server configuration to connect to
     */
    func connectToServer(_ server: MCPServerConfig) {
        guard mcpEnabled else { return }
        if connecting.contains(server.name) || activeClients[server.name] != nil { return }
        
        connecting.insert(server.name)
        DispatchQueue.main.async { self.connectionStatus[server.name] = .connecting }
        
        Task {
            do {
                switch server.transportType {
                case .http:
                    try await connectViaHTTP(server)
                case .stdio:
                    try await connectViaStdio(server)
                }
            } catch {
                logger.error("Failed to connect to server '\(server.name)': \(error.localizedDescription)")
                
                await MainActor.run {
                    self.connectionStatus[server.name] = .failed(error: error.localizedDescription)
                    self.connecting.remove(server.name)
                }
            }
        }
    }
    
    /**
     * Connects to an MCP server via HTTP transport (Streamable HTTP).
     * Supports OAuth 2.0 authentication for servers that require it.
     */
    private func connectViaHTTP(_ server: MCPServerConfig) async throws {
        guard let urlString = server.url, let endpoint = URL(string: urlString) else {
            throw NSError(domain: "MCPManager", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid URL for HTTP transport"])
        }
        
        logger.info("Connecting to MCP server via HTTP: \(endpoint)")
        
        // Try initial connection, handle OAuth if needed
        var serverConfig = server
        var lastError: Error?
        
        for attempt in 1...2 {
            do {
                let client = Client(name: "bedrock-client", version: "1.0.0")
                let transport = createHTTPTransport(endpoint: endpoint, headers: serverConfig.headers)
                
                let result = try await withTimeout(seconds: 15) {
                    try await client.connect(transport: transport)
                }
                
                // Connection successful
                if result.capabilities.tools != nil {
                    logger.info("HTTP Server \(server.name) supports tools")
                }
                
                // Fetch available tools and complete connection
                try await completeHTTPConnection(client: client, server: server)
                return
                
            } catch let error as MCPError {
                // Check if this is an authentication error
                if case .internalError(let message) = error,
                   let msg = message,
                   (msg.contains("Authentication required") || msg.contains("401") || msg.contains("invalid_token")) {
                    
                    if attempt == 1 {
                        logger.info("Server requires OAuth authentication, starting auth flow...")
                        
                        // TODO: Fix OAuth flow - ASWebAuthenticationSession crashes with MainActor isolation issues
                        // The OAuth implementation needs to be rewritten to properly handle Swift concurrency
                        // See: https://github.com/AzureAD/microsoft-authentication-library-for-objc/issues/588
                        // do {
                        //     serverConfig = try await MCPOAuthManager.shared.authenticate(for: serverConfig)
                        //     logger.info("OAuth authentication successful, retrying connection...")
                        //     continue
                        // } catch let oauthError {
                        //     logger.error("OAuth authentication failed: \(oauthError.localizedDescription)")
                        //     throw oauthError
                        // }
                        
                        // For now, throw an error indicating OAuth is not yet supported
                        throw NSError(domain: "MCPManager", code: 401,
                                     userInfo: [NSLocalizedDescriptionKey: "OAuth authentication required but not yet supported. Please configure server with pre-authenticated headers."])
                    }
                }
                lastError = error
                break
            } catch {
                lastError = error
                break
            }
        }
        
        if let error = lastError {
            throw error
        }
    }
    
    /**
     * Creates an HTTP transport with optional headers.
     */
    private func createHTTPTransport(endpoint: URL, headers: [String: String]?) -> HTTPClientTransport {
        if let headers = headers, !headers.isEmpty {
            let headersCopy = headers
            return HTTPClientTransport(
                endpoint: endpoint,
                requestModifier: { @Sendable request in
                    var modifiedRequest = request
                    for (key, value) in headersCopy {
                        modifiedRequest.addValue(value, forHTTPHeaderField: key)
                    }
                    return modifiedRequest
                },
                logger: logger
            )
        } else {
            return HTTPClientTransport(
                endpoint: endpoint,
                logger: logger
            )
        }
    }
    
    /**
     * Completes HTTP connection by fetching tools and updating state.
     */
    private func completeHTTPConnection(client: Client, server: MCPServerConfig) async throws {
        // Fetch available tools
        let tools: [Tool]?
        do {
            let (toolList, _) = try await client.listTools()
            tools = toolList
            logger.info("Successfully loaded \(tools?.count ?? 0) tools from HTTP server \(server.name)")
        } catch {
            tools = nil
            logger.warning("Failed to get tools from HTTP server \(server.name): \(error.localizedDescription)")
        }
        
        await MainActor.run {
            self.activeClients[server.name] = client
            self.connectionStatus[server.name] = .connected
            self.connecting.remove(server.name)
            
            if let tools = tools {
                self.availableTools[server.name] = tools
                self.updateToolInfos()
                
                let toolCount = self.toolInfos.count
                let serverCount = self.connectionStatus.values.filter { $0 == .connected }.count
                NotificationCenter.default.post(
                    name: .mcpServerConnected,
                    object: nil,
                    userInfo: [
                        "serverName": server.name,
                        "toolCount": toolCount,
                        "serverCount": serverCount
                    ]
                )
            }
        }
    }
    

    
    /**
     * Connects to an MCP server via stdio transport (local subprocess).
     */
    private func connectViaStdio(_ server: MCPServerConfig) async throws {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let args = server.args.map { $0.replacingOccurrences(of: "$HOME", with: homeDir) }
        let command = server.command.replacingOccurrences(of: "$HOME", with: homeDir)
        let workingDirectory = server.cwd?.replacingOccurrences(of: "$HOME", with: homeDir)
                
                // Get user's shell
                let shell = getUserShell()
                
                // Create shell command that sources configuration
                let shellCommand = createShellCommand(
                    command: command,
                    args: args,
                    workingDirectory: workingDirectory
                )
                
                logger.info("Executing MCP server via shell: \(shell) -l -c '\(shellCommand)'")
                
                // Create process with shell execution
                let process = Process()
                process.executableURL = URL(fileURLWithPath: shell)
                process.arguments = ["-l", "-c", shellCommand]
                
                // Set up basic environment
                var env = ProcessInfo.processInfo.environment
                env["HOME"] = homeDir
                
                // Add custom environment variables if specified
                if let customEnv = server.env {
                    for (key, value) in customEnv {
                        env[key] = value.replacingOccurrences(of: "$HOME", with: homeDir)
                    }
                }
                
                process.environment = env
                
                // Set up pipes for stdio
                let stdinPipe = Pipe()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.standardInput = stdinPipe
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                // Start the process
                try process.run()

                // Create client with timeout
                let client = try await withTimeout(seconds: 15) {
                    // First import System module if not already imported
                    let client = Client(
                        name: "bedrock-client",
                        version: "version"
                    )
                    
                    // Get the raw file descriptors
                    let stdoutFD = stdoutPipe.fileHandleForReading.fileDescriptor
                    let stdinFD = stdinPipe.fileHandleForWriting.fileDescriptor
                    
                    // Create FileDescriptor objects from raw values
                    let inputFileDescriptor = FileDescriptor(rawValue: stdoutFD)
                    let outputFileDescriptor = FileDescriptor(rawValue: stdinFD)
                    
                    // Create stdio transport with properly typed file descriptors
                    let logger = await MainActor.run { self.logger }
                    let transport = StdioTransport(
                        input: inputFileDescriptor,
                        output: outputFileDescriptor,
                        logger: logger
                    )

                    let result = try await client.connect(transport: transport)
                    
                    // Check if server supports tools
                    if result.capabilities.tools != nil {
                        await MainActor.run {
                            self.logger.info("Server \(server.name) supports tools")
                        }
                    }
                    
                    return client
                }
                
                // Fetch available tools
                let tools: [Tool]?
                do {
                    let (toolList, _) = try await client.listTools()
                    tools = toolList
                    logger.info("Successfully loaded \(tools?.count ?? 0) tools from server \(server.name)")
                    if let tools = tools, !tools.isEmpty {
                        for tool in tools {
                            logger.info("Tool loaded: \(tool.name) with schema: \(String(describing: tool.inputSchema))")
                        }
                    }
                } catch {
                    tools = nil
                    logger.warning("Failed to get tools from server \(server.name): \(error.localizedDescription)")
                }
                
                await MainActor.run {
                    self.activeClients[server.name] = client
                    self.connectionStatus[server.name] = .connected
                    self.connecting.remove(server.name)
                    
                    if let tools = tools {
                        self.availableTools[server.name] = tools
                        self.updateToolInfos()
                        
                        // Post notification when server connects with tools
                        let toolCount = self.toolInfos.count
                        let serverCount = self.connectionStatus.values.filter { $0 == .connected }.count
                        NotificationCenter.default.post(
                            name: .mcpServerConnected,
                            object: nil,
                            userInfo: [
                                "serverName": server.name,
                                "toolCount": toolCount,
                                "serverCount": serverCount
                            ]
                        )
                    }
                }
    }

    /**
     * Helper function to implement timeout for async operations.
     *
     * @param seconds The timeout duration in seconds
     * @param operation The async operation to perform with timeout
     * @return The result of the operation if completed within timeout
     * @throws Error if timeout occurs or operation fails
     */
    func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Task to perform the actual operation
            group.addTask {
                return try await operation()
            }
            
            // Task to handle timeout
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "MCPManager", code: 1,
                             userInfo: [NSLocalizedDescriptionKey: "Connection timeout"])
            }
            
            // Return result from first completed task and cancel others
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
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
        self.toolInfos = infos
        logger.info("Updated tool info list with \(infos.count) tools from \(availableTools.keys.count) servers")
    }
    
    /**
     * Disconnects from all connected servers.
     */
    func disconnectAllServers() {
        Task {
            for serverName in activeClients.keys {
                await disconnectServer(serverName)
            }
        }
    }
    
    /**
     * Disconnects from a specific server.
     *
     * @param serverName The name of the server to disconnect from
     */
    func disconnectServer(_ serverName: String) async {
        if let client = activeClients[serverName] {
            await client.disconnect()
        }
        
        await MainActor.run {
            activeClients.removeValue(forKey: serverName)
            availableTools.removeValue(forKey: serverName)
            connectionStatus[serverName] = .notConnected
            updateToolInfos()
            logger.info("Disconnected from server: \(serverName)")
        }
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
        } else if let intValue = value as? Int {
            return .int(intValue)
        } else if let doubleValue = value as? Double {
            return .double(doubleValue)
        } else if let boolValue = value as? Bool {
            return .bool(boolValue)
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
            // Check if this is multi-modal input
            if hasMultiModalContent(inputDict) {
                return try convertMultiModalInput(inputDict)
            } else {
                return convertArgumentsToMCPValues(inputDict)
            }
        } else if let inputDict = input as? [String: String] {
            return convertArgumentsToMCPValues(inputDict)
        } else {
            return ["value": convertToMCPValue(input)]
        }
    }
    
    /**
     * Checks if input contains multi-modal content.
     *
     * @param input Dictionary to check
     * @return True if contains multi-modal content
     */
    private func hasMultiModalContent(_ input: [String: Any]) -> Bool {
        return input.keys.contains { key in
            ["images", "documents", "audio", "content", "attachments"].contains(key.lowercased())
        }
    }
    
    /**
     * Converts multi-modal input to MCP format.
     *
     * @param input Multi-modal input dictionary
     * @return MCP-compatible arguments
     */
    private func convertMultiModalInput(_ input: [String: Any]) throws -> [String: Value] {
        var mcpArguments: [String: Value] = [:]
        var contentArray: [Value] = []
        
        // Add text content if present
        if let text = input["text"] as? String, !text.isEmpty {
            contentArray.append(.object([
                "type": .string("text"),
                "text": .string(text)
            ]))
        }
        
        // Add images if present
        if let images = input["images"] as? [[String: Any]] {
            for imageData in images {
                var imageContent: [String: Value] = [
                    "type": .string("image")
                ]
                
                if let data = imageData["data"] as? String {
                    imageContent["data"] = .string(data)
                }
                if let mimeType = imageData["mimeType"] as? String {
                    imageContent["mimeType"] = .string(mimeType)
                }
                if let metadata = imageData["metadata"] as? [String: Any] {
                    imageContent["metadata"] = .object(convertArgumentsToMCPValues(metadata))
                }
                
                contentArray.append(.object(imageContent))
            }
        }
        
        // Add documents if present
        if let documents = input["documents"] as? [[String: Any]] {
            for docData in documents {
                var docContent: [String: Value] = [
                    "type": .string("document")
                ]
                
                if let data = docData["data"] as? String {
                    docContent["data"] = .string(data)
                }
                if let mimeType = docData["mimeType"] as? String {
                    docContent["mimeType"] = .string(mimeType)
                }
                if let name = docData["name"] as? String {
                    docContent["name"] = .string(name)
                }
                
                contentArray.append(.object(docContent))
            }
        }
        
        // Add audio if present
        if let audioList = input["audio"] as? [[String: Any]] {
            for audioData in audioList {
                var audioContent: [String: Value] = [
                    "type": .string("audio")
                ]
                
                if let data = audioData["data"] as? String {
                    audioContent["data"] = .string(data)
                }
                if let mimeType = audioData["mimeType"] as? String {
                    audioContent["mimeType"] = .string(mimeType)
                }
                
                contentArray.append(.object(audioContent))
            }
        }
        
        // If we have multi-modal content, use content array
        if !contentArray.isEmpty {
            mcpArguments["content"] = .array(contentArray)
        }
        
        // Add any other parameters that aren't multi-modal
        for (key, value) in input {
            if !["text", "images", "documents", "audio", "content", "attachments"].contains(key.lowercased()) {
                mcpArguments[key] = convertToMCPValue(value)
            }
        }
        
        // If no content array was created, fall back to simple conversion
        if contentArray.isEmpty {
            return convertArgumentsToMCPValues(input)
        }
        
        return mcpArguments
    }
    
    /**
     * Extracts multi-modal content from tool execution result.
     *
     * @param content Array of content items from tool execution
     * @return Extracted multi-modal content in standardized format
     */
    private func extractMultiModalContent(_ content: [Tool.Content]) -> [[String: Any]] {
        var resultContent: [[String: Any]] = []
        
        for item in content {
            do {
                switch item {
                case .text(let text):
                    resultContent.append([
                        "type": "text",
                        "text": text
                    ])
                    
                case .image(let data, let mimeType, let metadata):
                    var imageResult: [String: Any] = [
                        "type": "image",
                        "mimeType": mimeType,
                        "size": data.count
                    ]
                    
                    // Add metadata if available
                    if let metadata = metadata {
                        imageResult["metadata"] = metadata
                        
                        // Safely extract width and height
                        var width = 0
                        var height = 0
                        
                        // Safely extract width - metadata values are strings
                        if let widthValue = metadata["width"], let widthInt = Int(widthValue) {
                            width = widthInt
                        }
                        
                        // Safely extract height - metadata values are strings
                        if let heightValue = metadata["height"], let heightInt = Int(heightValue) {
                            height = heightInt
                        }
                        
                        if width > 0 && height > 0 {
                            imageResult["description"] = "Generated \(width)x\(height) image"
                        } else {
                            imageResult["description"] = "Generated image"
                        }
                    } else {
                        imageResult["description"] = "Generated image"
                    }
                    
                    // Convert image data to base64 for transport
                    let base64String = try data.base64EncodedString()
                    imageResult["data"] = base64String
                    
                    resultContent.append(imageResult)
                    
                case .audio(let data, let mimeType):
                    let base64String = try data.base64EncodedString()
                    resultContent.append([
                        "type": "audio",
                        "mimeType": mimeType,
                        "size": data.count,
                        "data": base64String,
                        "description": "Generated audio"
                    ])

                case .resource(let uri, let mimeType, let text):
                    var resourceResult: [String: Any] = [
                        "type": "resource",
                        "uri": uri,
                        "mimeType": mimeType
                    ]
                    
                    if let text = text {
                        resourceResult["text"] = text
                        resourceResult["description"] = "Resource from \(uri)"
                    } else {
                        resourceResult["description"] = "Resource reference: \(uri)"
                    }
                    
                    resultContent.append(resourceResult)
                }
            } catch {
                logger.error("Error processing content item: \(error)")
                resultContent.append([
                    "type": "text",
                    "text": "Error processing content: \(error.localizedDescription)"
                ])
            }
        }
        
        // If no specific content was found, return a simple success message
        if resultContent.isEmpty {
            resultContent.append([
                "type": "text",
                "text": "Tool execution completed successfully"
            ])
        }
        
        return resultContent
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
            // Ensure we have a valid ID
            let toolId = id.isEmpty ? "tool_\(UUID().uuidString)" : id
            
            logger.info("Executing tool '\(name)' with input: \(input)")
            
            // Find server with the tool
            var serverWithTool: (name: String, client: Client)? = nil
            
            for (serverName, client) in activeClients {
                if let tools = availableTools[serverName],
                   tools.contains(where: { $0.name == name }) {
                    serverWithTool = (serverName, client)
                    break
                }
            }
            
            if let (serverName, client) = serverWithTool {
                logger.debug("Executing tool '\(name)' on server '\(serverName)'")
                
                // Convert input to proper format for tool call with multi-modal support
                let arguments = try convertToMultiModalArguments(input)
                
                let (content, isError) = try await client.callTool(name: name, arguments: arguments)
                
                let extractedContent = extractMultiModalContent(content)
                
                let hasError = isError ?? false
                if hasError {
                    return [
                        "id": toolId,
                        "status": "error",
                        "content": extractedContent
                    ]
                } else {
                    return [
                        "id": toolId,
                        "status": "success",
                        "content": extractedContent
                    ]
                }
            } else {
                logger.warning("Tool '\(name)' not found in any connected server")
                return [
                    "id": toolId,
                    "status": "error",
                    "content": [["text": "Tool '\(name)' not found in any connected server"]]
                ]
            }
        } catch let error as MCPError {
            logger.error("Tool execution error: \(error)")
            
            return [
                "id": id,
                "status": "error",
                "content": [["json": ["text": "Error executing tool:\n\(error.localizedDescription)"]]]
            ]
        } catch {
            logger.error("Tool execution error: \(error)")
            return [
                "id": id,
                "status": "error",
                "content": [["json": ["text": "Error executing tool:\n\(error.localizedDescription)"]]]
            ]
        }
    }
}
