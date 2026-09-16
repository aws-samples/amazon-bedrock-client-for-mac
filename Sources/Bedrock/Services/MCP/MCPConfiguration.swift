import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum MCPConfiguration {
    static func decode(_ data: Data) throws -> [MCPServerConfig] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = root["mcpServers"] as? [String: [String: Any]] else {
            throw LocalOperationError.invalid("Expected a JSON object containing mcpServers.")
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
        guard Set(servers.map(\.name)).count == servers.count else { throw LocalOperationError.invalid("MCP server names must be unique.") }
        var result: [String: Any] = [:]
        for server in servers {
            var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(server)) as! [String: Any]
            value["name"] = nil
            value["type"] = value.removeValue(forKey: "transportType")
            result[server.name] = value
        }
        return try JSONSerialization.data(withJSONObject: ["mcpServers": result], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// The private config retains credentials. A shareable export must never
    /// reuse that serializer without removing configured secret values first.
    static func exportData(_ servers: [MCPServerConfig]) throws -> Data {
        let sanitized = servers.map { original in
            var server = original
            server.enabled = false
            server.env = original.env?.mapValues { _ in "" }
            server.headers = original.headers?.mapValues { _ in "" }
            server.clientSecret = nil
            server.command = redact(original.command, using: original)
            server.args = sanitizedArguments(original.args, using: original)
            server.url = original.url.map { sanitizedURL(redact($0, using: original)) }
            return server
        }
        var root = try JSONSerialization.jsonObject(with: encode(sanitized)) as! [String: Any]
        root["bedrockExport"] = [
            "version": 1,
            "secretsOmitted": true,
            "note": "Environment and header values, OAuth secrets and credential arguments were omitted. Review each disabled server before connecting."
        ] as [String: Any]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    static func redactedDiagnostic(_ text: String, server: MCPServerConfig) -> String {
        redact(text, using: server)
    }

    static func previewAddress(_ server: MCPServerConfig) -> String {
        let value = redact(server.transportType == .stdio ? server.command : server.url ?? "", using: server)
        return server.transportType == .stdio ? value : sanitizedURL(value)
    }

    private static func redact(_ text: String, using server: MCPServerConfig) -> String {
        // Do not turn harmless PORT/PATH/Accept values into substitutions in
        // executable paths or ordinary diagnostics. Exports omit all dictionary
        // values; embedded copies are scrubbed using credential-bearing keys.
        var values = (server.env ?? [:]).filter { sensitiveKey($0.key) }.map(\.value)
            + (server.headers ?? [:]).filter { sensitiveKey($0.key) }.map(\.value)
        if let secret = server.clientSecret { values.append(secret) }
        for value in server.headers?.values ?? Dictionary<String, String>().values {
            if value.lowercased().hasPrefix("bearer ") { values.append(String(value.dropFirst(7))) }
        }
        var hideNext = false
        for argument in server.args {
            if hideNext { values.append(argument); hideNext = false; continue }
            if let equals = argument.firstIndex(of: "="), sensitiveKey(String(argument[..<equals])) {
                values.append(String(argument[argument.index(after: equals)...]))
            } else if argument.hasPrefix("-"), sensitiveKey(argument) { hideNext = true }
        }
        if let url = server.url.flatMap({ URLComponents(string: $0) }) {
            if let password = url.password { values.append(password) }
            values += (url.queryItems ?? []).filter { sensitiveKey($0.name) }.compactMap(\.value)
        }
        return Set(values.filter { !$0.isEmpty }).sorted { $0.count > $1.count }.reduce(text) {
            $0.replacingOccurrences(of: $1, with: "<redacted>")
        }
    }

    private static func sensitiveKey(_ key: String) -> Bool {
        let normalized = key.lowercased().filter(\.isLetter)
        return ["authorization", "apikey", "token", "password", "passwd", "secret", "credential", "cookie", "signature"]
            .contains { normalized.contains($0) }
    }

    private static func sanitizedURL(_ text: String) -> String {
        guard var url = URLComponents(string: text) else { return text }
        url.user = nil
        url.password = nil
        url.queryItems = url.queryItems?.map {
            URLQueryItem(name: $0.name, value: sensitiveKey($0.name) ? "" : $0.value)
        }
        return url.string ?? text
    }

    private static func sanitizedArguments(_ arguments: [String], using server: MCPServerConfig) -> [String] {
        var hideNext = false
        return arguments.map { argument in
            if hideNext { hideNext = false; return "<redacted>" }
            if let equals = argument.firstIndex(of: "="), sensitiveKey(String(argument[..<equals])) {
                return String(argument[...equals]) + "<redacted>"
            }
            if argument.hasPrefix("-"), sensitiveKey(argument) { hideNext = true; return argument }
            let value = redact(argument, using: server)
            return value.hasPrefix("http://") || value.hasPrefix("https://") ? sanitizedURL(value) : value
        }
    }

    /// Selection is explicit for replacements. Importing never starts a process
    /// or changes the configuration of an unselected server.
    static func merging(_ imported: [MCPServerConfig], selected: Set<String>, into current: [MCPServerConfig]) throws -> [MCPServerConfig] {
        guard Set(imported.map(\.name)).count == imported.count else {
            throw LocalOperationError.invalid("MCP server names must be unique.")
        }
        var result = current
        for var server in imported where selected.contains(server.name) {
            try validate(server)
            server.enabled = false
            if let index = result.firstIndex(where: { $0.name == server.name }) { result[index] = server }
            else { result.append(server) }
        }
        return result
    }
    static func validate(_ server: MCPServerConfig) throws {
        guard !server.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, server.name.count <= 100,
              !server.name.contains("\0") else { throw LocalOperationError.invalid("Use a nonempty server name of at most 100 characters.") }
        switch server.transportType {
        case .http: _ = try LocalPath.validatedWebURL(server.url ?? "", allowedDomains: "")
        case .stdio:
            guard !server.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !server.command.contains("\0"), !server.args.contains(where: { $0.contains("\0") }) else {
                throw LocalOperationError.invalid("Enter a command and valid arguments for the local server.")
            }
            if let cwd = server.cwd, !cwd.isEmpty {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: (cwd as NSString).expandingTildeInPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                    throw LocalOperationError.invalid("The MCP working directory does not exist.")
                }
            }
        }
        for (key, value) in server.env ?? [:] {
            guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil,
                  !value.contains("\0") else {
                throw LocalOperationError.invalid("Invalid environment variable name: \(key)")
            }
        }
        for (key, value) in server.headers ?? [:] {
            guard key.range(of: #"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$"#, options: .regularExpression) != nil,
                  !value.contains(where: \.isNewline),
                  !value.unicodeScalars.contains(where: { ($0.value < 32 && $0.value != 9) || $0.value == 127 }) else {
                throw LocalOperationError.invalid("Use valid HTTP header names and values without control characters.")
            }
        }
    }
    static func importFile(onPreview: @escaping ([MCPServerConfig]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_000_000 else { throw LocalOperationError.tooLarge(1_000_000) }
                let imported = try decode(Data(contentsOf: url))
                guard !imported.isEmpty else { throw LocalOperationError.invalid("This file contains no MCP servers.") }
                onPreview(imported)
            } catch { AppStore.shared.errorMessage = "MCP import failed: \(error.localizedDescription)" }
        }
    }
    static func exportFile() {
        do {
            let data = try exportData(MCPClientManager.shared.servers)
            AppActions.save(data: data, filename: "mcp_config.json", type: .json)
        } catch { AppStore.shared.errorMessage = error.localizedDescription }
    }
}
