import XCTest
@testable import BedrockCore

final class NavigationPerformanceTests: XCTestCase {
    func testBackSkipsDeletedChatsWithoutMakingAReturnLoop() throws {
        let a = NavigationLocation(destination: .chats, threadID: "a")
        let b = NavigationLocation(destination: .chats, threadID: "b")
        let library = NavigationLocation(destination: .demos, threadID: "b")
        var history = NavigationHistory()
        history.record(from: a, to: b)
        history.record(from: b, to: library)
        let previous = try XCTUnwrap(history.back { $0.threadID != "b" })
        XCTAssertEqual(previous, a)
        history.record(from: library, to: previous)
        XCTAssertFalse(history.canGoBack { _ in true })
        XCTAssertNil(history.back { _ in true })
    }

    func testHistoryKeepsWelcomeAndPageLocationsAndBoundsMemory() {
        var history = NavigationHistory()
        var previous = NavigationLocation(destination: .chats, threadID: nil)
        for index in 0..<200 {
            let next = NavigationLocation(destination: .chats, threadID: "\(index)")
            history.record(from: previous, to: next)
            history.record(from: next, to: next)
            previous = next
        }
        XCTAssertEqual(history.entries.count, 80)
        XCTAssertEqual(history.back { _ in true }?.threadID, "198")
        XCTAssertEqual(NavigationLocation(destination: .activity, threadID: "a"),
                       NavigationLocation(destination: .activity, threadID: "b"))
    }

    func testCompleteHistoryRemainsAvailableInOrder() {
        let messages = (0..<10_000).map { MessageData(text: "Message \($0)", user: $0.isMultiple(of: 2) ? "User" : "Assistant", sentTime: Date()) }
        let rows = ConversationTranscript.rows(in: messages)
        XCTAssertEqual(rows.count, messages.count)
        XCTAssertEqual(rows.map(\.id), messages.map(\.id))
        XCTAssertEqual(rows.map(\.sourceIndex), Array(messages.indices))
        XCTAssertEqual(rows.first?.message.text, "Message 0")
        XCTAssertEqual(rows.last?.message.text, "Message 9999")
    }

    func testLargeReplyDoesNotHideEarlierMessages() {
        let messages = [
            MessageData(text: "Old answer", user: "Assistant", sentTime: Date()),
            MessageData(text: String(repeating: "Long reply.\n", count: 20_000), user: "Assistant", sentTime: Date()),
            MessageData(text: "Tool result", user: "ToolResult", sentTime: Date())
        ]
        let rows = ConversationTranscript.rows(in: messages)
        XCTAssertEqual(rows.map(\.sourceIndex), [0, 1])
        XCTAssertEqual(rows.map(\.message.text), Array(messages.prefix(2)).map(\.text))
        XCTAssertEqual(ConversationTranscript.prewarmingTexts(in: messages), [messages[1].text])
        XCTAssertEqual(ConversationTranscript.rows(in: messages).map(\.id), rows.map(\.id))
    }

    func testPrewarmingBoundsParsingWithoutTruncatingTheTranscript() {
        let messages = (0..<10_000).map {
            MessageData(text: "Message \($0)\n" + String(repeating: "Text ", count: 2_000), user: "Assistant", sentTime: Date())
        }
        let warm = ConversationTranscript.prewarmingTexts(in: messages)
        XCTAssertLessThan(warm.count, messages.count)
        XCTAssertLessThanOrEqual(warm.reduce(0) { $0 + $1.utf8.count }, 96_000)
        XCTAssertEqual(warm.last, messages.last?.text)
        XCTAssertEqual(ConversationTranscript.rows(in: messages).count, 10_000)
    }

    func testTranscriptKeepsSearchOffsetsWhileHidingAPIToolResults() {
        let messages = (0..<300).map {
            MessageData(text: "\($0)", user: $0.isMultiple(of: 3) ? "Assistant" : "ToolResult", sentTime: Date())
        }
        let rows = ConversationTranscript.rows(in: messages)
        XCTAssertEqual(rows.count, 100)
        XCTAssertEqual(rows.map(\.sourceIndex), Array(stride(from: 0, to: 300, by: 3)))
        XCTAssertTrue(rows.allSatisfy { $0.id == messages[$0.sourceIndex].id })
        XCTAssertTrue(ConversationTranscript.rows(in: []).isEmpty)
        XCTAssertTrue(ConversationTranscript.prewarmingTexts(in: []).isEmpty)
    }

    func testModelSwitchAppearsAtTheFirstMessageUsingTheNewModel() throws {
        let old = "amazon.nova-2-lite-v1:0"
        let new = "anthropic.claude-fable-5-1"
        let messages = [
            modelMessage("Hello", user: "User", model: old),
            modelMessage("Hi", model: old),
            modelMessage("Follow-up", user: "User", model: new),
            modelMessage("Calling a tool", model: new),
            modelMessage("Tool payload", user: "ToolResult", model: new),
            modelMessage("Answer", model: new)
        ]
        let rows = ConversationTranscript.rows(in: messages)
        XCTAssertEqual(rows.compactMap(\.modelTransition),
                       [.init(fromModelID: old, toModelID: new)])
        XCTAssertEqual(rows.first(where: { $0.modelTransition != nil })?.id, messages[2].id)
        XCTAssertNil(ConversationTranscript.pendingTransition(after: rows, to: new))

        let reopened = try JSONDecoder().decode([MessageData].self, from: JSONEncoder().encode(messages))
        XCTAssertEqual(ConversationTranscript.rows(in: reopened).compactMap(\.modelTransition),
                       rows.compactMap(\.modelTransition))
        XCTAssertEqual(reopened.map(\.text), messages.map(\.text))
        XCTAssertFalse(reopened.contains { $0.text.contains("Switched to") })
    }

    func testIdleModelSwitchMovesIntoHistoryOnceAndSwitchingBackCancelsIt() {
        let old = "amazon.nova-2-lite-v1:0"
        let new = "openai.gpt-6-astra"
        let messages = [modelMessage("Existing answer", model: old)]
        let rows = ConversationTranscript.rows(in: messages)
        XCTAssertEqual(ConversationTranscript.pendingTransition(after: rows, to: new),
                       .init(fromModelID: old, toModelID: new))
        XCTAssertNil(ConversationTranscript.pendingTransition(after: rows, to: old))
        let sent = ConversationTranscript.rows(in: messages + [modelMessage("Next", user: "User", model: new)])
        XCTAssertEqual(sent.compactMap(\.modelTransition).count, 1)
        XCTAssertNil(ConversationTranscript.pendingTransition(after: sent, to: new))
        XCTAssertNil(ConversationTranscript.pendingTransition(after: [], to: new))
    }

    func testRegionalRoutingAndLegacyUnknownIDsDoNotInventModelSwitches() {
        let model = "amazon.nova-2-lite-v1:0"
        let messages = [
            modelMessage("Legacy message", model: nil),
            modelMessage("Known answer", model: "us.\(model)"),
            modelMessage("Same model through another profile", model: "global.\(model)"),
            modelMessage("Unknown older metadata", model: nil),
            modelMessage("Same foundation model", model: model)
        ]
        let rows = ConversationTranscript.rows(in: messages)
        XCTAssertTrue(rows.allSatisfy { $0.modelTransition == nil })
        XCTAssertNil(ConversationTranscript.pendingTransition(after: rows, to: "eu.\(model)"))
        XCTAssertNil(ConversationTranscript.pendingTransition(
            after: ConversationTranscript.rows(in: [messages[0]]), to: model))
    }

    private func modelMessage(_ text: String, user: String = "Assistant", model: String?) -> MessageData {
        var message = MessageData(text: text, user: user, sentTime: Date())
        message.modelID = model
        return message
    }
}
