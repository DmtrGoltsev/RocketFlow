import SwiftUI

@MainActor
struct TaskEditorView: View {
    @StateObject private var coordinator: EditorSaveCoordinator
    @State private var draft: TaskEditorDraft
    @State private var validation = EditorValidationResult.valid
    @State private var presentsTagCreator = false
    @State private var isInFocus: Bool
    @State private var focusError = false

    private let mode: EditorMode
    private let goalID: UUID
    private let access: TaskEditorAccess
    private let timezone: TimeZone
    private let copy: EditorCopy
    private let tagCreator: (any EditorTagCreating)?
    private let focusUpdater: (any EditorFocusUpdating)?
    private let onCancel: () -> Void

    init(
        mode: EditorMode,
        goalID: UUID,
        initialDraft: TaskEditorDraft,
        initialIsInFocus: Bool,
        access: TaskEditorAccess,
        timezone: TimeZone,
        language: AppLanguage,
        coordinator: EditorSaveCoordinator,
        tagCreator: (any EditorTagCreating)? = nil,
        focusUpdater: (any EditorFocusUpdating)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.goalID = goalID
        self.access = access
        self.timezone = timezone
        _draft = State(initialValue: initialDraft)
        _isInFocus = State(initialValue: initialIsInFocus)
        copy = EditorCopy(language: language)
        _coordinator = StateObject(wrappedValue: coordinator)
        self.tagCreator = tagCreator
        self.focusUpdater = focusUpdater
        self.onCancel = onCancel
    }

    var body: some View {
        Form {
            if access.mutationScope == .statusOnly {
                Section {
                    Label(copy.statusOnly, systemImage: "eye")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            statusSection
            basicsSection
            datesSection
            recurrenceSection
            checklistSection
            tagsSection
            focusSection
        }
        .editorChrome(
            title: isCreate ? copy.newTask : copy.editTask,
            copy: copy,
            coordinator: coordinator,
            canSave: true,
            onCancel: onCancel,
            onSave: save,
            accessibilityID: "editor.task"
        )
        .sheet(isPresented: $presentsTagCreator) {
            NavigationStack {
                if let tagCreator {
                    TaskTagCreationView(
                        copy: copy,
                        creator: tagCreator,
                        isOnline: coordinator.isOnline,
                        onCreated: receiveCreatedTag,
                        onCancel: { presentsTagCreator = false }
                    )
                }
            }
        }
        .onChange(of: draft.plannedAt) { _ in synchronizeRecurrenceAnchor() }
        .onChange(of: draft.dueAt) { _ in synchronizeRecurrenceAnchor() }
        .onAppear(perform: synchronizeRecurrenceAnchor)
    }

    private var statusSection: some View {
        Section {
            Picker(copy.status, selection: $draft.status) {
                ForEach(DetailTaskStatus.allCases, id: \.self) { status in
                    Text(copy.statusTitle(status)).tag(status)
                }
            }
            .accessibilityIdentifier("editor.task.status")
        }
    }

    private var basicsSection: some View {
        Section {
            TextField(copy.title, text: $draft.title)
                .textInputAutocapitalization(.sentences)
                .accessibilityIdentifier("editor.task.title")
            EditorValidationMessage(issue: validation.errors[.title], copy: copy)
            TextEditor(text: $draft.description)
                .frame(minHeight: 120)
                .accessibilityLabel(copy.description)
            EditorValidationMessage(issue: validation.errors[.description], copy: copy)
            Picker(copy.type, selection: $draft.type) {
                Text(copy.green).tag(DetailTaskType.green)
                Text(copy.red).tag(DetailTaskType.red)
            }
            .pickerStyle(.segmented)
            LabeledContent(copy.effort) {
                TextField(copy.effort, value: $draft.effort, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(copy.effort)
            }
            EditorValidationMessage(issue: validation.errors[.effort], copy: copy)
        }
        .disabled(access.mutationScope == .statusOnly)
    }

    private var datesSection: some View {
        Section {
            NullableDateEditorRow(title: copy.plannedDate, value: $draft.plannedAt)
            NullableDateEditorRow(title: copy.dueDate, value: $draft.dueAt)
        }
        .disabled(access.mutationScope == .statusOnly)
    }

    @ViewBuilder
    private var recurrenceSection: some View {
        if access.canManageRecurrence || draft.recurrence.mode != nil {
            Section(copy.recurrence) {
                Picker(copy.recurrence, selection: $draft.recurrence.mode) {
                    Text(copy.noRecurrence).tag(DetailRecurrenceMode?.none)
                    ForEach(DetailRecurrenceMode.allCases, id: \.self) { mode in
                        Text(copy.recurrenceTitle(mode)).tag(Optional(mode))
                    }
                }
                .onChange(of: draft.recurrence.mode) { _ in synchronizeRecurrenceAnchor() }
                if let recurrenceMode = draft.recurrence.mode {
                    if draft.plannedAt != nil, draft.dueAt != nil {
                        Picker(
                            copy.recurrenceAnchorSource,
                            selection: recurrenceAnchorSourceBinding
                        ) {
                            Text(copy.plannedDate).tag(TaskRecurrenceAnchorSource.planned)
                            Text(copy.dueDate).tag(TaskRecurrenceAnchorSource.due)
                        }
                    }
                    LabeledContent(copy.interval) {
                        TextField(
                            copy.interval,
                            value: $draft.recurrence.interval,
                            format: .number
                        )
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel(copy.interval)
                    }
                    if recurrenceMode == .weekly {
                        weekdaySelection
                    } else if recurrenceMode == .monthly {
                        Stepper(
                            value: Binding(
                                get: { draft.recurrence.dayOfMonth ?? 1 },
                                set: { draft.recurrence.dayOfMonth = $0 }
                            ),
                            in: 1...31
                        ) {
                            LabeledContent(
                                copy.monthDay,
                                value: String(draft.recurrence.dayOfMonth ?? 1)
                            )
                        }
                    }
                    NullableDateEditorRow(title: copy.recurrenceEnd, value: $draft.recurrence.endAt)
                }
                EditorValidationMessage(issue: recurrenceIssue, copy: copy)
            }
            .disabled(!access.canManageRecurrence || access.mutationScope == .statusOnly)
        }
    }

    private var weekdaySelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(copy.weekdays).font(.subheadline)
            ForEach(DetailWeekday.allCases, id: \.self) { weekday in
                Toggle(weekdayTitle(weekday), isOn: weekdayBinding(weekday))
            }
        }
    }

    @ViewBuilder
    private var checklistSection: some View {
        if access.canManageChecklist || !draft.checklist.isEmpty {
            Section {
                ForEach($draft.checklist) { $item in
                    HStack(spacing: 8) {
                        Button { item.checked.toggle() } label: {
                            Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            copy.checklistToggleLabel(text: item.text, checked: item.checked)
                        )
                        TextField(copy.addChecklist, text: $item.text)
                            .textInputAutocapitalization(.sentences)
                        if access.canManageChecklist && access.mutationScope == .full {
                            Button(role: .destructive) {
                                draft.removeChecklistItem(id: item.id)
                            } label: {
                                Image(systemName: "trash")
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(copy.checklistDeleteLabel(text: item.text))
                        }
                    }
                }
                .onMove { offsets, destination in
                    draft.checklist.move(fromOffsets: offsets, toOffset: destination)
                }
                if access.canManageChecklist && access.mutationScope == .full {
                    Button { draft.addChecklistItem() } label: {
                        Label(copy.addChecklist, systemImage: "plus.circle")
                    }
                }
                EditorValidationMessage(issue: validation.errors[.checklist], copy: copy)
            } header: {
                HStack {
                    Text(copy.checklist)
                    Spacer()
                    if access.canManageChecklist && access.mutationScope == .full {
                        EditButton()
                    }
                }
            }
            .disabled(access.mutationScope == .statusOnly)
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        if access.canManageTags || !draft.tags.isEmpty {
            Section(copy.tags) {
                ForEach($draft.tags) { $tag in
                    Toggle(isOn: $tag.assigned) {
                        Label(tag.name, systemImage: "tag.fill")
                    }
                }
                if access.canManageTags && access.mutationScope == .full, tagCreator != nil {
                    Button { presentsTagCreator = true } label: {
                        Label(copy.createTag, systemImage: "plus.circle")
                    }
                }
            }
            .disabled(access.mutationScope == .statusOnly)
        }
    }

    @ViewBuilder
    private var focusSection: some View {
        if let taskID, focusUpdater != nil {
            Section {
                Toggle(copy.focus, isOn: focusBinding(taskID: taskID))
                    .accessibilityIdentifier("editor.task.focus")
                if focusError {
                    Text(copy.failed)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var isCreate: Bool { if case .create = mode { return true }; return false }

    private var taskID: UUID? {
        guard case let .edit(reference) = mode, reference.kind == .task else { return nil }
        return reference.id
    }

    private var recurrenceIssue: EditorValidationIssue? {
        let keys: [EditorField] = [
            .recurrence, .recurrenceInterval, .recurrenceWeekdays,
            .recurrenceDayOfMonth, .recurrenceEnd
        ]
        return keys.compactMap { validation.errors[$0] }.first
    }

    private func save() {
        validation = EditorValidator.validate(
            draft,
            timezone: timezone,
            scope: access.mutationScope
        )
        guard
            validation.isValid,
            let payload = EditorValidator.payload(
                draft,
                timezone: timezone,
                scope: access.mutationScope
            )
        else {
            return
        }
        Task {
            await coordinator.save(.task(mode: mode, goalID: goalID, payload: payload))
        }
    }

    private func receiveCreatedTag(_ tag: TagEditorItemDraft) {
        var assignedTag = tag
        assignedTag.assigned = true
        if let index = draft.tags.firstIndex(where: { $0.id == tag.id }) {
            draft.tags[index] = assignedTag
        } else {
            draft.tags.append(assignedTag)
        }
        presentsTagCreator = false
    }

    private func focusBinding(taskID: UUID) -> Binding<Bool> {
        Binding(
            get: { isInFocus },
            set: { focused in
                let previous = isInFocus
                isInFocus = focused
                focusError = false
                Task {
                    do {
                        try await focusUpdater?.setTaskFocus(taskID: taskID, focused: focused)
                    } catch {
                        isInFocus = previous
                        focusError = true
                    }
                }
            }
        )
    }

    private func weekdayBinding(_ weekday: DetailWeekday) -> Binding<Bool> {
        Binding(
            get: { draft.recurrence.weekdays.contains(weekday) },
            set: { selected in
                if selected {
                    draft.recurrence.weekdays.insert(weekday)
                } else {
                    draft.recurrence.weekdays.remove(weekday)
                }
            }
        )
    }

    private var recurrenceAnchorSourceBinding: Binding<TaskRecurrenceAnchorSource> {
        Binding(
            get: {
                draft.recurrence.resolvedAnchorSource(
                    plannedAt: draft.plannedAt,
                    dueAt: draft.dueAt
                ) ?? .planned
            },
            set: { source in
                draft.recurrence.anchorSource = source
                synchronizeRecurrenceAnchor()
            }
        )
    }

    private func synchronizeRecurrenceAnchor() {
        draft.recurrence.synchronizeAnchor(plannedAt: draft.plannedAt, dueAt: draft.dueAt)
        guard
            let mode = draft.recurrence.mode,
            let anchor = draft.recurrence.resolvedAnchor(
                plannedAt: draft.plannedAt,
                dueAt: draft.dueAt
            )
        else {
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        if mode == .weekly {
            draft.recurrence.weekdays.insert(weekday(for: calendar.component(.weekday, from: anchor)))
        } else if mode == .monthly {
            draft.recurrence.dayOfMonth = calendar.component(.day, from: anchor)
        }
    }

    private func weekday(for calendarValue: Int) -> DetailWeekday {
        switch calendarValue {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        default: .saturday
        }
    }

    private func weekdayTitle(_ weekday: DetailWeekday) -> String {
        copy.weekdayTitle(weekday)
    }
}

@MainActor
private struct TaskTagCreationView: View {
    let copy: EditorCopy
    let creator: any EditorTagCreating
    let isOnline: Bool
    let onCreated: (TagEditorItemDraft) -> Void
    let onCancel: () -> Void

    @State private var draft = TagEditorDraft(name: "", colorHex: "")
    @State private var validation = EditorValidationResult.valid
    @State private var isSaving = false
    @State private var failureText: String?

    init(
        copy: EditorCopy,
        creator: any EditorTagCreating,
        isOnline: Bool,
        onCreated: @escaping (TagEditorItemDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.copy = copy
        self.creator = creator
        self.isOnline = isOnline
        self.onCreated = onCreated
        self.onCancel = onCancel
    }

    var body: some View {
        Form {
            Section {
                TextField(copy.tagName, text: $draft.name)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("editor.tag.name")
                EditorValidationMessage(issue: validation.errors[.tagName], copy: copy)
                TextField(copy.tagColor, text: $draft.colorHex)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                EditorValidationMessage(issue: validation.errors[.tagColor], copy: copy)
            }
            if let failureText {
                Section {
                    Label(failureText, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(copy.newTag)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(copy.cancel, action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(copy.save, action: save)
                    .disabled(isSaving)
            }
        }
        .accessibilityIdentifier("editor.tag")
    }

    private func save() {
        validation = EditorValidator.validate(draft)
        guard validation.isValid else { return }
        guard isOnline else {
            failureText = copy.networkRequired
            return
        }
        isSaving = true
        failureText = nil
        Task {
            do {
                let tag = try await creator.createTag(EditorValidator.payload(draft))
                isSaving = false
                onCreated(tag)
            } catch is CancellationError {
                isSaving = false
            } catch {
                isSaving = false
                failureText = copy.failed
            }
        }
    }
}
