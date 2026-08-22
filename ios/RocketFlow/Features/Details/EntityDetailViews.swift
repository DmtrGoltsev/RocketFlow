import SwiftUI

@MainActor
struct FolderDetailView: View {
    @StateObject private var model: DetailViewModel
    private let copy: DetailCopy
    @State private var pendingDelete = false

    init(model: DetailViewModel, language: AppLanguage) {
        _model = StateObject(wrappedValue: model)
        copy = DetailCopy(language: language)
    }

    var body: some View {
        Group {
            if case let .folder(folder) = model.content {
                List {
                    Section {
                        Text(folder.name)
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        if !folder.description.isEmpty {
                            Text(folder.description)
                                .textSelection(.enabled)
                        }
                        accessLabel(shared: folder.shared, fullAccess: folder.fullAccess)
                    }
                    if !folder.activitySummary.isEmpty {
                        Section(copy.activity) {
                            Text(folder.activitySummary)
                        }
                    }
                    createSection(actions: model.menuActions)
                    Section(copy.children) {
                        if folder.children.isEmpty {
                            DetailEmptyLabel(text: copy.empty)
                        } else {
                            ForEach(folder.children) { child in
                                DetailChildRow(item: child) { model.open(child) }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                fallback
            }
        }
        .navigationTitle(copy.folder)
        .navigationBarTitleDisplayMode(.inline)
        .detailScreen(
            model: model,
            copy: copy,
            pendingDelete: $pendingDelete,
            accessibilityID: "detail.folder"
        )
    }

    @ViewBuilder
    private func createSection(actions: [DetailMenuAction]) -> some View {
        let creates = actions.compactMap { action -> DetailCreateKind? in
            if case let .create(kind) = action { return kind }
            return nil
        }
        if !creates.isEmpty {
            Section {
                ForEach(creates, id: \.self) { kind in
                    Button { model.handle(.create(kind)) } label: {
                        Label(copy.createTitle(kind), systemImage: createSymbol(kind))
                    }
                }
            }
        }
    }

    private var fallback: some View {
        Group {
            if model.phase == .loading || model.phase == .idle {
                ProgressView(copy.loading)
            } else {
                DetailUnavailableView(text: copy.unavailable, systemImage: "folder.badge.questionmark")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func accessLabel(shared: Bool, fullAccess: Bool) -> some View {
        Label(
            shared && !fullAccess ? copy.readOnly : copy.fullAccess,
            systemImage: shared && !fullAccess ? "eye" : "pencil"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func createSymbol(_ kind: DetailCreateKind) -> String {
        switch kind {
        case .folder: "folder.badge.plus"
        case .goal: "target"
        case .task: "checkmark.circle"
        case .idea: "lightbulb"
        case .note: "square.and.pencil"
        case .ideaHistory: "clock.badge.plus"
        }
    }
}

@MainActor
struct GoalDetailView: View {
    @StateObject private var model: DetailViewModel
    private let copy: DetailCopy
    @State private var pendingDelete = false

    init(model: DetailViewModel, language: AppLanguage) {
        _model = StateObject(wrappedValue: model)
        copy = DetailCopy(language: language)
    }

    var body: some View {
        Group {
            if case let .goal(goal) = model.content {
                List {
                    Section {
                        Text(goal.name)
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        if !goal.description.isEmpty {
                            Text(goal.description).textSelection(.enabled)
                        }
                        LabeledContent(copy.status, value: copy.statusTitle(goal.status))
                    }
                    if goal.capabilities.contains(.createTask) {
                        Section {
                            Button { model.handle(.create(.task)) } label: {
                                Label(copy.createTask, systemImage: "plus.circle")
                            }
                            .accessibilityIdentifier("detail.goal.createTask")
                        }
                    }
                    Section(copy.tasks) {
                        if goal.tasks.isEmpty {
                            DetailEmptyLabel(text: copy.empty)
                        } else {
                            ForEach(goal.tasks) { task in
                                DetailChildRow(item: task) { model.open(task) }
                            }
                        }
                    }
                    DetailLinksSection(links: goal.links, copy: copy)
                }
                .listStyle(.insetGrouped)
            } else {
                fallback
            }
        }
        .navigationTitle(copy.goal)
        .navigationBarTitleDisplayMode(.inline)
        .detailScreen(
            model: model,
            copy: copy,
            pendingDelete: $pendingDelete,
            accessibilityID: "detail.goal"
        )
    }

    private var fallback: some View {
        Group {
            if model.phase == .loading || model.phase == .idle {
                ProgressView(copy.loading)
            } else {
                DetailUnavailableView(text: copy.unavailable, systemImage: "target")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
struct TaskDetailView: View {
    @StateObject private var model: DetailViewModel
    private let copy: DetailCopy
    private let language: AppLanguage
    @State private var pendingDelete = false

    init(model: DetailViewModel, language: AppLanguage) {
        _model = StateObject(wrappedValue: model)
        self.language = language
        copy = DetailCopy(language: language)
    }

    var body: some View {
        Group {
            if case let .task(task) = model.content {
                List {
                    Section {
                        Text(task.title)
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        if !task.description.isEmpty {
                            Text(task.description).textSelection(.enabled)
                        }
                        Picker(copy.status, selection: statusBinding(task)) {
                            ForEach(DetailTaskStatus.allCases, id: \.self) { status in
                                Text(copy.statusTitle(status)).tag(status)
                            }
                        }
                        .disabled(
                            !task.capabilities.contains(.updateTaskStatus)
                                || model.isPerformingAction
                        )
                        .accessibilityIdentifier("detail.task.status")
                        LabeledContent(
                            copy.type,
                            value: task.type == .green ? copy.typeGreen : copy.typeRed
                        )
                        LabeledContent(copy.effort, value: String(task.effort))
                    }
                    datesSection(task)
                    if let recurrence = task.recurrence {
                        Section(copy.recurrence) {
                            Text(recurrenceSummary(recurrence))
                            if let end = recurrence.end {
                                LabeledContent(copy.dueDate, value: dateText(end))
                            }
                        }
                    }
                    Section(copy.checklist) {
                        if task.checklist.isEmpty {
                            DetailEmptyLabel(text: copy.empty)
                        } else {
                            ForEach(task.checklist) { item in
                                Button {
                                    Task { await model.toggleChecklistItem(item.id) }
                                } label: {
                                    Label(
                                        item.text,
                                        systemImage: item.checked ? "checkmark.circle.fill" : "circle"
                                    )
                                    .foregroundStyle(item.checked ? .secondary : .primary)
                                }
                                .buttonStyle(.plain)
                                .disabled(
                                    !task.capabilities.contains(.manageChecklist)
                                        || model.isPerformingAction
                                )
                                .accessibilityValue(item.checked ? copy.statusDone : copy.statusTodo)
                            }
                        }
                    }
                    if !task.tags.isEmpty {
                        Section(copy.tags) {
                            ForEach(task.tags.filter(\.assigned)) { tag in
                                Label(tag.name, systemImage: "tag.fill")
                            }
                        }
                    }
                    Section {
                        Button {
                            Task { await model.setFocus(!task.isInFocus) }
                        } label: {
                            Label(
                                task.isInFocus ? copy.removeFromFocus : copy.addToFocus,
                                systemImage: task.isInFocus ? "scope" : "scope"
                            )
                        }
                        .disabled(
                            !task.capabilities.contains(.manageFocus)
                                || model.isPerformingAction
                        )
                        .accessibilityIdentifier("detail.task.focus")
                    }
                    DetailLinksSection(links: task.links, copy: copy)
                }
                .listStyle(.insetGrouped)
            } else {
                fallback
            }
        }
        .navigationTitle(copy.task)
        .navigationBarTitleDisplayMode(.inline)
        .detailScreen(
            model: model,
            copy: copy,
            pendingDelete: $pendingDelete,
            accessibilityID: "detail.task"
        )
    }

    private func statusBinding(_ task: TaskDetailViewData) -> Binding<DetailTaskStatus> {
        Binding(
            get: { task.status },
            set: { status in Task { await model.updateTaskStatus(status) } }
        )
    }

    @ViewBuilder
    private func datesSection(_ task: TaskDetailViewData) -> some View {
        if task.plannedAt != nil || task.dueAt != nil {
            Section {
                if let plannedAt = task.plannedAt {
                    LabeledContent(copy.plannedDate, value: dateText(plannedAt))
                }
                if let dueAt = task.dueAt {
                    LabeledContent(copy.dueDate, value: dateText(dueAt))
                }
            }
        }
    }

    private var fallback: some View {
        Group {
            if model.phase == .loading || model.phase == .idle {
                ProgressView(copy.loading)
            } else {
                DetailUnavailableView(text: copy.unavailable, systemImage: "checkmark.circle")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(Locale(identifier: language == .ru ? "ru_RU" : "en_US"))
        )
    }

    private func recurrenceSummary(_ value: DetailRecurrenceViewData) -> String {
        let mode: String
        switch value.mode {
        case .daily: mode = language == .ru ? "Ежедневно" : "Daily"
        case .weekly: mode = language == .ru ? "Еженедельно" : "Weekly"
        case .monthly: mode = language == .ru ? "Ежемесячно" : "Monthly"
        }
        return value.interval == 1 ? mode : "\(mode), \(value.interval)"
    }
}

@MainActor
struct IdeaDetailView: View {
    @StateObject private var model: DetailViewModel
    private let copy: DetailCopy
    private let language: AppLanguage
    @State private var pendingDelete = false
    @State private var historyPendingDelete: DetailIdeaHistoryViewData?

    init(model: DetailViewModel, language: AppLanguage) {
        _model = StateObject(wrappedValue: model)
        self.language = language
        copy = DetailCopy(language: language)
    }

    var body: some View {
        Group {
            if case let .idea(idea) = model.content {
                List {
                    Section {
                        Text(idea.title)
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        if !idea.body.isEmpty { Text(idea.body).textSelection(.enabled) }
                        LabeledContent(copy.status, value: idea.status)
                        LabeledContent(
                            copy.authorHistoryEdits,
                            value: idea.allowAuthorHistoryEdits ? copy.enabled : copy.disabled
                        )
                    }
                    if idea.capabilities.contains(.createIdeaHistory) {
                        Section {
                            Button { model.handle(.create(.ideaHistory)) } label: {
                                Label(copy.createHistory, systemImage: "clock.badge.plus")
                            }
                            .accessibilityIdentifier("detail.idea.createHistory")
                        }
                    }
                    Section(copy.history) {
                        if idea.history.isEmpty {
                            DetailEmptyLabel(text: copy.empty)
                        } else {
                            ForEach(idea.history) { entry in
                                historyRow(entry, idea: idea)
                            }
                        }
                    }
                    DetailLinksSection(links: idea.links, copy: copy)
                }
                .listStyle(.insetGrouped)
            } else {
                fallback
            }
        }
        .navigationTitle(copy.idea)
        .navigationBarTitleDisplayMode(.inline)
        .detailScreen(
            model: model,
            copy: copy,
            pendingDelete: $pendingDelete,
            accessibilityID: "detail.idea"
        )
        .confirmationDialog(
            copy.delete,
            isPresented: Binding(
                get: { historyPendingDelete != nil },
                set: { if !$0 { historyPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(copy.delete, role: .destructive) {
                guard let entry = historyPendingDelete else { return }
                Task { await model.deleteIdeaHistory(entry) }
                historyPendingDelete = nil
            }
            Button(copy.cancel, role: .cancel) {}
        } message: {
            Text(copy.confirmDelete)
        }
    }

    private func historyRow(
        _ entry: DetailIdeaHistoryViewData,
        idea: IdeaDetailViewData
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.eventType)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(dateText(entry.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !entry.body.isEmpty { Text(entry.body) }
            if let authorName = entry.authorName {
                Text("\(copy.author): \(authorName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            if DetailIdeaHistoryPolicy.canEdit(entry) {
                Button { model.editIdeaHistory(entry) } label: {
                    Label(copy.edit, systemImage: "pencil")
                }
            }
            if DetailIdeaHistoryPolicy.canDelete(from: idea) {
                Button(role: .destructive) { historyPendingDelete = entry } label: {
                    Label(copy.delete, systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail.idea.history.\(entry.id)")
    }

    private var fallback: some View {
        Group {
            if model.phase == .loading || model.phase == .idle {
                ProgressView(copy.loading)
            } else {
                DetailUnavailableView(text: copy.unavailable, systemImage: "lightbulb")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(Locale(identifier: language == .ru ? "ru_RU" : "en_US"))
        )
    }
}

@MainActor
struct NoteDetailView: View {
    @StateObject private var model: DetailViewModel
    private let copy: DetailCopy
    @State private var pendingDelete = false

    init(model: DetailViewModel, language: AppLanguage) {
        _model = StateObject(wrappedValue: model)
        copy = DetailCopy(language: language)
    }

    var body: some View {
        Group {
            if case let .note(note) = model.content {
                List {
                    Section {
                        Text(note.title)
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        if !note.body.isEmpty { Text(note.body).textSelection(.enabled) }
                        if let authorName = note.authorName {
                            LabeledContent(copy.author, value: authorName)
                        }
                    }
                    DetailLinksSection(links: note.links, copy: copy)
                }
                .listStyle(.insetGrouped)
            } else if model.phase == .loading || model.phase == .idle {
                ProgressView(copy.loading)
            } else {
                DetailUnavailableView(text: copy.unavailable, systemImage: "note.text")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(copy.note)
        .navigationBarTitleDisplayMode(.inline)
        .detailScreen(
            model: model,
            copy: copy,
            pendingDelete: $pendingDelete,
            accessibilityID: "detail.note"
        )
    }
}
