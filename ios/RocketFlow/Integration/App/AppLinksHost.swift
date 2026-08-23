import SwiftUI

@MainActor
struct AppLinksHost: View {
    let reference: DetailEntityReference
    let origin: DetailOriginTab
    let runtime: AppUserRuntime
    @ObservedObject var appStore: AppStore
    @ObservedObject var languageStore: AppLanguageStore

    @State private var model: EntityLinksViewModel?
    @State private var errorText: String?
    private var copy: AppIntegrationCopy { AppIntegrationCopy(language: languageStore.language) }

    var body: some View {
        Group {
            if let model {
                List {
                    EntityLinksSection(model: model)
                }
                .navigationTitle(model.copy.title)
                .navigationBarTitleDisplayMode(.inline)
                .accessibilityIdentifier("links.screen")
            } else if let errorText {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(errorText)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .navigationTitle(copy.links)
            } else {
                ProgressView(copy.loading)
            }
        }
        .task { await load() }
        .onChange(of: languageStore.language) { model?.setLanguage($0) }
    }

    private func load() async {
        guard model == nil, errorText == nil else { return }
        do {
            guard let linkedType = LinkedEntityType(reference.kind) else {
                throw PlannerDetailsIntegrationError.unsupported(operation: "folder.entity_links")
            }
            let content = (try await runtime.plannerDetailsActions.loadDetail(reference)).content
            let serverID = try await runtime.plannerDetailsActions.serverID(
                kind: reference.kind,
                localID: reference.id
            )
            let context = EntityLinkContext(
                type: linkedType,
                id: serverID,
                title: content.appTitle,
                canManage: content.capabilities.contains(.manageLinks)
            )
            let search = AppEntityLinkCandidateSearch(
                repository: runtime.planningRepository,
                adapter: runtime.plannerDetailsActions
            )
            model = EntityLinksViewModel(
                context: context,
                language: languageStore.language,
                service: runtime.entityLinkActions,
                search: search,
                onOpen: { target in
                    Task {
                        guard let kind = DetailEntityKind(target.type) else { return }
                        do {
                            let localID = try await runtime.plannerDetailsActions.localID(
                                kind: kind,
                                serverID: target.id
                            )
                            await MainActor.run {
                                appStore.navigation.open(
                                    DetailEntityReference(kind: kind, id: localID),
                                    origin: origin
                                )
                            }
                        } catch {
                            return
                        }
                    }
                },
                onUnauthorized: { Task { await appStore.handleUnauthorized(for: runtime.lease) } }
            )
        } catch {
            errorText = error.localizedDescription
        }
    }

}

private struct AppEntityLinkCandidateSearch: EntityLinkCandidateSearching, Sendable {
    let repository: any PlanningRepository
    let adapter: any PlannerDetailsResourceIDResolving

    func searchEntityLinkCandidates(query: String) async throws -> [EntityLinkCandidate] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = try await repository.snapshot()
        var values: [(DetailEntityKind, UUID, String, String?)] = []
        values += snapshot.goals.map { (.goal, $0.id, $0.name, nil) }
        values += snapshot.tasks.map { (.task, $0.id, $0.title, nil) }
        values += snapshot.ideas.map { (.idea, $0.id, $0.title, nil) }
        values += snapshot.notes.map { (.note, $0.id, $0.title, nil) }

        var result: [EntityLinkCandidate] = []
        for (kind, localID, title, path) in values where normalized.isEmpty
            || title.localizedCaseInsensitiveContains(normalized) {
            guard let type = LinkedEntityType(kind),
                  let serverID = try? await adapter.serverID(
                    kind: kind,
                    localID: localID
                  ) else {
                continue
            }
            result.append(EntityLinkCandidate(id: serverID, type: type, title: title, path: path))
        }
        return result
    }
}

private extension LinkedEntityType {
    init?(_ kind: DetailEntityKind) {
        switch kind {
        case .folder: return nil
        case .goal: self = .goal
        case .task: self = .task
        case .idea: self = .idea
        case .note: self = .note
        }
    }
}

private extension DetailEntityKind {
    init?(_ type: LinkedEntityType) {
        switch type {
        case .goal: self = .goal
        case .task: self = .task
        case .idea: self = .idea
        case .note: self = .note
        }
    }
}

private extension DetailContent {
    var appTitle: String {
        switch self {
        case let .folder(value): value.name
        case let .goal(value): value.name
        case let .task(value): value.title
        case let .idea(value): value.title
        case let .note(value): value.title
        }
    }
}
