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
