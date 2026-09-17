import Foundation

struct ConversationDateGroup<Item>: Identifiable {
    let day: Date
    let title: String
    let items: [Item]
    var id: Date { day }

    static func group(_ items: [Item], date: KeyPath<Item, Date>, now: Date = Date(),
                      calendar: Calendar = .current, locale: Locale = .current) -> [Self] {
        guard !items.isEmpty else { return [] }
        // Calendar days, rather than 24-hour intervals, retain the original
        // Today / Yesterday behavior across time zones and daylight saving.
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        let ordered = items.enumerated().sorted {
            let a = $0.element[keyPath: date], b = $1.element[keyPath: date]
            return a == b ? $0.offset < $1.offset : a > b
        }.map(\.element)
        let days = Dictionary(grouping: ordered) { calendar.startOfDay(for: $0[keyPath: date]) }
        return days.keys.sorted(by: >).map { day in
            formatter.setLocalizedDateFormatFromTemplate(
                calendar.component(.year, from: day) == calendar.component(.year, from: today) ? "MMM d" : "MMM d yyyy")
            let title = day == today ? "Today" : day == yesterday ? "Yesterday" : formatter.string(from: day)
            return Self(day: day, title: title, items: days[day] ?? [])
        }
    }
}
