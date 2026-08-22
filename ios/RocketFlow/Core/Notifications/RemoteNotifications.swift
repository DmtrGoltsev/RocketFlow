import Foundation

enum RemoteNotificationPayload: Equatable, Sendable {
    case task(taskID: UUID, title: String, body: String)
    case focus(periodID: UUID, eventID: UUID, title: String, body: String)

    var deepLink: URL {
        switch self {
        case let .task(taskID, _, _):
            return URL(string: "rocketflow://task/\(taskID.uuidString.lowercased())")!
        case .focus:
            return URL(string: "rocketflow://focus")!
        }
    }
}

enum RemoteNotificationPayloadParser {
    static func parse(
        data: [String: String],
        hasNotificationPayload: Bool = false
    ) -> RemoteNotificationPayload? {
        guard !hasNotificationPayload else { return nil }
        let type = data["type"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case "task_reminder":
            guard let taskID = uuid(data["taskId"]) else { return nil }
            return .task(
                taskID: taskID,
                title: nonEmpty(data["title"]) ?? "RocketFlow reminder",
                body: nonEmpty(data["body"]) ?? "Open this task in RocketFlow."
            )
        case "focus_reminder":
            guard let periodID = uuid(data["periodId"]),
                  let eventID = uuid(data["eventId"]) else {
                return nil
            }
            return .focus(
                periodID: periodID,
                eventID: eventID,
                title: nonEmpty(data["title"]) ?? "RocketFlow",
                body: nonEmpty(data["body"]) ?? "Open your weekly focus."
            )
        default:
            return nil
        }
    }

    private static func uuid(_ value: String?) -> UUID? {
        value.flatMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }
}

protocol FocusNotificationEventDeduplicating: Sendable {
    func markIfNew(eventID: UUID, now: Date) async throws -> Bool
}

actor InMemoryFocusNotificationEventStore: FocusNotificationEventDeduplicating {
    static let retention: TimeInterval = 14 * 24 * 60 * 60
    private var events: [UUID: Date] = [:]

    func markIfNew(eventID: UUID, now: Date) -> Bool {
        let cutoff = now.addingTimeInterval(-Self.retention)
        events = events.filter { $0.value >= cutoff }
        if let existing = events[eventID], existing >= cutoff { return false }
        events[eventID] = now
        return true
    }
}

actor UserDefaultsFocusNotificationEventStore: FocusNotificationEventDeduplicating {
    static let retention: TimeInterval = 14 * 24 * 60 * 60
    private let suiteName: String?
    private let key: String

    init(
        suiteName: String? = nil,
        key: String = "rocketflow.focus-notification-events.v1"
    ) {
        self.suiteName = suiteName
        self.key = key
    }

    func markIfNew(eventID: UUID, now: Date) throws -> Bool {
        let defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        let existingData = defaults.data(forKey: key)
        var values = existingData.flatMap {
            try? JSONDecoder().decode([String: TimeInterval].self, from: $0)
        } ?? [:]
        let cutoff = now.addingTimeInterval(-Self.retention).timeIntervalSince1970
        values = values.filter { $0.value >= cutoff }
        let eventKey = eventID.uuidString.lowercased()
        if let existing = values[eventKey], existing >= cutoff { return false }
        values[eventKey] = now.timeIntervalSince1970
        defaults.set(try JSONEncoder().encode(values), forKey: key)
        return true
    }
}

enum RemoteNotificationHandlingResult: Equatable, Sendable {
    case rejected
    case duplicate
    case presented(URL)
}

actor RemoteNotificationHandler {
    private let center: any UserNotificationCenterServing
    private let dedupe: any FocusNotificationEventDeduplicating
    private let now: @Sendable () -> Date
    private let requestID: @Sendable () -> UUID

    init(
        center: any UserNotificationCenterServing,
        dedupe: any FocusNotificationEventDeduplicating,
        now: @escaping @Sendable () -> Date = Date.init,
        requestID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.center = center
        self.dedupe = dedupe
        self.now = now
        self.requestID = requestID
    }

    func handle(
        data: [String: String],
        hasNotificationPayload: Bool = false
    ) async throws -> RemoteNotificationHandlingResult {
        guard let payload = RemoteNotificationPayloadParser.parse(
            data: data,
            hasNotificationPayload: hasNotificationPayload
        ) else {
            return .rejected
        }

        let title: String
        let body: String
        let identifier: String
        let userInfo: [String: String]
        let timeSensitive: Bool
        switch payload {
        case let .task(taskID, valueTitle, valueBody):
            title = valueTitle
            body = valueBody
            identifier = "rocketflow.remote.task.\(requestID().uuidString.lowercased())"
            userInfo = [
                "type": "task_reminder",
                "taskId": taskID.uuidString.lowercased(),
                "deepLink": payload.deepLink.absoluteString
            ]
            timeSensitive = true
        case let .focus(periodID, eventID, valueTitle, valueBody):
            guard try await dedupe.markIfNew(eventID: eventID, now: now()) else {
                return .duplicate
            }
            title = valueTitle
            body = valueBody
            identifier = "rocketflow.remote.focus.\(eventID.uuidString.lowercased())"
            userInfo = [
                "type": "focus_reminder",
                "periodId": periodID.uuidString.lowercased(),
                "eventId": eventID.uuidString.lowercased(),
                "deepLink": payload.deepLink.absoluteString
            ]
            timeSensitive = false
        }

        try await center.add(
            UserNotificationRequestValue(
                identifier: identifier,
                title: title,
                body: body,
                fireDate: nil,
                timeZoneIdentifier: nil,
                userInfo: userInfo,
                timeSensitive: timeSensitive
            )
        )
        return .presented(payload.deepLink)
    }
}
