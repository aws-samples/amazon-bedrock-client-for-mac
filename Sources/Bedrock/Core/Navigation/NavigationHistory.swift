import Foundation

struct NavigationLocation: Equatable, Sendable {
    var destination: NavigationDestination
    var threadID: String?

    init(destination: NavigationDestination, threadID: String?) {
        self.destination = destination
        self.threadID = destination == .chats ? threadID : nil
    }
}

/// Window-local history. Going back never changes a conversation or its draft.
struct NavigationHistory {
    private(set) var entries: [NavigationLocation] = []
    private var returningTo: NavigationLocation?

    mutating func record(from previous: NavigationLocation, to next: NavigationLocation) {
        guard previous != next else { return }
        if returningTo == next {
            returningTo = nil
            return
        }
        returningTo = nil
        if entries.last != previous { entries.append(previous) }
        if entries.count > 80 { entries.removeFirst(entries.count - 80) }
    }

    func canGoBack(where available: (NavigationLocation) -> Bool) -> Bool {
        entries.contains(where: available)
    }

    mutating func back(where available: (NavigationLocation) -> Bool) -> NavigationLocation? {
        while let location = entries.popLast() {
            guard available(location) else { continue }
            returningTo = location
            return location
        }
        return nil
    }
}

/// Bound the initial layout, not the conversation sent to the model or searched.
/// Exact stack geometry is retained, avoiding lazy-stack scroll-height jumps.
enum ConversationViewport {
    static let pageSize = 32
    static let maximumVisibleMessages = 96
    static let initialTextBudget = 96_000

    static func initialStart(in messages: [MessageData]) -> Int {
        var count = 0
        var bytes = 0
        var start = messages.count
        for index in messages.indices.reversed() {
            let message = messages[index]
            guard isVisible(message) else { start = index; continue }
            let size = message.text.utf8.count + (message.thinking?.utf8.count ?? 0)
            if count > 0 && (count >= pageSize || bytes + size > initialTextBudget) { break }
            count += 1
            bytes += size
            start = index
        }
        return start
    }

    static func earlierStart(before start: Int, in messages: [MessageData]) -> Int {
        Self.start(before: start, visibleCount: pageSize, in: messages)
    }

    static func initialRange(in messages: [MessageData]) -> Range<Int> {
        initialStart(in: messages)..<messages.count
    }

    static func around(_ index: Int, in messages: [MessageData]) -> Range<Int> {
        guard !messages.isEmpty else { return 0..<0 }
        let selected = min(max(0, index), messages.count - 1)
        let lower = start(before: selected, visibleCount: pageSize / 2, in: messages)
        return lower..<end(after: selected, visibleCount: pageSize / 2, in: messages)
    }

    static func earlier(than range: Range<Int>, in messages: [MessageData]) -> Range<Int> {
        let lower = earlierStart(before: range.lowerBound, in: messages)
        let upper = min(range.upperBound, end(after: lower, visibleCount: maximumVisibleMessages, in: messages))
        return lower..<max(lower, upper)
    }

    static func newer(than range: Range<Int>, in messages: [MessageData]) -> Range<Int> {
        let upper = end(after: range.upperBound, visibleCount: pageSize, in: messages)
        let lower = max(range.lowerBound, start(before: upper, visibleCount: maximumVisibleMessages, in: messages))
        return min(lower, upper)..<upper
    }

    private static func start(before start: Int, visibleCount: Int, in messages: [MessageData]) -> Int {
        let end = min(max(0, start), messages.count)
        var remaining = visibleCount
        var result = end
        for index in (0..<end).reversed() {
            result = index
            if isVisible(messages[index]) { remaining -= 1 }
            if remaining == 0 { break }
        }
        return result
    }

    private static func end(after start: Int, visibleCount: Int, in messages: [MessageData]) -> Int {
        let start = min(max(0, start), messages.count)
        var remaining = visibleCount
        for index in start..<messages.count {
            if isVisible(messages[index]) { remaining -= 1 }
            if remaining == 0 { return index + 1 }
        }
        return messages.count
    }

    static func isVisible(_ message: MessageData) -> Bool {
        message.user != "ToolResult" && !(message.user == "User" && message.toolUses != nil)
    }
}
