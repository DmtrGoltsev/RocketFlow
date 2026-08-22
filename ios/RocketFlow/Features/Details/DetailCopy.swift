import Foundation

struct DetailCopy: Sendable {
    let folder: String
    let goal: String
    let task: String
    let idea: String
    let note: String
    let description: String
    let activity: String
    let children: String
    let tasks: String
    let checklist: String
    let tags: String
    let links: String
    let history: String
    let status: String
    let type: String
    let effort: String
    let plannedDate: String
    let dueDate: String
    let recurrence: String
    let author: String
    let authorHistoryEdits: String
    let enabled: String
    let disabled: String
    let loading: String
    let offline: String
    let pending: String
    let unavailable: String
    let networkRequired: String
    let dependencyBlocked: String
    let dependencyAction: String
    let retry: String
    let empty: String
    let create: String
    let createFolder: String
    let createGoal: String
    let createTask: String
    let createIdea: String
    let createNote: String
    let createHistory: String
    let edit: String
    let move: String
    let clone: String
    let delete: String
    let share: String
    let reschedule: String
    let addToFocus: String
    let removeFromFocus: String
    let cancel: String
    let confirmDelete: String
    let moreActions: String
    let readOnly: String
    let fullAccess: String
    let statusTodo: String
    let statusInProgress: String
    let statusDone: String
    let statusCancelled: String
    let typeGreen: String
    let typeRed: String

    init(language: AppLanguage) {
        if language == .ru {
            folder = "Папка"
            goal = "Цель"
            task = "Задача"
            idea = "Идея"
            note = "Заметка"
            description = "Описание"
            activity = "Активность"
            children = "Содержимое"
            tasks = "Задачи"
            checklist = "Чек-лист"
            tags = "Теги"
            links = "Связи"
            history = "История"
            status = "Статус"
            type = "Тип"
            effort = "Трудоемкость"
            plannedDate = "Плановая дата"
            dueDate = "Срок"
            recurrence = "Повторение"
            author = "Автор"
            authorHistoryEdits = "Авторы могут изменять свои записи"
            enabled = "Включено"
            disabled = "Выключено"
            loading = "Загрузка"
            offline = "Нет сети. Показаны сохраненные данные"
            pending = "Изменения ожидают синхронизации"
            unavailable = "Данные сейчас недоступны"
            networkRequired = "Для этого действия требуется подключение к сети"
            dependencyBlocked = "Задачу нельзя завершить: сначала выполните зависимые задачи"
            dependencyAction = "Показать связи"
            retry = "Повторить"
            empty = "Пока пусто"
            create = "Создать"
            createFolder = "Вложенную папку"
            createGoal = "Цель"
            createTask = "Задачу"
            createIdea = "Идею"
            createNote = "Заметку"
            createHistory = "Запись истории"
            edit = "Изменить"
            move = "Переместить"
            clone = "Клонировать"
            delete = "Удалить"
            share = "Поделиться"
            reschedule = "Перенести дату"
            addToFocus = "Добавить в фокус"
            removeFromFocus = "Убрать из фокуса"
            cancel = "Отмена"
            confirmDelete = "Удалить без возможности отмены?"
            moreActions = "Другие действия"
            readOnly = "Только просмотр"
            fullAccess = "Полный доступ"
            statusTodo = "К выполнению"
            statusInProgress = "В работе"
            statusDone = "Выполнено"
            statusCancelled = "Отменено"
            typeGreen = "Зеленая"
            typeRed = "Красная"
        } else {
            folder = "Folder"
            goal = "Goal"
            task = "Task"
            idea = "Idea"
            note = "Note"
            description = "Description"
            activity = "Activity"
            children = "Contents"
            tasks = "Tasks"
            checklist = "Checklist"
            tags = "Tags"
            links = "Links"
            history = "History"
            status = "Status"
            type = "Type"
            effort = "Effort"
            plannedDate = "Planned date"
            dueDate = "Due date"
            recurrence = "Recurrence"
            author = "Author"
            authorHistoryEdits = "Authors can edit their entries"
            enabled = "Enabled"
            disabled = "Disabled"
            loading = "Loading"
            offline = "Offline. Showing saved data"
            pending = "Changes are waiting to sync"
            unavailable = "Data is currently unavailable"
            networkRequired = "This action requires a network connection"
            dependencyBlocked = "This task cannot be completed until its dependencies are done"
            dependencyAction = "Show links"
            retry = "Retry"
            empty = "Nothing here yet"
            create = "Create"
            createFolder = "Child folder"
            createGoal = "Goal"
            createTask = "Task"
            createIdea = "Idea"
            createNote = "Note"
            createHistory = "History entry"
            edit = "Edit"
            move = "Move"
            clone = "Clone"
            delete = "Delete"
            share = "Share"
            reschedule = "Reschedule"
            addToFocus = "Add to Focus"
            removeFromFocus = "Remove from Focus"
            cancel = "Cancel"
            confirmDelete = "Delete permanently?"
            moreActions = "More actions"
            readOnly = "View only"
            fullAccess = "Full access"
            statusTodo = "To do"
            statusInProgress = "In progress"
            statusDone = "Done"
            statusCancelled = "Cancelled"
            typeGreen = "Green"
            typeRed = "Red"
        }
    }

    func statusTitle(_ value: DetailTaskStatus) -> String {
        switch value {
        case .todo: statusTodo
        case .inProgress: statusInProgress
        case .done: statusDone
        case .cancelled: statusCancelled
        }
    }

    func createTitle(_ value: DetailCreateKind) -> String {
        switch value {
        case .folder: createFolder
        case .goal: createGoal
        case .task: createTask
        case .idea: createIdea
        case .note: createNote
        case .ideaHistory: createHistory
        }
    }

    func actionTitle(_ action: DetailMenuAction) -> String {
        switch action {
        case let .create(kind): createTitle(kind)
        case .edit: edit
        case .move: move
        case .clone: clone
        case .delete: delete
        case .share: share
        case .links: links
        case .reschedule: reschedule
        }
    }
}
