import Foundation

enum CalendarMarkerKind: String, Codable, Sendable {
    case planned
    case deadline

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = CalendarMarkerKind(rawValue: try container.decode(String.self)) ?? .planned
    }
}

struct CalendarMarkerDTO: Codable, Equatable, Sendable, Identifiable {
    var id: UUID { markerId }
    let markerId: UUID
    let occurrenceId: UUID
    let taskId: UUID
    let goalId: UUID?
    let title: String
    let status: PlanningStatus
    let effort: Int
    let kind: CalendarMarkerKind
    let at: Date
    let localDate: LocalDate
    let recurring: Bool
}

struct CalendarMarkersResponseDTO: Codable, Equatable, Sendable {
    let timezone: String
    let from: LocalDate
    let toExclusive: LocalDate
    let markers: [CalendarMarkerDTO]
}

struct FocusProgressDTO: Codable, Equatable, Sendable {
    let completedWeight: Int
    let totalWeight: Int
    let percent: Int
    let completedCount: Int
    let totalCount: Int
}

struct FocusItemDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let taskId: UUID
    let title: String
    let status: PlanningStatus
    let effort: Int?
    let effectiveWeight: Int
    let plannedTime: Date?
    let dueTime: Date?
    let position: Int
    let historyOnly: Bool
    let folderId: UUID
    let folderTitle: String
    let goalId: UUID
    let goalTitle: String
    let shared: Bool
    let canWrite: Bool
}

struct FocusRolloverOfferDTO: Codable, Equatable, Sendable {
    let sourcePeriodId: UUID
    let items: [FocusItemDTO]
}

struct FocusPeriodDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let weekStart: LocalDate
    let weekEndExclusive: LocalDate
    let startsAt: Date
    let endsAt: Date
    let timezone: String
    let status: String
    let version: Int64
    let progress: FocusProgressDTO
    let items: [FocusItemDTO]
    let rolloverOffer: FocusRolloverOfferDTO?
}

struct FocusCandidateDTO: Codable, Equatable, Sendable, Identifiable {
    var id: UUID { taskId }
    let taskId: UUID
    let title: String
    let status: PlanningStatus
    let effort: Int?
    let effectiveWeight: Int
    let plannedTime: Date?
    let dueTime: Date?
    let folderId: UUID
    let folderTitle: String
    let goalId: UUID
    let goalTitle: String
    let shared: Bool
    let canWrite: Bool
    let inFocus: Bool
}

struct FocusCandidateListResponseDTO: Codable, Equatable, Sendable {
    let items: [FocusCandidateDTO]
    let nextCursor: String?
}

struct FocusHistorySummaryDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let weekStart: LocalDate
    let weekEndExclusive: LocalDate
    let startsAt: Date
    let endsAt: Date
    let timezone: String
    let status: String
    let version: Int64
    let progress: FocusProgressDTO
}

struct FocusHistoryResponseDTO: Codable, Equatable, Sendable {
    let items: [FocusHistorySummaryDTO]
}

struct FocusNotificationSettingsDTO: Codable, Equatable, Sendable {
    let intervalMinutes: Int?
    let quietHoursStart: String?
    let quietHoursEnd: String?
    let version: Int64
}

struct FocusMutationRequestDTO: Codable, Equatable, Sendable {
    let periodVersion: Int64?
    let idempotencyKey: String?
}

struct FocusReorderRequestDTO: Codable, Equatable, Sendable {
    let taskIds: [UUID]
    let periodVersion: Int64?
    let idempotencyKey: String?
}

struct FocusResolveRolloverRequestDTO: Codable, Equatable, Sendable {
    let taskIds: [UUID]
    let periodVersion: Int64?
    let idempotencyKey: String?
}

struct FocusNotificationSettingsRequestDTO: Codable, Equatable, Sendable {
    let intervalMinutes: Int?
    let quietHoursStart: String?
    let quietHoursEnd: String?
    let version: Int64
}

struct PriorityDecayPolicyDTO: Codable, Equatable, Sendable {
    let taskType: String
    let enabled: Bool
    let thresholdPreset: String
    let decayAmount: Int
}

struct UpdatePriorityDecayPolicyRequestDTO: Codable, Equatable, Sendable {
    let enabled: Bool
    let thresholdPreset: String
    let decayAmount: Int
}

struct UserSettingsDTO: Codable, Equatable, Sendable {
    let language: AppLanguage
    let greenPriorityDecayPolicy: PriorityDecayPolicyDTO?
    let redPriorityDecayPolicy: PriorityDecayPolicyDTO?
    let notificationsEnabled: Bool
    let version: Int64
}

struct UpdateUserSettingsRequestDTO: Codable, Equatable, Sendable {
    let language: AppLanguage
    let greenPriorityDecayPolicy: UpdatePriorityDecayPolicyRequestDTO?
    let redPriorityDecayPolicy: UpdatePriorityDecayPolicyRequestDTO?
    let notificationsEnabled: Bool
    let version: Int64
}

enum DevicePlatform: String, Codable, Sendable {
    case android
    case ios
}

struct RegisterDeviceRequestDTO: Codable, Equatable, Sendable {
    let platform: DevicePlatform
    let pushToken: String
    let installationId: String?
    let deviceName: String?
}

struct DeviceRegistrationDTO: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let platform: DevicePlatform
    let deviceName: String?
    let active: Bool
    let createdAt: Date
}
