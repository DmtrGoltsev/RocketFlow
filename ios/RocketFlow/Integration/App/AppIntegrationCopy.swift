import Foundation

struct AppIntegrationCopy: Sendable {
    let planner: String
    let calendar: String
    let focus: String
    let offline: String
    let preparingData: String
    let retry: String
    let loading: String
    let unavailable: String
    let editorUnavailable: String
    let links: String
    let close: String
    let cancel: String
    let done: String
    let destination: String
    let root: String
    let plannedDate: String
    let move: String
    let clone: String
    let reschedule: String

    init(language: AppLanguage) {
        if language == .ru {
            planner = "Главная"
            calendar = "Календарь"
            focus = "Фокус"
            offline = "Нет соединения. Показаны сохранённые данные."
            preparingData = "Подготовка локальных данных…"
            retry = "Повторить"
            loading = "Загрузка…"
            unavailable = "Недоступно"
            editorUnavailable = "Редактор недоступен"
            links = "Связи"
            close = "Закрыть"
            cancel = "Отмена"
            done = "Готово"
            destination = "Куда"
            root = "В корень"
            plannedDate = "Плановая дата"
            move = "Переместить"
            clone = "Клонировать"
            reschedule = "Перенести дату"
        } else {
            planner = "Planner"
            calendar = "Calendar"
            focus = "Focus"
            offline = "Offline. Showing saved data."
            preparingData = "Preparing local data…"
            retry = "Retry"
            loading = "Loading…"
            unavailable = "Unavailable"
            editorUnavailable = "Editor unavailable"
            links = "Links"
            close = "Close"
            cancel = "Cancel"
            done = "Done"
            destination = "Destination"
            root = "Top level"
            plannedDate = "Planned date"
            move = "Move"
            clone = "Clone"
            reschedule = "Reschedule"
        }
    }
}
