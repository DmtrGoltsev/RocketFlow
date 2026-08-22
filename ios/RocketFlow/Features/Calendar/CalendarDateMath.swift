import Foundation

struct CalendarMonth: Equatable, Hashable, Sendable {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        precondition((1...12).contains(month))
        self.year = year
        self.month = month
    }

    init(containing date: LocalDate) {
        let parts = date.rawValue.split(separator: "-")
        year = Int(parts[0])!
        month = Int(parts[1])!
    }

    var firstDay: LocalDate {
        LocalDate(rawValue: String(format: "%04d-%02d-01", year, month))!
    }

    func contains(_ date: LocalDate) -> Bool {
        CalendarMonth(containing: date) == self
    }

    func shifted(by offset: Int) -> CalendarMonth {
        let zeroBased = year * 12 + month - 1 + offset
        let shiftedYear = Int(floor(Double(zeroBased) / 12.0))
        let shiftedMonth = zeroBased - shiftedYear * 12 + 1
        return CalendarMonth(year: shiftedYear, month: shiftedMonth)
    }
}

struct CalendarGridDay: Equatable, Hashable, Sendable, Identifiable {
    let date: LocalDate
    let isInVisibleMonth: Bool

    var id: String { date.rawValue }
}

struct CalendarGridRange: Equatable, Sendable {
    let from: LocalDate
    let toExclusive: LocalDate
}

enum CalendarDateMath {
    static func today(now: Date = Date(), timezoneIdentifier: String) -> LocalDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        return makeLocalDate(
            year: components.year!,
            month: components.month!,
            day: components.day!
        )
    }

    static func grid(for month: CalendarMonth) -> [CalendarGridDay] {
        let firstDate = foundationDate(month.firstDay)
        var calendar = utcCalendar()
        let weekday = calendar.component(.weekday, from: firstDate)
        let daysSinceMonday = (weekday + 5) % 7
        let gridStart = calendar.date(byAdding: .day, value: -daysSinceMonday, to: firstDate)!

        return (0..<42).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: gridStart)!
            let localDate = localDate(fromUTCDate: date)
            return CalendarGridDay(date: localDate, isInVisibleMonth: month.contains(localDate))
        }
    }

    static func range(for month: CalendarMonth) -> CalendarGridRange {
        let days = grid(for: month)
        let from = days[0].date
        let lastDate = foundationDate(days[41].date)
        let toDate = utcCalendar().date(byAdding: .day, value: 1, to: lastDate)!
        return CalendarGridRange(from: from, toExclusive: localDate(fromUTCDate: toDate))
    }

    static func dayNumber(_ date: LocalDate) -> Int {
        Int(date.rawValue.suffix(2))!
    }

    static func monthTitle(_ month: CalendarMonth, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: language == .ru ? "ru_RU" : "en_US")
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        let value = formatter.string(from: foundationDate(month.firstDay))
        return String(value.prefix(1)).uppercased(with: formatter.locale) + String(value.dropFirst())
    }

    static func fullDateTitle(_ date: LocalDate, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: language == .ru ? "ru_RU" : "en_US")
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        let value = formatter.string(from: foundationDate(date))
        return String(value.prefix(1)).uppercased(with: formatter.locale) + String(value.dropFirst())
    }

    static func weekdaySymbols(language: AppLanguage) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .ru ? "ru_RU" : "en_US")
        let sundayFirst = formatter.shortStandaloneWeekdaySymbols ?? formatter.shortWeekdaySymbols ?? []
        guard sundayFirst.count == 7 else {
            return language == .ru
                ? ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]
                : ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        }
        return Array(sundayFirst[1...6]) + [sundayFirst[0]]
    }

    static func markerTime(_ date: Date, timezoneIdentifier: String, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .ru ? "ru_RU" : "en_US")
        formatter.timeZone = TimeZone(identifier: timezoneIdentifier) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func makeLocalDate(year: Int, month: Int, day: Int) -> LocalDate {
        LocalDate(rawValue: String(format: "%04d-%02d-%02d", year, month, day))!
    }

    private static func foundationDate(_ date: LocalDate) -> Date {
        let parts = date.rawValue.split(separator: "-").map { Int($0)! }
        return utcCalendar().date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }

    private static func localDate(fromUTCDate date: Date) -> LocalDate {
        let components = utcCalendar().dateComponents([.year, .month, .day], from: date)
        return makeLocalDate(year: components.year!, month: components.month!, day: components.day!)
    }

    private static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

enum CalendarMarkerOrdering {
    static func sorted(_ markers: [CalendarMarkerDTO], language: AppLanguage) -> [CalendarMarkerDTO] {
        let locale = Locale(identifier: language == .ru ? "ru_RU" : "en_US")
        return markers.sorted { lhs, rhs in
            if lhs.at != rhs.at { return lhs.at < rhs.at }
            let titleOrder = lhs.title.compare(
                rhs.title,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: nil,
                locale: locale
            )
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            if lhs.kind != rhs.kind { return lhs.kind == .planned }
            return lhs.markerId.uuidString.lowercased() < rhs.markerId.uuidString.lowercased()
        }
    }
}
