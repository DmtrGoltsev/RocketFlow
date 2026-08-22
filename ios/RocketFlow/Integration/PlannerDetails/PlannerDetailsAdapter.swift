import Foundation

enum PlannerDetailsEditorSeed: Equatable, Sendable {
    case folder(FolderEditorDraft, parentFolderID: UUID?)
    case goal(GoalEditorDraft, folderID: UUID)
    case task(
        TaskEditorDraft,
        goalID: UUID,
        access: TaskEditorAccess,
        isInFocus: Bool
    )
    case idea(IdeaEditorDraft, folderID: UUID)
    case ideaHistory(IdeaHistoryEditorDraft, ideaID: UUID)
    case note(NoteEditorDraft, folderID: UUID)
}

protocol PlannerDetailsCommandServing: Sendable {
    func move(
        _ reference: DetailEntityReference,
        toParentID: UUID?
    ) async throws -> DetailEntityReference
    func clone(
        _ reference: DetailEntityReference,
        toParentID: UUID?
    ) async throws -> DetailEntityReference
    func invite(
        _ reference: DetailEntityReference,
        request: SharingInvitationRequest
    ) async throws -> ShareInvitationDTO
    func rescheduleTask(localID: UUID, plannedAt: Date) async throws
}

protocol PlannerDetailsEditorSeedLoading: Sendable {
    func editorSeed(for route: DetailEditorRoute) async throws -> PlannerDetailsEditorSeed
}

protocol PlannerDetailsResourceIDResolving: Sendable {
    func localID(kind: DetailEntityKind, serverID: UUID) async throws -> UUID
    func serverID(kind: DetailEntityKind, localID: UUID) async throws -> UUID
}

actor PlannerDetailsAdapter: PlannerLoading, PlannerActionPerforming,
    DetailLoading, DetailMutationPerforming, EditorSaving,
    EditorTagCreating, EditorFocusUpdating, PlannerDetailsCommandServing,
    PlannerDetailsEditorSeedLoading, PlannerDetailsResourceIDResolving {

    struct Availability: Sendable {
        let source: PlannerLoadSource
        let detailSource: DetailLoadSource
        let warning: String?
        let createTaskGoalIDs: Set<UUID>
    }

    let repository: any PlanningRepository
    let persistence: any PlannerDetailsPersistenceAccessing
    let account: PlannerDetailsAccountContext
    let refresher: (any PlannerDetailsRefreshing)?
    let remote: (any PlannerDetailsRemoteActioning)?
    let sharing: (any PlannerDetailsSharingAccessing)?
    let focus: (any FocusRepositoryServing)?
    let network: any NetworkMonitoring
    let makeID: @Sendable () -> UUID
    var activeRemoteOperations: Set<PlannerDetailsRemoteOperationKey> = []

    init(
        repository: any PlanningRepository,
        persistence: any PlannerDetailsPersistenceAccessing,
        account: PlannerDetailsAccountContext,
        network: any NetworkMonitoring,
        refresher: (any PlannerDetailsRefreshing)? = nil,
        remote: (any PlannerDetailsRemoteActioning)? = nil,
        sharing: (any PlannerDetailsSharingAccessing)? = nil,
        focus: (any FocusRepositoryServing)? = nil,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.repository = repository
        self.persistence = persistence
        self.account = account
        self.network = network
        self.refresher = refresher
        self.remote = remote
        self.sharing = sharing
        self.focus = focus
        self.makeID = makeID
    }

    func loadPlanner() async throws -> PlannerLoadResult {
        do {
            let availability = try await refreshAvailability()
            let local = try await repository.snapshot()
            return PlannerLoadResult(
                snapshot: plannerSnapshot(local, createTaskGoalIDs: availability.createTaskGoalIDs),
                source: availability.source,
                warning: mergedWarning(
                    availability.warning,
                    pendingCount: local.pendingCount,
                    conflictCount: local.conflictCount
                )
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PlannerDetailsErrorTranslator.map(error)
        }
    }

    func loadDetail(_ reference: DetailEntityReference) async throws -> DetailLoadResult {
        do {
            let availability = try await refreshAvailability()
            let local = try await repository.snapshot()
            let content = try await detailContent(
                reference,
                snapshot: local,
                createTaskGoalIDs: availability.createTaskGoalIDs
            )
            return DetailLoadResult(
                content: content,
                source: availability.detailSource,
                hasPendingChanges: try await persistence.hasPendingMutation(
                    kind: PlanningEntityKind(reference.kind),
                    localID: reference.id
                )
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PlannerDetailsErrorTranslator.detailFailure(error)
        }
    }

    func editorSeed(for route: DetailEditorRoute) async throws -> PlannerDetailsEditorSeed {
        do {
            let snapshot = try await repository.snapshot()
            switch route {
            case let .edit(reference):
                return try await editorSeed(reference, snapshot: snapshot)
            case let .editIdeaHistory(ideaID, noteID):
                let notes = try await persistence.ideaNotes(ideaID: ideaID)
                guard let note = notes.first(where: { $0.id == noteID }) else {
                    throw PlannerDetailsIntegrationError.notFound(kind: .ideaNote, id: noteID)
                }
                return .ideaHistory(
                    IdeaHistoryEditorDraft(
                        eventType: note.eventType,
                        body: note.body,
                        metadata: metadataStrings(note.metadata)
                    ),
                    ideaID: ideaID
                )
            case .create, .move, .clone, .share, .links, .reschedule:
                throw PlannerDetailsIntegrationError.unsupported(
                    operation: "editor_seed_requires_resolved_create_or_edit_context"
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PlannerDetailsErrorTranslator.map(error)
        }
    }

    private func editorSeed(
        _ reference: DetailEntityReference,
        snapshot: PlanningSnapshot
    ) async throws -> PlannerDetailsEditorSeed {
        switch reference.kind {
        case .folder:
            guard let value = snapshot.folders.first(where: { $0.id == reference.id }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .folder, id: reference.id)
            }
            return .folder(
                FolderEditorDraft(name: value.name, description: value.description),
                parentFolderID: value.parentFolderId
            )
        case .goal:
            guard let value = snapshot.goals.first(where: { $0.id == reference.id }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .goal, id: reference.id)
            }
            return .goal(
                GoalEditorDraft(
                    name: value.name,
                    description: value.description,
                    status: DetailTaskStatus(value.status)
                ),
                folderID: value.folderId
            )
        case .task:
            guard let value = snapshot.tasks.first(where: { $0.id == reference.id }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .task, id: reference.id)
            }
            let allTags = try await persistence.allTags()
            let assigned = Set(value.tags.map(\.id))
            let isOwner = value.creatorUserId == nil || value.creatorUserId == account.currentUserID
            let access = value.shared && !value.fullAccess
                ? TaskEditorAccess.statusOnly
                : TaskEditorAccess(
                    mutationScope: .full,
                    canManageRecurrence: isOwner,
                    canManageChecklist: true,
                    canManageTags: true
                )
            return .task(
                TaskEditorDraft(
                    title: value.title,
                    description: value.description,
                    status: DetailTaskStatus(value.status),
                    type: DetailTaskType(value.type),
                    effort: value.effort,
                    plannedAt: value.plannedTime,
                    dueAt: value.dueTime,
                    recurrence: TaskRecurrenceEditorDraft(
                        value.recurrence,
                        plannedAt: value.plannedTime,
                        dueAt: value.dueTime
                    ),
                    checklist: value.checklistItems.map {
                        ChecklistEditorItemDraft(
                            id: $0.id,
                            serverID: $0.id,
                            text: $0.text,
                            checked: $0.checked
                        )
                    },
                    tags: allTags.map {
                        TagEditorItemDraft(
                            id: $0.id,
                            name: $0.name,
                            colorHex: $0.color,
                            assigned: assigned.contains($0.id)
                        )
                    }
                ),
                goalID: value.goalId,
                access: access,
                isInFocus: try await isTaskInFocus(value)
            )
        case .idea:
            guard let value = snapshot.ideas.first(where: { $0.id == reference.id }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .idea, id: reference.id)
            }
            return .idea(
                IdeaEditorDraft(
                    title: value.title,
                    body: value.body,
                    status: value.status,
                    allowAuthorHistoryEdits: value.allowAuthorNoteEdits
                ),
                folderID: value.folderId
            )
        case .note:
            guard let value = snapshot.notes.first(where: { $0.id == reference.id }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .note, id: reference.id)
            }
            return .note(
                NoteEditorDraft(title: value.title, body: value.body),
                folderID: value.folderId
            )
        }
    }

    private func refreshAvailability() async throws -> Availability {
        var isCurrent = false
        var warnings: [String] = []
        if let refresher {
            let result = try await refresher.refreshPlannerDetails()
            isCurrent = result.isCurrent
            if let warning = result.warning { warnings.append(warning) }
        } else {
            warnings.append("sync_adapter_not_configured")
        }

        var createTaskGoalIDs = try await persistence.cachedCreateTaskGoalIDs()
        if isCurrent, let sharing, await network.isConnected() {
            do {
                let response = try await sharing.sharedResources()
                createTaskGoalIDs = try await persistence.applySharedResources(
                    response
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let mapped = PlannerDetailsErrorTranslator.map(error)
                if mapped == .unauthorized { throw mapped }
                warnings.append("shared_resources_unavailable")
            }
        }
        let warning = warnings.isEmpty ? nil : warnings.joined(separator: ",")
        return Availability(
            source: isCurrent ? .network : .offlineCache,
            detailSource: isCurrent ? .network : .offlineCache,
            warning: warning,
            createTaskGoalIDs: createTaskGoalIDs
        )
    }

    func plannerSnapshot(
        _ value: PlanningSnapshot,
        createTaskGoalIDs: Set<UUID>
    ) -> PlannerSnapshot {
        let items = newest(value.folders).map { PlannerItemViewData(folder: $0) }
            + newest(value.goals).map {
                PlannerItemViewData(
                    goal: $0,
                    legacyCreateTaskAllowed: createTaskGoalIDs.contains($0.id)
                )
            }
            + newest(value.tasks).map { PlannerItemViewData(task: $0) }
            + newest(value.ideas).map { idea in
                PlannerItemViewData(
                    reference: PlannerItemReference(kind: .idea, id: idea.id),
                    parent: PlannerItemReference(kind: .folder, id: idea.folderId),
                    title: idea.title,
                    subtitle: idea.body,
                    searchText: "\(idea.body) \(idea.status)",
                    createdAt: idea.createdAt,
                    isArchived: idea.archived,
                    isShared: idea.shared,
                    fullAccess: idea.fullAccess,
                    canDelete: idea.creatorUserId.map { $0 == account.currentUserID } ?? !idea.shared
                )
            }
            + newest(value.notes).map { PlannerItemViewData(note: $0) }
        return PlannerSnapshot(
            items: items.sorted(by: newestViewData),
            createTaskGoalIDs: createTaskGoalIDs
        )
    }

    private func detailContent(
        _ reference: DetailEntityReference,
        snapshot: PlanningSnapshot,
        createTaskGoalIDs: Set<UUID>
    ) async throws -> DetailContent {
        switch reference.kind {
        case .folder:
            guard let folder = snapshot.folders.first(where: { $0.id == reference.id }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .folder, id: reference.id)
            }
            let children = (
                snapshot.folders.filter { $0.parentFolderId == folder.id }.map(detailChild)
                    + snapshot.goals.filter { $0.folderId == folder.id }.map(detailChild)
                    + snapshot.ideas.filter { $0.folderId == folder.id }.map(detailChild)
                    + snapshot.notes.filter { $0.folderId == folder.id }.map(detailChild)
            ).sorted(by: newestChild)
            return .folder(
                FolderDetailViewData(
                    id: folder.id,
                    parentFolderID: folder.parentFolderId,
                    name: folder.name,
                    description: folder.description,
                    activitySummary: "\(children.count)",
                    shared: folder.shared,
                    fullAccess: folder.fullAccess,
                    capabilities: DetailCapabilityPolicy.folder(
                        shared: folder.shared,
                        fullAccess: folder.fullAccess
                    ),
                    children: children
                )
            )
        case .goal:
            guard let goal = snapshot.goals.first(where: { $0.id == reference.id }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .goal, id: reference.id)
            }
            let links = try await detailLinks(kind: .goal, localID: goal.id)
            return .goal(
                GoalDetailViewData(
                    id: goal.id,
                    folderID: goal.folderId,
                    name: goal.name,
                    description: goal.description,
                    status: DetailTaskStatus(goal.status),
                    shared: goal.shared,
                    fullAccess: goal.fullAccess,
                    capabilities: DetailCapabilityPolicy.goal(
                        shared: goal.shared,
                        fullAccess: goal.fullAccess,
                        canCreateTask: createTaskGoalIDs.contains(goal.id)
                    ),
                    tasks: snapshot.tasks.filter { $0.goalId == goal.id }.map(detailChild).sorted(by: newestChild),
                    links: links
                )
            )
        case .task:
            guard let task = snapshot.tasks.first(where: { $0.id == reference.id }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .task, id: reference.id)
            }
            let isOwner = task.creatorUserId == nil || task.creatorUserId == account.currentUserID
            return .task(
                TaskDetailViewData(
                    id: task.id,
                    goalID: task.goalId,
                    title: task.title,
                    description: task.description,
                    status: DetailTaskStatus(task.status),
                    type: DetailTaskType(task.type),
                    effort: task.effort,
                    plannedAt: task.plannedTime,
                    dueAt: task.dueTime,
                    shared: task.shared,
                    fullAccess: task.fullAccess,
                    isOwner: isOwner,
                    capabilities: DetailCapabilityPolicy.task(
                        shared: task.shared,
                        fullAccess: task.fullAccess,
                        isOwner: isOwner
                    ),
                    checklist: task.checklistItems.map {
                        DetailChecklistItemViewData(
                            id: $0.id,
                            text: $0.text,
                            checked: $0.checked,
                            displayOrder: $0.displayOrder,
                            createdAt: $0.createdAt
                        )
                    },
                    tags: task.tags.map {
                        DetailTagViewData(id: $0.id, name: $0.name, colorHex: $0.color, assigned: true)
                    },
                    recurrence: task.recurrence.map(DetailRecurrenceViewData.init),
                    links: try await detailLinks(kind: .task, localID: task.id),
                    isInFocus: try await isTaskInFocus(task),
                    version: task.version
                )
            )
        case .idea:
            guard let idea = snapshot.ideas.first(where: { $0.id == reference.id }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .idea, id: reference.id)
            }
            let isCreator = idea.creatorUserId.map { $0 == account.currentUserID } ?? !idea.shared
            let ideaNotes = try await persistence.ideaNotes(ideaID: idea.id)
            let history = ideaNotes.map {
                DetailIdeaHistoryViewData(
                    id: $0.id,
                    ideaID: idea.id,
                    eventType: $0.eventType,
                    body: $0.body,
                    metadata: metadataStrings($0.metadata),
                    authorName: $0.authorName,
                    authorUserID: $0.authorUserId,
                    isAuthoredByCurrentUser: $0.authorUserId == account.currentUserID,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    version: $0.version
                )
            }
            return .idea(
                IdeaDetailViewData(
                    id: idea.id,
                    folderID: idea.folderId,
                    title: idea.title,
                    body: idea.body,
                    status: idea.status,
                    allowAuthorHistoryEdits: idea.allowAuthorNoteEdits,
                    shared: idea.shared,
                    fullAccess: idea.fullAccess,
                    isCreator: isCreator,
                    capabilities: DetailCapabilityPolicy.idea(
                        shared: idea.shared,
                        fullAccess: idea.fullAccess,
                        isCreator: isCreator
                    ),
                    history: history,
                    links: try await detailLinks(kind: .idea, localID: idea.id)
                )
            )
        case .note:
            guard let note = snapshot.notes.first(where: { $0.id == reference.id }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .note, id: reference.id)
            }
            return .note(
                NoteDetailViewData(
                    id: note.id,
                    folderID: note.folderId,
                    title: note.title,
                    body: note.body,
                    authorName: note.authorName,
                    shared: note.shared,
                    fullAccess: note.fullAccess,
                    capabilities: DetailCapabilityPolicy.note(
                        shared: note.shared,
                        fullAccess: note.fullAccess
                    ),
                    links: try await detailLinks(kind: .note, localID: note.id)
                )
            )
        }
    }

    private func detailLinks(
        kind: LinkedEntityType,
        localID: UUID
    ) async throws -> [DetailLinkViewData] {
        let links = try await persistence.links(kind: kind, localID: localID)
        return links.map { link in
            let sourceMatches = link.source.identity?.type == kind && link.source.identity?.id == localID
            let other = sourceMatches ? link.target : link.source
            let target = other.identity.flatMap { identity in
                DetailEntityReference(kind: DetailEntityKind(identity.type), id: identity.id)
            }
            return DetailLinkViewData(
                id: link.id,
                target: target,
                title: other.identity?.title ?? "",
                subtitle: other.subtitle ?? other.path ?? "",
                relation: DetailRelationKind(link.relationType),
                redacted: other.redacted
            )
        }
    }

    private func isTaskInFocus(_ task: TaskDTO) async throws -> Bool {
        guard let focus else { return false }
        guard let remoteTaskID = try? await persistence.remoteID(for: .task, localID: task.id) else {
            return false
        }
        let result = try await focus.loadCurrent(
            accountID: account.accountID,
            timezone: account.timezone
        )
        return result.period?.items.contains {
            !$0.historyOnly && $0.taskId == remoteTaskID
        } == true
    }

    func currentDetail(_ reference: DetailEntityReference) async throws -> DetailContent {
        let snapshot = try await repository.snapshot()
        return try await detailContent(
            reference,
            snapshot: snapshot,
            createTaskGoalIDs: try await persistence.cachedCreateTaskGoalIDs()
        )
    }

    func localID(
        kind: DetailEntityKind,
        serverID: UUID
    ) async throws -> UUID {
        guard let local = try await persistence.localID(
            for: PlanningEntityKind(kind),
            remoteID: serverID
        ) else {
            throw PlannerDetailsIntegrationError.missingMapping(
                kind: PlanningEntityKind(kind),
                id: serverID
            )
        }
        return local
    }

    func serverID(kind: DetailEntityKind, localID: UUID) async throws -> UUID {
        do {
            return try await persistence.remoteID(
                for: PlanningEntityKind(kind),
                localID: localID
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PlannerDetailsErrorTranslator.map(error)
        }
    }

    private func mergedWarning(
        _ warning: String?,
        pendingCount: Int,
        conflictCount: Int
    ) -> String? {
        var values = warning.map { [$0] } ?? []
        if pendingCount > 0 { values.append("pending:\(pendingCount)") }
        if conflictCount > 0 { values.append("conflicts:\(conflictCount)") }
        return values.isEmpty ? nil : values.joined(separator: ",")
    }

    private func newest<Value: Identifiable>(_ values: [Value]) -> [Value] where Value.ID == UUID {
        values.sorted { lhs, rhs in
            let left = createdAt(lhs)
            let right = createdAt(rhs)
            if left != right { return left > right }
            return lhs.id.uuidString.lowercased() > rhs.id.uuidString.lowercased()
        }
    }

    private func createdAt<Value>(_ value: Value) -> Date {
        switch value {
        case let item as FolderDTO: item.createdAt
        case let item as GoalDTO: item.createdAt
        case let item as TaskDTO: item.createdAt
        case let item as IdeaDTO: item.createdAt
        case let item as NoteDTO: item.createdAt
        default: .distantPast
        }
    }

    private func newestViewData(_ lhs: PlannerItemViewData, _ rhs: PlannerItemViewData) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.reference.id.uuidString.lowercased() > rhs.reference.id.uuidString.lowercased()
    }

    private func newestChild(_ lhs: DetailChildViewData, _ rhs: DetailChildViewData) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.reference.id.uuidString.lowercased() > rhs.reference.id.uuidString.lowercased()
    }

    private func metadataStrings(_ metadata: [String: JSONValue]) -> [String: String] {
        metadata.reduce(into: [:]) { result, entry in
            if case let .string(value) = entry.value {
                result[entry.key] = value
            } else if let data = try? WireJSON.encoder().encode(entry.value) {
                result[entry.key] = String(data: data, encoding: .utf8)
            }
        }
    }
}

private func detailChild(_ value: FolderDTO) -> DetailChildViewData {
    DetailChildViewData(
        reference: DetailEntityReference(kind: .folder, id: value.id),
        title: value.name,
        subtitle: value.description,
        createdAt: value.createdAt
    )
}

private func detailChild(_ value: GoalDTO) -> DetailChildViewData {
    DetailChildViewData(
        reference: DetailEntityReference(kind: .goal, id: value.id),
        title: value.name,
        subtitle: value.description,
        createdAt: value.createdAt
    )
}

private func detailChild(_ value: TaskDTO) -> DetailChildViewData {
    DetailChildViewData(
        reference: DetailEntityReference(kind: .task, id: value.id),
        title: value.title,
        subtitle: value.description,
        createdAt: value.createdAt
    )
}

private func detailChild(_ value: IdeaDTO) -> DetailChildViewData {
    DetailChildViewData(
        reference: DetailEntityReference(kind: .idea, id: value.id),
        title: value.title,
        subtitle: value.body,
        createdAt: value.createdAt
    )
}

private func detailChild(_ value: NoteDTO) -> DetailChildViewData {
    DetailChildViewData(
        reference: DetailEntityReference(kind: .note, id: value.id),
        title: value.title,
        subtitle: value.body,
        createdAt: value.createdAt
    )
}

private extension DetailTaskStatus {
    init(_ value: PlanningStatus) {
        self = DetailTaskStatus(rawValue: value.rawValue) ?? .todo
    }
}

private extension DetailTaskType {
    init(_ value: TaskType) {
        self = DetailTaskType(rawValue: value.rawValue) ?? .green
    }
}

private extension DetailRecurrenceMode {
    init(_ value: RecurrenceMode) {
        self = DetailRecurrenceMode(rawValue: value.rawValue) ?? .daily
    }
}

private extension DetailWeekday {
    init(_ value: Weekday) {
        self = DetailWeekday(rawValue: value.rawValue) ?? .monday
    }
}

private extension TaskRecurrenceEditorDraft {
    init(_ value: RecurrenceDTO?, plannedAt: Date?, dueAt: Date?) {
        let anchorSource: TaskRecurrenceAnchorSource?
        if value?.startAt == plannedAt, plannedAt != nil {
            anchorSource = .planned
        } else if value?.startAt == dueAt, dueAt != nil {
            anchorSource = .due
        } else {
            anchorSource = nil
        }
        self.init(
            mode: value.map { DetailRecurrenceMode($0.mode) },
            interval: value?.interval ?? 1,
            weekdays: Set(value?.daysOfWeek.map(DetailWeekday.init) ?? []),
            dayOfMonth: value?.dayOfMonth,
            endAt: value?.endAt,
            anchorSource: anchorSource,
            startAt: value?.startAt
        )
    }
}

private extension DetailRecurrenceViewData {
    init(_ value: RecurrenceDTO) {
        self.init(
            mode: DetailRecurrenceMode(value.mode),
            interval: value.interval,
            weekdays: Set(value.daysOfWeek.map(DetailWeekday.init)),
            dayOfMonth: value.dayOfMonth,
            anchor: value.startAt,
            end: value.endAt,
            active: value.active
        )
    }
}

private extension DetailEntityKind {
    init(_ value: LinkedEntityType) {
        switch value {
        case .goal: self = .goal
        case .task: self = .task
        case .idea: self = .idea
        case .note: self = .note
        }
    }
}

private extension DetailRelationKind {
    init(_ value: EntityRelationType) {
        switch value {
        case .related: self = .related
        case .dependency: self = .dependency
        }
    }
}
