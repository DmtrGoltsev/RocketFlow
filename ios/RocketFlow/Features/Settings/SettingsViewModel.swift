import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var phase: SettingsScreenPhase = .idle
    @Published var language: AppLanguage
    @Published var notificationsEnabled = false
    @Published private(set) var authorization: NotificationAuthorizationState = .notDetermined
    @Published var defaultReminderEnabled = false
    @Published var defaultOffsetMinutes = TaskReminderSchedule.defaultOffsetMinutes
    @Published var defaultRepeatRule: TaskReminderRepeat = .none
    @Published private(set) var currentReminders: [LocalTaskReminder] = []
    @Published private(set) var registrationState: DeviceRegistrationDisplayState = .unregistered
    @Published private(set) var failure: SettingsFeatureFailure?
    @Published private(set) var validationMessage: String?
    @Published private(set) var hasPendingChanges = false

    let accountID: UUID
    private let repository: any SettingsRepositoryServing
    private let notificationCenter: any UserNotificationCenterServing
    private let reminderStore: any TaskReminderStoreServing
    private let registration: any DeviceRegistrationServicing
    private let notificationCleaner: any AccountNotificationClearing
    private let deviceName: String?
    private let onOpenFocusCadence: () -> Void
    private let onUnauthorized: () -> Void
    private var stateGeneration: UInt64 = 0

    init(
        accountID: UUID,
        initialLanguage: AppLanguage,
        repository: any SettingsRepositoryServing,
        notificationCenter: any UserNotificationCenterServing,
        reminderStore: any TaskReminderStoreServing,
        registration: any DeviceRegistrationServicing,
        notificationCleaner: any AccountNotificationClearing = NoopAccountNotificationCleaner(),
        deviceName: String?,
        onOpenFocusCadence: @escaping () -> Void,
        onUnauthorized: @escaping () -> Void = {}
    ) {
        self.accountID = accountID
        language = initialLanguage
        self.repository = repository
        self.notificationCenter = notificationCenter
        self.reminderStore = reminderStore
        self.registration = registration
        self.notificationCleaner = notificationCleaner
        self.deviceName = deviceName
        self.onOpenFocusCadence = onOpenFocusCadence
        self.onUnauthorized = onUnauthorized
    }

    var copy: SettingsCopy { SettingsCopy(language: language) }

    var canChangeDeviceRegistration: Bool {
        switch registrationState {
        case .unavailable, .syncing: false
        case .unregistered, .registered, .failed: true
        }
    }

    var deviceRegistrationExplanation: String? {
        registrationState == .unavailable ? copy.pushUnavailableHint : nil
    }

    func load() async {
        let generation = nextGeneration()
        phase = .loading
        validationMessage = nil
        async let settingsResult = repository.load(accountID: accountID)
        async let authorizationResult = notificationCenter.authorizationState()
        async let defaultResult = reminderStore.defaultReminder(accountID: accountID)
        async let remindersResult = reminderStore.reminders(accountID: accountID)
        async let registrationResult = registration.state(accountID: accountID)
        do {
            let snapshot = try await settingsResult
            let loadedAuthorization = await authorizationResult
            let defaultReminder = try await defaultResult
            let loadedReminders = try await remindersResult
            let loadedRegistration = await registrationResult
            guard generation == stateGeneration else { return }
            authorization = loadedAuthorization
            currentReminders = loadedReminders.filter(\.enabled).sorted { lhs, rhs in
                lhs.triggerAt == rhs.triggerAt
                    ? lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
                    : lhs.triggerAt < rhs.triggerAt
            }
            registrationState = loadedRegistration
            apply(snapshot)
            defaultReminderEnabled = defaultReminder?.enabled ?? false
            defaultOffsetMinutes = defaultReminder?.offsetMinutes ?? TaskReminderSchedule.defaultOffsetMinutes
            defaultRepeatRule = defaultReminder?.repeatRule ?? .none
        } catch {
            let loadedAuthorization = await authorizationResult
            let loadedRegistration = await registrationResult
            let isUnauthorized = (error as? APIError)?.isUnauthorized == true
            guard generation == stateGeneration || isUnauthorized else { return }
            if generation == stateGeneration {
                authorization = loadedAuthorization
                registrationState = loadedRegistration
            }
            await handle(error)
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        let generation = nextGeneration()
        validationMessage = nil
        guard enabled else {
            notificationsEnabled = false
            do {
                try await notificationCleaner.clear(accountID: accountID)
            } catch {
                guard generation == stateGeneration else { return }
                await handle(error)
            }
            return
        }
        var state = await notificationCenter.authorizationState()
        if state == .notDetermined {
            _ = try? await notificationCenter.requestAuthorization()
            state = await notificationCenter.authorizationState()
        }
        guard generation == stateGeneration else { return }
        authorization = state
        guard state == .authorized || state == .provisional || state == .ephemeral else {
            notificationsEnabled = false
            validationMessage = copy.permissionRequired
            return
        }
        notificationsEnabled = true
    }

    @discardableResult
    func save() async -> Bool {
        validationMessage = nil
        do {
            try SettingsValidation.validateDefaultReminder(
                enabled: defaultReminderEnabled,
                offsetMinutes: defaultOffsetMinutes
            )
        } catch {
            validationMessage = copy.invalidOffset
            return false
        }

        let generation = nextGeneration()
        let desiredLanguage = language
        let desiredNotificationsEnabled = notificationsEnabled
        let desiredDefaultEnabled = defaultReminderEnabled
        let desiredDefaultOffset = defaultOffsetMinutes
        let desiredDefaultRepeat = defaultRepeatRule
        phase = .loading
        do {
            if desiredDefaultEnabled {
                try await reminderStore.saveDefault(
                    DefaultTaskReminder(
                        accountID: accountID,
                        offsetMinutes: desiredDefaultOffset,
                        repeatRule: desiredDefaultRepeat,
                        enabled: true
                    )
                )
            } else {
                try await reminderStore.clearDefault(accountID: accountID)
            }
            let snapshot = try await repository.save(
                accountID: accountID,
                language: desiredLanguage,
                notificationsEnabled: desiredNotificationsEnabled
            )
            if !desiredNotificationsEnabled {
                try await notificationCleaner.clear(accountID: accountID)
            }
            guard generation == stateGeneration else { return true }
            apply(snapshot)
            return phase != .unauthorized && phase != .error
        } catch {
            guard generation == stateGeneration || (error as? APIError)?.isUnauthorized == true else {
                return false
            }
            await handle(error)
            return false
        }
    }

    func retry() async {
        let generation = nextGeneration()
        phase = .loading
        do {
            let snapshot = try await repository.retry(accountID: accountID)
            guard generation == stateGeneration else { return }
            apply(snapshot)
        } catch {
            guard generation == stateGeneration || (error as? APIError)?.isUnauthorized == true else { return }
            await handle(error)
        }
    }

    func syncDeviceRegistration() async {
        registrationState = .syncing
        do {
            _ = try await registration.sync(accountID: accountID, deviceName: deviceName)
            registrationState = await registration.state(accountID: accountID)
        } catch {
            if (error as? APIError)?.isUnauthorized == true {
                await handle(error)
            } else {
                registrationState = .failed(SettingsFeatureFailure(error).code)
            }
        }
    }

    func unregisterDevice() async {
        registrationState = .syncing
        do {
            _ = try await registration.unregister(accountID: accountID)
            registrationState = .unregistered
        } catch {
            if (error as? APIError)?.isUnauthorized == true {
                await handle(error)
            } else {
                registrationState = .failed(SettingsFeatureFailure(error).code)
            }
        }
    }

    func openFocusCadence() {
        onOpenFocusCadence()
    }

    private func apply(_ snapshot: SettingsRepositorySnapshot) {
        if let settings = snapshot.settings {
            language = settings.language
            notificationsEnabled = settings.notificationsEnabled
        }
        hasPendingChanges = snapshot.pending
        failure = snapshot.failure
        if snapshot.pending {
            phase = .pending
        } else if snapshot.source == .cache || snapshot.failure != nil {
            phase = snapshot.settings == nil ? .error : .offline
        } else {
            phase = .loaded
        }
    }

    private func handle(_ error: Error) async {
        if let api = error as? APIError, api.isUnauthorized {
            try? await notificationCleaner.clear(accountID: accountID)
            phase = .unauthorized
            onUnauthorized()
            return
        }
        failure = SettingsFeatureFailure(error)
        phase = .error
    }

    private func nextGeneration() -> UInt64 {
        stateGeneration &+= 1
        return stateGeneration
    }
}
