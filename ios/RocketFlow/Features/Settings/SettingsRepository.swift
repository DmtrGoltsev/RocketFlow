import Foundation

protocol SettingsRequestSending: Sendable {
    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response
}

extension AuthSession: SettingsRequestSending {}

protocol SettingsRemoteServing: Sendable {
    func current() async throws -> UserSettingsDTO
    func update(
        language: AppLanguage,
        notificationsEnabled: Bool,
        current: UserSettingsDTO
    ) async throws -> UserSettingsDTO
}

struct AuthenticatedSettingsRemote: SettingsRemoteServing {
    private let sender: any SettingsRequestSending

    init(sender: any SettingsRequestSending) {
        self.sender = sender
    }

    func current() async throws -> UserSettingsDTO {
        try await sender.send(SettingsEndpoints.current)
    }

    func update(
        language: AppLanguage,
        notificationsEnabled: Bool,
        current: UserSettingsDTO
    ) async throws -> UserSettingsDTO {
        try await sender.send(
            Endpoint(
                method: .patch,
                path: ["me", "settings"],
                body: UpdateUserSettingsRequestDTO(
                    language: language,
                    greenPriorityDecayPolicy: compatibilityPolicy(current.greenPriorityDecayPolicy),
                    redPriorityDecayPolicy: compatibilityPolicy(current.redPriorityDecayPolicy),
                    notificationsEnabled: notificationsEnabled,
                    version: current.version
                )
            )
        )
    }

    private func compatibilityPolicy(
        _ value: PriorityDecayPolicyDTO?
    ) -> UpdatePriorityDecayPolicyRequestDTO? {
        value.map {
            UpdatePriorityDecayPolicyRequestDTO(
                enabled: $0.enabled,
                thresholdPreset: $0.thresholdPreset,
                decayAmount: $0.decayAmount
            )
        }
    }
}

struct PendingSettingsUpdate: Codable, Equatable, Sendable {
    let mutationID: UUID
    let language: AppLanguage
    let notificationsEnabled: Bool

    init(
        mutationID: UUID = UUID(),
        language: AppLanguage,
        notificationsEnabled: Bool
    ) {
        self.mutationID = mutationID
        self.language = language
        self.notificationsEnabled = notificationsEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case mutationID
        case language
        case notificationsEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mutationID = try container.decodeIfPresent(UUID.self, forKey: .mutationID)
            ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        language = try container.decode(AppLanguage.self, forKey: .language)
        notificationsEnabled = try container.decode(Bool.self, forKey: .notificationsEnabled)
    }
}

protocol SettingsCacheServing: Sendable {
    func settings(accountID: UUID) async throws -> UserSettingsDTO?
    func save(_ settings: UserSettingsDTO, accountID: UUID) async throws
    func pending(accountID: UUID) async throws -> PendingSettingsUpdate?
    func savePending(_ pending: PendingSettingsUpdate, accountID: UUID) async throws
    func clearPending(accountID: UUID) async throws
}

actor InMemorySettingsCache: SettingsCacheServing {
    private var values: [UUID: UserSettingsDTO] = [:]
    private var pendingValues: [UUID: PendingSettingsUpdate] = [:]

    func settings(accountID: UUID) -> UserSettingsDTO? { values[accountID] }
    func save(_ settings: UserSettingsDTO, accountID: UUID) { values[accountID] = settings }
    func pending(accountID: UUID) -> PendingSettingsUpdate? { pendingValues[accountID] }
    func savePending(_ pending: PendingSettingsUpdate, accountID: UUID) { pendingValues[accountID] = pending }
    func clearPending(accountID: UUID) { pendingValues.removeValue(forKey: accountID) }
}

enum SettingsLoadSource: Equatable, Sendable {
    case network
    case cache
    case optimistic
}

struct SettingsFeatureFailure: Equatable, Sendable {
    let code: String
    let statusCode: Int?

    init(_ error: Error) {
        if let api = error as? APIError {
            code = api.code
            statusCode = api.statusCode
        } else {
            code = "settings_unavailable"
            statusCode = nil
        }
    }
}

struct SettingsRepositorySnapshot: Equatable, Sendable {
    let settings: UserSettingsDTO?
    let source: SettingsLoadSource
    let pending: Bool
    let failure: SettingsFeatureFailure?
}

enum SettingsRepositoryError: Error, Equatable, Sendable {
    case settingsUnavailable
}

protocol SettingsRepositoryServing: Sendable {
    func load(accountID: UUID) async throws -> SettingsRepositorySnapshot
    func save(
        accountID: UUID,
        language: AppLanguage,
        notificationsEnabled: Bool
    ) async throws -> SettingsRepositorySnapshot
    func retry(accountID: UUID) async throws -> SettingsRepositorySnapshot
}

actor SettingsRepository: SettingsRepositoryServing {
    private struct FlushFlight {
        let id: UUID
        let task: Task<SettingsRepositorySnapshot, Error>
    }

    private let remote: any SettingsRemoteServing
    private let cache: any SettingsCacheServing
    private var generations: [UUID: UInt64] = [:]
    private var flushFlights: [UUID: FlushFlight] = [:]

    init(remote: any SettingsRemoteServing, cache: any SettingsCacheServing) {
        self.remote = remote
        self.cache = cache
    }

    func load(accountID: UUID) async throws -> SettingsRepositorySnapshot {
        let generation = generations[accountID, default: 0]
        if try await cache.pending(accountID: accountID) != nil {
            do {
                return try await flushSerialized(accountID: accountID)
            } catch let api as APIError where api.isUnauthorized {
                throw api
            } catch {
                return await cachedSnapshot(accountID: accountID, failure: error)
            }
        }
        do {
            let settings = try await remote.current()
            guard generations[accountID, default: 0] == generation else {
                return await cachedSnapshot(accountID: accountID, failure: nil)
            }
            try? await cache.save(settings, accountID: accountID)
            return SettingsRepositorySnapshot(
                settings: settings, source: .network, pending: false, failure: nil
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let api as APIError where api.isUnauthorized {
            throw api
        } catch {
            return await cachedSnapshot(accountID: accountID, failure: error)
        }
    }

    func save(
        accountID: UUID,
        language: AppLanguage,
        notificationsEnabled: Bool
    ) async throws -> SettingsRepositorySnapshot {
        generations[accountID, default: 0] &+= 1
        let current: UserSettingsDTO
        if let cached = try await cache.settings(accountID: accountID) {
            current = cached
        } else {
            let loaded = try await load(accountID: accountID)
            guard let settings = loaded.settings else { throw SettingsRepositoryError.settingsUnavailable }
            current = settings
        }

        let pending = PendingSettingsUpdate(
            language: language,
            notificationsEnabled: notificationsEnabled
        )
        let optimistic = replacing(
            current,
            language: language,
            notificationsEnabled: notificationsEnabled
        )
        try await cache.save(optimistic, accountID: accountID)
        try await cache.savePending(pending, accountID: accountID)

        do {
            return try await flushSerialized(accountID: accountID)
        } catch is CancellationError {
            throw CancellationError()
        } catch let api as APIError where api.isUnauthorized {
            throw api
        } catch {
            return await cachedSnapshot(accountID: accountID, failure: error)
        }
    }

    func retry(accountID: UUID) async throws -> SettingsRepositorySnapshot {
        guard try await cache.pending(accountID: accountID) != nil else {
            return try await load(accountID: accountID)
        }
        return try await flushSerialized(accountID: accountID)
    }

    private func flushSerialized(accountID: UUID) async throws -> SettingsRepositorySnapshot {
        while true {
            let flight: FlushFlight
            if let existing = flushFlights[accountID] {
                flight = existing
            } else {
                let id = UUID()
                let task = Task { try await self.drainPending(accountID: accountID) }
                flight = FlushFlight(id: id, task: task)
                flushFlights[accountID] = flight
            }

            do {
                let snapshot = try await flight.task.value
                removeFlight(id: flight.id, accountID: accountID)
                if try await cache.pending(accountID: accountID) != nil {
                    continue
                }
                return snapshot
            } catch {
                removeFlight(id: flight.id, accountID: accountID)
                throw error
            }
        }
    }

    private func drainPending(accountID: UUID) async throws -> SettingsRepositorySnapshot {
        var latest: SettingsRepositorySnapshot?
        while let desired = try await cache.pending(accountID: accountID) {
            let initial: UserSettingsDTO
            if let cached = try await cache.settings(accountID: accountID) {
                initial = cached
            } else {
                initial = try await remote.current()
            }
            let updated: UserSettingsDTO
            do {
                updated = try await remote.update(
                    language: desired.language,
                    notificationsEnabled: desired.notificationsEnabled,
                    current: initial
                )
            } catch let api as APIError where api.statusCode == 409 || api.statusCode == 412 {
                let fresh = try await remote.current()
                updated = try await remote.update(
                    language: desired.language,
                    notificationsEnabled: desired.notificationsEnabled,
                    current: fresh
                )
            }

            let currentPending = try await cache.pending(accountID: accountID)
            guard currentPending?.mutationID == desired.mutationID else {
                latest = await cachedSnapshot(accountID: accountID, failure: nil)
                continue
            }
            try await cache.save(updated, accountID: accountID)
            try await cache.clearPending(accountID: accountID)
            latest = SettingsRepositorySnapshot(
                settings: updated, source: .network, pending: false, failure: nil
            )
        }

        if let latest { return latest }
        return await cachedSnapshot(accountID: accountID, failure: nil)
    }

    private func removeFlight(id: UUID, accountID: UUID) {
        guard flushFlights[accountID]?.id == id else { return }
        flushFlights.removeValue(forKey: accountID)
    }

    private func cachedSnapshot(
        accountID: UUID,
        failure: Error?
    ) async -> SettingsRepositorySnapshot {
        let settings = try? await cache.settings(accountID: accountID)
        let hasPending = (try? await cache.pending(accountID: accountID)) != nil
        return SettingsRepositorySnapshot(
            settings: settings,
            source: hasPending ? .optimistic : .cache,
            pending: hasPending,
            failure: failure.map(SettingsFeatureFailure.init)
        )
    }

    private func replacing(
        _ current: UserSettingsDTO,
        language: AppLanguage,
        notificationsEnabled: Bool
    ) -> UserSettingsDTO {
        UserSettingsDTO(
            language: language,
            greenPriorityDecayPolicy: current.greenPriorityDecayPolicy,
            redPriorityDecayPolicy: current.redPriorityDecayPolicy,
            notificationsEnabled: notificationsEnabled,
            version: current.version
        )
    }
}
