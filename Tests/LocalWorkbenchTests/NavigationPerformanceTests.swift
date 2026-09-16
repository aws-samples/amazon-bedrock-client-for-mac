import XCTest
@testable import LocalWorkbench

final class NavigationPerformanceTests: XCTestCase {
    func testBackSkipsDeletedChatsWithoutMakingAReturnLoop() throws {
        let a = WorkbenchNavigationLocation(destination: .chats, threadID: "a")
        let b = WorkbenchNavigationLocation(destination: .chats, threadID: "b")
        let library = WorkbenchNavigationLocation(destination: .demos, threadID: "b")
        var history = WorkbenchNavigationHistory()
        history.record(from: a, to: b)
        history.record(from: b, to: library)
        let previous = try XCTUnwrap(history.back { $0.threadID != "b" })
        XCTAssertEqual(previous, a)
        history.record(from: library, to: previous)
        XCTAssertFalse(history.canGoBack { _ in true })
        XCTAssertNil(history.back { _ in true })
    }

    func testHistoryKeepsWelcomeAndPageLocationsAndBoundsMemory() {
        var history = WorkbenchNavigationHistory()
        var previous = WorkbenchNavigationLocation(destination: .chats, threadID: nil)
        for index in 0..<200 {
            let next = WorkbenchNavigationLocation(destination: .chats, threadID: "\(index)")
            history.record(from: previous, to: next)
            history.record(from: next, to: next)
            previous = next
        }
        XCTAssertEqual(history.entries.count, 80)
        XCTAssertEqual(history.back { _ in true }?.threadID, "198")
        XCTAssertEqual(WorkbenchNavigationLocation(destination: .activity, threadID: "a"),
                       WorkbenchNavigationLocation(destination: .activity, threadID: "b"))
    }

    func testLargeHistoryStartsWithRecentPageAndCanReachEveryEarlierMessage() {
        let messages = (0..<10_000).map { MessageData(text: "Message \($0)", user: $0.isMultiple(of: 2) ? "User" : "Assistant", sentTime: Date()) }
        var start = ConversationViewport.initialStart(in: messages)
        XCTAssertEqual(start, 10_000 - ConversationViewport.pageSize)
        var pages = 1
        while start > 0 {
            let next = ConversationViewport.earlierStart(before: start, in: messages)
            XCTAssertLessThan(next, start)
            start = next
            pages += 1
        }
        XCTAssertEqual(pages, 313)
        XCTAssertEqual(messages.first?.text, "Message 0")
        XCTAssertEqual(messages.last?.text, "Message 9999")
    }

    func testLargeIndividualReplyRemainsVisibleWhileOlderLayoutIsDeferred() {
        let messages = [
            MessageData(text: "Old answer", user: "Assistant", sentTime: Date()),
            MessageData(text: String(repeating: "Long reply.\n", count: 20_000), user: "Assistant", sentTime: Date()),
            MessageData(text: "Tool result", user: "ToolResult", sentTime: Date())
        ]
        XCTAssertEqual(ConversationViewport.initialStart(in: messages), 1)
        XCTAssertEqual(ConversationViewport.earlierStart(before: 1, in: messages), 0)
        XCTAssertEqual(ConversationViewport.initialStart(in: []), 0)
        XCTAssertEqual(ConversationViewport.earlierStart(before: -1, in: messages), 0)
    }

    func testSearchingOldMessageDoesNotMaterializeThousandsOfLaterMessages() {
        let messages = (0..<10_000).map {
            MessageData(text: "Message \($0)", user: "Assistant", sentTime: Date())
        }
        for index in [0, 1, 100, 5_000, 9_999] {
            let range = ConversationViewport.around(index, in: messages)
            XCTAssertTrue(range.contains(index))
            XCTAssertLessThanOrEqual(range.count, ConversationViewport.pageSize)
        }
        var range = ConversationViewport.initialRange(in: messages)
        for _ in 0..<20 {
            let previousFirst = range.lowerBound
            range = ConversationViewport.earlier(than: range, in: messages)
            XCTAssertTrue(range.contains(previousFirst), "Paging must retain the current anchor.")
            XCTAssertLessThanOrEqual(range.count, ConversationViewport.maximumVisibleMessages)
        }
        while range.upperBound < messages.count {
            let previousLast = range.upperBound - 1
            range = ConversationViewport.newer(than: range, in: messages)
            XCTAssertTrue(range.contains(previousLast))
            XCTAssertLessThanOrEqual(range.count, ConversationViewport.maximumVisibleMessages)
        }
        XCTAssertEqual(range.upperBound, messages.count)
    }

    func testViewportPagingCountsVisibleMessagesAndHandlesEmptyHistory() {
        let messages = (0..<300).map {
            MessageData(text: "\($0)", user: $0.isMultiple(of: 3) ? "Assistant" : "ToolResult", sentTime: Date())
        }
        let range = ConversationViewport.around(150, in: messages)
        XCTAssertTrue(range.contains(150))
        XCTAssertEqual(messages[range].filter(ConversationViewport.isVisible).count, ConversationViewport.pageSize)
        XCTAssertEqual(ConversationViewport.around(10, in: []), 0..<0)
        XCTAssertEqual(ConversationViewport.earlier(than: 0..<0, in: []), 0..<0)
        XCTAssertEqual(ConversationViewport.newer(than: 0..<0, in: []), 0..<0)
    }
}
