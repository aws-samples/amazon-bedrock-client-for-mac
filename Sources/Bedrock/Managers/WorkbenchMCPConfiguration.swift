import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum WorkbenchMCPConfiguration {
    static func decode(_ data: Data) throws -> [MCPServerConfig] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = root["mcpServers"] as? [String: [String: Any]] else {
            throw LocalWorkbenchError.invalid("Expected a JSON object containing mcpServers.")
        }
        return try values.sorted { $0.key < $1.key }.map { name, value in
            var object = value
            object["name"] = name
            object["transportType"] = value["type"] ?? value["transportType"] ?? (value["url"] == nil ? "stdio" : "http")
            let server = try JSONDecoder().decode(MCPServerConfig.self, from: JSONSerialization.data(withJSONObject: object))
            try validate(server)
            return server
        }
    }
    static func encode(_ servers: [MCPServerConfig]) throws -> Data {
        guard Set(servers.map(\.name)).count == servers.count else { throw LocalWorkbenchError.invalid("MCP server names must be unique.") }
        var result: [String: Any] = [:]
        for server in servers {
            var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(server)) as! [String: Any]
            value["name"] = nil
            value["type"] = value.removeValue(forKey: "transportType")
            result[server.name] = value
        }
        return try JSONSerialization.data(withJSONObject: ["mcpServers": result], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
    static func validate(_ server: MCPServerConfig) throws {
        guard !server.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, server.name.count <= 100,
              !server.name.contains("\0") else { throw LocalWorkbenchError.invalid("Use a nonempty server name of at most 100 characters.") }
        switch server.transportType {
        case .http: _ = try LocalPath.validatedWebURL(server.url ?? "", allowedDomains: "")
        case .stdio:
            guard !server.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !server.command.contains("\0"), !server.args.contains(where: { $0.contains("\0") }) else {
                throw LocalWorkbenchError.invalid("Enter a command and valid arguments for the local server.")
            }
            if let cwd = server.cwd, !cwd.isEmpty {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: (cwd as NSString).expandingTildeInPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                    throw LocalWorkbenchError.invalid("The MCP working directory does not exist.")
                }
            }
        }
        for key in server.env?.keys ?? Dictionary<String, String>().keys {
            guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
                throw LocalWorkbenchError.invalid("Invalid environment variable name: \(key)")
            }
        }
        for (key, value) in server.headers ?? [:] {
            guard !key.isEmpty, !key.contains(where: \.isNewline), !value.contains(where: \.isNewline) else {
                throw LocalWorkbenchError.invalid("HTTP headers cannot contain line breaks.")
            }
        }
    }
    static func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_000_000 else { throw LocalWorkbenchError.tooLarge(1_000_000) }
                var imported = try decode(Data(contentsOf: url))
                for server in imported where MCPManager.shared.servers.contains(where: { $0.name == server.name }) {
                    throw LocalWorkbenchError.invalid("A server named “\(server.name)” already exists. Rename it before importing.")
                }
                for index in imported.indices { imported[index].enabled = false }
                MCPManager.shared.servers.append(contentsOf: imported)
            } catch { WorkbenchStore.shared.errorMessage = "MCP import failed: \(error.localizedDescription)" }
        }
    }
    static func exportFile() {
        do {
            let data = try encode(MCPManager.shared.servers)
            WorkbenchActions.save(data: data, filename: "mcp_config.json", type: .json)
        } catch { WorkbenchStore.shared.errorMessage = error.localizedDescription }
    }
}
