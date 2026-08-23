import Foundation
import XCTest
@testable import RocketFlow

private enum CalendarViewModelStubFailure: Error, Sendable {
    case offline
}

private actor ImmediateCalendarLoader: CalendarLoading {
    enum Behavior: Sendable {
        case markers([CalendarMarkerDTO])
        case emptyOffline
        case unauthorized(APIError)
    }

    private let behavior: Behavior
    private let localTaskIDsByMarkerID: [UUID: UUID]
    private var capturedRanges: [CalendarGridRange] = []

    init(
        _ behavior: Behavior,
        localTaskIDsByMarkerID: [UUID: UUID] = [:]
    ) {
        self.behavior = behavior
        self.localTaskIDsByMarkerID = localTaskIDsByMarkerID
    }

    func load(
        accountID: UUID,
        accountTimezone: String,
        from: LocalDate,
        toExclusive: LocalDate
    ) async throws -> CalendarLoadResult {
        capturedRanges.append(CalendarGridRange(from: from, toExclusive: toExclusive))
        switch behavior {
        case let .markers(markers):
            return CalendarLoadResult(
                response: CalendarMarkersResponseDTO(
                    timezone: accountTimezone,
                    from: from,
                    toExclusive: toExclusive,
                    markers: markers
                ),
                source: .network,
                failure: nil,
                localTaskIDsByMarkerID: localTaskIDsByMarkerID
            )
        case .emptyOffline:
            return CalendarLoadResult(
                response: CalendarMarkersResponseDTO(
                    timezone: accountTimezone,
                    from: from,
                    toExclusive: toExclusive,
                    markers: []
                ),
                source: .emptyOffline,
                failure: CalendarLoadFailure(CalendarViewModelStubFailure.offline)
            )
        case let .unauthorized(error):
            throw error
        }
    }

    func ranges() -> [CalendarGridRange] { capturedRanges }
}

private actor ControlledCalendarLoader: CalendarLoading {
    private struct Request: Sendable {
        let accountTimezone: String
        let range: CalendarGridRange
    }

    private var requests: [Request] = []
    private var continuations: [Int: CheckedContinuation<CalendarLoadResult, Error>] = [:]

    func load(
        accountID: UUID,
        accountTimezone: String,
        from: LocalDate,
        toExclusive: LocalDate
    ) async throws -> CalendarLoadResult {
        let index = requests.count
        requests.append(
            Request(
                accountTimezone: accountTimezone,
                range: CalendarGridRange(from: from, toExclusive: toExclusive)
            )
        )
        return try await withCheckedThrowingContinuation { continuation in
            continuations[index] = continuation
        }
    }

    func requestCount() -> Int { requests.count }

    func complete(_ index: Int, title: String) {
        let request = requests[index]
        let marker = CalendarMarkerDTO(
            markerId: UUID(),
            occurrenceId: UUID(),
            taskId: UUID(),
            goalId: nil,
            title: title,
            status: .todo,
            effort: 1,
            kind: .planned,
            at: Date(timeIntervalSince1970: 1_786_333_200),
            localDate: request.range.from,
            recurring: false
        )
        continuations.removeValue(forKey: index)?.resume(
            returning: CalendarLoadResult(
                response: CalendarMarkersResponseDTO(
                    timezone: request.accountTimezone,
                    from: request.range.from,
                    toExclusive: request.range.toExclusive,
                    markers: [marker]
                ),
                source: .network,
                failure: nil
            )
        )
    }
}

@MainActor
final class CalendarViewModelTests: XCTestCase {
    private let now = try! WireDateCodec.decode("2026-08-10T08:00:00Z")

    func testOutsideMonthSelectionChangesVisibleMonthAndLoadsItsExactGrid() async {
        let loader = ImmediateCalendarLoader(.markers([]))
        let model = makeModel(loader: loader)
        let selected = LocalDate(rawValue: "2026-07-27")!

        await model.select(selected)
        let ranges = await loader.ranges()

        XCTAssertEqual(model.selectedDate, selected)
        XCTAssertEqual(model.visibleMonth, CalendarMonth(year: 2026, month: 7))
        XCTAssertEqual(ranges.last, CalendarDateMath.range(for: CalendarMonth(year: 2026, month: 7)))
    }

    func testSelectedAgendaKeepsAndSortsPlannedAndDeadlineMarkers() async throws {
        let selected = LocalDate(rawValue: "2026-08-10")!
        let at = try WireDateCodec.decode("2026-08-10T09:00:00Z")
        let taskID = UUID()
        let planned = marker(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            taskID: taskID,
            title: "Alpha",
            kind: .planned,
            at: at,
            date: selected
        )
        let deadline = marker(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            taskID: taskID,
            title: "Alpha",
            kind: .deadline,
            at: at,
            date: selected
        )
        let loader = ImmediateCalendarLoader(.markers([deadline, planned]))
        let model = makeModel(loader: loader)

        await model.reload()

        XCTAssertEqual(model.selectedMarkers.map(\.markerId), [planned.markerId, deadline.markerId])
        XCTAssertEqual(model.counts(on: selected), CalendarMarkerCounts(planned: 1, deadlines: 1))
    }

    func testOlderMonthResponseCannotOverwriteNewerVisibleMonth() async {
        let loader = ControlledCalendarLoader()
        let model = makeModel(loader: loader)

        let first = Task { await model.reload() }
        await waitForRequests(1, loader: loader)
        let second = Task { await model.moveMonth(by: 1) }
        await waitForRequests(2, loader: loader)

        await loader.complete(1, title: "September")
        await second.value
        await loader.complete(0, title: "August stale")
        await first.value

        XCTAssertEqual(model.visibleMonth, CalendarMonth(year: 2026, month: 9))
        XCTAssertEqual(model.response?.markers.first?.title, "September")
        XCTAssertEqual(model.phase, .loaded)
    }

    func testUnauthorizedStateInvokesIntegrationHookAndDoesNotExposeCacheState() async {
        let error = APIError(
            statusCode: 401,
            code: "unauthorized",
            message: "Unauthorized",
            details: [],
            traceID: nil,
            requestID: UUID()
        )
        let loader = ImmediateCalendarLoader(.unauthorized(error))
        var unauthorizedCount = 0
        let now = self.now
        let model = CalendarViewModel(
            accountID: UUID(),
            accountTimezone: "Europe/Moscow",
            language: .en,
            loader: loader,
            now: { now },
            onUnauthorized: { unauthorizedCount += 1 }
        )

        await model.reload()

        XCTAssertEqual(model.phase, .unauthorized)
        XCTAssertNil(model.response)
        XCTAssertEqual(unauthorizedCount, 1)
    }

    func testEmptyOfflineResultRetainsRangeAndExposesOfflinePhase() async {
        let loader = ImmediateCalendarLoader(.emptyOffline)
        let model = makeModel(loader: loader)

        await model.reload()

        XCTAssertEqual(model.phase, .offline)
        XCTAssertTrue(model.response?.markers.isEmpty == true)
        XCTAssertNotNil(model.lastFailure)
        XCTAssertEqual(model.response?.timezone, "Europe/Moscow")
    }

    func testTodayUsesAccountTimezoneAndLoadsMissingCurrentMonth() async throws {
        let edgeInstant = try WireDateCodec.decode("2026-09-01T00:30:00Z")
        let loader = ImmediateCalendarLoader(.markers([]))
        let model = CalendarViewModel(
            accountID: UUID(),
            accountTimezone: "America/Los_Angeles",
            language: .en,
            loader: loader,
            now: { edgeInstant }
        )

        XCTAssertEqual(model.selectedDate, LocalDate(rawValue: "2026-08-31")!)
        await model.selectToday()
        let ranges = await loader.ranges()

        XCTAssertEqual(ranges, [CalendarDateMath.range(for: CalendarMonth(year: 2026, month: 8))])
    }

    func testNavigationUsesResolvedLocalIDAndExposesActionOrUnavailableHint() async throws {
        let date = LocalDate(rawValue: "2026-08-10")!
        let backendTaskID = UUID()
        let localTaskID = UUID()
        let item = marker(
            id: UUID(),
            taskID: backendTaskID,
            title: "Mapped task",
            kind: .planned,
            at: try WireDateCodec.decode("2026-08-10T09:00:00Z"),
            date: date
        )
        let mappedLoader = ImmediateCalendarLoader(
            .markers([item]),
            localTaskIDsByMarkerID: [item.markerId: localTaskID]
        )
        let mappedModel = makeModel(loader: mappedLoader)
        await mappedModel.reload()

        XCTAssertEqual(mappedModel.localTaskID(for: item), localTaskID)
        XCTAssertEqual(mappedModel.taskActionHint(for: item), "Double-tap to open task details")

        let unresolvedModel = makeModel(loader: ImmediateCalendarLoader(.markers([item])))
        await unresolvedModel.reload()

        XCTAssertNil(unresolvedModel.localTaskID(for: item))
        XCTAssertEqual(
            unresolvedModel.taskActionHint(for: item),
            "Sync the task to open its details"
        )
        XCTAssertEqual(
            CalendarCopy(language: .ru).openTask,
            "Дважды коснитесь, чтобы открыть карточку задачи"
        )
        XCTAssertEqual(
            CalendarCopy(language: .ru).taskUnavailable,
            "Синхронизируйте задачу, чтобы открыть её карточку"
        )
    }

    private func makeModel(loader: any CalendarLoading) -> CalendarViewModel {
        CalendarViewModel(
            accountID: UUID(),
            accountTimezone: "Europe/Moscow",
            language: .en,
            loader: loader,
            now: { self.now }
        )
    }

    private func waitForRequests(_ count: Int, loader: ControlledCalendarLoader) async {
        for _ in 0..<200 {
            if await loader.requestCount() >= count { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(count) calendar requests")
    }

    private func marker(
        id: UUID,
        taskID: UUID,
        title: String,
        kind: CalendarMarkerKind,
        at: Date,
        date: LocalDate
    ) -> CalendarMarkerDTO {
        CalendarMarkerDTO(
            markerId: id,
            occurrenceId: UUID(),
            taskId: taskID,
            goalId: nil,
            title: title,
            status: .todo,
            effort: 1,
            kind: kind,
            at: at,
            localDate: date,
            recurring: true
        )
    }
}
