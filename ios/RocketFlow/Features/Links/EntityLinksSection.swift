import SwiftUI

@MainActor
struct EntityLinksSection: View {
    @ObservedObject var model: EntityLinksViewModel

    var body: some View {
        Section {
            stateContent
            if model.rows.isEmpty, model.phase == .loaded {
                Text(model.copy.empty)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.rows) { row in
                    linkRow(row)
                }
            }
            if model.context.canManage {
                Button {
                    model.presentPicker()
                } label: {
                    Label(model.copy.add, systemImage: "plus.circle")
                }
                .disabled(model.isBusy)
                .accessibilityIdentifier("links.add")
            } else {
                Label(model.copy.readOnly, systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(model.copy.title)
        }
        .task {
            if model.phase == .idle { await model.load() }
        }
        .sheet(
            isPresented: Binding(
                get: { model.isPickerPresented },
                set: { if !$0 { model.dismissPicker() } }
            )
        ) {
            EntityLinkPickerView(model: model)
        }
        .confirmationDialog(
            model.copy.confirmDelete,
            isPresented: Binding(
                get: { model.pendingDeleteID != nil },
                set: { if !$0 { model.cancelDelete() } }
            ),
            titleVisibility: .visible
        ) {
            Button(model.copy.delete, role: .destructive) {
                Task { await model.confirmDelete() }
            }
            .disabled(model.isBusy)
            Button(model.copy.cancel, role: .cancel) { model.cancelDelete() }
        }
        .accessibilityIdentifier("links.section")
    }

    @ViewBuilder
    private var stateContent: some View {
        if model.phase == .loading, model.rows.isEmpty {
            HStack {
                Spacer()
                ProgressView(model.copy.loading)
                Spacer()
            }
        } else if let issue = model.issue {
            Label(issueTitle(issue.kind), systemImage: issueSymbol(issue.kind))
                .foregroundStyle(
                    issue.kind == .offline ? Color.secondary : Color.red
                )
            if issue.kind == .offline || issue.kind == .unavailable {
                Button(model.copy.retry) { Task { await model.load() } }
            }
        }
    }

    @ViewBuilder
    private func linkRow(_ row: EntityLinkRow) -> some View {
        if row.redacted {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill")
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.copy.restricted)
                    Text(model.copy.restrictedHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(model.copy.restricted)
            .accessibilityHint(model.copy.restrictedHint)
            .contextMenu {
                if model.context.canManage {
                    deleteButton(row.id)
                }
            }
        } else {
            Button {
                model.open(row)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: row.relation == .dependency ? "arrow.triangle.branch" : "link")
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        if let subtitle = row.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(model.copy.relationTitle(row.relation))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!row.isTappable)
            .accessibilityLabel("\(row.title), \(model.copy.relationTitle(row.relation))")
            .accessibilityIdentifier("links.row.\(row.id.uuidString.lowercased())")
            .contextMenu {
                if model.context.canManage {
                    relationButtons(row)
                    deleteButton(row.id)
                }
            }
        }
    }

    @ViewBuilder
    private func relationButtons(_ row: EntityLinkRow) -> some View {
        ForEach(row.supportsDependency ? EntityRelationType.allCases : [.related], id: \.self) { relation in
            Button {
                Task { await model.updateRelation(linkID: row.id, relation: relation) }
            } label: {
                Label(
                    model.copy.relationTitle(relation),
                    systemImage: relation == row.relation ? "checkmark" : "arrow.left.arrow.right"
                )
            }
            .disabled(relation == row.relation || model.isBusy)
        }
    }

    private func deleteButton(_ id: UUID) -> some View {
        Button(role: .destructive) {
            model.requestDelete(linkID: id)
        } label: {
            Label(model.copy.delete, systemImage: "trash")
        }
        .disabled(model.isBusy)
    }

    private func issueTitle(_ kind: EntityLinkIssueKind) -> String {
        switch kind {
        case .selfLink: model.copy.selfLink
        case .dependencyRequiresTasks: model.copy.dependencyRequiresTasks
        case .duplicate: model.copy.duplicate
        case .dependencyCycle: model.copy.dependencyCycle
        case .unauthorized: model.copy.unauthorized
        case .forbidden: model.copy.forbidden
        case .notFound: model.copy.notFound
        case .conflict: model.copy.conflict
        case .validation: model.issue?.message ?? model.copy.unavailable
        case .offline: model.copy.offline
        case .unavailable: model.copy.unavailable
        }
    }

    private func issueSymbol(_ kind: EntityLinkIssueKind) -> String {
        switch kind {
        case .selfLink, .dependencyRequiresTasks, .duplicate, .dependencyCycle, .validation:
            "exclamationmark.circle"
        case .unauthorized:
            "person.crop.circle.badge.exclamationmark"
        case .forbidden:
            "lock"
        case .notFound:
            "questionmark.circle"
        case .conflict:
            "arrow.triangle.2.circlepath"
        case .offline:
            "wifi.slash"
        case .unavailable:
            "exclamationmark.triangle"
        }
    }
}
