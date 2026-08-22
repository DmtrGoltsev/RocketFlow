import Foundation
@testable import RocketFlow

enum PlannerTestFixtures {
    static let folderID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let goalID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    static let taskID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    static let ideaID = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
    static let noteID = UUID(uuidString: "50000000-0000-0000-0000-000000000005")!

    static func item(
        kind: PlannerItemKind,
        id: UUID,
        parent: PlannerItemReference? = nil,
        title: String,
        subtitle: String = "",
        status: PlanningStatus? = nil,
        createdAt: TimeInterval,
        archived: Bool = false,
        shared: Bool = false,
        fullAccess: Bool = true,
        canDelete: Bool? = nil,
        capabilities: PlannerCapabilitySet? = nil
    ) -> PlannerItemViewData {
        PlannerItemViewData(
            reference: PlannerItemReference(kind: kind, id: id),
            parent: parent,
            title: title,
            subtitle: subtitle,
            searchText: subtitle,
            status: status,
            createdAt: Date(timeIntervalSince1970: createdAt),
            isArchived: archived,
            isShared: shared,
            fullAccess: fullAccess,
            canDelete: canDelete,
            capabilities: capabilities
        )
    }

    static func hierarchy(shared: Bool = false, fullAccess: Bool = true) -> [PlannerItemViewData] {
        let folder = item(
            kind: .folder,
            id: folderID,
            title: "Работа",
            subtitle: "Основная папка",
            createdAt: 100,
            shared: shared,
            fullAccess: fullAccess
        )
        let goal = item(
            kind: .goal,
            id: goalID,
            parent: folder.reference,
            title: "Выпустить iOS",
            subtitle: "Релизная цель",
            createdAt: 200,
            shared: shared,
            fullAccess: fullAccess
        )
        let task = item(
            kind: .task,
            id: taskID,
            parent: goal.reference,
            title: "Проверить сборку",
            subtitle: "На симуляторе",
            status: .todo,
            createdAt: 300,
            shared: shared,
            fullAccess: fullAccess
        )
        let idea = item(
            kind: .idea,
            id: ideaID,
            parent: folder.reference,
            title: "Идея интерфейса",
            subtitle: "Компактные строки",
            createdAt: 400,
            shared: shared,
            fullAccess: fullAccess
        )
        let note = item(
            kind: .note,
            id: noteID,
            parent: folder.reference,
            title: "Заметка релиза",
            subtitle: "Проверить локализацию",
            createdAt: 500,
            shared: shared,
            fullAccess: fullAccess
        )
        return [folder, goal, task, idea, note]
    }

    static var snapshot: PlannerSnapshot {
        PlannerSnapshot(items: hierarchy())
    }
}
