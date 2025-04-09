//
//  MCPModels.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 3/24/25.
//

import Foundation
import MCPClient
import MCPInterface

/**
 * Configuration model for MCP (Model Context Protocol) servers.
 * Represents a server connection that can provide tools for the application.
 */
struct MCPServerConfig: Codable, Identifiable, Equatable {
    var id: String { name }
    var name: String
    var command: String
    var args: [String]
    var enabled: Bool = true
    var env: [String: String]? = nil
    var cwd: String? = nil
    
    static func == (lhs: MCPServerConfig, rhs: MCPServerConfig) -> Bool {
        return lhs.name == rhs.name
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
