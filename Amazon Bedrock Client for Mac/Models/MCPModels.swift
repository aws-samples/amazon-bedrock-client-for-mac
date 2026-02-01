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

// MARK: - Tool name namespacing (Bedrock requires unique names across MCP servers)

/// Delimiter between server namespace and tool name in Bedrock tool names.
private let toolNamespaceDelimiter = "__"

/// Sanitizes a server name to a Bedrock-safe namespace: lowercase, non-alphanumeric → underscore, collapsed.
/// Multiple different server names can map to the same value (e.g. "my-server" and "my_server"); use
/// assignUniqueNamespaces(serverNames:) to get a collision-free mapping.
func sanitizeServerNameToNamespace(_ serverName: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
    let folded = serverName.lowercased()
        .unicodeScalars
        .map { allowed.contains($0) ? String($0) : "_" }
        .joined()
    return folded
        .split(separator: "_", omittingEmptySubsequences: true)
        .joined(separator: "_")
}

/// Assigns a unique Bedrock-safe namespace to each server name. Collisions (e.g. "my-server" and "my_server")
/// are resolved by appending _2, _3, etc. so tool calls route to the correct server. Deterministic for a given set.
func assignUniqueNamespaces(serverNames: [String]) -> [String: String] {
    var used = Set<String>()
    var result: [String: String] = [:]
    for serverName in serverNames.sorted() {
        var base = sanitizeServerNameToNamespace(serverName)
        if base.isEmpty { base = "server" }
        var candidate = base
        var suffix = 1
        while used.contains(candidate) {
            suffix += 1
            candidate = "\(base)_\(suffix)"
        }
        used.insert(candidate)
        result[serverName] = candidate
    }
    return result
}

/// Returns the tool name sent to Bedrock using an already-assigned unique namespace.
func namespacedToolName(namespace: String, toolName: String) -> String {
    namespace.isEmpty ? toolName : "\(namespace)\(toolNamespaceDelimiter)\(toolName)"
}

/// Parses a Bedrock tool name back to (serverName, originalToolName) using the unique namespace → server map.
/// Returns nil if not namespaced or namespace unknown. Use assignUniqueNamespaces to build the reverse map.
func parseNamespacedToolName(_ name: String, namespaceToServer: [String: String]) -> (serverName: String, toolName: String)? {
    guard let idx = name.range(of: toolNamespaceDelimiter) else { return nil }
    let prefix = String(name[..<idx.lowerBound])
    let suffix = String(name[idx.upperBound...])
    guard !prefix.isEmpty, !suffix.isEmpty else { return nil }
    guard let serverName = namespaceToServer[prefix] else { return nil }
    return (serverName, suffix)
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
    /// Unique namespace for this server (from assignUniqueNamespaces); used for Bedrock tool names only.
    var uniqueNamespace: String

    /// Name sent to Bedrock (namespaced so duplicate tool names across servers are unique and collision-free).
    var bedrockToolName: String { namespacedToolName(namespace: uniqueNamespace, toolName: toolName) }

    init(serverName: String, tool: Tool, uniqueNamespace: String) {
        self.serverName = serverName
        self.toolName = tool.name
        self.description = (tool.description?.isEmpty ?? true) ? "No description available" : (tool.description ?? "No description available")
        self.tool = tool
        self.uniqueNamespace = uniqueNamespace
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(uniqueNamespace)
    }

    static func == (lhs: MCPToolInfo, rhs: MCPToolInfo) -> Bool {
        return lhs.id == rhs.id && lhs.uniqueNamespace == rhs.uniqueNamespace
    }
}
