import Foundation
import UserNotifications

enum TaskReminderRepeat: String, Codable, CaseIterable, Sendable {
    case none
    case hourly
    case daily
    case weekly
    case monthly
}

struct TaskReminderCopy: Sendable {
    let reminder: String
    let mode: String
    let accountDefault: String
    let keepCurrent: String
    let disabled: String
    let custom: String
    let fireAt: String
    let repeatRule: String
    let noRepeat: String
    let hourly: String
    let daily: String
    let weekly: String
    let monthly: String
    let loading: String
    let unavailable: String
    let openTaskBody: String

    init(language: AppLanguage) {
        if language == .ru {
            reminder = "Напоминание"
            mode = "Режим напоминания"
            accountDefault = "Настройка аккаунта"
            keepCurrent = "Без изменений"
            disabled = "Выключено"
            custom = "Своё"
            fireAt = "Дата и время"
            repeatRule = "Повтор"
            noRepeat = "Без повтора"
            hourly = "Каждый час"
            daily = "Ежедневно"
            weekly = "Еженедельно"
            monthly = "Ежемесячно"
            loading = "Загрузка"
            unavailable = "Напоминание недоступно"
            openTaskBody = "Открыть задачу в RocketFlow."
        } else {
            reminder = "Reminder"
            mode = "Reminder mode"
            accountDefault = "Account default"
            keepCurrent = "Keep current"
            disabled = "Off"
            custom = "Custom"
            fireAt = "Date and time"
            repeatRule = "Repeat"
            noRepeat = "No repeat"
            hourly = "Hourly"
            daily = "Daily"
            weekly = "Weekly"
            monthly = "Monthly"
            loading = "Loading"
            unavailable = "Reminder unavailable"
            openTaskBody = "Open this task in RocketFlow."
        }
    }

    func repeatTitle(_ value: TaskReminderRepeat) -> String {
        switch value {
        case .none: noRepeat
        case .hourly: hourly
        case .daily: daily
        case .weekly: weekly
        case .monthly: monthly
        }
    }
}

struct LocalTaskReminder: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let accountID: UUID
    let taskID: UUID
    let taskTitle: String
    let triggerAt: Date
    let repeatRule: TaskReminderRepeat
    let enabled: Bool
    let anchorAt: Date

    init(
        id: UUID,
        accountID: UUID,
        taskID: UUID,
        taskTitle: String,
        triggerAt: Date,
        repeatRule: TaskReminderRepeat,
        enabled: Bool = true,
        anchorAt: Date? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.triggerAt = triggerAt
        self.repeatRule = repeatRule
        self.enabled = enabled
        self.anchorAt = anchorAt ?? triggerAt
    }
}

struct DefaultTaskReminder: Codable, Equatable, Sendable {
    let accountID: UUID
    let offsetMinutes: Int
    let repeatRule: TaskReminderRepeat
    let enabled: Bool
}

enum ReminderTaskState: String, Codable, Equatable, Sendable {
    case active
    case done
    case cancelled
    case archived
    case missing

    var canNotify: Bool { self == .active }
}

struct TaskReminderReconciliationItem: Equatable, Sendable {
    let reminder: LocalTaskReminder
    let taskState: ReminderTaskState
}

struct TaskReminderPlanningSnapshot: Equatable, Sendable {
    let taskID: UUID
    let title: String
    let taskState: ReminderTaskState
}

protocol TaskReminderPlanningSnapshotProviding: Sendable {
    func planningTask(
        accountID: UUID,
        taskID: UUID
    ) async throws -> TaskReminderPlanningSnapshot?
}

enum ReminderReconcileReason: String, Sendable {
    case launch
    case foreground
    case timezoneChange
    case settingsChange
    case taskStateChange
}

enum TaskReminderScheduleResult: Equatable, Sendable {
    case scheduled(Date)
    case expired
    case removedForTaskState(ReminderTaskState)
    case disabled
}

enum NotificationAuthorizationState: String, Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
}

struct UserNotificationRequestValue: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let fireDate: Date?
    let timeZoneIdentifier: String?
    let userInfo: [String: String]
    let timeSensitive: Bool
    let calendarTrigger: UserNotificationCalendarTriggerValue?

    init(
        identifier: String,
        title: String,
        body: String,
        fireDate: Date?,
        timeZoneIdentifier: String?,
        userInfo: [String: String],
        timeSensitive: Bool,
        calendarTrigger: UserNotificationCalendarTriggerValue? = nil
    ) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.userInfo = userInfo
        self.timeSensitive = timeSensitive
        self.calendarTrigger = calendarTrigger
    }
}

struct UserNotificationCalendarTriggerValue: Equatable, Sendable {
    let timeZoneIdentifier: String
    let year: Int?
    let month: Int?
    let day: Int?
    let weekday: Int?
    let hour: Int?
    let minute: Int?
    let second: Int?
    let repeats: Bool

    var dateComponents: DateComponents {
        var value = DateComponents()
        value.timeZone = TimeZone(identifier: timeZoneIdentifier)
        value.year = year
        value.month = month
        value.day = day
        value.weekday = weekday
        value.hour = hour
        value.minute = minute
        value.second = second
        return value
    }
}

protocol UserNotificationCenterServing: Sendable {
    func authorizationState() async -> NotificationAuthorizationState
    func requestAuthorization() async throws -> Bool
    func pendingIdentifiers() async -> Set<String>
    func deliveredIdentifiers() async -> Set<String>
    func add(_ request: UserNotificationRequestValue) async throws
    func remove(identifiers: [String]) async
}

extension UserNotificationCenterServing {
    func deliveredIdentifiers() async -> Set<String> { [] }
}

final class SystemUserNotificationCenter: UserNotificationCenterServing, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationState() async -> NotificationAuthorizationState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func pendingIdentifiers() async -> Set<String> {
        let requests = await center.pendingNotificationRequests()
        return Set(requests.map(\.identifier))
    }

    func deliveredIdentifiers() async -> Set<String> {
        let notifications = await center.deliveredNotifications()
        return Set(notifications.map(\.request.identifier))
    }

    func add(_ request: UserNotificationRequestValue) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = request.userInfo
        if request.timeSensitive {
            content.interruptionLevel = .timeSensitive
        }

        let trigger: UNNotificationTrigger?
        if let calendarTrigger = request.calendarTrigger {
            trigger = UNCalendarNotificationTrigger(
                dateMatching: calendarTrigger.dateComponents,
                repeats: calendarTrigger.repeats
            )
        } else if let fireDate = request.fireDate {
            var calendar = Calendar(identifier: .gregorian)
            if let identifier = request.timeZoneIdentifier, let timezone = TimeZone(identifier: identifier) {
                calendar.timeZone = timezone
            }
            let components = calendar.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        }
        try await center.add(
            UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)
        )
    }

    func remove(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

protocol TaskReminderStoreServing: Sendable {
    func reconciliationItems(accountID: UUID) async throws -> [TaskReminderReconciliationItem]
    func reminders(accountID: UUID) async throws -> [LocalTaskReminder]
    func save(_ reminder: LocalTaskReminder, taskState: ReminderTaskState) async throws
    func remove(accountID: UUID, taskID: UUID, reminderID: UUID) async throws
    func defaultReminder(accountID: UUID) async throws -> DefaultTaskReminder?
    func saveDefault(_ reminder: DefaultTaskReminder) async throws
    func clearDefault(accountID: UUID) async throws
    func clear(accountID: UUID) async throws
}

protocol TaskReminderReading: Sendable {
    func reminder(taskID: UUID) async throws -> LocalTaskReminder?
}

extension TaskReminderStoreServing {
    func clear(accountID: UUID) async throws {
        for reminder in try await reminders(accountID: accountID) {
            try await remove(
                accountID: accountID,
                taskID: reminder.taskID,
                reminderID: reminder.id
            )
        }
        try await clearDefault(accountID: accountID)
    }
}

actor InMemoryTaskReminderStore: TaskReminderStoreServing {
    private struct Key: Hashable {
        let accountID: UUID
        let taskID: UUID
        let reminderID: UUID
    }

    private var values: [Key: TaskReminderReconciliationItem] = [:]
    private var defaults: [UUID: DefaultTaskReminder] = [:]

    func reconciliationItems(accountID: UUID) -> [TaskReminderReconciliationItem] {
        values.values.filter { $0.reminder.accountID == accountID }
            .sorted { $0.reminder.id.uuidString.lowercased() < $1.reminder.id.uuidString.lowercased() }
    }

    func reminders(accountID: UUID) -> [LocalTaskReminder] {
        reconciliationItems(accountID: accountID).map(\.reminder)
    }

    func save(_ reminder: LocalTaskReminder, taskState: ReminderTaskState) {
        values[Key(accountID: reminder.accountID, taskID: reminder.taskID, reminderID: reminder.id)] =
            TaskReminderReconciliationItem(reminder: reminder, taskState: taskState)
    }

    func remove(accountID: UUID, taskID: UUID, reminderID: UUID) {
        values.removeValue(forKey: Key(accountID: accountID, taskID: taskID, reminderID: reminderID))
    }

    func defaultReminder(accountID: UUID) -> DefaultTaskReminder? { defaults[accountID] }

    func saveDefault(_ reminder: DefaultTaskReminder) { defaults[reminder.accountID] = reminder }

    func clearDefault(accountID: UUID) { defaults.removeValue(forKey: accountID) }

    func clear(accountID: UUID) {
        values = values.filter { $0.key.accountID != accountID }
        defaults.removeValue(forKey: accountID)
    }
}

protocol AccountNotificationClearing: Sendable {
    func clear(accountID: UUID) async throws
    func suspendNotifications(accountID: UUID) async
    func resumeNotifications(accountID: UUID, timeZone: TimeZone) async throws
}

extension AccountNotificationClearing {
    func suspendNotifications(accountID: UUID) async {}
    func resumeNotifications(accountID: UUID, timeZone: TimeZone) async throws {}
}

struct NoopAccountNotificationCleaner: AccountNotificationClearing {
    func clear(accountID: UUID) async throws {}
}

enum TaskReminderSchedule {
    static let defaultOffsetMinutes = 60
    static let maximumPendingTaskRequests = 48

    // iOS permits 64 pending notifications. RocketFlow reserves 16 slots for
    // non-task notifications and rolls exact occurrences on lifecycle reconciliation.
    static func occurrenceLimit(for repeatRule: TaskReminderRepeat) -> Int {
        switch repeatRule {
        case .none: 1
        case .hourly, .daily: 16
        case .weekly, .monthly: 12
        }
    }

    static func materializeDefault(
        accountID: UUID,
        taskID: UUID,
        title: String,
        dueAt: Date?,
        setting: DefaultTaskReminder?,
        reminderID: UUID = UUID()
    ) -> LocalTaskReminder? {
        guard let dueAt, let setting, setting.enabled else { return nil }
        let offset = max(setting.offsetMinutes, 0)
        let trigger = dueAt.addingTimeInterval(TimeInterval(-offset * 60))
        return LocalTaskReminder(
            id: reminderID,
            accountID: accountID,
            taskID: taskID,
            taskTitle: title,
            triggerAt: trigger,
            repeatRule: setting.repeatRule,
            anchorAt: trigger
        )
    }

    static func nextFireDate(
        for reminder: LocalTaskReminder,
        now: Date,
        timeZone: TimeZone
    ) -> Date? {
        guard reminder.enabled else { return nil }
        if reminder.triggerAt > now { return reminder.triggerAt }
        guard reminder.repeatRule != .none else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let anchor = reminder.anchorAt

        switch reminder.repeatRule {
        case .none:
            return nil
        case .hourly:
            return advanced(anchor: anchor, now: now, component: .hour, multiplier: 1, calendar: calendar)
        case .daily:
            return advanced(anchor: anchor, now: now, component: .day, multiplier: 1, calendar: calendar)
        case .weekly:
            return advanced(anchor: anchor, now: now, component: .day, multiplier: 7, calendar: calendar)
        case .monthly:
            return nextAnchoredMonth(anchor: anchor, now: now, calendar: calendar)
        }
    }

    static func notificationTrigger(
        for _: LocalTaskReminder,
        fireDate: Date,
        timeZone: TimeZone
    ) -> UserNotificationCalendarTriggerValue {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let values = calendar.dateComponents(
            [.year, .month, .day, .weekday, .hour, .minute, .second],
            from: fireDate
        )
        return UserNotificationCalendarTriggerValue(
            timeZoneIdentifier: timeZone.identifier,
            year: values.year,
            month: values.month,
            day: values.day,
            weekday: nil,
            hour: values.hour,
            minute: values.minute,
            second: values.second,
            repeats: false
        )
    }

    static func occurrenceDates(
        for reminder: LocalTaskReminder,
        now: Date,
        timeZone: TimeZone,
        limit: Int
    ) -> [Date] {
        guard limit > 0 else { return [] }
        var values: [Date] = []
        var threshold = now
        while values.count < limit,
              let next = nextFireDate(for: reminder, now: threshold, timeZone: timeZone) {
            guard values.last != next else { break }
            values.append(next)
            guard reminder.repeatRule != .none else { break }
            threshold = next.addingTimeInterval(0.001)
        }
        return values
    }

    private static func advanced(
        anchor: Date,
        now: Date,
        component: Calendar.Component,
        multiplier: Int,
        calendar: Calendar
    ) -> Date? {
        let rawDistance: Int
        switch component {
        case .hour:
            rawDistance = calendar.dateComponents([.hour], from: anchor, to: now).hour ?? 0
        default:
            rawDistance = calendar.dateComponents([.day], from: anchor, to: now).day ?? 0
        }
        var steps = max(rawDistance / multiplier, 0)
        var candidate = calendar.date(byAdding: component, value: steps * multiplier, to: anchor)
        if let value = candidate, value <= now {
            steps += 1
            candidate = calendar.date(byAdding: component, value: steps * multiplier, to: anchor)
        }
        return candidate.flatMap { $0 > now ? $0 : nil }
    }

    private static func nextAnchoredMonth(anchor: Date, now: Date, calendar: Calendar) -> Date? {
        let anchorParts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: anchor)
        let nowParts = calendar.dateComponents([.year, .month], from: now)
        guard let anchorYear = anchorParts.year,
              let anchorMonth = anchorParts.month,
              let nowYear = nowParts.year,
              let nowMonth = nowParts.month else {
            return nil
        }
        var offset = max((nowYear - anchorYear) * 12 + nowMonth - anchorMonth, 0)
        var candidate = anchoredMonth(anchorParts: anchorParts, monthOffset: offset, calendar: calendar)
        if let value = candidate, value <= now {
            offset += 1
            candidate = anchoredMonth(anchorParts: anchorParts, monthOffset: offset, calendar: calendar)
        }
        return candidate.flatMap { $0 > now ? $0 : nil }
    }

    private static func anchoredMonth(
        anchorParts: DateComponents,
        monthOffset: Int,
        calendar: Calendar
    ) -> Date? {
        guard let year = anchorParts.year, let month = anchorParts.month, let anchorDay = anchorParts.day,
              let baseMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let targetMonth = calendar.date(byAdding: .month, value: monthOffset, to: baseMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: targetMonth) else {
            return nil
        }
        var target = calendar.dateComponents([.year, .month], from: targetMonth)
        target.day = min(anchorDay, dayRange.count)
        target.hour = anchorParts.hour
        target.minute = anchorParts.minute
        target.second = anchorParts.second
        target.timeZone = calendar.timeZone
        return calendar.date(from: target)
    }
}

enum TaskReminderSchedulingError: Error, Equatable, Sendable {
    case authorizationDenied
    case authorizationRequestFailed
    case expired
    case pendingLimitReached
}

actor TaskReminderScheduler {
    private let center: any UserNotificationCenterServing
    private let store: any TaskReminderStoreServing
    private let planning: (any TaskReminderPlanningSnapshotProviding)?
    private let now: @Sendable () -> Date
    private let notificationBody: @Sendable () async -> String

    init(
        center: any UserNotificationCenterServing,
        store: any TaskReminderStoreServing,
        planning: (any TaskReminderPlanningSnapshotProviding)? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        notificationBody: @escaping @Sendable () async -> String = {
            "Open this task in RocketFlow."
        }
    ) {
        self.center = center
        self.store = store
        self.planning = planning ?? (store as? any TaskReminderPlanningSnapshotProviding)
        self.now = now
        self.notificationBody = notificationBody
    }

    func schedule(
        _ reminder: LocalTaskReminder,
        taskState: ReminderTaskState,
        timeZone: TimeZone,
        occurrenceLimit: Int? = nil
    ) async throws -> TaskReminderScheduleResult {
        guard taskState.canNotify else {
            try await erase(reminder)
            return .removedForTaskState(taskState)
        }
        try await store.save(reminder, taskState: taskState)
        await suspend(reminder)
        guard reminder.enabled else {
            return .disabled
        }
        let requestedLimit = occurrenceLimit
            ?? TaskReminderSchedule.occurrenceLimit(for: reminder.repeatRule)
        let taskPendingCount = await center.pendingIdentifiers().filter {
            $0.hasPrefix(Self.rootPrefix)
        }.count
        let available = max(
            TaskReminderSchedule.maximumPendingTaskRequests - taskPendingCount,
            0
        )
        let dates = TaskReminderSchedule.occurrenceDates(
            for: reminder,
            now: now(),
            timeZone: timeZone,
            limit: min(requestedLimit, available)
        )
        guard !dates.isEmpty else {
            if TaskReminderSchedule.nextFireDate(for: reminder, now: now(), timeZone: timeZone) == nil {
                try await store.remove(
                    accountID: reminder.accountID,
                    taskID: reminder.taskID,
                    reminderID: reminder.id
                )
                return .expired
            }
            throw TaskReminderSchedulingError.pendingLimitReached
        }

        switch await center.authorizationState() {
        case .authorized, .provisional, .ephemeral:
            break
        case .denied:
            throw TaskReminderSchedulingError.authorizationDenied
        case .notDetermined:
            do {
                guard try await center.requestAuthorization() else {
                    throw TaskReminderSchedulingError.authorizationDenied
                }
            } catch let error as TaskReminderSchedulingError {
                throw error
            } catch {
                throw TaskReminderSchedulingError.authorizationRequestFailed
            }
        }

        let body = await notificationBody()
        for fireDate in dates {
            let calendarTrigger = TaskReminderSchedule.notificationTrigger(
                for: reminder,
                fireDate: fireDate,
                timeZone: timeZone
            )
            try await center.add(
                UserNotificationRequestValue(
                    identifier: Self.occurrenceIdentifier(for: reminder, fireDate: fireDate),
                    title: reminder.taskTitle,
                    body: body,
                    fireDate: fireDate,
                    timeZoneIdentifier: timeZone.identifier,
                    userInfo: [
                        "type": "task_reminder",
                        "taskId": reminder.taskID.uuidString.lowercased(),
                        "deepLink": "rocketflow://task/\(reminder.taskID.uuidString.lowercased())"
                    ],
                    timeSensitive: true,
                    calendarTrigger: calendarTrigger
                )
            )
        }
        return .scheduled(dates[0])
    }

    func reconcile(
        accountID: UUID,
        timeZone: TimeZone,
        reason: ReminderReconcileReason
    ) async throws -> [UUID: TaskReminderScheduleResult] {
        let stored = try await store.reconciliationItems(accountID: accountID)
        await suspendNotifications(accountID: accountID)

        var prepared: [TaskReminderReconciliationItem] = []
        var results: [UUID: TaskReminderScheduleResult] = [:]
        for item in stored {
            guard let planning else {
                prepared.append(item)
                continue
            }
            guard let task = try await planning.planningTask(
                accountID: accountID,
                taskID: item.reminder.taskID
            ) else {
                try await erase(item.reminder)
                results[item.reminder.id] = .removedForTaskState(.missing)
                continue
            }
            let refreshed = LocalTaskReminder(
                id: item.reminder.id,
                accountID: item.reminder.accountID,
                taskID: item.reminder.taskID,
                taskTitle: task.title,
                triggerAt: item.reminder.triggerAt,
                repeatRule: item.reminder.repeatRule,
                enabled: item.reminder.enabled,
                anchorAt: item.reminder.anchorAt
            )
            prepared.append(TaskReminderReconciliationItem(
                reminder: refreshed,
                taskState: task.taskState
            ))
        }

        let schedulableCount = prepared.filter {
            $0.taskState.canNotify && $0.reminder.enabled
        }.count
        let fairLimit = schedulableCount == 0
            ? 1
            : max(TaskReminderSchedule.maximumPendingTaskRequests / schedulableCount, 1)
        for item in prepared {
            let limit = min(
                TaskReminderSchedule.occurrenceLimit(for: item.reminder.repeatRule),
                fairLimit
            )
            results[item.reminder.id] = try await schedule(
                item.reminder,
                taskState: item.taskState,
                timeZone: timeZone,
                occurrenceLimit: limit
            )
        }
        _ = reason
        return results
    }

    func cancel(_ reminder: LocalTaskReminder) async throws {
        try await erase(reminder)
    }

    func cancelTask(accountID: UUID, taskID: UUID) async throws {
        let reminders = try await store.reminders(accountID: accountID).filter { $0.taskID == taskID }
        let prefix = Self.taskPrefix(accountID: accountID, taskID: taskID)
        let pendingIdentifiers = await center.pendingIdentifiers().filter { $0.hasPrefix(prefix) }
        let deliveredIdentifiers = await center.deliveredIdentifiers().filter { $0.hasPrefix(prefix) }
        let identifiers = pendingIdentifiers.union(deliveredIdentifiers)
        if !identifiers.isEmpty {
            await center.remove(identifiers: Array(identifiers))
        }
        for reminder in reminders {
            try await store.remove(accountID: reminder.accountID, taskID: reminder.taskID, reminderID: reminder.id)
        }
    }

    func cancelAll(accountID: UUID) async throws {
        await suspendNotifications(accountID: accountID)
        try await store.clear(accountID: accountID)
    }

    func suspendNotifications(accountID: UUID) async {
        let prefix = Self.accountPrefix(accountID)
        let pendingIdentifiers = await center.pendingIdentifiers().filter { $0.hasPrefix(prefix) }
        let deliveredIdentifiers = await center.deliveredIdentifiers().filter { $0.hasPrefix(prefix) }
        let identifiers = pendingIdentifiers.union(deliveredIdentifiers)
        if !identifiers.isEmpty {
            await center.remove(identifiers: Array(identifiers))
        }
    }

    func resumeNotifications(accountID: UUID, timeZone: TimeZone) async throws {
        _ = try await reconcile(
            accountID: accountID,
            timeZone: timeZone,
            reason: .settingsChange
        )
    }

    private func suspend(_ reminder: LocalTaskReminder) async {
        let base = Self.identifier(for: reminder)
        let pending = await center.pendingIdentifiers().filter {
            $0 == base || $0.hasPrefix(base + ".")
        }
        let delivered = await center.deliveredIdentifiers().filter {
            $0 == base || $0.hasPrefix(base + ".")
        }
        let identifiers = pending.union(delivered)
        if !identifiers.isEmpty {
            await center.remove(identifiers: Array(identifiers))
        }
    }

    private func erase(_ reminder: LocalTaskReminder) async throws {
        await suspend(reminder)
        try await store.remove(
            accountID: reminder.accountID,
            taskID: reminder.taskID,
            reminderID: reminder.id
        )
    }

    static func identifier(for reminder: LocalTaskReminder) -> String {
        taskPrefix(accountID: reminder.accountID, taskID: reminder.taskID)
            + reminder.id.uuidString.lowercased()
    }

    static func occurrenceIdentifier(for reminder: LocalTaskReminder, fireDate: Date) -> String {
        let milliseconds = Int64((fireDate.timeIntervalSince1970 * 1_000).rounded())
        return identifier(for: reminder) + "." + String(milliseconds)
    }

    static func taskPrefix(accountID: UUID, taskID: UUID) -> String {
        accountPrefix(accountID) + taskID.uuidString.lowercased() + "."
    }

    static func accountPrefix(_ accountID: UUID) -> String {
        rootPrefix + accountID.uuidString.lowercased() + "."
    }

    private static let rootPrefix = "rocketflow.task-reminder."
}

extension TaskReminderScheduler: AccountNotificationClearing {
    func clear(accountID: UUID) async throws {
        try await cancelAll(accountID: accountID)
    }
}
