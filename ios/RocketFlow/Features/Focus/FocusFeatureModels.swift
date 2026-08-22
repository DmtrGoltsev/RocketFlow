import Foundation

enum FocusScreenPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case offline
    case unauthorized
    case error
}

struct FocusCandidateGoalGroup: Equatable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let candidates: [FocusCandidateDTO]
}

struct FocusCandidateFolderGroup: Equatable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let goals: [FocusCandidateGoalGroup]
}

enum FocusCandidateCollection {
    static func merge(
        existing: [FocusCandidateDTO],
        incoming: [FocusCandidateDTO],
        selectedTaskIDs: Set<UUID>
    ) -> [FocusCandidateDTO] {
        var byTask: [UUID: FocusCandidateDTO] = [:]
        for candidate in existing + incoming {
            byTask[candidate.taskId] = candidate
        }
        return byTask.values.filter {
            !$0.inFocus && !selectedTaskIDs.contains($0.taskId)
        }
        .sorted { $0.taskId.uuidString.lowercased() < $1.taskId.uuidString.lowercased() }
    }

    static func hierarchy(
        _ candidates: [FocusCandidateDTO],
        language: AppLanguage
    ) -> [FocusCandidateFolderGroup] {
        let locale = Locale(identifier: language == .ru ? "ru_RU" : "en_US")
        let folders = Dictionary(grouping: candidates, by: \.folderId)
        return folders.map { folderID, folderCandidates in
            let goals = Dictionary(grouping: folderCandidates, by: \.goalId).map { goalID, goalCandidates in
                FocusCandidateGoalGroup(
                    id: goalID,
                    title: goalCandidates.first?.goalTitle ?? "",
                    candidates: goalCandidates.sorted {
                        localizedCompare($0.title, $1.title, locale: locale)
                    }
                )
            }
            .sorted { localizedCompare($0.title, $1.title, locale: locale) }
            return FocusCandidateFolderGroup(
                id: folderID,
                title: folderCandidates.first?.folderTitle ?? "",
                goals: goals
            )
        }
        .sorted { localizedCompare($0.title, $1.title, locale: locale) }
    }

    private static func localizedCompare(_ lhs: String, _ rhs: String, locale: Locale) -> Bool {
        let comparison = lhs.compare(
            rhs,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: nil,
            locale: locale
        )
        return comparison == .orderedAscending
    }
}

enum FocusFormatting {
    static func path(folder: String, goal: String) -> String {
        [folder, goal].filter { !$0.isEmpty }.joined(separator: " / ")
    }

    static func week(
        start: LocalDate,
        endExclusive: LocalDate,
        language: AppLanguage
    ) -> String {
        let locale = Locale(identifier: language == .ru ? "ru_RU" : "en_US")
        let startDate = date(start)
        let endDate = utcCalendar().date(byAdding: .day, value: -1, to: date(endExclusive))!
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }

    static func cadence(_ minutes: Int?, language: AppLanguage) -> String {
        guard let minutes else { return language == .ru ? "Выключено" : "Off" }
        if minutes < 60 {
            return language == .ru ? "Каждые \(minutes) мин" : "Every \(minutes) min"
        }
        let hours = minutes / 60
        return language == .ru ? "Каждые \(hours) ч" : "Every \(hours) hr"
    }

    private static func date(_ value: LocalDate) -> Date {
        let values = value.rawValue.split(separator: "-").map { Int($0)! }
        return utcCalendar().date(
            from: DateComponents(year: values[0], month: values[1], day: values[2])
        )!
    }

    private static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

enum FocusAccessibility {
    static func status(_ status: PlanningStatus, copy: FocusCopy) -> String {
        switch status {
        case .todo: copy.statusTodo
        case .inProgress: copy.statusInProgress
        case .done: copy.statusDone
        case .cancelled: copy.statusCancelled
        }
    }

    static func itemLabel(_ item: FocusItemDTO, copy: FocusCopy) -> String {
        var parts = [
            item.title,
            status(item.status, copy: copy),
            FocusFormatting.path(folder: item.folderTitle, goal: item.goalTitle),
            "\(copy.effort): \(max(item.effectiveWeight, 1))"
        ]
        if item.shared { parts.append(copy.shared) }
        if !item.canWrite { parts.append(copy.readOnly) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static func candidateLabel(_ candidate: FocusCandidateDTO, copy: FocusCopy) -> String {
        var parts = [
            candidate.title,
            status(candidate.status, copy: copy),
            FocusFormatting.path(folder: candidate.folderTitle, goal: candidate.goalTitle),
            "\(copy.effort): \(max(candidate.effectiveWeight, 1))"
        ]
        if candidate.shared { parts.append(copy.shared) }
        if !candidate.canWrite { parts.append(copy.readOnly) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct FocusCopy: Sendable {
    let title: String
    let add: String
    let history: String
    let settings: String
    let loading: String
    let empty: String
    let offline: String
    let unavailable: String
    let unauthorized: String
    let pending: String
    let terminalIssue: String
    let completed: String
    let effort: String
    let shared: String
    let readOnly: String
    let moveUp: String
    let moveDown: String
    let remove: String
    let rollover: String
    let carryOver: String
    let selectedState: String
    let notSelectedState: String
    let apply: String
    let cancel: String
    let search: String
    let noCandidates: String
    let loadMore: String
    let currentWeek: String
    let back: String
    let cadence: String
    let quietHours: String
    let quietStart: String
    let quietEnd: String
    let save: String
    let cadenceInvalid: String
    let quietPairInvalid: String
    let quietTimeInvalid: String
    let retry: String
    let openTask: String
    let taskUnavailable: String
    let statusTodo: String
    let statusInProgress: String
    let statusDone: String
    let statusCancelled: String

    init(language: AppLanguage) {
        if language == .ru {
            title = "Фокус"
            add = "Добавить задачу"
            history = "История"
            settings = "Настройки фокуса"
            loading = "Загрузка фокуса"
            empty = "Добавьте задачи из ваших целей"
            offline = "Нет сети. Показаны сохранённые данные"
            unavailable = "Фокус сейчас недоступен"
            unauthorized = "Сеанс завершён. Войдите снова"
            pending = "Ожидают синхронизации"
            terminalIssue = "Требуется внимание"
            completed = "Выполнено"
            effort = "Вес"
            shared = "Общая задача"
            readOnly = "Только чтение"
            moveUp = "Переместить выше"
            moveDown = "Переместить ниже"
            remove = "Убрать из фокуса"
            rollover = "Перенос с прошлой недели"
            carryOver = "Перенести выбранные"
            selectedState = "Выбрано"
            notSelectedState = "Не выбрано"
            apply = "Применить"
            cancel = "Отмена"
            search = "Поиск задач"
            noCandidates = "Подходящих задач нет"
            loadMore = "Показать ещё"
            currentWeek = "Текущая неделя"
            back = "Назад"
            cadence = "Частота напоминаний"
            quietHours = "Тихие часы"
            quietStart = "Начало"
            quietEnd = "Окончание"
            save = "Сохранить"
            cadenceInvalid = "Выберите поддерживаемую частоту"
            quietPairInvalid = "Укажите оба значения тихих часов или очистите оба"
            quietTimeInvalid = "Используйте формат ЧЧ:мм"
            retry = "Повторить"
            openTask = "Открыть задачу"
            taskUnavailable = "Задача пока недоступна на этом устройстве"
            statusTodo = "Не начата"
            statusInProgress = "В работе"
            statusDone = "Выполнена"
            statusCancelled = "Отменена"
        } else {
            title = "Focus"
            add = "Add task"
            history = "History"
            settings = "Focus settings"
            loading = "Loading focus"
            empty = "Add tasks from your goals"
            offline = "Offline. Showing saved data"
            unavailable = "Focus is currently unavailable"
            unauthorized = "Your session ended. Sign in again"
            pending = "Pending sync"
            terminalIssue = "Needs attention"
            completed = "Completed"
            effort = "Weight"
            shared = "Shared task"
            readOnly = "Read only"
            moveUp = "Move up"
            moveDown = "Move down"
            remove = "Remove from focus"
            rollover = "Carry over from last week"
            carryOver = "Carry over selected"
            selectedState = "Selected"
            notSelectedState = "Not selected"
            apply = "Apply"
            cancel = "Cancel"
            search = "Search tasks"
            noCandidates = "No eligible tasks"
            loadMore = "Show more"
            currentWeek = "Current week"
            back = "Back"
            cadence = "Reminder cadence"
            quietHours = "Quiet hours"
            quietStart = "Start"
            quietEnd = "End"
            save = "Save"
            cadenceInvalid = "Choose a supported cadence"
            quietPairInvalid = "Set both quiet-hour values or clear both"
            quietTimeInvalid = "Use HH:mm format"
            retry = "Retry"
            openTask = "Open task"
            taskUnavailable = "Task is not available on this device yet"
            statusTodo = "Not started"
            statusInProgress = "In progress"
            statusDone = "Completed"
            statusCancelled = "Cancelled"
        }
    }
}
