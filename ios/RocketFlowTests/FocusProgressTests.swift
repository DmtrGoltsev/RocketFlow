import Foundation
import XCTest
@testable import RocketFlow

final class FocusProgressTests: XCTestCase {
    func testProgressUsesMinimumWeightCountsOnlyDoneAndExcludesHistoryOnly() {
        let items = [
            item(title: "Done nil", status: .done, effort: nil, position: 0),
            item(title: "Done zero", status: .done, effort: 0, position: 1),
            item(title: "Todo", status: .todo, effort: 4, position: 2),
            item(title: "History", status: .done, effort: 100, position: 3, historyOnly: true)
        ]

        let progress = FocusProgressCalculator.current(items)

        XCTAssertEqual(progress.completedWeight, 2)
        XCTAssertEqual(progress.totalWeight, 6)
        XCTAssertEqual(progress.percent, 33)
        XCTAssertEqual(progress.completedCount, 2)
        XCTAssertEqual(progress.totalCount, 3)
    }

    func testHistoricalProgressIncludesHistoryOnlySnapshots() {
        let items = [
            item(title: "Done", status: .done, effort: 2, position: 0),
            item(title: "Historical", status: .done, effort: 3, position: 1, historyOnly: true),
            item(title: "Todo", status: .todo, effort: 1, position: 2)
        ]

        let progress = FocusProgressCalculator.history(items)

        XCTAssertEqual(progress.completedWeight, 5)
        XCTAssertEqual(progress.totalWeight, 6)
        XCTAssertEqual(progress.percent, 83)
        XCTAssertEqual(progress.completedCount, 2)
        XCTAssertEqual(progress.totalCount, 3)
    }

    func testProgressUsesBackendEffectiveWeightSnapshot() {
        let progress = FocusProgressCalculator.history([
            item(title: "Done", status: .done, effort: 100, effectiveWeight: 2, position: 0),
            item(title: "Todo", status: .todo, effort: 1, effectiveWeight: 4, position: 1)
        ])

        XCTAssertEqual(progress.completedWeight, 2)
        XCTAssertEqual(progress.totalWeight, 6)
        XCTAssertEqual(progress.percent, 33)
    }

    func testProgressRoundsToNearestServerCompatiblePercent() {
        let seventeen = FocusProgressCalculator.current([
            item(title: "Done", status: .done, effort: 1, position: 0),
            item(title: "Todo", status: .todo, effort: 5, position: 1)
        ])
        let sixtySeven = FocusProgressCalculator.current([
            item(title: "Done", status: .done, effort: 2, position: 0),
            item(title: "Todo", status: .todo, effort: 1, position: 1)
        ])

        XCTAssertEqual(seventeen.percent, 17)
        XCTAssertEqual(sixtySeven.percent, 67)
    }

    func testEmptyCurrentProgressIsZero() {
        let progress = FocusProgressCalculator.current([
            item(title: "History", status: .done, effort: 10, position: 0, historyOnly: true)
        ])

        XCTAssertEqual(progress, FocusProgressDTO(
            completedWeight: 0,
            totalWeight: 0,
            percent: 0,
            completedCount: 0,
            totalCount: 0
        ))
    }

    func testCadenceAcceptsFrozenOptionsPairedStrictTimesAndOvernightRange() throws {
        for interval in [nil, 30, 60, 120, 240] as [Int?] {
            XCTAssertNoThrow(
                try FocusCadenceValidator.validate(
                    FocusCadenceValues(
                        intervalMinutes: interval,
                        quietHoursStart: "22:00",
                        quietHoursEnd: "08:00"
                    )
                )
            )
        }
        XCTAssertNoThrow(
            try FocusCadenceValidator.validate(
                FocusCadenceValues(intervalMinutes: nil, quietHoursStart: nil, quietHoursEnd: nil)
            )
        )
    }

    func testCadenceRejectsUnsupportedPairAndNonStrictTime() {
        XCTAssertThrowsError(
            try FocusCadenceValidator.validate(
                FocusCadenceValues(intervalMinutes: 45, quietHoursStart: nil, quietHoursEnd: nil)
            )
        ) { XCTAssertEqual($0 as? FocusCadenceValidationError, .unsupportedInterval) }
        XCTAssertThrowsError(
            try FocusCadenceValidator.validate(
                FocusCadenceValues(intervalMinutes: 60, quietHoursStart: "22:00", quietHoursEnd: nil)
            )
        ) { XCTAssertEqual($0 as? FocusCadenceValidationError, .quietHoursPairRequired) }
        XCTAssertThrowsError(
            try FocusCadenceValidator.validate(
                FocusCadenceValues(intervalMinutes: 60, quietHoursStart: "8:00", quietHoursEnd: "24:00")
            )
        ) { XCTAssertEqual($0 as? FocusCadenceValidationError, .invalidQuietHours) }
    }

    func testCandidateMergeDeduplicatesLatestExcludesSelectedAndKeepsEligibleShared() {
        let duplicateID = UUID()
        let selectedID = UUID()
        let sharedID = UUID()
        let result = FocusCandidateCollection.merge(
            existing: [candidate(id: duplicateID, title: "Old")],
            incoming: [
                candidate(id: duplicateID, title: "New"),
                candidate(id: selectedID, title: "Selected"),
                candidate(id: sharedID, title: "Shared", shared: true, canWrite: false)
            ],
            selectedTaskIDs: [selectedID]
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first(where: { $0.taskId == duplicateID })?.title, "New")
        XCTAssertTrue(result.contains(where: { $0.taskId == sharedID && $0.shared && !$0.canWrite }))
    }

    func testCandidateHierarchyGroupsByStableFolderAndGoalIDs() {
        let folderA = UUID()
        let folderB = UUID()
        let goalA = UUID()
        let goalB = UUID()
        let values = [
            candidate(id: UUID(), title: "Zulu", folderID: folderA, folder: "Alpha", goalID: goalA, goal: "One"),
            candidate(id: UUID(), title: "Alpha", folderID: folderA, folder: "Alpha", goalID: goalA, goal: "One"),
            candidate(id: UUID(), title: "Task", folderID: folderB, folder: "Beta", goalID: goalB, goal: "Two")
        ]

        let hierarchy = FocusCandidateCollection.hierarchy(values, language: .en)

        XCTAssertEqual(hierarchy.map(\.id), [folderA, folderB])
        XCTAssertEqual(hierarchy[0].goals.first?.id, goalA)
        XCTAssertEqual(hierarchy[0].goals.first?.candidates.map(\.title), ["Alpha", "Zulu"])
    }

    func testAccessibilityLabelsExposeTaskStatusInBothLanguages() {
        let value = item(title: "Launch", status: .done, effort: 2, position: 0)

        let english = FocusAccessibility.itemLabel(value, copy: FocusCopy(language: .en))
        let russian = FocusAccessibility.itemLabel(value, copy: FocusCopy(language: .ru))

        XCTAssertTrue(english.contains("Completed"))
        XCTAssertTrue(russian.contains("Выполнена"))
    }

    private func item(
        title: String,
        status: PlanningStatus,
        effort: Int?,
        effectiveWeight: Int? = nil,
        position: Int,
        historyOnly: Bool = false
    ) -> FocusItemDTO {
        FocusItemDTO(
            id: UUID(), taskId: UUID(), title: title, status: status,
            effort: effort, effectiveWeight: effectiveWeight ?? max(effort ?? 0, 1),
            plannedTime: nil, dueTime: nil, position: position,
            historyOnly: historyOnly, folderId: UUID(), folderTitle: "Folder",
            goalId: UUID(), goalTitle: "Goal", shared: false, canWrite: true
        )
    }

    private func candidate(
        id: UUID,
        title: String,
        folderID: UUID = UUID(),
        folder: String = "Folder",
        goalID: UUID = UUID(),
        goal: String = "Goal",
        shared: Bool = false,
        canWrite: Bool = true
    ) -> FocusCandidateDTO {
        FocusCandidateDTO(
            taskId: id, title: title, status: .todo, effort: 1, effectiveWeight: 1,
            plannedTime: nil, dueTime: nil, folderId: folderID, folderTitle: folder,
            goalId: goalID, goalTitle: goal, shared: shared, canWrite: canWrite, inFocus: false
        )
    }
}
