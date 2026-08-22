import Foundation

enum SettingsScreenPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case offline
    case pending
    case unauthorized
    case error
}

enum SettingsValidationError: Error, Equatable, Sendable {
    case invalidDefaultOffset
}

enum SettingsValidation {
    static let maximumDefaultOffsetMinutes = 365 * 24 * 60

    static func validateDefaultReminder(enabled: Bool, offsetMinutes: Int) throws {
        guard !enabled || (0...maximumDefaultOffsetMinutes).contains(offsetMinutes) else {
            throw SettingsValidationError.invalidDefaultOffset
        }
    }
}

struct SettingsCopy: Sendable {
    let title: String
    let language: String
    let russian: String
    let english: String
    let notifications: String
    let notificationPermission: String
    let permissionNotDetermined: String
    let permissionDenied: String
    let permissionAllowed: String
    let defaultReminder: String
    let currentReminders: String
    let reminderOffset: String
    let repeatRule: String
    let none: String
    let hourly: String
    let daily: String
    let weekly: String
    let monthly: String
    let focusCadence: String
    let deviceRegistration: String
    let register: String
    let unregister: String
    let registered: String
    let notRegistered: String
    let unavailable: String
    let pushUnavailable: String
    let pushUnavailableHint: String
    let loading: String
    let offline: String
    let pending: String
    let save: String
    let retry: String
    let invalidOffset: String
    let permissionRequired: String
    let minutes: String

    init(language: AppLanguage) {
        if language == .ru {
            title = "Настройки"
            self.language = "Язык"
            russian = "Русский"
            english = "English"
            notifications = "Уведомления"
            notificationPermission = "Разрешение системы"
            permissionNotDetermined = "Не запрошено"
            permissionDenied = "Запрещено"
            permissionAllowed = "Разрешено"
            defaultReminder = "Напоминание для новых задач"
            currentReminders = "Текущие напоминания"
            reminderOffset = "За сколько минут"
            repeatRule = "Повтор"
            none = "Без повтора"
            hourly = "Каждый час"
            daily = "Каждый день"
            weekly = "Каждую неделю"
            monthly = "Каждый месяц"
            focusCadence = "Частота напоминаний фокуса"
            deviceRegistration = "Удалённые уведомления"
            register = "Зарегистрировать устройство"
            unregister = "Удалить регистрацию"
            registered = "Устройство зарегистрировано"
            notRegistered = "Устройство не зарегистрировано"
            unavailable = "Настройки сейчас недоступны"
            pushUnavailable = "Удалённые уведомления недоступны"
            pushUnavailableHint = "Сервис push-уведомлений не настроен на этом устройстве"
            loading = "Загрузка настроек"
            offline = "Нет сети. Показаны сохранённые настройки"
            pending = "Изменения ожидают синхронизации"
            save = "Сохранить"
            retry = "Повторить"
            invalidOffset = "Укажите корректное число минут"
            permissionRequired = "Разрешите уведомления в настройках iOS"
            minutes = "мин"
        } else {
            title = "Settings"
            self.language = "Language"
            russian = "Russian"
            english = "English"
            notifications = "Notifications"
            notificationPermission = "System permission"
            permissionNotDetermined = "Not requested"
            permissionDenied = "Denied"
            permissionAllowed = "Allowed"
            defaultReminder = "Reminder for new tasks"
            currentReminders = "Current reminders"
            reminderOffset = "Minutes before due"
            repeatRule = "Repeat"
            none = "No repeat"
            hourly = "Hourly"
            daily = "Daily"
            weekly = "Weekly"
            monthly = "Monthly"
            focusCadence = "Focus reminder cadence"
            deviceRegistration = "Remote notifications"
            register = "Register device"
            unregister = "Remove registration"
            registered = "Device registered"
            notRegistered = "Device not registered"
            unavailable = "Settings are currently unavailable"
            pushUnavailable = "Remote notifications are unavailable"
            pushUnavailableHint = "The push notification service is not configured on this device"
            loading = "Loading settings"
            offline = "Offline. Showing saved settings"
            pending = "Changes are waiting to sync"
            save = "Save"
            retry = "Retry"
            invalidOffset = "Enter a valid number of minutes"
            permissionRequired = "Allow notifications in iOS Settings"
            minutes = "min"
        }
    }

    func repeatLabel(_ value: TaskReminderRepeat) -> String {
        switch value {
        case .none: none
        case .hourly: hourly
        case .daily: daily
        case .weekly: weekly
        case .monthly: monthly
        }
    }
}
