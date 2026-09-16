import Foundation

enum NavigationDestination: String, CaseIterable, Identifiable, Codable, Sendable {
    case chats, demos, automations, activity
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chats: "Threads"
        case .demos: "Demo library"
        case .automations: "Automations"
        case .activity: "Activity"
        }
    }
    var symbol: String {
        switch self {
        case .chats: "bubble.left.and.bubble.right"
        case .demos: "square.grid.2x2"
        case .automations: "clock.arrow.circlepath"
        case .activity: "chart.bar.xaxis"
        }
    }
}
