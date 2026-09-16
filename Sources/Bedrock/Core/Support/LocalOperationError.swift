import Foundation

enum LocalOperationError: LocalizedError, Equatable {
    case invalid(String)
    case outsideProject
    case tooLarge(Int)
    case unavailable(String)
    var errorDescription: String? {
        switch self {
        case .invalid(let message), .unavailable(let message): message
        case .outsideProject: "This path is outside the folders allowed in Settings → Tools & MCP."
        case .tooLarge(let limit): "This file exceeds the \(limit.formatted()) byte limit."
        }
    }
}
