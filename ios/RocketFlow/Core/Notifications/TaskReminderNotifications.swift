import Foundation
import UserNotifications

enum TaskReminderRepeat: String, Codable, CaseIterable, Sendable {
    case none
    case hourly
    case daily
    case weekly
    case monthly
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
        if let fireDate = request.fireDate {
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
}

struct NoopAccountNotificationCleaner: AccountNotificationClearing {
    func clear(accountID: UUID) async throws {}
}

enum TaskReminderSchedule {
    static let defaultOffsetMinutes = 60

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
        if reminder.triggerAt >= now { return reminder.triggerAt }
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

actor TaskReminderScheduler {
    private let center: any UserNotificationCenterServing
    private let store: any TaskReminderStoreServing
    private let now: @Sendable () -> Date

    init(
        center: any UserNotificationCenterServing,
        store: any TaskReminderStoreServing,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.center = center
        self.store = store
        self.now = now
    }

    func schedule(
        _ reminder: LocalTaskReminder,
        taskState: ReminderTaskState,
        timeZone: TimeZone
    ) async throws -> TaskReminderScheduleResult {
        let identifier = Self.identifier(for: reminder)
        guard taskState.canNotify else {
            await center.remove(identifiers: [identifier])
            try await store.remove(accountID: reminder.accountID, taskID: reminder.taskID, reminderID: reminder.id)
            return .removedForTaskState(taskState)
        }
        guard reminder.enabled else {
            await center.remove(identifiers: [identifier])
            return .disabled
        }
        guard let fireDate = TaskReminderSchedule.nextFireDate(
            for: reminder,
            now: now(),
            timeZone: timeZone
        ) else {
            await center.remove(identifiers: [identifier])
            try await store.remove(accountID: reminder.accountID, taskID: reminder.taskID, reminderID: reminder.id)
            return .expired
        }

        let advanced = LocalTaskReminder(
            id: reminder.id,
            accountID: reminder.accountID,
            taskID: reminder.taskID,
            taskTitle: reminder.taskTitle,
            triggerAt: fireDate,
            repeatRule: reminder.repeatRule,
            enabled: reminder.enabled,
            anchorAt: reminder.anchorAt
        )
        try await store.save(advanced, taskState: taskState)
        try await center.add(
            UserNotificationRequestValue(
                identifier: identifier,
                title: reminder.taskTitle,
                body: "Open this task in RocketFlow.",
                fireDate: fireDate,
                timeZoneIdentifier: timeZone.identifier,
                userInfo: [
                    "type": "task_reminder",
                    "taskId": reminder.taskID.uuidString.lowercased(),
                    "deepLink": "rocketflow://task/\(reminder.taskID.uuidString.lowercased())"
                ],
                timeSensitive: true
            )
        )
        return .scheduled(fireDate)
    }

    func reconcile(
        accountID: UUID,
        timeZone: TimeZone,
        reason: ReminderReconcileReason
    ) async throws -> [UUID: TaskReminderScheduleResult] {
        let items = try await store.reconciliationItems(accountID: accountID)
        var results: [UUID: TaskReminderScheduleResult] = [:]
        var desiredIdentifiers = Set<String>()
        for item in items {
            if item.taskState.canNotify && item.reminder.enabled {
                desiredIdentifiers.insert(Self.identifier(for: item.reminder))
            }
            results[item.reminder.id] = try await schedule(
                item.reminder,
                taskState: item.taskState,
                timeZone: timeZone
            )
        }

        let prefix = Self.accountPrefix(accountID)
        let pendingIdentifiers = await center.pendingIdentifiers()
        let obsolete = pendingIdentifiers.filter {
            $0.hasPrefix(prefix) && !desiredIdentifiers.contains($0)
        }
        if !obsolete.isEmpty { await center.remove(identifiers: Array(obsolete)) }
        _ = reason
        return results
    }

    func cancel(_ reminder: LocalTaskReminder) async throws {
        await center.remove(identifiers: [Self.identifier(for: reminder)])
        try await store.remove(accountID: reminder.accountID, taskID: reminder.taskID, reminderID: reminder.id)
    }

    func cancelAll(accountID: UUID) async throws {
        let storedIdentifiers = Set(
            try await store.reminders(accountID: accountID).map(Self.identifier)
        )
        let prefix = Self.accountPrefix(accountID)
        let pendingIdentifiers = await center.pendingIdentifiers().filter { $0.hasPrefix(prefix) }
        let deliveredIdentifiers = await center.deliveredIdentifiers().filter { $0.hasPrefix(prefix) }
        let identifiers = storedIdentifiers
            .union(pendingIdentifiers)
            .union(deliveredIdentifiers)
        if !identifiers.isEmpty {
            await center.remove(identifiers: Array(identifiers))
        }
        try await store.clear(accountID: accountID)
    }

    static func identifier(for reminder: LocalTaskReminder) -> String {
        accountPrefix(reminder.accountID)
            + reminder.taskID.uuidString.lowercased() + "."
            + reminder.id.uuidString.lowercased()
    }

    static func accountPrefix(_ accountID: UUID) -> String {
        "rocketflow.task-reminder.\(accountID.uuidString.lowercased())."
    }
}

extension TaskReminderScheduler: AccountNotificationClearing {
    func clear(accountID: UUID) async throws {
        try await cancelAll(accountID: accountID)
    }
}
