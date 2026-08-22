import Combine
import Foundation

enum CalendarScreenPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case offline
    case unauthorized
    case error
}

struct CalendarMarkerCounts: Equatable, Sendable {
    let planned: Int
    let deadlines: Int

    var isEmpty: Bool { planned == 0 && deadlines == 0 }
}

struct CalendarCopy: Sendable {
    let title: String
    let today: String
    let previousMonth: String
    let nextMonth: String
    let agenda: String
    let noTasks: String
    let loading: String
    let offline: String
    let unavailable: String
    let unauthorized: String
    let planned: String
    let deadline: String
    let recurring: String
    let selected: String
    let outsideMonth: String
    let openTask: String
    let taskUnavailable: String

    init(language: AppLanguage) {
        if language == .ru {
            title = "Календарь"
            today = "Сегодня"
            previousMonth = "Предыдущий месяц"
            nextMonth = "Следующий месяц"
            agenda = "План на день"
            noTasks = "На выбранный день задач нет"
            loading = "Загрузка календаря"
            offline = "Нет сети. Показаны сохранённые данные"
            unavailable = "Календарь сейчас недоступен"
            unauthorized = "Сеанс завершён. Войдите снова"
            planned = "Запланировано"
            deadline = "Дедлайн"
            recurring = "Повторяется"
            selected = "Выбрано"
            outsideMonth = "Другой месяц"
            openTask = "Дважды коснитесь, чтобы открыть карточку задачи"
            taskUnavailable = "Синхронизируйте задачу, чтобы открыть её карточку"
        } else {
            title = "Calendar"
            today = "Today"
            previousMonth = "Previous month"
            nextMonth = "Next month"
            agenda = "Day agenda"
            noTasks = "No tasks for the selected day"
            loading = "Loading calendar"
            offline = "Offline. Showing saved data"
            unavailable = "Calendar is currently unavailable"
            unauthorized = "Your session ended. Sign in again"
            planned = "Planned"
            deadline = "Deadline"
            recurring = "Recurring"
            selected = "Selected"
            outsideMonth = "Other month"
            openTask = "Double-tap to open task details"
            taskUnavailable = "Sync the task to open its details"
        }
    }
}

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published private(set) var visibleMonth: CalendarMonth
    @Published private(set) var selectedDate: LocalDate
    @Published private(set) var phase: CalendarScreenPhase = .idle
    @Published private(set) var response: CalendarMarkersResponseDTO?
    @Published private(set) var lastFailure: CalendarLoadFailure?
    @Published private(set) var localTaskIDsByMarkerID: [UUID: UUID] = [:]

    let language: AppLanguage
    let accountTimezone: String

    private let accountID: UUID
    private let loader: any CalendarLoading
    private let now: () -> Date
    private let onUnauthorized: () -> Void
    private var requestGeneration: UInt64 = 0

    init(
        accountID: UUID,
        accountTimezone: String,
        language: AppLanguage,
        loader: any CalendarLoading,
        now: @escaping () -> Date = Date.init,
        onUnauthorized: @escaping () -> Void = {}
    ) {
        self.accountID = accountID
        self.accountTimezone = accountTimezone
        self.language = language
        self.loader = loader
        self.now = now
        self.onUnauthorized = onUnauthorized

        let today = CalendarDateMath.today(now: now(), timezoneIdentifier: accountTimezone)
        visibleMonth = CalendarMonth(containing: today)
        selectedDate = today
    }

    var copy: CalendarCopy { CalendarCopy(language: language) }
    var gridDays: [CalendarGridDay] { CalendarDateMath.grid(for: visibleMonth) }
    var monthTitle: String { CalendarDateMath.monthTitle(visibleMonth, language: language) }
    var selectedDateTitle: String { CalendarDateMath.fullDateTitle(selectedDate, language: language) }
    var weekdaySymbols: [String] { CalendarDateMath.weekdaySymbols(language: language) }
    var displayTimezone: String { response?.timezone ?? accountTimezone }
    var isLoading: Bool { phase == .loading }
    var isOffline: Bool { phase == .offline }

    var selectedMarkers: [CalendarMarkerDTO] {
        CalendarMarkerOrdering.sorted(
            response?.markers.filter { $0.localDate == selectedDate } ?? [],
            language: language
        )
    }

    func markers(on date: LocalDate) -> [CalendarMarkerDTO] {
        response?.markers.filter { $0.localDate == date } ?? []
    }

    func counts(on date: LocalDate) -> CalendarMarkerCounts {
        let dayMarkers = markers(on: date)
        return CalendarMarkerCounts(
            planned: dayMarkers.lazy.filter { $0.kind == .planned }.count,
            deadlines: dayMarkers.lazy.filter { $0.kind == .deadline }.count
        )
    }

    func localTaskID(for marker: CalendarMarkerDTO) -> UUID? {
        localTaskIDsByMarkerID[marker.markerId]
    }

    func taskActionHint(for marker: CalendarMarkerDTO) -> String {
        localTaskID(for: marker) == nil ? copy.taskUnavailable : copy.openTask
    }

    func loadIfNeeded() async {
        guard response == nil, phase != .loading else { return }
        await reload()
    }

    func reload() async {
        requestGeneration &+= 1
        let generation = requestGeneration
        let requestedMonth = visibleMonth
        let range = CalendarDateMath.range(for: requestedMonth)
        let previousPhase = phase
        let previousFailure = lastFailure
        phase = .loading
        lastFailure = nil

        do {
            let result = try await loader.load(
                accountID: accountID,
                accountTimezone: accountTimezone,
                from: range.from,
                toExclusive: range.toExclusive
            )
            guard generation == requestGeneration, requestedMonth == visibleMonth else { return }
            response = result.response
            localTaskIDsByMarkerID = result.localTaskIDsByMarkerID
            lastFailure = result.failure
            phase = result.isOffline ? .offline : .loaded
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            lastFailure = previousFailure
            phase = response == nil ? .idle : previousPhase
        } catch let apiError as APIError where apiError.isUnauthorized {
            guard generation == requestGeneration else { return }
            response = nil
            localTaskIDsByMarkerID = [:]
            lastFailure = CalendarLoadFailure(apiError)
            phase = .unauthorized
            onUnauthorized()
        } catch {
            guard generation == requestGeneration else { return }
            lastFailure = CalendarLoadFailure(error)
            phase = .error
        }
    }

    func moveMonth(by offset: Int) async {
        guard offset != 0 else { return }
        visibleMonth = visibleMonth.shifted(by: offset)
        selectedDate = visibleMonth.firstDay
        response = nil
        localTaskIDsByMarkerID = [:]
        lastFailure = nil
        await reload()
    }

    func select(_ date: LocalDate) async {
        selectedDate = date
        guard !visibleMonth.contains(date) else { return }
        visibleMonth = CalendarMonth(containing: date)
        response = nil
        localTaskIDsByMarkerID = [:]
        lastFailure = nil
        await reload()
    }

    func selectToday() async {
        let today = CalendarDateMath.today(now: now(), timezoneIdentifier: accountTimezone)
        selectedDate = today
        let todayMonth = CalendarMonth(containing: today)
        if todayMonth != visibleMonth {
            visibleMonth = todayMonth
            response = nil
            localTaskIDsByMarkerID = [:]
            lastFailure = nil
            await reload()
        } else if response == nil {
            await reload()
        }
    }

    func markerTime(_ marker: CalendarMarkerDTO) -> String {
        CalendarDateMath.markerTime(
            marker.at,
            timezoneIdentifier: displayTimezone,
            language: language
        )
    }
}
