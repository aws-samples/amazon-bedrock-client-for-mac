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
    
    private init() {
        // Listen for MCP enabled state changes
        NotificationCenter.default.publisher(for: .mcpEnabledChanged)
            .sink { [weak self] _ in
                let enabled = SettingManager.shared.mcpEnabled
                if enabled {
                    self?.connectToAllServers()
                } else {
                    self?.disconnectAllServers()
                }
            }
            .store(in: &cancellables)
        
        SettingManager.shared.loadMCPServers()
        startServersIfEnabled()
    }
    
    /**
     * Starts MCP servers if enabled in settings.
     * Called once during app initialization.
     */
    func startServersIfEnabled() {
        if autoStartCompleted { return }
        
        autoStartCompleted = true
        if SettingManager.shared.mcpEnabled {
            connectToAllServers()
        }
    }
    
    /**
     * Connects to all enabled MCP servers.
     */
    func connectToAllServers() {
        guard SettingManager.shared.mcpEnabled else { return }
        
        for server in SettingManager.shared.mcpServers.filter({ $0.enabled }) {
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
     * Connects to a specific MCP server using shell environment.
     * Handles process creation, client initialization, and tool discovery.
     *
     * @param server The server configuration to connect to
     */
    func connectToServer(_ server: MCPServerConfig) {
        guard SettingManager.shared.mcpEnabled else { return }
        if connecting.contains(server.name) || activeClients[server.name] != nil { return }
        
        connecting.insert(server.name)
        DispatchQueue.main.async { self.connectionStatus[server.name] = .connecting }
        
        Task {
            do {
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
                    }
                }
            } catch {
                // Handle errors safely
                logger.error("Failed to connect to server '\(server.name)': \(error.localizedDescription)")
                
                await MainActor.run {
                    self.connectionStatus[server.name] = .failed(error: error.localizedDescription)
                    self.connecting.remove(server.name)
                    
                    // Auto-disable the server on connection failure
                    if let index = SettingManager.shared.mcpServers.firstIndex(where: { $0.name == server.name }) {
                        SettingManager.shared.mcpServers[index].enabled = false
                    }
                }
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
