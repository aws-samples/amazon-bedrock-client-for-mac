import XCTest
@testable import BedrockCore

final class ConversationDateGroupTests: XCTestCase {
    private struct Item {
        let id: String
        let date: Date
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func calendar(_ timeZone: String = "America/Los_Angeles") -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: timeZone)!
        return result
    }
    private func groups(_ items: [Item], now: String, zone: String = "America/Los_Angeles") -> [ConversationDateGroup<Item>] {
        ConversationDateGroup.group(items, date: \.date, now: date(now), calendar: calendar(zone),
                                   locale: Locale(identifier: "en_US"))
    }

    func testGroupsTodayYesterdayAndOlderDatesInOrderWithStableTies() {
        let items = [
            Item(id: "old", date: date("2026-09-10T12:00:00-07:00")),
            Item(id: "yesterday", date: date("2026-09-16T23:59:00-07:00")),
            Item(id: "morning", date: date("2026-09-17T08:00:00-07:00")),
            Item(id: "new", date: date("2026-09-17T09:00:00-07:00")),
            Item(id: "tied", date: date("2026-09-17T09:00:00-07:00"))
        ]
        let result = groups(items, now: "2026-09-17T10:00:00-07:00")
        XCTAssertEqual(result.map(\.title), ["Today", "Yesterday", "Sep 10"])
        XCTAssertEqual(result.map { $0.items.map(\.id) }, [["new", "tied", "morning"], ["yesterday"], ["old"]])
        XCTAssertTrue(groups([], now: "2026-09-17T10:00:00-07:00").isEmpty)
    }

    func testOlderYearsRemainUnambiguousAndDatesFollowTheLocale() {
        let items = [Item(id: "older", date: date("2025-09-15T12:00:00-07:00"))]
        XCTAssertEqual(groups(items, now: "2026-09-17T10:00:00-07:00").map(\.title), ["Sep 15, 2025"])
        let localized = ConversationDateGroup.group(items, date: \.date,
            now: date("2026-09-17T10:00:00-07:00"), calendar: calendar(), locale: Locale(identifier: "ko_KR"))
        XCTAssertTrue(localized[0].title.contains("2025"))
        XCTAssertTrue(localized[0].title.contains("9월"))
    }

    func testYesterdayIncludesTheWholeCalendarDayAcrossBothDaylightSavingChanges() {
        for (now, earlier) in [
            ("2026-03-09T00:15:00-07:00", "2026-03-08T00:05:00-08:00"),
            ("2026-11-02T00:15:00-08:00", "2026-11-01T00:05:00-07:00")
        ] {
            let result = groups([Item(id: "yesterday", date: date(earlier))], now: now)
            XCTAssertEqual(result.map(\.title), ["Yesterday"])
        }
    }

    func testTimeZoneAndMidnightChangesUpdateLabelsWithoutChangingTheThreads() {
        let items = [Item(id: "chat", date: date("2026-09-16T23:30:00Z"))]
        XCTAssertEqual(groups(items, now: "2026-09-17T00:30:00Z", zone: "UTC").map(\.title), ["Yesterday"])
        XCTAssertEqual(groups(items, now: "2026-09-17T00:30:00Z").map(\.title), ["Today"])
        let before = groups(items, now: "2026-09-16T23:50:00Z", zone: "UTC")
        let after = groups(items, now: "2026-09-17T00:10:00Z", zone: "UTC")
        XCTAssertEqual(before.map(\.id), after.map(\.id), "Relative labels must not replace the group identity at midnight.")
        XCTAssertEqual(before.flatMap(\.items).map(\.id), after.flatMap(\.items).map(\.id))
    }

    func testEarlierWorkspacesDefaultToExpandedAndCollapseChoicesSurviveRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(AppPreferences())) as? [String: Any])
        object.removeValue(forKey: "collapsedSidebarSections")
        var preferences = try decoder.decode(AppPreferences.self, from: JSONSerialization.data(withJSONObject: object))
        for section in ["library", "pinned", "chats"] {
            XCTAssertTrue(preferences.isSidebarSectionExpanded(section))
        }
        preferences.setSidebarSection("library", expanded: false)
        preferences.setSidebarSection("chats", expanded: false)
        preferences = try decoder.decode(AppPreferences.self, from: encoder.encode(preferences))
        XCTAssertFalse(preferences.isSidebarSectionExpanded("library"))
        XCTAssertFalse(preferences.isSidebarSectionExpanded("chats"))
        XCTAssertTrue(preferences.isSidebarSectionExpanded("pinned"))
        preferences.setSidebarSection("library", expanded: true)
        XCTAssertTrue(preferences.isSidebarSectionExpanded("library"))
        XCTAssertFalse(preferences.isSidebarSectionExpanded("chats"))
        preferences.setSidebarSection("chats", expanded: true)
        XCTAssertNil(preferences.collapsedSidebarSections)
    }
}
