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
    // Optional additions keep schedules written by earlier versions readable.
    var timeZoneIdentifier: String?
    var weekdays: Set<Int>?
    var activeStartMinute: Int?
    var activeEndMinute: Int?

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        var calendar = calendar
        if let timeZoneIdentifier {
            guard let zone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
            calendar.timeZone = zone
        }
        switch cadence {
        case .once: return scheduledAt > date ? scheduledAt : nil
        case .interval:
            let earliest = date.addingTimeInterval(TimeInterval(max(1, intervalMinutes)) * 60)
            // Include the previous day: a Monday 22:00–06:00 window also
            // permits Tuesday morning, and belongs to Monday's weekday.
            let day = calendar.startOfDay(for: earliest)
            for offset in -1...8 {
                guard let anchor = calendar.date(byAdding: .day, value: offset, to: day),
                      let window = activeWindow(on: anchor, calendar: calendar) else { continue }
                let candidate = max(earliest, window.start)
                if candidate < window.end { return candidate }
            }
            return nil
        case .daily:
            let components = calendar.dateComponents([.hour, .minute], from: scheduledAt)
            var cursor = date
            for _ in 0..<8 {
                guard let next = calendar.nextDate(after: cursor, matching: components,
                    matchingPolicy: .nextTime, repeatedTimePolicy: .first) else { return nil }
                if weekdays?.contains(calendar.component(.weekday, from: next)) ?? true { return next }
                cursor = next
            }
            return nil
        }
    }

    private func activeWindow(on day: Date, calendar: Calendar) -> DateInterval? {
        guard weekdays?.contains(calendar.component(.weekday, from: day)) ?? true,
              let following = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        guard let start = activeStartMinute, let end = activeEndMinute else {
            return DateInterval(start: day, end: following)
        }
        guard (0..<1440).contains(start), (0..<1440).contains(end), start != end else { return nil }
        func wallTime(_ minute: Int, on day: Date) -> Date? {
            calendar.nextDate(after: day.addingTimeInterval(-1),
                matching: DateComponents(hour: minute / 60, minute: minute % 60),
                matchingPolicy: .nextTime, repeatedTimePolicy: .first)
        }
        guard let lower = wallTime(start, on: day),
              let upper = wallTime(end, on: end > start ? day : following),
              upper > lower else { return nil }
        return DateInterval(start: lower, end: upper)
    }

    var timeZone: TimeZone {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
    }

    func formattedNextRun(after date: Date = Date()) -> String? {
        guard let next = nextDate(after: date) else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(formatter.string(from: next)) · \(timeZone.abbreviation(for: next) ?? timeZone.identifier)"
    }

    var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give this automation a name." }
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a prompt to run." }
        if modelID.isEmpty { return "Choose a Bedrock model." }
        if !(1...43_200).contains(intervalMinutes) { return "Use an interval between 1 minute and 30 days." }
        if !(10...3_600).contains(maximumRuntime) { return "Use a runtime limit between 10 seconds and 1 hour." }
        if let timeZoneIdentifier, TimeZone(identifier: timeZoneIdentifier) == nil { return "Choose a valid time zone." }
        if let weekdays, weekdays.isEmpty || !weekdays.isSubset(of: Set(1...7)) { return "Choose at least one day of the week." }
        if cadence == .interval, activeStartMinute != nil || activeEndMinute != nil {
            guard let start = activeStartMinute, let end = activeEndMinute,
                  (0..<1440).contains(start), (0..<1440).contains(end), start != end else {
                return "Choose different start and end times for active hours."
            }
        }
        return nil
    }
}
