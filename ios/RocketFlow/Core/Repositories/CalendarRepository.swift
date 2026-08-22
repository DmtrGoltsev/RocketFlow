import Foundation

protocol CalendarRequestSending: Sendable {
    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response
}

extension AuthSession: CalendarRequestSending {}

protocol CalendarRemoteLoading: Sendable {
    func load(from: LocalDate, toExclusive: LocalDate) async throws -> CalendarMarkersResponseDTO
}

protocol CalendarTaskIDMapping: Sendable {
    func localTaskID(forBackendTaskID backendTaskID: UUID) async throws -> UUID?
}

struct PersistedCalendarTaskIDMappingAdapter: CalendarTaskIDMapping {
    typealias MappingLookup = @Sendable (UUID) async throws -> UUID?
    typealias LocalIdentityLookup = @Sendable (UUID) async throws -> Bool

    private let mappedLocalID: MappingLookup
    private let isKnownLocalID: LocalIdentityLookup

    init(
        mappedLocalID: @escaping MappingLookup,
        isKnownLocalID: @escaping LocalIdentityLookup
    ) {
        self.mappedLocalID = mappedLocalID
        self.isKnownLocalID = isKnownLocalID
    }

    func localTaskID(forBackendTaskID backendTaskID: UUID) async throws -> UUID? {
        if let localID = try await mappedLocalID(backendTaskID) {
            return localID
        }
        return try await isKnownLocalID(backendTaskID) ? backendTaskID : nil
    }
}

struct UnavailableCalendarTaskIDMapping: CalendarTaskIDMapping {
    func localTaskID(forBackendTaskID backendTaskID: UUID) -> UUID? { nil }
}

struct AuthenticatedCalendarRemote: CalendarRemoteLoading {
    private let sender: any CalendarRequestSending

    init(sender: any CalendarRequestSending) {
        self.sender = sender
    }

    func load(from: LocalDate, toExclusive: LocalDate) async throws -> CalendarMarkersResponseDTO {
        try await sender.send(CalendarEndpoints.markers(from: from, toExclusive: toExclusive))
    }
}

struct CalendarRangeKey: Hashable, Sendable {
    let accountID: UUID
    let timezoneID: String
    let from: LocalDate
    let toExclusive: LocalDate
}

protocol CalendarRangeCaching: Sendable {
    func load(_ key: CalendarRangeKey) async throws -> CalendarMarkersResponseDTO?
    func save(_ response: CalendarMarkersResponseDTO, for key: CalendarRangeKey) async throws
}

actor InMemoryCalendarRangeCache: CalendarRangeCaching {
    private var ranges: [CalendarRangeKey: CalendarMarkersResponseDTO] = [:]

    func load(_ key: CalendarRangeKey) -> CalendarMarkersResponseDTO? {
        ranges[key]
    }

    func save(_ response: CalendarMarkersResponseDTO, for key: CalendarRangeKey) {
        ranges[key] = response
    }
}

enum CalendarLoadSource: Equatable, Sendable {
    case network
    case exactCache
    case emptyOffline
}

struct CalendarLoadFailure: Equatable, Sendable {
    let code: String
    let statusCode: Int?

    init(_ error: Error) {
        if let apiError = error as? APIError {
            code = apiError.code
            statusCode = apiError.statusCode
        } else if let repositoryError = error as? CalendarRepositoryError {
            code = repositoryError.code
            statusCode = nil
        } else {
            code = "calendar_unavailable"
            statusCode = nil
        }
    }
}

struct CalendarLoadResult: Equatable, Sendable {
    let response: CalendarMarkersResponseDTO
    let source: CalendarLoadSource
    let failure: CalendarLoadFailure?
    let localTaskIDsByMarkerID: [UUID: UUID]

    init(
        response: CalendarMarkersResponseDTO,
        source: CalendarLoadSource,
        failure: CalendarLoadFailure?,
        localTaskIDsByMarkerID: [UUID: UUID] = [:]
    ) {
        self.response = response
        self.source = source
        self.failure = failure
        self.localTaskIDsByMarkerID = localTaskIDsByMarkerID
    }

    var isOffline: Bool { source != .network }
}

protocol CalendarLoading: Sendable {
    func load(
        accountID: UUID,
        accountTimezone: String,
        from: LocalDate,
        toExclusive: LocalDate
    ) async throws -> CalendarLoadResult
}

enum CalendarRepositoryError: Error, Equatable, Sendable {
    case invalidRange
    case responseRangeMismatch
    case invalidResponseTimezone

    var code: String {
        switch self {
        case .invalidRange: "calendar_range_invalid"
        case .responseRangeMismatch: "calendar_range_mismatch"
        case .invalidResponseTimezone: "calendar_timezone_invalid"
        }
    }
}

actor CalendarRepository: CalendarLoading {
    private let remote: any CalendarRemoteLoading
    private let cache: any CalendarRangeCaching
    private let taskIDMapping: any CalendarTaskIDMapping

    init(
        remote: any CalendarRemoteLoading,
        cache: any CalendarRangeCaching,
        taskIDMapping: any CalendarTaskIDMapping = UnavailableCalendarTaskIDMapping()
    ) {
        self.remote = remote
        self.cache = cache
        self.taskIDMapping = taskIDMapping
    }

    init(
        sender: any CalendarRequestSending,
        cache: any CalendarRangeCaching,
        taskIDMapping: any CalendarTaskIDMapping = UnavailableCalendarTaskIDMapping()
    ) {
        remote = AuthenticatedCalendarRemote(sender: sender)
        self.cache = cache
        self.taskIDMapping = taskIDMapping
    }

    func load(
        accountID: UUID,
        accountTimezone: String,
        from: LocalDate,
        toExclusive: LocalDate
    ) async throws -> CalendarLoadResult {
        guard from.rawValue < toExclusive.rawValue else {
            throw CalendarRepositoryError.invalidRange
        }

        let timezoneID = TimeZone(identifier: accountTimezone)?.identifier ?? "UTC"
        let key = CalendarRangeKey(
            accountID: accountID,
            timezoneID: timezoneID,
            from: from,
            toExclusive: toExclusive
        )
        do {
            let response = try await remote.load(from: from, toExclusive: toExclusive)
            guard response.from == from, response.toExclusive == toExclusive else {
                throw CalendarRepositoryError.responseRangeMismatch
            }
            guard TimeZone(identifier: response.timezone) != nil else {
                throw CalendarRepositoryError.invalidResponseTimezone
            }
            try Task.checkCancellation()
            let localTaskIDs = try await resolveLocalTaskIDs(in: response)
            try Task.checkCancellation()
            try? await cache.save(response, for: key)
            return CalendarLoadResult(
                response: response,
                source: .network,
                failure: nil,
                localTaskIDsByMarkerID: localTaskIDs
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let apiError as APIError where apiError.isUnauthorized {
            throw apiError
        } catch {
            let cached = try? await cache.load(key)
            if let cached,
               cached.from == from,
               cached.toExclusive == toExclusive,
               TimeZone(identifier: cached.timezone) != nil {
                let localTaskIDs = try await resolveLocalTaskIDs(in: cached)
                return CalendarLoadResult(
                    response: cached,
                    source: .exactCache,
                    failure: CalendarLoadFailure(error),
                    localTaskIDsByMarkerID: localTaskIDs
                )
            }

            return CalendarLoadResult(
                response: CalendarMarkersResponseDTO(
                    timezone: timezoneID,
                    from: from,
                    toExclusive: toExclusive,
                    markers: []
                ),
                source: .emptyOffline,
                failure: CalendarLoadFailure(error)
            )
        }
    }

    private func resolveLocalTaskIDs(
        in response: CalendarMarkersResponseDTO
    ) async throws -> [UUID: UUID] {
        var resolved: [UUID: UUID] = [:]
        for marker in response.markers {
            try Task.checkCancellation()
            do {
                if let localID = try await taskIDMapping.localTaskID(
                    forBackendTaskID: marker.taskId
                ) {
                    resolved[marker.markerId] = localID
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        return resolved
    }
}
