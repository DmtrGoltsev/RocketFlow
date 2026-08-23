import Combine
import Foundation

@MainActor
final class EditorSaveCoordinator: ObservableObject {
    @Published private(set) var state: EditorSaveState = .idle

    let context: EditorContext
    var isOnline: Bool

    private let saver: any EditorSaving
    private let onComplete: @MainActor (DetailNavigationResult) -> Void

    init(
        context: EditorContext,
        isOnline: Bool,
        saver: any EditorSaving,
        onComplete: @escaping @MainActor (DetailNavigationResult) -> Void
    ) {
        self.context = context
        self.isOnline = isOnline
        self.saver = saver
        self.onComplete = onComplete
    }

    func save(_ request: EditorSaveRequest) async {
        guard state != .saving else { return }
        if request.requiresNetwork, !isOnline {
            state = .networkRequired
            return
        }
        state = .saving
        do {
            let result = try await saver.saveEditor(request)
            state = result.pending ? .pending : .saved
            onComplete(navigation(for: result))
        } catch is CancellationError {
            state = .idle
        } catch let failure as EditorReminderFailure {
            state = .reminderError(failure)
        } catch {
            state = .error
        }
    }

    func resetError() {
        switch state {
        case .error, .networkRequired, .reminderError:
            state = .idle
        case .idle, .saving, .saved, .pending:
            break
        }
    }

    func abandonOperation(_ operationID: UUID) async {
        guard let recovery = saver as? any EditorOperationRecoveryManaging else { return }
        await recovery.abandonEditorOperation(operationID)
    }

    private func navigation(for result: EditorSaveResult) -> DetailNavigationResult {
        switch context.afterSave {
        case .stayOnCurrentDetail:
            if let parent = context.parent {
                return .open(parent, origin: context.origin)
            }
            return .open(result.reference, origin: context.origin)
        case .openCreated:
            return .open(result.reference, origin: context.origin)
        case let .goalDetail(goalID):
            if result.reference.kind == .task {
                return .taskCreated(
                    taskID: result.reference.id,
                    returnToGoalID: goalID,
                    origin: context.origin
                )
            }
            return .open(
                DetailEntityReference(kind: .goal, id: goalID),
                origin: context.origin
            )
        }
    }
}
