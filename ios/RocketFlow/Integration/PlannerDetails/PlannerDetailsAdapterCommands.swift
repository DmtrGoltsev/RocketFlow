import Foundation

extension PlannerDetailsAdapter {
    func move(
        _ reference: DetailEntityReference,
        toParentID: UUID?
    ) async throws -> DetailEntityReference {
        do {
            let snapshot = try await repository.snapshot()
            switch reference.kind {
            case .folder:
                guard let value = snapshot.folders.first(where: { $0.id == reference.id }) else {
                    throw PlannerDetailsIntegrationError.notFound(kind: .folder, id: reference.id)
                }
                try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
                if let toParentID {
                    _ = try requireWritableFolder(toParentID, snapshot: snapshot)
                }
                try ensureNoActiveRemoteOperation(kind: .folder, localID: value.id)
                try await repository.moveFolder(id: value.id, to: toParentID)
            case .goal:
                guard let value = snapshot.goals.first(where: { $0.id == reference.id }),
                      let toParentID else {
                    throw PlannerDetailsIntegrationError.validation(
                        message: "Goal move requires a destination folder.",
                        fields: ["targetFolderId": "required"]
                    )
                }
                try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
                _ = try requireWritableFolder(toParentID, snapshot: snapshot)
                try ensureNoActiveRemoteOperation(kind: .goal, localID: value.id)
                try await repository.moveGoal(id: value.id, to: toParentID)
            case .task:
                guard let value = snapshot.tasks.first(where: { $0.id == reference.id }),
                      let toParentID else {
                    throw PlannerDetailsIntegrationError.validation(
                        message: "Task move requires a destination goal.",
                        fields: ["targetGoalId": "required"]
                    )
                }
                try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
                _ = try requireWritableGoal(toParentID, snapshot: snapshot)
                try ensureNoActiveRemoteOperation(kind: .task, localID: value.id)
                try await repository.moveTask(id: value.id, to: toParentID)
            case .idea:
                guard let value = snapshot.ideas.first(where: { $0.id == reference.id }),
                      let toParentID else {
                    throw PlannerDetailsIntegrationError.validation(
                        message: "Idea move requires a destination folder.",
                        fields: ["targetFolderId": "required"]
                    )
                }
                try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
                _ = try requireWritableFolder(toParentID, snapshot: snapshot)
                let remote = try await requireRemote(operation: "idea.move")
                let lease = try await beginRemoteOperation(kind: .idea, localID: value.id)
                defer { endRemoteOperation(lease) }
                let valueRemoteID = try await persistence.remoteID(for: .idea, localID: value.id)
                let folderRemoteID = try await persistence.remoteID(for: .folder, localID: toParentID)
                let moved = try await remote.moveIdea(
                    id: valueRemoteID,
                    request: MoveIdeaRequestDTO(
                        targetFolderId: folderRemoteID,
                        version: value.version
                    )
                )
                try requireApplied(
                    try await persist(moved, localID: value.id, expectedGeneration: lease.generation)
                )
            case .note:
                guard let value = snapshot.notes.first(where: { $0.id == reference.id }),
                      let toParentID else {
                    throw PlannerDetailsIntegrationError.validation(
                        message: "Note move requires a destination folder.",
                        fields: ["targetFolderId": "required"]
                    )
                }
                try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
                _ = try requireWritableFolder(toParentID, snapshot: snapshot)
                let remote = try await requireRemote(operation: "note.move")
                let lease = try await beginRemoteOperation(kind: .note, localID: value.id)
                defer { endRemoteOperation(lease) }
                let valueRemoteID = try await persistence.remoteID(for: .note, localID: value.id)
                let folderRemoteID = try await persistence.remoteID(for: .folder, localID: toParentID)
                let moved = try await remote.moveNote(
                    id: valueRemoteID,
                    request: MoveNoteRequestDTO(
                        targetFolderId: folderRemoteID,
                        version: value.version
                    )
                )
                try requireApplied(
                    try await persist(moved, localID: value.id, expectedGeneration: lease.generation)
                )
            }
            return reference
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PlannerDetailsErrorTranslator.map(error)
        }
    }

    func clone(
        _ reference: DetailEntityReference,
        toParentID: UUID?
    ) async throws -> DetailEntityReference {
        do {
            let remote = try await requireRemote(operation: "resource.clone")
            let snapshot = try await repository.snapshot()
            let localID = makeID()
            switch reference.kind {
            case .folder:
                guard let value = snapshot.folders.first(where: { $0.id == reference.id }) else {
                    throw PlannerDetailsIntegrationError.notFound(kind: .folder, id: reference.id)
                }
                try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
                try await requireNoPending(kind: .folder, localID: value.id)
                if let toParentID {
                    _ = try requireWritableFolder(toParentID, snapshot: snapshot)
                }
                let sourceRemoteID = try await persistence.remoteID(for: .folder, localID: value.id)
                let targetRemoteID = try await optionalRemoteID(kind: .folder, localID: toParentID)
                let cloned = try await remote.cloneFolder(
                    id: sourceRemoteID,
                    request: CloneFolderRequestDTO(
                        targetFolderId: targetRemoteID,
                        name: nil,
                        includeChildren: true
                    )
                )
                try await persist(cloned, localID: localID)
            case .goal:
                guard let value = snapshot.goals.first(where: { $0.id == reference.id }) else {
                    throw PlannerDetailsIntegrationError.notFound(kind: .goal, id: reference.id)
                }
                try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
                try await requireNoPending(kind: .goal, localID: value.id)
                let target = toParentID ?? value.folderId
                _ = try requireWritableFolder(target, snapshot: snapshot)
                let sourceRemoteID = try await persistence.remoteID(for: .goal, localID: value.id)
                let targetRemoteID = try await persistence.remoteID(for: .folder, localID: target)
                let cloned = try await remote.cloneGoal(
                    id: sourceRemoteID,
                    request: CloneGoalRequestDTO(
                        targetFolderId: targetRemoteID,
                        name: nil
                    )
                )
                try await persist(cloned, localID: localID)
            case .task:
                guard let value = snapshot.tasks.first(where: { $0.id == reference.id }) else {
                    throw PlannerDetailsIntegrationError.notFound(kind: .task, id: reference.id)
                }
                try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
                try await requireNoPending(kind: .task, localID: value.id)
                let target = toParentID ?? value.goalId
                _ = try requireWritableGoal(target, snapshot: snapshot)
                let sourceRemoteID = try await persistence.remoteID(for: .task, localID: value.id)
                let targetRemoteID = try await persistence.remoteID(for: .goal, localID: target)
                let cloned = try await remote.cloneTask(
                    id: sourceRemoteID,
                    request: CloneTaskRequestDTO(
                        targetGoalId: targetRemoteID,
                        title: nil,
                        includeTags: true
                    )
                )
                try await persist(cloned, localID: localID)
            case .idea:
                guard let value = snapshot.ideas.first(where: { $0.id == reference.id }) else {
                    throw PlannerDetailsIntegrationError.notFound(kind: .idea, id: reference.id)
                }
                try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
                try await requireNoPending(kind: .idea, localID: value.id)
                let target = toParentID ?? value.folderId
                _ = try requireWritableFolder(target, snapshot: snapshot)
                let sourceRemoteID = try await persistence.remoteID(for: .idea, localID: value.id)
                let targetRemoteID = try await persistence.remoteID(for: .folder, localID: target)
                let cloned = try await remote.cloneIdea(
                    id: sourceRemoteID,
                    request: CloneIdeaRequestDTO(
                        targetFolderId: targetRemoteID,
                        title: nil
                    )
                )
                try await persist(cloned, localID: localID)
            case .note:
                guard let value = snapshot.notes.first(where: { $0.id == reference.id }) else {
                    throw PlannerDetailsIntegrationError.notFound(kind: .note, id: reference.id)
                }
                try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
                try await requireNoPending(kind: .note, localID: value.id)
                let target = toParentID ?? value.folderId
                _ = try requireWritableFolder(target, snapshot: snapshot)
                let sourceRemoteID = try await persistence.remoteID(for: .note, localID: value.id)
                let targetRemoteID = try await persistence.remoteID(for: .folder, localID: target)
                let cloned = try await remote.cloneNote(
                    id: sourceRemoteID,
                    request: CloneNoteRequestDTO(
                        targetFolderId: targetRemoteID,
                        title: nil
                    )
                )
                try await persist(cloned, localID: localID)
            }
            return DetailEntityReference(kind: reference.kind, id: localID)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PlannerDetailsErrorTranslator.map(error)
        }
    }

    func invite(
        _ reference: DetailEntityReference,
        request: SharingInvitationRequest
    ) async throws -> ShareInvitationDTO {
        do {
            guard await network.isConnected() else {
                throw PlannerDetailsIntegrationError.networkRequired
            }
            guard let sharing else {
                throw PlannerDetailsIntegrationError.unsupported(operation: "sharing.adapter_missing")
            }
            try await requireShareAccess(reference)
            let resource: ShareableResourceKind
            switch reference.kind {
            case .folder: resource = .folder
            case .goal: resource = .goal
            case .task: resource = .task
            case .idea: resource = .idea
            case .note:
                throw PlannerDetailsIntegrationError.unsupported(operation: "note.direct_share")
            }
            let remoteID = try await persistence.remoteID(
                for: PlanningEntityKind(reference.kind),
                localID: reference.id
            )
            return try await sharing.createInvitation(
                resource: resource,
                id: remoteID,
                request: request
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PlannerDetailsErrorTranslator.map(error)
        }
    }

    func rescheduleTask(localID: UUID, plannedAt: Date) async throws {
        do {
            let snapshot = try await repository.snapshot()
            guard let task = snapshot.tasks.first(where: { $0.id == localID }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .task, id: localID)
            }
            try requireFullAccess(shared: task.shared, fullAccess: task.fullAccess)
            let lease = try await beginRemoteOperation(kind: .task, localID: localID)
            defer { endRemoteOperation(lease) }
            let remote = try await requireRemote(operation: "task.reschedule")
            let remoteID = try await persistence.remoteID(for: .task, localID: localID)
            let response = try await remote.moveTask(id: remoteID, plannedTime: plannedAt)
            try requireApplied(
                try await persistence.applyTaskMoveGuarded(
                    localID: localID,
                    response: response,
                    expectedGeneration: lease.generation
                )
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PlannerDetailsErrorTranslator.map(error)
        }
    }

    private func optionalRemoteID(
        kind: PlanningEntityKind,
        localID: UUID?
    ) async throws -> UUID? {
        guard let localID else { return nil }
        return try await persistence.remoteID(for: kind, localID: localID)
    }

    private func requireShareAccess(_ reference: DetailEntityReference) async throws {
        let snapshot = try await repository.snapshot()
        switch reference.kind {
        case .folder:
            guard let value = snapshot.folders.first(where: { $0.id == reference.id }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .folder, id: reference.id)
            }
            try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
        case .goal:
            guard let value = snapshot.goals.first(where: { $0.id == reference.id }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .goal, id: reference.id)
            }
            try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
        case .task:
            guard let value = snapshot.tasks.first(where: { $0.id == reference.id }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .task, id: reference.id)
            }
            try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
        case .idea:
            guard let value = snapshot.ideas.first(where: { $0.id == reference.id }) else {
                throw PlannerDetailsIntegrationError.notFound(kind: .idea, id: reference.id)
            }
            try requireFullAccess(shared: value.shared, fullAccess: value.fullAccess)
        case .note:
            throw PlannerDetailsIntegrationError.unsupported(operation: "note.direct_share")
        }
    }

    private func persist(_ value: ActionFolderDTO, localID: UUID) async throws {
        let dto = PlannerDetailsDTOMapper.folder(value)
        try await persistence.bindAndApply(
            kind: .folder,
            localID: localID,
            remoteID: dto.id,
            version: dto.version,
            payloadJSON: WireJSON.encoder().encode(dto)
        )
    }

    private func persist(_ value: ActionGoalDTO, localID: UUID) async throws {
        let dto = PlannerDetailsDTOMapper.goal(value)
        try await persistence.bindAndApply(
            kind: .goal,
            localID: localID,
            remoteID: dto.id,
            version: dto.version,
            payloadJSON: WireJSON.encoder().encode(dto)
        )
    }
}
