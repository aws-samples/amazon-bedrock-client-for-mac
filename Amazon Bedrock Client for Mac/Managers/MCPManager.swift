//
//  MCPManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 3/24/25.
//

import Foundation
import Combine
import MCPClient
import MCPInterface
import Logging

/**
 * Manages Model Context Protocol (MCP) integrations.
 * Handles server connections, tool discovery, and tool execution.
 */
class MCPManager: ObservableObject {
    static let shared = MCPManager()
    private var logger = Logger(label: "MCPManager")
    
    // Published properties
    @Published private(set) var activeClients: [String: MCPClient] = [:]
    @Published private(set) var availableTools: [String: [Tool]] = [:]
    @Published private(set) var toolInfos: [MCPToolInfo] = []
    @Published private(set) var connectionStatus: [String: ConnectionStatus] = [:]
    
    // Status tracking
    private var autoStartCompleted = false
    private var connecting: Set<String> = []
    
    /**
     * Represents a tool available from an MCP server.
     * Used primarily for UI display and server tool management.
     */
    struct MCPToolInfo: Identifiable, Hashable {
        var id: String { "\(serverName).\(toolName)" }
        var serverName: String
        var toolName: String
        var description: String
        var tool: Tool  // Store the complete Tool object
        
        init(serverName: String, tool: Tool) {
            self.serverName = serverName
            self.toolName = tool.name
            self.description = tool.description ?? "No description available"
            self.tool = tool
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: MCPToolInfo, rhs: MCPToolInfo) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
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
     * Connects to a specific MCP server.
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
                // Set up environment variables
                let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
                let args = server.args.map { $0.replacingOccurrences(of: "$HOME", with: homeDir) }
                
                var env = ProcessInfo.processInfo.environment
                let paths = [
                    "/usr/local/bin", "/opt/homebrew/bin",
                    "\(homeDir)/.nvm/versions/node/*/bin", env["PATH"] ?? ""
                ].joined(separator: ":")
                
                env["PATH"] = paths
                env["HOME"] = homeDir
                
                // Create process transport
                let transport: Transport
                do {
                    transport = try Transport.stdioProcess(
                        server.command, args: args, env: env, verbose: true)
                } catch {
                    await MainActor.run {
                        self.connectionStatus[server.name] = .failed(error: "Failed to start process: \(error.localizedDescription)")
                    }
                    connecting.remove(server.name)
                    return
                }
                
                // Create client with timeout protection
                let client = try await withTimeout(seconds: 15) {
                    try await MCPClient(
                        info: .init(name: "bedrock-client", version: "1.0.0"),
                        transport: transport,
                        capabilities: .init())
                }
                
                // Fetch available tools
                let tools: [Tool]?
                do {
                    tools = try await client.tools.value.get()
                    logger.info("Successfully loaded \(tools?.count ?? 0) tools from server \(server.name)")
                    if let tools = tools, !tools.isEmpty {
                        for tool in tools {
                            logger.info("Tool loaded: \(tool.name) with schema: \(tool.inputSchema)")
                        }
                    }
                } catch {
                    tools = nil
                    logger.warning("Failed to get tools from server \(server.name): \(error.localizedDescription)")
                }
                
                await MainActor.run {
                    self.activeClients[server.name] = client
                    self.connectionStatus[server.name] = .connected
                    
                    if let tools = tools {
                        self.availableTools[server.name] = tools
                        self.updateToolInfos()
                    }
                }
            } catch {
                await MainActor.run {
                    self.connectionStatus[server.name] = .failed(error: error.localizedDescription)
                }
            }
            
            connecting.remove(server.name)
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
    func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
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
        await MainActor.run {
            activeClients.removeValue(forKey: serverName)
            availableTools.removeValue(forKey: serverName)
            connectionStatus[serverName] = .notConnected
            updateToolInfos()
            logger.info("Disconnected from server: \(serverName)")
        }
    }
    
    /**
     * Executes a Bedrock tool through the MCP interface.
     * Handles complex JSON structures, tool execution, and result formatting.
     *
     * @param id The unique identifier for this tool execution
     * @param name The name of the tool to execute
     * @param input The input parameters (can be any valid JSON structure)
     * @return A dictionary containing the execution result
     */
    func executeBedrockTool(id: String, name: String, input: Any) async -> [String: Any] {
        do {
            // Ensure we have a valid ID
            let toolId = id.isEmpty ? "tool_\(UUID().uuidString)" : id
            
            // Convert input to MCPInterface.JSON format
            let jsonArguments: MCPInterface.JSON
            
            logger.info("Executing tool '\(name)' with input: \(input)")
            
            if let inputString = input as? String {
                // Parse JSON string input
                if let data = inputString.data(using: .utf8),
                   let jsonObject = try? JSONSerialization.jsonObject(with: data) {
                    jsonArguments = try convertToMCPJSON(jsonObject)
                } else {
                    // Plain string - wrap as text
                    jsonArguments = .object(["text": .string(inputString)])
                }
            } else if let inputDict = input as? [String: Any] {
                // Dictionary input
                jsonArguments = try convertToMCPJSON(inputDict)
            } else if let inputDict = input as? [String: String] {
                // Simple string dictionary
                var jsonDict = [String: MCPInterface.JSON.Value]()
                for (key, value) in inputDict {
                    jsonDict[key] = .string(value)
                }
                jsonArguments = .object(jsonDict)
            } else {
                // Try to serialize other types
                jsonArguments = try convertToMCPJSON(input)
            }
            
            // Find server with the tool
            var serverWithTool: (name: String, client: MCPClient)? = nil
            
            for (serverName, client) in activeClients {
                if let tools = availableTools[serverName],
                   tools.contains(where: { $0.name == name }) {
                    serverWithTool = (serverName, client)
                    break
                }
            }
            
            if let (serverName, client) = serverWithTool {
                logger.debug("Executing tool '\(name)' on server '\(serverName)'")
                
                let result = try await client.callTool(named: name, arguments: jsonArguments)
                let extractedText = extractTextFromToolResult(result)
                
                return [
                    "id": toolId,
                    "status": "success",
                    "content": [["json": ["text": extractedText]]]
                ]
            } else {
                logger.warning("Tool '\(name)' not found in any connected server")
                return [
                    "id": toolId,
                    "status": "error",
                    "content": [["text": "Tool '\(name)' not found in any connected server"]]
                ]
            }
        } catch let error as MCPClientError {
            logger.error("Tool execution error: \(error)")
            
            let errorMessage: String
            switch error {
            case .toolCallError(let executionErrors):
                errorMessage = executionErrors.map { $0.text }.joined(separator: "\n")
            default:
                errorMessage = error.localizedDescription
            }
            
            return [
                "id": id,
                "status": "error",
                "content": [["json": ["text": "Error executing tool:\n\(errorMessage)"]]]
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

    /**
     * Converts any Swift type to MCPInterface.JSON format
     *
     * @param value The value to convert
     * @return MCPInterface.JSON representation
     */
    func convertToMCPJSON(_ value: Any) throws -> MCPInterface.JSON {
        if let dict = value as? [String: Any] {
            var jsonDict = [String: MCPInterface.JSON.Value]()
            for (key, val) in dict {
                jsonDict[key] = try convertToMCPJSONValue(val)
            }
            return .object(jsonDict)
        } else if let array = value as? [Any] {
            var jsonArray = [MCPInterface.JSON.Value]()
            for item in array {
                jsonArray.append(try convertToMCPJSONValue(item))
            }
            return .array(jsonArray)
        } else {
            // Single value - wrap in object
            return .object(["value": try convertToMCPJSONValue(value)])
        }
    }

    /**
     * Converts any Swift value to MCPInterface.JSON.Value format
     *
     * @param value The value to convert
     * @return MCPInterface.JSON.Value representation
     */
    func convertToMCPJSONValue(_ value: Any) throws -> MCPInterface.JSON.Value {
        switch value {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .number(Double(int))
        case let double as Double:
            return .number(double)
        case let bool as Bool:
            return .bool(bool)
        case let dict as [String: Any]:
            var jsonDict = [String: MCPInterface.JSON.Value]()
            for (key, val) in dict {
                jsonDict[key] = try convertToMCPJSONValue(val)
            }
            return .object(jsonDict)
        case let array as [Any]:
            var jsonArray = [MCPInterface.JSON.Value]()
            for item in array {
                jsonArray.append(try convertToMCPJSONValue(item))
            }
            return .array(jsonArray)
        case is NSNull:
            return .null
        case nil:
            return .null
        default:
            // Try JSON serialization for unknown types
            if JSONSerialization.isValidJSONObject([value]) {
                let data = try JSONSerialization.data(withJSONObject: value)
                let jsonStr = String(data: data, encoding: .utf8) ?? String(describing: value)
                return .string(jsonStr)
            } else {
                return .string(String(describing: value))
            }
        }
    }

    /**
     * Parses a JSON string to a native Swift object (Dictionary or Array).
     *
     * @param jsonString The JSON string to parse
     * @return The parsed Swift object or nil if parsing fails
     */
    func parseJSONString(_ jsonString: String) -> Any? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        
        do {
            return try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            logger.error("Failed to parse JSON string: \(error)")
            return nil
        }
    }

    /**
     * Extracts text from a tool execution result.
     *
     * @param result The CallToolResult from executing the tool
     * @return Extracted text representation of the result
     */
    private func extractTextFromToolResult(_ result: CallToolResult) -> String {
        // Extract text from content blocks - handling only text content for now
        let textContent = result.content.compactMap { content -> String? in
            // Check for text content
            if let textContent = content.text {
                return textContent.text
            }
            
            // Add other content type handling if needed
            return nil
        }.joined(separator: "\n")
        
        if textContent.isEmpty {
            // If we couldn't extract text directly, serialize the whole result
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(result)
                return String(data: data, encoding: .utf8) ?? "Tool execution completed"
            } catch {
                logger.error("Failed to encode result: \(error)")
                return "Tool execution completed"
            }
        }
        
        return textContent
    }
    
    /**
     * Converts string input values to appropriate types based on content.
     * Handles numeric, boolean, null, and JSON conversions.
     *
     * @param input The input parameters as string dictionary
     * @return Converted parameters with appropriate types
     */
    private func convertInputToArguments(_ input: [String: String]) -> [String: Any] {
        var result: [String: Any] = [:]
        
        for (key, value) in input {
            // Convert numbers, booleans, null
            if let intValue = Int(value) {
                result[key] = intValue
            } else if let doubleValue = Double(value) {
                result[key] = doubleValue
            } else if value.lowercased() == "true" {
                result[key] = true
            } else if value.lowercased() == "false" {
                result[key] = false
            } else if value == "null" {
                result[key] = NSNull()
            } else {
                // Try JSON conversion
                if let jsonData = value.data(using: .utf8),
                   let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) {
                    result[key] = jsonObject
                } else {
                    result[key] = value
                }
            }
        }
        
        return result
    }
}
