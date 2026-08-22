import SwiftUI

struct PlannerRowView: View {
    let row: PlannerTreeRow
    let copy: PlannerCopy
    let actions: [PlannerContextAction]
    let isBusy: Bool
    let onOpen: () -> Void
    let onToggleExpanded: () -> Void
    let onToggleTaskStatus: () -> Void
    let onAction: (PlannerContextAction) -> Void

    var body: some View {
        HStack(spacing: 6) {
            expansionControl

            Button(action: onOpen) {
                HStack(spacing: 9) {
                    Image(systemName: itemSymbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(itemColor)
                        .frame(width: 22)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.item.title)
                            .font(titleFont)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .strikethrough(row.item.status == .done)

                        if !detailLine.isEmpty {
                            Text(detailLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel(rowAccessibilityLabel)
            .accessibilityHint(copy.open)

            if row.item.isShared {
                Image(systemName: row.item.fullAccess ? "person.2.fill" : "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 32)
                    .accessibilityLabel(row.item.fullAccess ? copy.fullAccess : copy.readOnly)
                    .help(row.item.fullAccess ? copy.fullAccess : copy.readOnly)
            }

            taskStatusControl
            actionsMenu
        }
        .padding(.leading, CGFloat(row.depth) * 18 + 4)
        .padding(.trailing, 2)
        .frame(minHeight: row.item.reference.kind == .task ? 54 : 48)
        .contentShape(Rectangle())
        .contextMenu { actionButtons }
        .plannerScrollRow(row.scrollAnchor, parentAnchor: row.parentScrollAnchor)
        .accessibilityIdentifier(
            "planner.row.\(row.item.reference.kind.rawValue).\(row.item.reference.id.uuidString.lowercased())"
        )
    }

    @ViewBuilder
    private var expansionControl: some View {
        if row.hasChildren {
            Button(action: onToggleExpanded) {
                Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .frame(width: 32, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.isExpanded ? copy.collapse : copy.expand)
            .accessibilityValue(String(row.visibleChildCount))
        } else {
            Color.clear
                .frame(width: 32, height: 40)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var taskStatusControl: some View {
        if row.item.reference.kind == .task {
            if row.item.capabilities.contains(.updateTaskStatus) {
                Button(action: onToggleTaskStatus) {
                    Image(systemName: row.item.status == .done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(row.item.status == .done ? Color.green : Color.secondary)
                        .frame(width: 36, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityLabel(copy.statusTitle(row.item.status) ?? copy.statusTodo)
                .accessibilityHint(copy.taskStatusActionHint(row.item.status))
            } else {
                Image(systemName: row.item.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 40)
                    .accessibilityLabel(copy.statusTitle(row.item.status) ?? copy.statusTodo)
            }
        }
    }

    private var actionsMenu: some View {
        Menu {
            actionButtons
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .disabled(isBusy)
        .accessibilityLabel(copy.moreActions)
        .help(copy.moreActions)
    }

    @ViewBuilder
    private var actionButtons: some View {
        ForEach(actions, id: \.self) { action in
            Button(role: action == .delete ? .destructive : nil) {
                onAction(action)
            } label: {
                Label(actionTitle(action), systemImage: actionSymbol(action))
            }
            .disabled(isBusy)
        }
    }

    private var itemSymbol: String {
        switch row.item.reference.kind {
        case .folder: "folder.fill"
        case .goal: "target"
        case .task: "checkmark.circle"
        case .idea: "lightbulb.fill"
        case .note: "note.text"
        }
    }

    private var itemColor: Color {
        switch row.item.reference.kind {
        case .folder: .blue
        case .goal: .indigo
        case .task: .secondary
        case .idea: .orange
        case .note: .teal
        }
    }

    private var titleFont: Font {
        switch row.item.reference.kind {
        case .folder: .body.weight(.semibold)
        case .goal: .subheadline.weight(.semibold)
        case .task, .idea, .note: .subheadline
        }
    }

    private var detailLine: String {
        let status = copy.statusTitle(row.item.status)
        return [row.item.subtitle, status]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }

    private var rowAccessibilityLabel: String {
        [row.item.title, detailLine, row.item.isShared ? copy.shared : nil]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ", ")
    }

    private func actionTitle(_ action: PlannerContextAction) -> String {
        switch action {
        case .openDetail: copy.open
        case let .create(kind):
            copy.createTitle(kind, nested: kind == .folder)
        case .edit: copy.edit
        case .move: copy.move
        case .clone: copy.clone
        case .delete: copy.delete
        case .share: copy.share
        }
    }

    private func actionSymbol(_ action: PlannerContextAction) -> String {
        switch action {
        case .openDetail: "arrow.right.circle"
        case let .create(kind):
            switch kind {
            case .folder: "folder.badge.plus"
            case .goal: "target"
            case .task: "plus.circle"
            case .idea: "lightbulb"
            case .note: "square.and.pencil"
            }
        case .edit: "pencil"
        case .move: "arrowshape.turn.up.right"
        case .clone: "plus.square.on.square"
        case .delete: "trash"
        case .share: "square.and.arrow.up"
        }
    }
}
