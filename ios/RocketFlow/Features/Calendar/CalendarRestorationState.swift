import Foundation

struct CalendarRestorationState: Codable, Equatable, Sendable {
    let timezoneIdentifier: String
    let visibleYear: Int
    let visibleMonth: Int
    let selectedDate: LocalDate

    init(
        timezoneIdentifier: String,
        visibleMonth: CalendarMonth,
        selectedDate: LocalDate
    ) {
        self.timezoneIdentifier = timezoneIdentifier
        visibleYear = visibleMonth.year
        self.visibleMonth = visibleMonth.month
        self.selectedDate = selectedDate
    }

    func validatedVisibleMonth(accountTimezone: String) -> CalendarMonth? {
        guard
            (1...12).contains(visibleMonth)
        else {
            return nil
        }

        let month = CalendarMonth(year: visibleYear, month: visibleMonth)
        guard
            month.contains(selectedDate),
            timezoneRulesMatch(accountTimezone: accountTimezone, visibleMonth: month)
        else {
            return nil
        }
        return month
    }

    private func timezoneRulesMatch(
        accountTimezone: String,
        visibleMonth: CalendarMonth
    ) -> Bool {
        guard
            let storedTimezone = TimeZone(identifier: timezoneIdentifier),
            let currentTimezone = TimeZone(identifier: accountTimezone)
        else {
            return false
        }
        if storedTimezone.identifier == currentTimezone.identifier { return true }

        // Compare the complete visible grid so aliases survive while DST/rule changes do not.
        return CalendarDateMath.grid(for: visibleMonth).allSatisfy { day in
            [0, 6, 12, 18].allSatisfy { hour in
                guard let anchor = utcAnchor(for: day.date, hour: hour) else { return false }
                return storedTimezone.secondsFromGMT(for: anchor)
                    == currentTimezone.secondsFromGMT(for: anchor)
            }
        }
    }

    private func utcAnchor(for date: LocalDate, hour: Int) -> Date? {
        let components = date.rawValue.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(
                year: components[0],
                month: components[1],
                day: components[2],
                hour: hour
            )
        )
    }
}
