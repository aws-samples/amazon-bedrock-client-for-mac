import Foundation

enum AutomationCadence: String, CaseIterable, Codable, Sendable {
    case once, interval, daily
    var title: String {
        switch self {
        case .once: "Once"
        case .interval: "Every interval"
        case .daily: "Daily"
        }
    }
}

struct AutomationDefinition: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var prompt: String
    var modelID: String
    var projectID: UUID?
    var workingDirectory: String?
    var skillIDs: [String] = []
    var cadence: AutomationCadence = .daily
    var scheduledAt = Date().addingTimeInterval(3600)
    var intervalMinutes = 60
    var maximumRuntime = 300
    var enabled = false
    var nextRunAt: Date?
    var lastRunAt: Date?
    var lastThreadID: String?
    var lastStatus: RunStatus?

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        switch cadence {
        case .once: return scheduledAt > date ? scheduledAt : nil
        case .interval: return date.addingTimeInterval(TimeInterval(max(1, intervalMinutes)) * 60)
        case .daily:
            let components = calendar.dateComponents([.hour, .minute], from: scheduledAt)
            return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
        }
    }
    var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give this automation a name." }
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a prompt to run." }
        if modelID.isEmpty { return "Choose a Bedrock model." }
        if !(1...43_200).contains(intervalMinutes) { return "Use an interval between 1 minute and 30 days." }
        if !(10...3_600).contains(maximumRuntime) { return "Use a runtime limit between 10 seconds and 1 hour." }
        return nil
    }
}
