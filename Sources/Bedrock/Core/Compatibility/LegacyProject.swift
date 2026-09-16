import Foundation

struct LegacyProject: Codable, Identifiable, Equatable, Sendable {
    // Decode old workspaces without losing their data. No longer used for tool access.
    var id = UUID()
    var name: String
    var path: String
    var addedAt = Date()
    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}
