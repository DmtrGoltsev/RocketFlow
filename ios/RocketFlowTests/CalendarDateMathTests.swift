import Foundation
import XCTest
@testable import RocketFlow

final class CalendarDateMathTests: XCTestCase {
    func testBuildsStableMondayFirstSixWeekGridAndHalfOpenRange() throws {
        let month = CalendarMonth(year: 2026, month: 8)

        let days = CalendarDateMath.grid(for: month)
        let range = CalendarDateMath.range(for: month)

        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(days.first?.date, localDate("2026-07-27"))
        XCTAssertEqual(days.last?.date, localDate("2026-09-06"))
        XCTAssertEqual(range.from, localDate("2026-07-27"))
        XCTAssertEqual(range.toExclusive, localDate("2026-09-07"))
        XCTAssertEqual(days.filter(\.isInVisibleMonth).count, 31)
    }

    func testDerivesTodayInAccountTimezoneRatherThanRuntimeTimezone() throws {
        let instant = try WireDateCodec.decode("2026-08-10T00:30:00Z")

        XCTAssertEqual(
            CalendarDateMath.today(now: instant, timezoneIdentifier: "Europe/Moscow"),
            localDate("2026-08-10")
        )
        XCTAssertEqual(
            CalendarDateMath.today(now: instant, timezoneIdentifier: "America/Los_Angeles"),
            localDate("2026-08-09")
        )
    }

    func testMonthShiftingCrossesYearBoundaries() {
        XCTAssertEqual(
            CalendarMonth(year: 2026, month: 1).shifted(by: -1),
            CalendarMonth(year: 2025, month: 12)
        )
        XCTAssertEqual(
            CalendarMonth(year: 2026, month: 12).shifted(by: 1),
            CalendarMonth(year: 2027, month: 1)
        )
    }

    func testAgendaOrderingKeepsDualMarkersAndUsesAtTitleKindAndID() throws {
        let at = try WireDateCodec.decode("2026-08-10T09:00:00Z")
        let later = try WireDateCodec.decode("2026-08-10T10:00:00Z")
        let plannedID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let deadlineID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let markers = [
            marker(id: UUID(), title: "Earlier", kind: .planned, at: later),
            marker(id: deadlineID, title: "Alpha", kind: .deadline, at: at),
            marker(id: plannedID, title: "Alpha", kind: .planned, at: at),
            marker(id: UUID(), title: "Zulu", kind: .planned, at: at)
        ]

        let sorted = CalendarMarkerOrdering.sorted(markers, language: .en)

        XCTAssertEqual(sorted.count, 4)
        XCTAssertEqual(sorted.map(\.markerId), [plannedID, deadlineID, markers[3].markerId, markers[0].markerId])
        XCTAssertEqual(sorted.filter { $0.title == "Alpha" }.map(\.kind), [.planned, .deadline])
    }

    private func marker(
        id: UUID,
        title: String,
        kind: CalendarMarkerKind,
        at: Date
    ) -> CalendarMarkerDTO {
        CalendarMarkerDTO(
            markerId: id,
            occurrenceId: UUID(),
            taskId: UUID(),
            goalId: nil,
            title: title,
            status: .todo,
            effort: 1,
            kind: kind,
            at: at,
            localDate: localDate("2026-08-10"),
            recurring: false
        )
    }

    private func localDate(_ value: String) -> LocalDate {
        LocalDate(rawValue: value)!
    }
}
