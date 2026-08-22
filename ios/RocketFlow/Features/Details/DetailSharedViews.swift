import SwiftUI

struct DetailActionMenu: View {
    let actions: [DetailMenuAction]
    let copy: DetailCopy
    let onAction: (DetailMenuAction) -> Void
    let onDelete: () -> Void

    var body: some View {
        if !actions.isEmpty {
            Menu {
                ForEach(actions, id: \.self) { action in
                    if action == .delete {
                        Button(role: .destructive, action: onDelete) {
                            Label(copy.delete, systemImage: "trash")
                        }
                    } else {
                        Button { onAction(action) } label: {
                            Label(copy.actionTitle(action), systemImage: symbol(for: action))
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel(copy.moreActions)
            .help(copy.moreActions)
        }
    }

    private func symbol(for action: DetailMenuAction) -> String {
        switch action {
        case let .create(kind):
            switch kind {
            case .folder: "folder.badge.plus"
            case .goal: "target"
            case .task: "checkmark.circle"
            case .idea: "lightbulb"
            case .note: "square.and.pencil"
            case .ideaHistory: "clock.badge.plus"
            }
        case .edit: "pencil"
        case .move: "arrow.up.arrow.down"
        case .clone: "plus.square.on.square"
        case .delete: "trash"
        case .share: "person.badge.plus"
        case .links: "link"
        case .reschedule: "calendar"
        }
    }
}

struct DetailStatusArea: View {
    let phase: DetailScreenPhase
    let isOffline: Bool
    let hasPendingChanges: Bool
    let issue: DetailIssue?
    let copy: DetailCopy
    let canOpenLinks: Bool
    let onOpenLinks: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if phase == .loading {
                ProgressView()
                    .progressViewStyle(.linear)
                    .accessibilityLabel(copy.loading)
            }
            if isOffline {
                banner(copy.offline, symbol: "wifi.slash", color: .orange)
            }
            if hasPendingChanges || phase == .pending {
                banner(copy.pending, symbol: "arrow.triangle.2.circlepath", color: .orange)
            }
            if let issue {
                banner(issueText(issue), symbol: "exclamationmark.triangle", color: .red)
                HStack {
                    if issue == .dependencyBlocked, canOpenLinks {
                        Button(copy.dependencyAction, action: onOpenLinks)
                    }
                    Button(copy.retry, action: onRetry)
                }
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .accessibilityIdentifier("detail.status")
    }

    private func banner(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.footnote)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
    }

    private func issueText(_ issue: DetailIssue) -> String {
        switch issue {
        case .dependencyBlocked: copy.dependencyBlocked
        case .networkRequired: copy.networkRequired
        case .unavailable: copy.unavailable
        }
    }
}

struct DetailChildRow: View {
    let item: DetailChildViewData
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 22)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("detail.child.\(item.reference.kind.rawValue).\(item.reference.id)")
    }

    private var symbol: String {
        switch item.reference.kind {
        case .folder: "folder"
        case .goal: "target"
        case .task: "checkmark.circle"
        case .idea: "lightbulb"
        case .note: "note.text"
        }
    }
}

struct DetailLinksSection: View {
    let links: [DetailLinkViewData]
    let copy: DetailCopy

    var body: some View {
        if !links.isEmpty {
            Section(copy.links) {
                ForEach(links) { link in
                    HStack(spacing: 10) {
                        Image(systemName: link.relation == .dependency ? "point.3.connected.trianglepath.dotted" : "link")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.title)
                            if !link.subtitle.isEmpty {
                                Text(link.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

struct DetailEmptyLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
    }
}

struct DetailUnavailableView: View {
    let text: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}

extension View {
    func detailScreen(
        model: DetailViewModel,
        copy: DetailCopy,
        pendingDelete: Binding<Bool>,
        accessibilityID: String
    ) -> some View {
        modifier(
            DetailScreenModifier(
                model: model,
                copy: copy,
                pendingDelete: pendingDelete,
                accessibilityID: accessibilityID
            )
        )
    }
}

private struct DetailScreenModifier: ViewModifier {
    @ObservedObject var model: DetailViewModel
    let copy: DetailCopy
    @Binding var pendingDelete: Bool
    let accessibilityID: String

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            DetailStatusArea(
                phase: model.phase,
                isOffline: model.isOffline,
                hasPendingChanges: model.hasPendingChanges,
                issue: model.issue,
                copy: copy,
                canOpenLinks: model.content?.capabilities.contains(.manageLinks) == true,
                onOpenLinks: { model.handle(.links) },
                onRetry: { Task { await model.reload() } }
            )
            content
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                DetailActionMenu(
                    actions: model.menuActions,
                    copy: copy,
                    onAction: model.handle,
                    onDelete: { pendingDelete = true }
                )
            }
        }
        .task { await model.loadIfNeeded() }
        .alert(copy.delete, isPresented: $pendingDelete) {
            Button(copy.cancel, role: .cancel) {}
            Button(copy.delete, role: .destructive) {
                Task { await model.delete() }
            }
        } message: {
            Text(copy.confirmDelete)
        }
        .accessibilityIdentifier(accessibilityID)
    }
}
