import Foundation
import XCTest
@testable import BedrockCore

final class AutomationScheduleTests: XCTestCase {
    private let parser = ISO8601DateFormatter()
    private func date(_ value: String) -> Date { parser.date(from: value)! }
    private func schedule() -> AutomationDefinition {
        var value = AutomationDefinition(name: "Routine", prompt: "Summarize", modelID: "amazon.nova-2-lite-v1:0")
        value.timeZoneIdentifier = "America/Los_Angeles"
        return value
    }

    func testWeekdayScheduleSkipsWeekendAndUsesItsConfiguredTimeZone() {
        var value = schedule()
        value.scheduledAt = date("2026-09-18T16:30:00Z") // 09:30 PDT, Friday
        value.weekdays = Set(2...6)
        XCTAssertEqual(value.nextDate(after: date("2026-09-18T17:00:00Z")),
                       date("2026-09-21T16:30:00Z"))
        XCTAssertEqual(value.nextDate(after: date("2026-09-21T16:29:00Z")),
                       date("2026-09-21T16:30:00Z"))
    }

    func testActiveHoursDelayIntervalsWithoutReplayingMissedWork() {
        var value = schedule()
        value.cadence = .interval
        value.intervalMinutes = 60
        value.weekdays = Set(2...6)
        value.activeStartMinute = 9 * 60
        value.activeEndMinute = 17 * 60
        XCTAssertEqual(value.nextDate(after: date("2026-09-18T23:30:00Z")),
                       date("2026-09-21T16:00:00Z"))
        XCTAssertEqual(value.nextDate(after: date("2026-09-21T16:15:00Z")),
                       date("2026-09-21T17:15:00Z"))
    }

    func testOvernightWindowBelongsToTheStartingWeekday() {
        var value = schedule()
        value.cadence = .interval
        value.intervalMinutes = 15
        value.weekdays = [2] // Monday
        value.activeStartMinute = 22 * 60
        value.activeEndMinute = 6 * 60
        XCTAssertEqual(value.nextDate(after: date("2026-09-22T10:00:00Z")),
                       date("2026-09-22T10:15:00Z")) // Tuesday 03:15 is in Monday's window
        XCTAssertEqual(value.nextDate(after: date("2026-09-22T12:50:00Z")),
                       date("2026-09-29T05:00:00Z")) // next Monday 22:00
    }

    func testDailyClockFollowsDSTAndDoesNotRunTwiceDuringRepeatedHour() {
        var value = schedule()
        value.scheduledAt = date("2026-03-07T10:30:00Z") // 02:30 PST
        XCTAssertEqual(value.nextDate(after: date("2026-03-08T09:00:00Z")),
                       date("2026-03-08T10:00:00Z")) // nonexistent 02:30 moves to 03:00
        value.scheduledAt = date("2026-10-31T08:30:00Z") // 01:30 PDT
        XCTAssertEqual(value.nextDate(after: date("2026-11-01T08:30:00Z")),
                       date("2026-11-02T09:30:00Z"))
    }

    func testLegacySchedulesKeepEveryDayWithoutActiveHours() throws {
        var value = schedule()
        value.cadence = .interval
        let encoded = try JSONEncoder().encode(value)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["timeZoneIdentifier", "weekdays", "activeStartMinute", "activeEndMinute"] { object.removeValue(forKey: key) }
        let restored = try JSONDecoder().decode(AutomationDefinition.self, from: JSONSerialization.data(withJSONObject: object))
        let now = date("2026-09-20T12:00:00Z")
        XCTAssertEqual(restored.nextDate(after: now), now.addingTimeInterval(3600))
        XCTAssertNil(restored.validationError)
    }

    func testInvalidScheduleOptionsFailBeforeSaving() {
        var value = schedule()
        value.weekdays = []
        XCTAssertNotNil(value.validationError)
        XCTAssertNil(value.nextDate(after: Date()))
        value.weekdays = nil
        value.timeZoneIdentifier = "Invalid/Zone"
        XCTAssertNotNil(value.validationError)
        XCTAssertNil(value.nextDate(after: Date()))
        value.timeZoneIdentifier = nil
        value.cadence = .interval
        value.activeStartMinute = 100
        XCTAssertNotNil(value.validationError)
        value.activeEndMinute = 100
        XCTAssertNotNil(value.validationError)
        value.activeEndMinute = 300
        XCTAssertNil(value.validationError)
    }
}
