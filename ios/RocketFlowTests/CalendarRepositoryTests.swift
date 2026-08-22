import Foundation
import XCTest
@testable import RocketFlow

private enum CalendarRemoteStubFailure: Error, Sendable {
    case offline
}

private actor CalendarRemoteStub: CalendarRemoteLoading {
    enum Behavior: Sendable {
        case response(CalendarMarkersResponseDTO)
        case offline
        case unauthorized(APIError)
    }

    private let behavior: Behavior
    private var requests: [CalendarGridRange] = []

    init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    func load(from: LocalDate, toExclusive: LocalDate) async throws -> CalendarMarkersResponseDTO {
        requests.append(CalendarGridRange(from: from, toExclusive: toExclusive))
        switch behavior {
        case let .response(response): return response
        case .offline: throw CalendarRemoteStubFailure.offline
        case let .unauthorized(error): throw error
        }
    }

    func capturedRequests() -> [CalendarGridRange] { requests }
}

private actor CalendarRequestSenderSpy: CalendarRequestSending {
    private let response: CalendarMarkersResponseDTO
    private var capturedPath: [String] = []
    private var capturedQuery: [URLQueryItem] = []

    init(response: CalendarMarkersResponseDTO) {
        self.response = response
    }

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response {
        capturedPath = endpoint.pathSegments
        capturedQuery = endpoint.queryItems
        guard let typed = response as? Response else {
            throw CalendarRemoteStubFailure.offline
        }
        return typed
    }

    func request() -> (path: [String], query: [URLQueryItem]) {
        (capturedPath, capturedQuery)
    }
}

private actor ThrowingCalendarCache: CalendarRangeCaching {
    func load(_ key: CalendarRangeKey) async throws -> CalendarMarkersResponseDTO? {
        throw CalendarRemoteStubFailure.offline
    }

    func save(_ response: CalendarMarkersResponseDTO, for key: CalendarRangeKey) async throws {
        throw CalendarRemoteStubFailure.offline
    }
}

final class CalendarRepositoryTests: XCTestCase {
    private let accountID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let from = LocalDate(rawValue: "2026-07-27")!
    private let toExclusive = LocalDate(rawValue: "2026-09-07")!

    func testAuthenticatedRemoteUsesExistingCalendarEndpointWithExactDateBounds() async throws {
        let response = makeResponse(from: from, toExclusive: toExclusive)
        let sender = CalendarRequestSenderSpy(response: response)
        let remote = AuthenticatedCalendarRemote(sender: sender)

        let loaded = try await remote.load(from: from, toExclusive: toExclusive)
        let request = await sender.request()
        let query = Dictionary(uniqueKeysWithValues: request.query.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(loaded, response)
        XCTAssertEqual(request.path, ["calendar"])
        XCTAssertEqual(query["from"], from.rawValue)
        XCTAssertEqual(query["toExclusive"], toExclusive.rawValue)
    }

    func testNetworkResponseIsSavedUnderExactAccountScopedRange() async throws {
        let response = makeResponse(from: from, toExclusive: toExclusive)
        let remote = CalendarRemoteStub(.response(response))
        let cache = InMemoryCalendarRangeCache()
        let repository = CalendarRepository(remote: remote, cache: cache)

        let result = try await repository.load(
            accountID: accountID,
            accountTimezone: "Europe/Moscow",
            from: from,
            toExclusive: toExclusive
        )
        let cached = try await cache.load(
            CalendarRangeKey(
                accountID: accountID,
                timezoneID: "Europe/Moscow",
                from: from,
                toExclusive: toExclusive
            )
        )

        XCTAssertEqual(result.source, .network)
        XCTAssertEqual(result.response, response)
        XCTAssertEqual(cached, response)
    }

    func testTransientFailureReturnsOnlyExactAccountRangeCache() async throws {
        let exact = makeResponse(from: from, toExclusive: toExclusive, title: "Exact")
        let otherAccount = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let cache = InMemoryCalendarRangeCache()
        try await cache.save(
            makeResponse(from: from, toExclusive: toExclusive, title: "Other account"),
            for: CalendarRangeKey(
                accountID: otherAccount,
                timezoneID: "Europe/Moscow",
                from: from,
                toExclusive: toExclusive
            )
        )
        try await cache.save(
            exact,
            for: CalendarRangeKey(
                accountID: accountID,
                timezoneID: "Europe/Moscow",
                from: from,
                toExclusive: toExclusive
            )
        )
        try await cache.save(
            makeResponse(
                from: LocalDate(rawValue: "2026-07-28")!,
                toExclusive: LocalDate(rawValue: "2026-09-08")!,
                title: "Wrong range"
            ),
            for: CalendarRangeKey(
                accountID: accountID,
                timezoneID: "Europe/Moscow",
                from: LocalDate(rawValue: "2026-07-28")!,
                toExclusive: LocalDate(rawValue: "2026-09-08")!
            )
        )
        let repository = CalendarRepository(remote: CalendarRemoteStub(.offline), cache: cache)

        let result = try await repository.load(
            accountID: accountID,
            accountTimezone: "Europe/Moscow",
            from: from,
            toExclusive: toExclusive
        )

        XCTAssertEqual(result.source, .exactCache)
        XCTAssertEqual(result.response.markers.first?.title, "Exact")
        XCTAssertEqual(result.failure?.code, "calendar_unavailable")
    }

    func testEmptyExactRangeRemainsAvailableOffline() async throws {
        let empty = CalendarMarkersResponseDTO(
            timezone: "Europe/Moscow",
            from: from,
            toExclusive: toExclusive,
            markers: []
        )
        let cache = InMemoryCalendarRangeCache()
        try await cache.save(
            empty,
            for: CalendarRangeKey(
                accountID: accountID,
                timezoneID: "Europe/Moscow",
                from: from,
                toExclusive: toExclusive
            )
        )
        let repository = CalendarRepository(remote: CalendarRemoteStub(.offline), cache: cache)

        let result = try await repository.load(
            accountID: accountID,
            accountTimezone: "Europe/Moscow",
            from: from,
            toExclusive: toExclusive
        )

        XCTAssertEqual(result.source, .exactCache)
        XCTAssertTrue(result.response.markers.isEmpty)
    }

    func testTransientFailureWithoutExactCacheReturnsEmptyOfflineAccountTimezoneRange() async throws {
        let repository = CalendarRepository(
            remote: CalendarRemoteStub(.offline),
            cache: InMemoryCalendarRangeCache()
        )

        let result = try await repository.load(
            accountID: accountID,
            accountTimezone: "America/Los_Angeles",
            from: from,
            toExclusive: toExclusive
        )

        XCTAssertEqual(result.source, .emptyOffline)
        XCTAssertEqual(result.response.timezone, "America/Los_Angeles")
        XCTAssertEqual(result.response.from, from)
        XCTAssertEqual(result.response.toExclusive, toExclusive)
        XCTAssertTrue(result.response.markers.isEmpty)
    }

    func testUnauthorizedNeverFallsBackToPopulatedCache() async throws {
        let cache = InMemoryCalendarRangeCache()
        try await cache.save(
            makeResponse(from: from, toExclusive: toExclusive),
            for: CalendarRangeKey(
                accountID: accountID,
                timezoneID: "Europe/Moscow",
                from: from,
                toExclusive: toExclusive
            )
        )
        let unauthorized = APIError(
            statusCode: 401,
            code: "unauthorized",
            message: "Unauthorized",
            details: [],
            traceID: nil,
            requestID: UUID()
        )
        let repository = CalendarRepository(
            remote: CalendarRemoteStub(.unauthorized(unauthorized)),
            cache: cache
        )

        do {
            _ = try await repository.load(
                accountID: accountID,
                accountTimezone: "Europe/Moscow",
                from: from,
                toExclusive: toExclusive
            )
            XCTFail("Expected terminal 401")
        } catch let error as APIError {
            XCTAssertTrue(error.isUnauthorized)
            XCTAssertEqual(error.code, "unauthorized")
        }
    }

    func testCacheWriteFailureDoesNotHideSuccessfulNetworkResponse() async throws {
        let response = makeResponse(from: from, toExclusive: toExclusive)
        let repository = CalendarRepository(
            remote: CalendarRemoteStub(.response(response)),
            cache: ThrowingCalendarCache()
        )

        let result = try await repository.load(
            accountID: accountID,
            accountTimezone: "Europe/Moscow",
            from: from,
            toExclusive: toExclusive
        )

        XCTAssertEqual(result.source, .network)
        XCTAssertEqual(result.response, response)
    }

    func testPersistedMappingConvertsBackendTaskIDToDifferentLocalID() async throws {
        let backendTaskID = UUID()
        let localTaskID = UUID()
        let markerID = UUID()
        let response = makeResponse(
            from: from,
            toExclusive: toExclusive,
            taskID: backendTaskID,
            markerID: markerID
        )
        let mapping = PersistedCalendarTaskIDMappingAdapter(
            mappedLocalID: { remoteID in remoteID == backendTaskID ? localTaskID : nil },
            isKnownLocalID: { _ in false }
        )
        let repository = CalendarRepository(
            remote: CalendarRemoteStub(.response(response)),
            cache: InMemoryCalendarRangeCache(),
            taskIDMapping: mapping
        )

        let result = try await repository.load(
            accountID: accountID,
            accountTimezone: "Europe/Moscow",
            from: from,
            toExclusive: toExclusive
        )

        XCTAssertEqual(result.response.markers.first?.taskId, backendTaskID)
        XCTAssertEqual(result.localTaskIDsByMarkerID[markerID], localTaskID)
    }

    func testKnownLocalOnlineTaskKeepsBackendIDWithoutMappingRow() async throws {
        let taskID = UUID()
        let markerID = UUID()
        let response = makeResponse(
            from: from,
            toExclusive: toExclusive,
            taskID: taskID,
            markerID: markerID
        )
        let mapping = PersistedCalendarTaskIDMappingAdapter(
            mappedLocalID: { _ in nil },
            isKnownLocalID: { candidate in candidate == taskID }
        )
        let repository = CalendarRepository(
            remote: CalendarRemoteStub(.response(response)),
            cache: InMemoryCalendarRangeCache(),
            taskIDMapping: mapping
        )

        let result = try await repository.load(
            accountID: accountID,
            accountTimezone: "Europe/Moscow",
            from: from,
            toExclusive: toExclusive
        )

        XCTAssertEqual(result.localTaskIDsByMarkerID[markerID], taskID)
    }

    func testUnresolvedBackendTaskRemainsVisibleButHasNoNavigationID() async throws {
        let markerID = UUID()
        let response = makeResponse(
            from: from,
            toExclusive: toExclusive,
            taskID: UUID(),
            markerID: markerID
        )
        let repository = CalendarRepository(
            remote: CalendarRemoteStub(.response(response)),
            cache: InMemoryCalendarRangeCache()
        )

        let result = try await repository.load(
            accountID: accountID,
            accountTimezone: "Europe/Moscow",
            from: from,
            toExclusive: toExclusive
        )

        XCTAssertEqual(result.response.markers.map(\.markerId), [markerID])
        XCTAssertNil(result.localTaskIDsByMarkerID[markerID])
    }

    func testTimezoneSwitchDoesNotReuseOldTimezoneExactCacheOffline() async throws {
        let cache = InMemoryCalendarRangeCache()
        try await cache.save(
            makeResponse(from: from, toExclusive: toExclusive),
            for: CalendarRangeKey(
                accountID: accountID,
                timezoneID: "Europe/Moscow",
                from: from,
                toExclusive: toExclusive
            )
        )
        let repository = CalendarRepository(
            remote: CalendarRemoteStub(.offline),
            cache: cache
        )

        let result = try await repository.load(
            accountID: accountID,
            accountTimezone: "America/Los_Angeles",
            from: from,
            toExclusive: toExclusive
        )

        XCTAssertEqual(result.source, .emptyOffline)
        XCTAssertEqual(result.response.timezone, "America/Los_Angeles")
        XCTAssertTrue(result.response.markers.isEmpty)
    }

    private func makeResponse(
        from: LocalDate,
        toExclusive: LocalDate,
        title: String = "Task",
        taskID: UUID = UUID(),
        markerID: UUID = UUID()
    ) -> CalendarMarkersResponseDTO {
        CalendarMarkersResponseDTO(
            timezone: "Europe/Moscow",
            from: from,
            toExclusive: toExclusive,
            markers: [
                CalendarMarkerDTO(
                    markerId: markerID,
                    occurrenceId: UUID(),
                    taskId: taskID,
                    goalId: nil,
                    title: title,
                    status: .todo,
                    effort: 2,
                    kind: .planned,
                    at: Date(timeIntervalSince1970: 1_786_333_200),
                    localDate: LocalDate(rawValue: "2026-08-10")!,
                    recurring: false
                )
            ]
        )
    }
}
