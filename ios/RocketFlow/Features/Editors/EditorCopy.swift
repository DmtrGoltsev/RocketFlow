import Foundation

struct EditorCopy: Sendable {
    private let language: AppLanguage
    let newFolder: String
    let editFolder: String
    let newGoal: String
    let editGoal: String
    let newTask: String
    let editTask: String
    let newIdea: String
    let editIdea: String
    let newHistory: String
    let editHistory: String
    let newNote: String
    let editNote: String
    let newTag: String
    let name: String
    let title: String
    let description: String
    let body: String
    let status: String
    let type: String
    let effort: String
    let plannedDate: String
    let dueDate: String
    let recurrence: String
    let noRecurrence: String
    let daily: String
    let weekly: String
    let monthly: String
    let interval: String
    let weekdays: String
    let monthDay: String
    let recurrenceEnd: String
    let recurrenceAnchorSource: String
    let checklist: String
    let addChecklist: String
    let tags: String
    let tagName: String
    let tagColor: String
    let createTag: String
    let focus: String
    let eventType: String
    let authorHistoryEdits: String
    let enabled: String
    let disabled: String
    let save: String
    let cancel: String
    let saving: String
    let pending: String
    let networkRequired: String
    let failed: String
    let required: String
    let nonnegative: String
    let recurrenceAnchor: String
    let recurrenceInvalid: String
    let recurrenceEndInvalid: String
    let statusOnly: String
    let todo: String
    let inProgress: String
    let done: String
    let cancelled: String
    let green: String
    let red: String

    init(language: AppLanguage) {
        self.language = language
        if language == .ru {
            newFolder = "Новая папка"
            editFolder = "Изменить папку"
            newGoal = "Новая цель"
            editGoal = "Изменить цель"
            newTask = "Новая задача"
            editTask = "Изменить задачу"
            newIdea = "Новая идея"
            editIdea = "Изменить идею"
            newHistory = "Новая запись"
            editHistory = "Изменить запись"
            newNote = "Новая заметка"
            editNote = "Изменить заметку"
            newTag = "Новый тег"
            name = "Название"
            title = "Заголовок"
            description = "Описание"
            body = "Текст"
            status = "Статус"
            type = "Тип"
            effort = "Трудоемкость"
            plannedDate = "Плановая дата"
            dueDate = "Срок"
            recurrence = "Повторение"
            noRecurrence = "Не повторять"
            daily = "Ежедневно"
            weekly = "Еженедельно"
            monthly = "Ежемесячно"
            interval = "Интервал"
            weekdays = "Дни недели"
            monthDay = "День месяца"
            recurrenceEnd = "Дата окончания"
            recurrenceAnchorSource = "Дата начала повторения"
            checklist = "Чек-лист"
            addChecklist = "Добавить пункт"
            tags = "Теги"
            tagName = "Название тега"
            tagColor = "Цвет HEX"
            createTag = "Создать тег"
            focus = "В фокусе"
            eventType = "Тип записи"
            authorHistoryEdits = "Авторы могут изменять свои записи"
            enabled = "Включено"
            disabled = "Выключено"
            save = "Сохранить"
            cancel = "Отмена"
            saving = "Сохранение"
            pending = "Сохранено локально, ожидает синхронизации"
            networkRequired = "Для этого действия требуется подключение к сети"
            failed = "Не удалось сохранить изменения"
            required = "Заполните поле"
            nonnegative = "Значение не может быть отрицательным"
            recurrenceAnchor = "Укажите плановую дату или срок"
            recurrenceInvalid = "Параметры повторения не совпадают с датой начала"
            recurrenceEndInvalid = "Дата окончания должна быть позже даты начала"
            statusOnly = "В общей задаче можно изменить только статус"
            todo = "К выполнению"
            inProgress = "В работе"
            done = "Выполнено"
            cancelled = "Отменено"
            green = "Зеленая"
            red = "Красная"
        } else {
            newFolder = "New folder"
            editFolder = "Edit folder"
            newGoal = "New goal"
            editGoal = "Edit goal"
            newTask = "New task"
            editTask = "Edit task"
            newIdea = "New idea"
            editIdea = "Edit idea"
            newHistory = "New history entry"
            editHistory = "Edit history entry"
            newNote = "New note"
            editNote = "Edit note"
            newTag = "New tag"
            name = "Name"
            title = "Title"
            description = "Description"
            body = "Body"
            status = "Status"
            type = "Type"
            effort = "Effort"
            plannedDate = "Planned date"
            dueDate = "Due date"
            recurrence = "Recurrence"
            noRecurrence = "Does not repeat"
            daily = "Daily"
            weekly = "Weekly"
            monthly = "Monthly"
            interval = "Interval"
            weekdays = "Weekdays"
            monthDay = "Day of month"
            recurrenceEnd = "End date"
            recurrenceAnchorSource = "Recurrence starts from"
            checklist = "Checklist"
            addChecklist = "Add item"
            tags = "Tags"
            tagName = "Tag name"
            tagColor = "HEX color"
            createTag = "Create tag"
            focus = "In Focus"
            eventType = "Entry type"
            authorHistoryEdits = "Authors can edit their entries"
            enabled = "Enabled"
            disabled = "Disabled"
            save = "Save"
            cancel = "Cancel"
            saving = "Saving"
            pending = "Saved locally and waiting to sync"
            networkRequired = "This action requires a network connection"
            failed = "Changes could not be saved"
            required = "This field is required"
            nonnegative = "Value cannot be negative"
            recurrenceAnchor = "Set a planned date or due date"
            recurrenceInvalid = "Recurrence settings do not match the anchor date"
            recurrenceEndInvalid = "The end date must be after the anchor date"
            statusOnly = "Only status can be changed on this shared task"
            todo = "To do"
            inProgress = "In progress"
            done = "Done"
            cancelled = "Cancelled"
            green = "Green"
            red = "Red"
        }
    }

    func statusTitle(_ status: DetailTaskStatus) -> String {
        switch status {
        case .todo: todo
        case .inProgress: inProgress
        case .done: done
        case .cancelled: cancelled
        }
    }

    func weekdayTitle(_ weekday: DetailWeekday) -> String {
        if language == .ru {
            switch weekday {
            case .monday: "Пн"
            case .tuesday: "Вт"
            case .wednesday: "Ср"
            case .thursday: "Чт"
            case .friday: "Пт"
            case .saturday: "Сб"
            case .sunday: "Вс"
            }
        } else {
            switch weekday {
            case .monday: "Mon"
            case .tuesday: "Tue"
            case .wednesday: "Wed"
            case .thursday: "Thu"
            case .friday: "Fri"
            case .saturday: "Sat"
            case .sunday: "Sun"
            }
        }
    }

    func checklistToggleLabel(text: String, checked: Bool) -> String {
        let item = text.isEmpty ? addChecklist : text
        if language == .ru {
            return checked
                ? "Отметить «\(item)» как невыполненное"
                : "Отметить «\(item)» как выполненное"
        }
        return checked ? "Mark \(item) as not done" : "Mark \(item) as done"
    }

    func checklistDeleteLabel(text: String) -> String {
        let item = text.isEmpty ? addChecklist : text
        return language == .ru ? "Удалить пункт «\(item)»" : "Delete \(item)"
    }

    func recurrenceTitle(_ mode: DetailRecurrenceMode?) -> String {
        switch mode {
        case nil: noRecurrence
        case .daily: daily
        case .weekly: weekly
        case .monthly: monthly
        }
    }

    func validationText(_ issue: EditorValidationIssue) -> String {
        return switch issue {
        case .required: required
        case let .tooLong(maximum):
            languageMaximum(maximum)
        case .mustBeNonnegative: nonnegative
        case .recurrenceAnchorRequired: recurrenceAnchor
        case .recurrenceEndInvalid: recurrenceEndInvalid
        case .recurrenceIntervalInvalid, .recurrenceWeekdayRequired,
             .recurrenceAnchorWeekdayRequired, .recurrenceDayInvalid,
             .recurrenceAnchorDayRequired:
            recurrenceInvalid
        }
    }

    private func languageMaximum(_ maximum: Int) -> String {
        if save == "Сохранить" { return "Не более \(maximum) символов" }
        return "Maximum \(maximum) characters"
    }
}
