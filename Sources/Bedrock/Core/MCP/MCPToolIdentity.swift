import CryptoKit
import Foundation

/// Stable, Bedrock-compatible names distinguish identical tools on different
/// servers. Never use Swift's randomized Hasher for persisted invocation names.
enum MCPToolIdentity {
    static func invocationName(server: String, tool: String) -> String {
        let digest = SHA256.hash(data: Data((server + "\0" + tool).utf8))
            .prefix(8).map { String(format: "%02x", $0) }.joined()
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        let readable = String(tool.map { allowed.contains($0) ? $0 : "_" }.prefix(43))
        return "mcp_\(readable.isEmpty ? "tool" : readable)_\(digest)"
    }
}
