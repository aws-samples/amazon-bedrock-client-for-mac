//
//  MCPModels.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 3/24/25.
//

import Foundation
import MCP

/**
 * Transport type for MCP server connections.
 */
enum MCPTransportType: String, Codable, CaseIterable {
    case stdio = "stdio"
    case http = "http"
    
    var displayName: String {
        switch self {
        case .stdio: return "Stdio (Local Process)"
        case .http: return "HTTP (Remote Server)"
        }
    }
}

/**
 * Configuration model for MCP (Model Context Protocol) servers.
 * Represents a server connection that can provide tools for the application.
 */
struct MCPServerConfig: Codable, Identifiable, Equatable {
    var id: String { name }
    var name: String
    var transportType: MCPTransportType = .stdio
    
    // Stdio transport fields
    var command: String
    var args: [String]
    var env: [String: String]? = nil
    var cwd: String? = nil
    
    // HTTP transport fields
    var url: String? = nil
    var headers: [String: String]? = nil  // Custom headers (e.g., Authorization)
    
    // OAuth credentials (optional, for servers that don't support Dynamic Client Registration)
    var clientId: String? = nil
    var clientSecret: String? = nil
    
    var enabled: Bool = true
    
    static func == (lhs: MCPServerConfig, rhs: MCPServerConfig) -> Bool {
        return lhs.name == rhs.name
    }
    
    // Coding keys for backward compatibility
    enum CodingKeys: String, CodingKey {
        case name, transportType, command, args, env, cwd, url, headers, clientId, clientSecret, enabled
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        transportType = try container.decodeIfPresent(MCPTransportType.self, forKey: .transportType) ?? .stdio
        command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        env = try container.decodeIfPresent([String: String].self, forKey: .env)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
        clientId = try container.decodeIfPresent(String.self, forKey: .clientId)
        clientSecret = try container.decodeIfPresent(String.self, forKey: .clientSecret)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
    
    init(name: String, transportType: MCPTransportType = .stdio, command: String = "", args: [String] = [], env: [String: String]? = nil, cwd: String? = nil, url: String? = nil, headers: [String: String]? = nil, clientId: String? = nil, clientSecret: String? = nil, enabled: Bool = true) {
        self.name = name
        self.transportType = transportType
        self.command = command
        self.args = args
        self.env = env
        self.cwd = cwd
        self.url = url
        self.headers = headers
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.enabled = enabled
    }
}

/**
 * Represents a tool available from an MCP server.
 * Used primarily for UI display and server tool management.
 */
struct MCPToolInfo: Identifiable, Hashable {
    var id: String { "\(serverName).\(toolName)" }
    var serverName: String
    var toolName: String
    var description: String
    var tool: Tool
    
    init(serverName: String, tool: Tool) {
        self.serverName = serverName
        self.toolName = tool.name
        self.description = (tool.description?.isEmpty ?? true) ? "No description available" : (tool.description ?? "No description available")
        self.tool = tool
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: MCPToolInfo, rhs: MCPToolInfo) -> Bool {
        return lhs.id == rhs.id
    }
}
