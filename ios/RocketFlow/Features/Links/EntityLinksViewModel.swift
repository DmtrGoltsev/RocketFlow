import Combine
import Foundation

@MainActor
final class EntityLinksViewModel: ObservableObject {
    @Published private(set) var phase: EntityLinkScreenPhase = .idle
    @Published private var links: [ActionEntityLinkDTO] = []
    @Published private(set) var issue: EntityLinkIssue?
    @Published private(set) var isMutating = false
    @Published private(set) var isPickerPresented = false
    @Published private(set) var pendingDeleteID: UUID?

    @Published var query = ""
    @Published var selectedRelation: EntityRelationType = .related
    @Published private(set) var candidatePhase: EntityLinkScreenPhase = .idle
    @Published private(set) var candidates: [EntityLinkCandidate] = []

    let context: EntityLinkContext
    @Published private(set) var language: AppLanguage

    private let service: any EntityLinkFeatureServing
    private let search: any EntityLinkCandidateSearching
    private let onOpen: (EntityLinkNavigationTarget) -> Void
    private let onUnauthorized: () -> Void
    private var loadGeneration: UInt64 = 0
    private var searchGeneration: UInt64 = 0
    private var searchTask: Task<Void, Never>?

    init(
        context: EntityLinkContext,
        language: AppLanguage,
        service: any EntityLinkFeatureServing,
        search: any EntityLinkCandidateSearching,
        onOpen: @escaping (EntityLinkNavigationTarget) -> Void,
        onUnauthorized: @escaping () -> Void = {}
    ) {
        self.context = context
        self.language = language
        self.service = service
        self.search = search
        self.onOpen = onOpen
        self.onUnauthorized = onUnauthorized
    }

    var copy: EntityLinkCopy { EntityLinkCopy(language: language) }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
    }
    var isBusy: Bool { phase == .loading || isMutating }

    var rows: [EntityLinkRow] {
        links
            .sorted { $0.createdAt > $1.createdAt }
            .map(row)
    }

    func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        phase = .loading
        issue = nil
        do {
            let values = try await service.listEntityLinks(type: context.type, id: context.id)
            guard generation == loadGeneration else { return }
            links = values
            phase = .loaded
        } catch is CancellationError {
            guard generation == loadGeneration else { return }
            phase = links.isEmpty ? .idle : .loaded
        } catch {
            guard generation == loadGeneration else { return }
            handle(error)
        }
    }

    func open(_ row: EntityLinkRow) {
        guard row.isTappable, let target = row.navigationTarget else { return }
        onOpen(target)
    }

    func presentPicker() {
        guard context.canManage else {
            setIssue(.forbidden, code: "full_access_required", message: copy.readOnly)
            return
        }
        guard !isBusy else { return }
        selectedRelation = .related
        query = ""
        candidates = []
        candidatePhase = .idle
        isPickerPresented = true
    }

    func dismissPicker() {
        searchTask?.cancel()
        searchGeneration &+= 1
        isPickerPresented = false
        query = ""
        candidates = []
        candidatePhase = .idle
    }

    func scheduleSearch(_ value: String) {
        query = value
        searchTask?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await self?.searchCandidates(generation: generation)
            } catch {
                return
            }
        }
    }

    func searchNow() async {
        searchTask?.cancel()
        searchGeneration &+= 1
        await searchCandidates(generation: searchGeneration)
    }

    func createLink(to candidate: EntityLinkCandidate) async {
        guard beginMutation() else { return }
        defer { isMutating = false }
        do {
            try EntityLinkValidator.validateCreate(
                context: context,
                candidate: candidate,
                relation: selectedRelation,
                existing: links
            )
            let created = try await service.createEntityLink(
                CreateEntityLinkRequestDTO(
                    sourceType: context.type,
                    sourceId: context.id,
                    targetType: candidate.type,
                    targetId: candidate.id,
                    relationType: selectedRelation
                )
            )
            invalidatePendingLoad()
            links.removeAll { $0.id == created.id }
            links.append(created)
            issue = nil
            phase = .loaded
            dismissPicker()
        } catch let validation as EntityLinkValidationError {
            handle(validation)
        } catch {
            handle(error)
        }
    }

    func updateRelation(linkID: UUID, relation: EntityRelationType) async {
        guard let link = links.first(where: { $0.id == linkID }) else { return }
        guard beginMutation() else { return }
        defer { isMutating = false }
        do {
            try EntityLinkValidator.validateUpdate(link: link, relation: relation, existing: links)
            let updated = try await service.updateEntityLink(
                id: link.id,
                request: UpdateEntityLinkRequestDTO(
                    relationType: relation,
                    version: link.version
                )
            )
            invalidatePendingLoad()
            replace(updated)
            issue = nil
            phase = .loaded
        } catch let validation as EntityLinkValidationError {
            handle(validation)
        } catch {
            handle(error)
        }
    }

    func requestDelete(linkID: UUID) {
        guard context.canManage else {
            setIssue(.forbidden, code: "full_access_required", message: copy.readOnly)
            return
        }
        guard !isBusy else { return }
        pendingDeleteID = linkID
    }

    func cancelDelete() {
        pendingDeleteID = nil
    }

    func confirmDelete() async {
        guard let id = pendingDeleteID, beginMutation() else { return }
        pendingDeleteID = nil
        defer { isMutating = false }
        do {
            try await service.deleteEntityLink(id: id)
            invalidatePendingLoad()
            links.removeAll { $0.id == id }
            issue = nil
            phase = .loaded
        } catch {
            handle(error)
        }
    }

    private func searchCandidates(generation: UInt64) async {
        guard generation == searchGeneration else { return }
        candidatePhase = .loading
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let values = try await search.searchEntityLinkCandidates(query: normalized)
            guard generation == searchGeneration else { return }
            candidates = Self.uniqueCandidates(values).sorted {
                if $0.title.localizedCaseInsensitiveCompare($1.title) != .orderedSame {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased()
            }
            issue = nil
            candidatePhase = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard generation == searchGeneration else { return }
            let mapped = Self.issue(error, copy: copy)
            issue = mapped
            candidatePhase = mapped.kind == .offline ? .offline : .error
            if mapped.kind == .unauthorized {
                candidatePhase = .unauthorized
                onUnauthorized()
            }
        }
    }

    private func beginMutation() -> Bool {
        guard context.canManage else {
            setIssue(.forbidden, code: "full_access_required", message: copy.readOnly)
            return false
        }
        guard !isMutating else { return false }
        isMutating = true
        return true
    }

    private func replace(_ value: ActionEntityLinkDTO) {
        if let index = links.firstIndex(where: { $0.id == value.id }) {
            links[index] = value
        } else {
            links.append(value)
        }
    }

    private func row(_ link: ActionEntityLinkDTO) -> EntityLinkRow {
        let sourceMatches = link.source.type == context.type && link.source.id == context.id
        let other = sourceMatches ? link.target : link.source
        let hidden = other.redacted || !other.accessible || other.identity == nil
        let identity = hidden ? nil : other.identity
        return EntityLinkRow(
            id: link.id,
            title: hidden ? copy.restricted : identity?.title ?? copy.restricted,
            subtitle: hidden ? nil : Self.nonEmpty(other.path) ?? Self.nonEmpty(other.subtitle),
            relation: link.relationType,
            redacted: hidden,
            supportsDependency: context.type == .task && identity?.type == .task,
            navigationTarget: identity.map {
                EntityLinkNavigationTarget(type: $0.type, id: $0.id)
            }
        )
    }

    private func handle(_ error: EntityLinkValidationError) {
        switch error {
        case .selfLink:
            setIssue(.selfLink, code: "self_link", message: copy.selfLink)
        case .dependencyRequiresTasks:
            setIssue(
                .dependencyRequiresTasks,
                code: "dependency_requires_tasks",
                message: copy.dependencyRequiresTasks
            )
        case .duplicate:
            setIssue(.duplicate, code: "duplicate", message: copy.duplicate)
        }
    }

    private func handle(_ error: Error) {
        let mapped = Self.issue(error, copy: copy)
        issue = mapped
        switch mapped.kind {
        case .unauthorized:
            phase = .unauthorized
            onUnauthorized()
        case .forbidden:
            phase = .forbidden
        case .notFound:
            phase = .notFound
        case .duplicate, .dependencyCycle, .conflict:
            phase = .conflict
        case .offline:
            phase = .offline
        case .selfLink, .dependencyRequiresTasks, .validation, .unavailable:
            phase = .error
        }
    }

    private func setIssue(_ kind: EntityLinkIssueKind, code: String, message: String) {
        issue = EntityLinkIssue(kind: kind, code: code, message: message)
        phase = kind == .forbidden ? .forbidden : .error
    }

    private static func issue(_ error: Error, copy: EntityLinkCopy) -> EntityLinkIssue {
        if let validation = error as? EntityLinkValidationError {
            switch validation {
            case .selfLink:
                return EntityLinkIssue(kind: .selfLink, code: "self_link", message: copy.selfLink)
            case .dependencyRequiresTasks:
                return EntityLinkIssue(
                    kind: .dependencyRequiresTasks,
                    code: "dependency_requires_tasks",
                    message: copy.dependencyRequiresTasks
                )
            case .duplicate:
                return EntityLinkIssue(kind: .duplicate, code: "duplicate", message: copy.duplicate)
            }
        }
        if let action = error as? RemoteActionError {
            switch action {
            case .unauthorized:
                return EntityLinkIssue(kind: .unauthorized, code: "unauthorized", message: copy.unauthorized)
            case let .forbidden(code, message):
                return EntityLinkIssue(kind: .forbidden, code: code, message: message)
            case let .notFound(code, message):
                return EntityLinkIssue(kind: .notFound, code: code, message: message)
            case let .versionConflict(code, message):
                return EntityLinkIssue(kind: .conflict, code: code, message: message)
            case let .dependencyBlocked(code, message):
                return EntityLinkIssue(kind: .conflict, code: code, message: message)
            case let .validation(message, _):
                let lower = message.lowercased()
                if lower.contains("itself") || lower.contains("самим собой") {
                    return EntityLinkIssue(kind: .selfLink, code: "self_link", message: copy.selfLink)
                }
                if lower.contains("only between tasks") || lower.contains("только между задачами") {
                    return EntityLinkIssue(
                        kind: .dependencyRequiresTasks,
                        code: "dependency_requires_tasks",
                        message: copy.dependencyRequiresTasks
                    )
                }
                return EntityLinkIssue(kind: .validation, code: "validation_error", message: message)
            case let .conflict(code, message):
                if code == "dependency_cycle" {
                    return EntityLinkIssue(kind: .dependencyCycle, code: code, message: copy.dependencyCycle)
                }
                if message.localizedCaseInsensitiveContains("already exists") {
                    return EntityLinkIssue(kind: .duplicate, code: code, message: copy.duplicate)
                }
                return EntityLinkIssue(kind: .conflict, code: code, message: message)
            case let .retryable(code, message):
                return EntityLinkIssue(
                    kind: isOfflineTransport(code: code) ? .offline : .unavailable,
                    code: code,
                    message: message
                )
            case .cancelled:
                return EntityLinkIssue(kind: .unavailable, code: "cancelled", message: copy.unavailable)
            case let .unexpected(_, code, message):
                return EntityLinkIssue(kind: .unavailable, code: code, message: message)
            }
        }
        if let api = error as? APIError {
            switch api.statusCode {
            case 401: return EntityLinkIssue(kind: .unauthorized, code: api.code, message: copy.unauthorized)
            case 403: return EntityLinkIssue(kind: .forbidden, code: api.code, message: api.message)
            case 404: return EntityLinkIssue(kind: .notFound, code: api.code, message: api.message)
            case 409 where api.code == "dependency_cycle":
                return EntityLinkIssue(kind: .dependencyCycle, code: api.code, message: copy.dependencyCycle)
            case 409:
                return EntityLinkIssue(kind: .conflict, code: api.code, message: api.message)
            case 400, 422:
                return EntityLinkIssue(kind: .validation, code: api.code, message: api.message)
            default:
                return EntityLinkIssue(kind: .unavailable, code: api.code, message: api.message)
            }
        }
        if error is URLError {
            return EntityLinkIssue(kind: .offline, code: "network_error", message: copy.offline)
        }
        return EntityLinkIssue(kind: .unavailable, code: "unavailable", message: copy.unavailable)
    }

    private static func uniqueCandidates(_ values: [EntityLinkCandidate]) -> [EntityLinkCandidate] {
        var seen: Set<String> = []
        return values.filter {
            seen.insert("\($0.type.rawValue):\($0.id.uuidString.lowercased())").inserted
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func invalidatePendingLoad() {
        loadGeneration &+= 1
    }

    private static func isOfflineTransport(code: String) -> Bool {
        code == "network_error"
            || code.hasPrefix("network_")
            || code == "transport_error"
            || code == "non_http_response"
    }
}
