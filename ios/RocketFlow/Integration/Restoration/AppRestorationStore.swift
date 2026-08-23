import Foundation

enum AppRestorationStoredSnapshot: Equatable, Sendable {
    case missing
    case loaded(AppRestorationSnapshot)
    case discarded(AppRestorationDiscardReason)
}

protocol AppRestorationPersisting: Sendable {
    func load(accountID: UUID) -> AppRestorationStoredSnapshot
    func acquireLease(accountID: UUID, leaseID: UUID) -> AppRestorationStoredSnapshot
    func isLeaseOwner(accountID: UUID, leaseID: UUID) -> Bool
    @discardableResult
    func save(_ snapshot: AppRestorationSnapshot, leaseID: UUID) -> Bool
    @discardableResult
    func clear(accountID: UUID, leaseID: UUID) -> Bool
}

struct AppRestorationUserDefaultsStore: AppRestorationPersisting, @unchecked Sendable {
    private static let coordinationLock = NSLock()

    private let defaults: UserDefaults
    private let keyPrefix: String

    init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "rocketflow.app-restoration"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    func load(accountID: UUID) -> AppRestorationStoredSnapshot {
        withCoordinationLock {
            loadUnlocked(accountID: accountID)
        }
    }

    func acquireLease(accountID: UUID, leaseID: UUID) -> AppRestorationStoredSnapshot {
        withCoordinationLock {
            let stored = loadUnlocked(accountID: accountID)
            defaults.set(leaseID.uuidString.lowercased(), forKey: leaseKey(for: accountID))
            return stored
        }
    }

    func isLeaseOwner(accountID: UUID, leaseID: UUID) -> Bool {
        withCoordinationLock {
            ownsLease(accountID: accountID, leaseID: leaseID)
        }
    }

    @discardableResult
    func save(_ snapshot: AppRestorationSnapshot, leaseID: UUID) -> Bool {
        guard
            snapshot.schemaVersion == AppRestorationSnapshot.currentSchemaVersion,
            let data = try? JSONEncoder().encode(snapshot)
        else {
            return false
        }

        return withCoordinationLock {
            guard ownsLease(accountID: snapshot.accountID, leaseID: leaseID) else {
                return false
            }

            // Encode first, then replace one UserDefaults value so readers never see partial JSON.
            defaults.set(data, forKey: key(for: snapshot.accountID))
            return true
        }
    }

    @discardableResult
    func clear(accountID: UUID, leaseID: UUID) -> Bool {
        withCoordinationLock {
            guard ownsLease(accountID: accountID, leaseID: leaseID) else {
                return false
            }
            defaults.removeObject(forKey: key(for: accountID))
            defaults.removeObject(forKey: leaseKey(for: accountID))
            return true
        }
    }

    private func loadUnlocked(accountID: UUID) -> AppRestorationStoredSnapshot {
        let storageKey = key(for: accountID)
        guard let data = defaults.data(forKey: storageKey) else { return .missing }

        let versionEnvelope: AppRestorationVersionEnvelope
        do {
            versionEnvelope = try JSONDecoder().decode(AppRestorationVersionEnvelope.self, from: data)
        } catch {
            defaults.removeObject(forKey: storageKey)
            return .discarded(.corrupt)
        }

        guard versionEnvelope.schemaVersion == AppRestorationSnapshot.currentSchemaVersion else {
            defaults.removeObject(forKey: storageKey)
            return .discarded(.versionMismatch)
        }

        let header: AppRestorationEnvelopeHeader
        do {
            header = try JSONDecoder().decode(AppRestorationEnvelopeHeader.self, from: data)
        } catch {
            defaults.removeObject(forKey: storageKey)
            return .discarded(.corrupt)
        }
        guard header.accountID == accountID else {
            defaults.removeObject(forKey: storageKey)
            return .discarded(.accountMismatch)
        }

        // Each supported version gets its own payload decoder/migrator branch.
        switch versionEnvelope.schemaVersion {
        case 1:
            do {
                return .loaded(try JSONDecoder().decode(AppRestorationSnapshot.self, from: data))
            } catch {
                defaults.removeObject(forKey: storageKey)
                return .discarded(.corrupt)
            }
        default:
            defaults.removeObject(forKey: storageKey)
            return .discarded(.versionMismatch)
        }
    }

    private func key(for accountID: UUID) -> String {
        "\(keyPrefix).\(accountID.uuidString.lowercased())"
    }

    private func leaseKey(for accountID: UUID) -> String {
        "\(key(for: accountID)).lease"
    }

    private func ownsLease(accountID: UUID, leaseID: UUID) -> Bool {
        guard let storedLease = defaults.string(forKey: leaseKey(for: accountID)) else {
            return false
        }
        return UUID(uuidString: storedLease) == leaseID
    }

    private func withCoordinationLock<T>(_ body: () -> T) -> T {
        Self.coordinationLock.lock()
        defer { Self.coordinationLock.unlock() }
        return body()
    }
}
