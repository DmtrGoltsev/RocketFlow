import Foundation

actor AppDeviceRegistrationRetryStore: DeviceRegistrationRetryStoring {
    private let defaults: UserDefaults
    private let keyPrefix: String

    init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "rocketflow.device-registration-retry.v1"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    func pending(accountID: UUID) throws -> PendingDeviceRegistrationRetry? {
        guard let data = defaults.data(forKey: key(accountID)) else { return nil }
        return try WireJSON.decoder().decode(PendingDeviceRegistrationRetry.self, from: data)
    }

    func save(_ pending: PendingDeviceRegistrationRetry) throws {
        defaults.set(
            try WireJSON.encoder().encode(pending),
            forKey: key(pending.accountID)
        )
    }

    func clear(accountID: UUID) {
        defaults.removeObject(forKey: key(accountID))
    }

    private func key(_ accountID: UUID) -> String {
        "\(keyPrefix).\(accountID.uuidString.lowercased())"
    }
}

struct AppDeviceRegistrationRetryScheduler: DeviceRegistrationRetryScheduling {
    let background: BackgroundRefreshCoordinator

    func scheduleDeviceRegistrationRetry(accountID _: UUID) async {
        try? await background.scheduleNext()
    }
}
