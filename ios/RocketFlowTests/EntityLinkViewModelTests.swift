import Foundation
import XCTest
@testable import RocketFlow

@MainActor
final class EntityLinkViewModelTests: XCTestCase {
    private let contextID = UUID()

    func testRedactedRowIsNeutralNonTappableAndCannotLeakMetadata() async {
        let visibleID = UUID(), redactedID = UUID()
        let visible = link(targetID: visibleID, title: "Visible", path: "Folder / Goal")
        let redacted = link(
            id: redactedID,
            targetID: UUID(),
            title: "SECRET TITLE",
            path: "SECRET / PATH",
            accessible: false,
            redacted: true
        )
        let service = EntityLinkServiceStub(links: [visible, redacted])
        var opened: [EntityLinkNavigationTarget] = []
        let model = makeModel(service: service) { opened.append($0) }

        await model.load()
        let hidden = model.rows.first { $0.id == redactedID }
        let normal = model.rows.first { $0.id == visible.id }
        XCTAssertEqual(hidden?.title, model.copy.restricted)
        XCTAssertNil(hidden?.subtitle)
        XCTAssertNil(hidden?.navigationTarget)
        XCTAssertFalse(hidden?.isTappable ?? true)
        XCTAssertFalse(model.rows.map(\.title).contains("SECRET TITLE"))
        XCTAssertFalse(model.rows.compactMap(\.subtitle).contains("SECRET / PATH"))

        if let hidden { model.open(hidden) }
        if let normal { model.open(normal) }
        XCTAssertEqual(opened, [EntityLinkNavigationTarget(type: .task, id: visibleID)])
    }

    func testReadOnlyContextCannotPresentPickerOrMutate() async {
        let service = EntityLinkServiceStub()
        let model = makeModel(
            service: service,
            context: EntityLinkContext(
                type: .task, id: contextID, title: "Task", canManage: false
            )
        )

        model.presentPicker()
        await model.createLink(
            to: EntityLinkCandidate(id: UUID(), type: .task, title: "Other", path: nil)
        )

        XCTAssertFalse(model.isPickerPresented)
        XCTAssertEqual(model.phase, .forbidden)
        XCTAssertEqual(model.issue?.kind, .forbidden)
        let operations = await service.operations()
        XCTAssertEqual(operations, [])
    }

    func testSearchReturnsAllSupportedTypesAndDeduplicatesIdentity() async {
        let duplicated = UUID()
        let search = EntityLinkSearchStub(values: [
            EntityLinkCandidate(id: duplicated, type: .goal, title: "Goal", path: nil),
            EntityLinkCandidate(id: duplicated, type: .goal, title: "Duplicate", path: nil),
            EntityLinkCandidate(id: UUID(), type: .task, title: "Task", path: nil),
            EntityLinkCandidate(id: UUID(), type: .idea, title: "Idea", path: nil),
            EntityLinkCandidate(id: UUID(), type: .note, title: "Note", path: nil)
        ])
        let model = makeModel(service: EntityLinkServiceStub(), search: search)
        model.presentPicker()
        model.query = "launch"

        await model.searchNow()

        XCTAssertEqual(Set(model.candidates.map(\.type)), Set(LinkedEntityType.allCases))
        XCTAssertEqual(model.candidates.filter { $0.type == .goal }.count, 1)
        let queries = await search.queries()
        XCTAssertEqual(queries, ["launch"])
        XCTAssertEqual(model.candidatePhase, .loaded)
    }

    func testCreateUpdateAndConfirmedDeleteEmitExactMutationIntents() async {
        let targetID = UUID()
        let created = link(targetID: targetID, title: "Target", relation: .dependency)
        let updated = link(
            id: created.id,
            targetID: targetID,
            title: "Target",
            relation: .related,
            version: 2
        )
        let service = EntityLinkServiceStub(created: created, updated: updated)
        let model = makeModel(service: service)
        model.presentPicker()
        model.selectedRelation = .dependency

        await model.createLink(
            to: EntityLinkCandidate(id: targetID, type: .task, title: "Target", path: nil)
        )
        await model.updateRelation(linkID: created.id, relation: .related)
        model.requestDelete(linkID: created.id)
        await model.confirmDelete()

        let operations = await service.operations()
        guard case let .create(request) = operations[0],
              case let .update(id, update) = operations[1] else {
            return XCTFail("Expected create/update intents")
        }
        XCTAssertEqual(request.sourceType, .task)
        XCTAssertEqual(request.sourceId, contextID)
        XCTAssertEqual(request.targetType, .task)
        XCTAssertEqual(request.targetId, targetID)
        XCTAssertEqual(request.relationType, .dependency)
        XCTAssertEqual(id, created.id)
        XCTAssertEqual(update.relationType, .related)
        XCTAssertEqual(update.version, 1)
        XCTAssertEqual(operations[2], .delete(created.id))
        XCTAssertTrue(model.rows.isEmpty)
    }

    func testSuccessfulMutationInvalidatesOlderEntityLinkLoad() async {
        let gate = EntityLinkAsyncGate()
        let targetID = UUID()
        let created = link(targetID: targetID, title: "Fresh")
        let service = EntityLinkServiceStub(
            links: [],
            created: created,
            listGate: gate
        )
        let model = makeModel(service: service)

        let load = Task { await model.load() }
        await gate.waitUntilSuspended()
        XCTAssertTrue(model.isBusy)

        await model.createLink(
            to: EntityLinkCandidate(id: targetID, type: .task, title: "Fresh", path: nil)
        )
        await gate.release()
        await load.value

        XCTAssertEqual(model.rows.map(\.id), [created.id])
        XCTAssertEqual(model.phase, .loaded)
        let operations = await service.operations()
        XCTAssertTrue(operations.contains(.create(CreateEntityLinkRequestDTO(
            sourceType: .task,
            sourceId: contextID,
            targetType: .task,
            targetId: targetID,
            relationType: .related
        ))))
    }

    func testCycleDuplicateAndTransportErrorsMapToStableStates() async {
        let candidate = EntityLinkCandidate(id: UUID(), type: .task, title: "Target", path: nil)
        let cycle = makeModel(
            service: EntityLinkServiceStub(
                error: .conflict(code: "dependency_cycle", message: "Cycle")
            )
        )
        cycle.presentPicker()
        cycle.selectedRelation = .dependency
        await cycle.createLink(to: candidate)
        XCTAssertEqual(cycle.issue?.kind, .dependencyCycle)
        XCTAssertEqual(cycle.phase, .conflict)

        let duplicate = makeModel(
            service: EntityLinkServiceStub(
                error: .conflict(code: "conflict", message: "This link already exists.")
            )
        )
        duplicate.presentPicker()
        await duplicate.createLink(to: candidate)
        XCTAssertEqual(duplicate.issue?.kind, .duplicate)
        XCTAssertEqual(duplicate.phase, .conflict)

        var unauthorizedCount = 0
        let unauthorized = makeModel(
            service: EntityLinkServiceStub(error: .unauthorized),
            onUnauthorized: { unauthorizedCount += 1 }
        )
        await unauthorized.load()
        XCTAssertEqual(unauthorized.phase, .unauthorized)
        XCTAssertEqual(unauthorizedCount, 1)

        let offline = makeModel(
            service: EntityLinkServiceStub(
                error: .retryable(code: "network_-1009", message: "Offline")
            )
        )
        await offline.load()
        XCTAssertEqual(offline.phase, .offline)

        let unavailable = makeModel(
            service: EntityLinkServiceStub(
                error: .retryable(code: "server_error", message: "Temporarily unavailable")
            )
        )
        await unavailable.load()
        XCTAssertEqual(unavailable.phase, .error)
        XCTAssertEqual(unavailable.issue?.kind, .unavailable)
    }

    func testPermissionNotFoundAndVersionConflictMapToVisibleStates() async {
        let cases: [(RemoteActionError, EntityLinkScreenPhase, EntityLinkIssueKind)] = [
            (.forbidden(code: "forbidden", message: "No access"), .forbidden, .forbidden),
            (.notFound(code: "not_found", message: "Missing"), .notFound, .notFound),
            (.versionConflict(code: "version_conflict", message: "Changed"), .conflict, .conflict),
            (.unexpected(statusCode: 500, code: "server_error", message: "Down"), .error, .unavailable)
        ]

        for (error, expectedPhase, expectedIssue) in cases {
            let model = makeModel(service: EntityLinkServiceStub(error: error))
            await model.load()
            XCTAssertEqual(model.phase, expectedPhase)
            XCTAssertEqual(model.issue?.kind, expectedIssue)
        }
    }

    private func makeModel(
        service: EntityLinkServiceStub,
        search: EntityLinkSearchStub = EntityLinkSearchStub(),
        context: EntityLinkContext? = nil,
        onOpen: @escaping (EntityLinkNavigationTarget) -> Void = { _ in },
        onUnauthorized: @escaping () -> Void = {}
    ) -> EntityLinksViewModel {
        EntityLinksViewModel(
            context: context ?? EntityLinkContext(
                type: .task, id: contextID, title: "Task", canManage: true
            ),
            language: .en,
            service: service,
            search: search,
            onOpen: onOpen,
            onUnauthorized: onUnauthorized
        )
    }

    private func link(
        id: UUID = UUID(),
        targetID: UUID,
        title: String,
        path: String? = nil,
        accessible: Bool = true,
        redacted: Bool = false,
        relation: EntityRelationType = .related,
        version: Int64 = 1
    ) -> ActionEntityLinkDTO {
        let date = Date(timeIntervalSince1970: 1_787_001_200)
        return ActionEntityLinkDTO(
            id: id,
            source: ActionEntityReferenceDTO(
                type: .task, id: contextID, title: "Task", subtitle: nil,
                status: nil, path: nil, archived: false, accessible: true, redacted: false
            ),
            target: ActionEntityReferenceDTO(
                type: redacted ? nil : .task,
                id: redacted ? nil : targetID,
                title: title,
                subtitle: "SECRET SUBTITLE",
                status: nil,
                path: path,
                archived: false,
                accessible: accessible,
                redacted: redacted
            ),
            relationType: relation,
            createdByUserId: nil,
            createdByName: nil,
            createdAt: date,
            updatedAt: date,
            version: version
        )
    }
}

private actor EntityLinkServiceStub: EntityLinkFeatureServing {
    enum Operation: Equatable, Sendable {
        case list
        case create(CreateEntityLinkRequestDTO)
        case update(UUID, UpdateEntityLinkRequestDTO)
        case delete(UUID)
    }

    private let listed: [ActionEntityLinkDTO]
    private let created: ActionEntityLinkDTO?
    private let updated: ActionEntityLinkDTO?
    private let error: RemoteActionError?
    private let listGate: EntityLinkAsyncGate?
    private var recorded: [Operation] = []

    init(
        links: [ActionEntityLinkDTO] = [],
        created: ActionEntityLinkDTO? = nil,
        updated: ActionEntityLinkDTO? = nil,
        error: RemoteActionError? = nil,
        listGate: EntityLinkAsyncGate? = nil
    ) {
        listed = links
        self.created = created
        self.updated = updated
        self.error = error
        self.listGate = listGate
    }

    func listEntityLinks(type: LinkedEntityType, id: UUID) async throws -> [ActionEntityLinkDTO] {
        try failIfNeeded()
        recorded.append(.list)
        if let listGate { await listGate.wait() }
        return listed
    }

    func createEntityLink(_ request: CreateEntityLinkRequestDTO) async throws -> ActionEntityLinkDTO {
        try failIfNeeded()
        recorded.append(.create(request))
        guard let created else { throw URLError(.badServerResponse) }
        return created
    }

    func updateEntityLink(
        id: UUID,
        request: UpdateEntityLinkRequestDTO
    ) async throws -> ActionEntityLinkDTO {
        try failIfNeeded()
        recorded.append(.update(id, request))
        guard let updated else { throw URLError(.badServerResponse) }
        return updated
    }

    func deleteEntityLink(id: UUID) async throws {
        try failIfNeeded()
        recorded.append(.delete(id))
    }

    func operations() -> [Operation] { recorded }

    private func failIfNeeded() throws {
        if let error { throw error }
    }
}

private actor EntityLinkSearchStub: EntityLinkCandidateSearching {
    private let values: [EntityLinkCandidate]
    private var recorded: [String] = []

    init(values: [EntityLinkCandidate] = []) {
        self.values = values
    }

    func searchEntityLinkCandidates(query: String) async throws -> [EntityLinkCandidate] {
        recorded.append(query)
        return values
    }

    func queries() -> [String] { recorded }
}

private actor EntityLinkAsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func waitUntilSuspended() async {
        while waiters.isEmpty { await Task.yield() }
    }

    func release() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
