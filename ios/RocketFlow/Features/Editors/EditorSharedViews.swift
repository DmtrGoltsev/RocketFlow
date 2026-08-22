import SwiftUI

struct EditorStateBanner: View {
    let state: EditorSaveState
    let copy: EditorCopy

    var body: some View {
        switch state {
        case .saving:
            Label(copy.saving, systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .pending:
            Label(copy.pending, systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.orange)
        case .networkRequired:
            Label(copy.networkRequired, systemImage: "wifi.slash")
                .foregroundStyle(.red)
        case .error:
            Label(copy.failed, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        case .idle, .saved:
            EmptyView()
        }
    }
}

struct EditorValidationMessage: View {
    let issue: EditorValidationIssue?
    let copy: EditorCopy

    var body: some View {
        if let issue {
            Text(copy.validationText(issue))
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("editor.validation")
        }
    }
}

struct NullableDateEditorRow: View {
    let title: String
    @Binding var value: Date?

    var body: some View {
        Toggle(isOn: enabled) {
            Text(title)
        }
        if let value {
            DatePicker(
                title,
                selection: Binding(
                    get: { value },
                    set: { self.value = $0 }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .accessibilityLabel(title)
        }
    }

    private var enabled: Binding<Bool> {
        Binding(
            get: { value != nil },
            set: { isEnabled in value = isEnabled ? (value ?? Date()) : nil }
        )
    }
}

extension View {
    func editorChrome(
        title: String,
        copy: EditorCopy,
        coordinator: EditorSaveCoordinator,
        canSave: Bool,
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void,
        accessibilityID: String
    ) -> some View {
        modifier(
            EditorChromeModifier(
                title: title,
                copy: copy,
                coordinator: coordinator,
                canSave: canSave,
                onCancel: onCancel,
                onSave: onSave,
                accessibilityID: accessibilityID
            )
        )
    }
}

private struct EditorChromeModifier: ViewModifier {
    let title: String
    let copy: EditorCopy
    @ObservedObject var coordinator: EditorSaveCoordinator
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    let accessibilityID: String

    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                EditorStateBanner(state: coordinator.state, copy: copy)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, coordinator.state == .idle || coordinator.state == .saved ? 0 : 8)
                    .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy.cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy.save, action: onSave)
                        .disabled(!canSave || coordinator.state == .saving)
                }
            }
            .accessibilityIdentifier(accessibilityID)
    }
}
