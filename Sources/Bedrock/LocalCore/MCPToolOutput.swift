import Foundation

enum MCPToolOutput {
    /// Use the same extraction for successful and failed tools. Servers often
    /// return several text blocks or structured output instead of one string.
    static func text(_ result: [String: Any]) -> String {
        var parts: [String] = []
        for item in result["content"] as? [[String: Any]] ?? [] {
            switch item["type"] as? String {
            case "text": if let text = item["text"] as? String { parts.append(text) }
            case "image": parts.append("Image result (\(item["mimeType"] as? String ?? "image")).")
            case "audio": parts.append("Audio result (\(item["mimeType"] as? String ?? "audio")).")
            case "resource":
                let resource = item["resource"] as? [String: Any] ?? item
                if let uri = resource["uri"] as? String { parts.append("Resource: \(uri)") }
                if let text = resource["text"] as? String { parts.append(text) }
            case "resource_link":
                if let uri = item["uri"] as? String {
                    parts.append("\(item["title"] as? String ?? item["name"] as? String ?? "Resource"): \(uri)")
                }
            default:
                if let text = item["text"] as? String { parts.append(text) }
                else if let json = item["json"] as? [String: Any], let text = json["text"] as? String { parts.append(text) }
            }
        }
        if let structured = result["structuredContent"],
           let data = try? JSONSerialization.data(withJSONObject: structured, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
           let text = String(data: data, encoding: .utf8), !parts.contains(text) {
            parts.append(text)
        }
        if parts.isEmpty, let error = result["error"] as? String { parts.append(error) }
        if parts.isEmpty { return result["status"] as? String == "success" ? "Tool completed without output." : "Tool execution failed." }
        return parts.joined(separator: "\n")
    }
}
