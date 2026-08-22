import Foundation

struct EntityLinkContext: Equatable, Sendable {
    let type: LinkedEntityType
    let id: UUID
    let title: String
    let canManage: Bool
}

struct EntityLinkCandidate: Equatable, Identifiable, Sendable {
    let id: UUID
    let type: LinkedEntityType
    let title: String
    let path: String?
}

struct EntityLinkNavigationTarget: Equatable, Sendable {
    let type: LinkedEntityType
    let id: UUID
}

struct EntityLinkRow: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String?
    let relation: EntityRelationType
    let redacted: Bool
    let supportsDependency: Bool
    let navigationTarget: EntityLinkNavigationTarget?

    var isTappable: Bool { !redacted && navigationTarget != nil }
}

enum EntityLinkScreenPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case offline
    case unauthorized
    case forbidden
    case notFound
    case conflict
    case error
}

enum EntityLinkIssueKind: Equatable, Sendable {
    case selfLink
    case dependencyRequiresTasks
    case duplicate
    case dependencyCycle
    case unauthorized
    case forbidden
    case notFound
    case conflict
    case validation
    case offline
    case unavailable
}

struct EntityLinkIssue: Equatable, Sendable {
    let kind: EntityLinkIssueKind
    let code: String
    let message: String
}

enum EntityLinkValidationError: Error, Equatable, Sendable {
    case selfLink
    case dependencyRequiresTasks
    case duplicate
}

protocol EntityLinkFeatureServing: Sendable {
    func listEntityLinks(type: LinkedEntityType, id: UUID) async throws -> [ActionEntityLinkDTO]
    func createEntityLink(_ request: CreateEntityLinkRequestDTO) async throws -> ActionEntityLinkDTO
    func updateEntityLink(
        id: UUID,
        request: UpdateEntityLinkRequestDTO
    ) async throws -> ActionEntityLinkDTO
    func deleteEntityLink(id: UUID) async throws
}

extension PlanningActionService: EntityLinkFeatureServing {}

protocol EntityLinkCandidateSearching: Sendable {
    func searchEntityLinkCandidates(query: String) async throws -> [EntityLinkCandidate]
}

struct EntityLinkSearchProvider: EntityLinkCandidateSearching, Sendable {
    private let handler: @Sendable (String) async throws -> [EntityLinkCandidate]

    init(
        handler: @escaping @Sendable (String) async throws -> [EntityLinkCandidate]
    ) {
        self.handler = handler
    }

    func searchEntityLinkCandidates(query: String) async throws -> [EntityLinkCandidate] {
        try await handler(query)
    }
}

enum EntityLinkValidator {
    static func validateCreate(
        context: EntityLinkContext,
        candidate: EntityLinkCandidate,
        relation: EntityRelationType,
        existing: [ActionEntityLinkDTO]
    ) throws {
        guard context.id != candidate.id || context.type != candidate.type else {
            throw EntityLinkValidationError.selfLink
        }
        if relation == .dependency,
           context.type != .task || candidate.type != .task {
            throw EntityLinkValidationError.dependencyRequiresTasks
        }
        if existing.contains(where: {
            isDuplicate(
                link: $0,
                sourceType: context.type,
                sourceID: context.id,
                targetType: candidate.type,
                targetID: candidate.id,
                relation: relation
            )
        }) {
            throw EntityLinkValidationError.duplicate
        }
    }

    static func validateUpdate(
        link: ActionEntityLinkDTO,
        relation: EntityRelationType,
        existing: [ActionEntityLinkDTO]
    ) throws {
        guard let source = link.source.identity, let target = link.target.identity else {
            throw EntityLinkValidationError.dependencyRequiresTasks
        }
        if relation == .dependency,
           source.type != .task || target.type != .task {
            throw EntityLinkValidationError.dependencyRequiresTasks
        }
        if existing.contains(where: {
            $0.id != link.id && isDuplicate(
                link: $0,
                sourceType: source.type,
                sourceID: source.id,
                targetType: target.type,
                targetID: target.id,
                relation: relation
            )
        }) {
            throw EntityLinkValidationError.duplicate
        }
    }

    private static func isDuplicate(
        link: ActionEntityLinkDTO,
        sourceType: LinkedEntityType,
        sourceID: UUID,
        targetType: LinkedEntityType,
        targetID: UUID,
        relation: EntityRelationType
    ) -> Bool {
        guard link.relationType == relation,
              let source = link.source.identity,
              let target = link.target.identity else {
            return false
        }
        let exact = source.type == sourceType
            && source.id == sourceID
            && target.type == targetType
            && target.id == targetID
        guard relation == .related else { return exact }
        let reverse = source.type == targetType
            && source.id == targetID
            && target.type == sourceType
            && target.id == sourceID
        return exact || reverse
    }
}

struct EntityLinkCopy: Sendable {
    let title: String
    let add: String
    let search: String
    let choose: String
    let relation: String
    let related: String
    let dependency: String
    let goal: String
    let task: String
    let idea: String
    let note: String
    let restricted: String
    let restrictedHint: String
    let readOnly: String
    let loading: String
    let offline: String
    let unauthorized: String
    let forbidden: String
    let notFound: String
    let conflict: String
    let unavailable: String
    let retry: String
    let empty: String
    let noResults: String
    let cancel: String
    let delete: String
    let confirmDelete: String
    let selfLink: String
    let dependencyRequiresTasks: String
    let duplicate: String
    let dependencyCycle: String

    init(language: AppLanguage) {
        if language == .ru {
            title = "Связи"
            add = "Добавить связь"
            search = "Поиск целей, задач, идей и заметок"
            choose = "Выбрать"
            relation = "Тип связи"
            related = "Связано"
            dependency = "Зависимость"
            goal = "Цель"
            task = "Задача"
            idea = "Идея"
            note = "Заметка"
            restricted = "Недоступный элемент"
            restrictedHint = "Сведения скрыты из-за ограничений доступа"
            readOnly = "Только просмотр"
            loading = "Загрузка"
            offline = "Нет сети"
            unauthorized = "Требуется вход"
            forbidden = "Недостаточно прав"
            notFound = "Связь или элемент не найдены"
            conflict = "Связь изменилась. Обновите данные"
            unavailable = "Связи сейчас недоступны"
            retry = "Повторить"
            empty = "Связей пока нет"
            noResults = "Ничего не найдено"
            cancel = "Отмена"
            delete = "Удалить"
            confirmDelete = "Удалить связь?"
            selfLink = "Нельзя связать элемент с самим собой"
            dependencyRequiresTasks = "Зависимость возможна только между задачами"
            duplicate = "Такая связь уже существует"
            dependencyCycle = "Зависимость создаст цикл"
        } else {
            title = "Links"
            add = "Add link"
            search = "Search goals, tasks, ideas, and notes"
            choose = "Choose"
            relation = "Relation"
            related = "Related"
            dependency = "Dependency"
            goal = "Goal"
            task = "Task"
            idea = "Idea"
            note = "Note"
            restricted = "Restricted item"
            restrictedHint = "Details are hidden by access controls"
            readOnly = "View only"
            loading = "Loading"
            offline = "Offline"
            unauthorized = "Sign in required"
            forbidden = "You do not have permission"
            notFound = "Link or item not found"
            conflict = "The link changed. Refresh and try again"
            unavailable = "Links are currently unavailable"
            retry = "Retry"
            empty = "No links yet"
            noResults = "No results"
            cancel = "Cancel"
            delete = "Delete"
            confirmDelete = "Delete this link?"
            selfLink = "An item cannot link to itself"
            dependencyRequiresTasks = "Dependencies are available only between tasks"
            duplicate = "This link already exists"
            dependencyCycle = "This dependency would create a cycle"
        }
    }

    func relationTitle(_ value: EntityRelationType) -> String {
        value == .dependency ? dependency : related
    }

    func typeTitle(_ value: LinkedEntityType) -> String {
        switch value {
        case .goal: goal
        case .task: task
        case .idea: idea
        case .note: note
        }
    }
}
