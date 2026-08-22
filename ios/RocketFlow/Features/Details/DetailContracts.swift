import Foundation

enum DetailLoadSource: Equatable, Sendable {
    case network
    case offlineCache
}

struct DetailLoadResult: Equatable, Sendable {
    let content: DetailContent
    let source: DetailLoadSource
    let hasPendingChanges: Bool
}

enum DetailMutation: Equatable, Sendable {
    case delete(DetailEntityReference)
    case updateTaskStatus(taskID: UUID, status: DetailTaskStatus, version: Int64)
    case replaceChecklist(taskID: UUID, items: [DetailChecklistItemViewData])
    case setFocus(taskID: UUID, focused: Bool)
    case createIdeaHistory(ideaID: UUID, eventType: String, body: String, metadata: [String: String])
    case updateIdeaHistory(ideaID: UUID, note: DetailIdeaHistoryViewData)
    case deleteIdeaHistory(ideaID: UUID, noteID: UUID)
}

struct DetailMutationResult: Equatable, Sendable {
    let content: DetailContent?
    let pending: Bool
    let navigation: DetailNavigationResult?

    init(
        content: DetailContent? = nil,
        pending: Bool = false,
        navigation: DetailNavigationResult? = nil
    ) {
        self.content = content
        self.pending = pending
        self.navigation = navigation
    }
}

struct DetailServiceFailure: Error, Equatable, Sendable {
    let statusCode: Int?
    let code: String
    let message: String
}

enum DetailIssue: Equatable, Sendable {
    case dependencyBlocked
    case networkRequired
    case unavailable
}

protocol DetailLoading: Sendable {
    func loadDetail(_ reference: DetailEntityReference) async throws -> DetailLoadResult
}

protocol DetailMutationPerforming: Sendable {
    func performDetailMutation(_ mutation: DetailMutation) async throws -> DetailMutationResult
}
