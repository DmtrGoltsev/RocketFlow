import SwiftUI

@MainActor
struct FolderEditorView: View {
    @StateObject private var coordinator: EditorSaveCoordinator
    @State private var draft: FolderEditorDraft
    @State private var validation = EditorValidationResult.valid
    private let mode: EditorMode
    private let parentFolderID: UUID?
    private let copy: EditorCopy
    private let onCancel: () -> Void

    init(
        mode: EditorMode,
        parentFolderID: UUID?,
        initialDraft: FolderEditorDraft,
        language: AppLanguage,
        coordinator: EditorSaveCoordinator,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.parentFolderID = parentFolderID
        _draft = State(initialValue: initialDraft)
        copy = EditorCopy(language: language)
        _coordinator = StateObject(wrappedValue: coordinator)
        self.onCancel = onCancel
    }

    var body: some View {
        Form {
            Section {
                TextField(copy.name, text: $draft.name)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("editor.folder.name")
                EditorValidationMessage(issue: validation.errors[.name], copy: copy)
                TextEditor(text: $draft.description)
                    .frame(minHeight: 110)
                    .accessibilityLabel(copy.description)
                    .accessibilityIdentifier("editor.folder.description")
                EditorValidationMessage(issue: validation.errors[.description], copy: copy)
            }
        }
        .editorChrome(
            title: isCreate ? copy.newFolder : copy.editFolder,
            copy: copy,
            coordinator: coordinator,
            canSave: true,
            onCancel: onCancel,
            onSave: save,
            accessibilityID: "editor.folder"
        )
    }

    private var isCreate: Bool { if case .create = mode { return true }; return false }

    private func save() {
        validation = EditorValidator.validate(draft)
        guard validation.isValid else { return }
        Task {
            await coordinator.save(
                .folder(
                    mode: mode,
                    parentFolderID: parentFolderID,
                    payload: EditorValidator.payload(draft)
                )
            )
        }
    }
}

@MainActor
struct GoalEditorView: View {
    @StateObject private var coordinator: EditorSaveCoordinator
    @State private var draft: GoalEditorDraft
    @State private var validation = EditorValidationResult.valid
    private let mode: EditorMode
    private let folderID: UUID
    private let copy: EditorCopy
    private let onCancel: () -> Void

    init(
        mode: EditorMode,
        folderID: UUID,
        initialDraft: GoalEditorDraft,
        language: AppLanguage,
        coordinator: EditorSaveCoordinator,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.folderID = folderID
        _draft = State(initialValue: initialDraft)
        copy = EditorCopy(language: language)
        _coordinator = StateObject(wrappedValue: coordinator)
        self.onCancel = onCancel
    }

    var body: some View {
        Form {
            Section {
                TextField(copy.name, text: $draft.name)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("editor.goal.name")
                EditorValidationMessage(issue: validation.errors[.name], copy: copy)
                TextEditor(text: $draft.description)
                    .frame(minHeight: 110)
                    .accessibilityLabel(copy.description)
                EditorValidationMessage(issue: validation.errors[.description], copy: copy)
                Picker(copy.status, selection: $draft.status) {
                    ForEach(DetailTaskStatus.allCases, id: \.self) { status in
                        Text(copy.statusTitle(status)).tag(status)
                    }
                }
            }
        }
        .editorChrome(
            title: isCreate ? copy.newGoal : copy.editGoal,
            copy: copy,
            coordinator: coordinator,
            canSave: true,
            onCancel: onCancel,
            onSave: save,
            accessibilityID: "editor.goal"
        )
    }

    private var isCreate: Bool { if case .create = mode { return true }; return false }

    private func save() {
        validation = EditorValidator.validate(draft)
        guard validation.isValid else { return }
        Task {
            await coordinator.save(
                .goal(mode: mode, folderID: folderID, payload: EditorValidator.payload(draft))
            )
        }
    }
}

@MainActor
struct IdeaEditorView: View {
    @StateObject private var coordinator: EditorSaveCoordinator
    @State private var draft: IdeaEditorDraft
    @State private var validation = EditorValidationResult.valid
    private let mode: EditorMode
    private let folderID: UUID
    private let copy: EditorCopy
    private let onCancel: () -> Void

    init(
        mode: EditorMode,
        folderID: UUID,
        initialDraft: IdeaEditorDraft,
        language: AppLanguage,
        coordinator: EditorSaveCoordinator,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.folderID = folderID
        _draft = State(initialValue: initialDraft)
        copy = EditorCopy(language: language)
        _coordinator = StateObject(wrappedValue: coordinator)
        self.onCancel = onCancel
    }

    var body: some View {
        Form {
            Section {
                TextField(copy.title, text: $draft.title)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("editor.idea.title")
                EditorValidationMessage(issue: validation.errors[.title], copy: copy)
                TextEditor(text: $draft.body)
                    .frame(minHeight: 180)
                    .accessibilityLabel(copy.body)
                EditorValidationMessage(issue: validation.errors[.body], copy: copy)
                TextField(copy.status, text: $draft.status)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                EditorValidationMessage(issue: validation.errors[.status], copy: copy)
                LabeledContent(
                    copy.authorHistoryEdits,
                    value: draft.allowAuthorHistoryEdits ? copy.enabled : copy.disabled
                )
            }
        }
        .editorChrome(
            title: isCreate ? copy.newIdea : copy.editIdea,
            copy: copy,
            coordinator: coordinator,
            canSave: true,
            onCancel: onCancel,
            onSave: save,
            accessibilityID: "editor.idea"
        )
    }

    private var isCreate: Bool { if case .create = mode { return true }; return false }

    private func save() {
        validation = EditorValidator.validate(draft)
        guard validation.isValid else { return }
        Task {
            await coordinator.save(
                .idea(mode: mode, folderID: folderID, payload: EditorValidator.payload(draft))
            )
        }
    }
}

@MainActor
struct IdeaHistoryEditorView: View {
    @StateObject private var coordinator: EditorSaveCoordinator
    @State private var draft: IdeaHistoryEditorDraft
    @State private var validation = EditorValidationResult.valid
    private let mode: EditorMode
    private let ideaID: UUID
    private let copy: EditorCopy
    private let onCancel: () -> Void

    init(
        mode: EditorMode,
        ideaID: UUID,
        initialDraft: IdeaHistoryEditorDraft,
        language: AppLanguage,
        coordinator: EditorSaveCoordinator,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.ideaID = ideaID
        _draft = State(initialValue: initialDraft)
        copy = EditorCopy(language: language)
        _coordinator = StateObject(wrappedValue: coordinator)
        self.onCancel = onCancel
    }

    var body: some View {
        Form {
            Section {
                TextField(copy.eventType, text: $draft.eventType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("editor.ideaHistory.type")
                EditorValidationMessage(issue: validation.errors[.eventType], copy: copy)
                TextEditor(text: $draft.body)
                    .frame(minHeight: 180)
                    .accessibilityLabel(copy.body)
                EditorValidationMessage(issue: validation.errors[.body], copy: copy)
            }
        }
        .editorChrome(
            title: isCreate ? copy.newHistory : copy.editHistory,
            copy: copy,
            coordinator: coordinator,
            canSave: true,
            onCancel: onCancel,
            onSave: save,
            accessibilityID: "editor.ideaHistory"
        )
    }

    private var isCreate: Bool { if case .create = mode { return true }; return false }

    private func save() {
        validation = EditorValidator.validate(draft)
        guard validation.isValid else { return }
        Task {
            await coordinator.save(
                .ideaHistory(mode: mode, ideaID: ideaID, payload: EditorValidator.payload(draft))
            )
        }
    }
}

@MainActor
struct NoteEditorView: View {
    @StateObject private var coordinator: EditorSaveCoordinator
    @State private var draft: NoteEditorDraft
    @State private var validation = EditorValidationResult.valid
    private let mode: EditorMode
    private let folderID: UUID
    private let copy: EditorCopy
    private let onCancel: () -> Void

    init(
        mode: EditorMode,
        folderID: UUID,
        initialDraft: NoteEditorDraft,
        language: AppLanguage,
        coordinator: EditorSaveCoordinator,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.folderID = folderID
        _draft = State(initialValue: initialDraft)
        copy = EditorCopy(language: language)
        _coordinator = StateObject(wrappedValue: coordinator)
        self.onCancel = onCancel
    }

    var body: some View {
        Form {
            Section {
                TextField(copy.title, text: $draft.title)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("editor.note.title")
                EditorValidationMessage(issue: validation.errors[.title], copy: copy)
                TextEditor(text: $draft.body)
                    .frame(minHeight: 220)
                    .accessibilityLabel(copy.body)
                EditorValidationMessage(issue: validation.errors[.body], copy: copy)
            }
        }
        .editorChrome(
            title: isCreate ? copy.newNote : copy.editNote,
            copy: copy,
            coordinator: coordinator,
            canSave: true,
            onCancel: onCancel,
            onSave: save,
            accessibilityID: "editor.note"
        )
    }

    private var isCreate: Bool { if case .create = mode { return true }; return false }

    private func save() {
        validation = EditorValidator.validate(draft)
        guard validation.isValid else { return }
        Task {
            await coordinator.save(
                .note(mode: mode, folderID: folderID, payload: EditorValidator.payload(draft))
            )
        }
    }
}
