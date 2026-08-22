import SwiftUI

@MainActor
struct CalendarView: View {
    @StateObject private var model: CalendarViewModel
    private let onOpenTask: (UUID) -> Void
    private let columns = Array(repeating: GridItem(.flexible(minimum: 44), spacing: 0), count: 7)

    init(model: CalendarViewModel, onOpenTask: @escaping (UUID) -> Void) {
        _model = StateObject(wrappedValue: model)
        self.onOpenTask = onOpenTask
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                monthHeader

                if model.isLoading {
                    ProgressView(model.copy.loading)
                        .progressViewStyle(.linear)
                        .accessibilityIdentifier("calendar.loading")
                }

                statusContent
                weekdayHeader
                monthGrid
                agenda
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 10)
            .padding(.bottom, 32)
        }
        .refreshable { await model.reload() }
        .navigationTitle(model.copy.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadIfNeeded() }
        .accessibilityIdentifier("calendar.screen")
    }

    private var monthHeader: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Button {
                    Task { await model.moveMonth(by: -1) }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.copy.previousMonth)
                .help(model.copy.previousMonth)

                Text(model.monthTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)

                Button {
                    Task { await model.moveMonth(by: 1) }
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.copy.nextMonth)
                .help(model.copy.nextMonth)
            }

            HStack {
                Spacer()
                Button {
                    Task { await model.selectToday() }
                } label: {
                    Label(model.copy.today, systemImage: "calendar")
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(minHeight: 44)
                .accessibilityIdentifier("calendar.today")
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var statusContent: some View {
        switch model.phase {
        case .offline:
            statusBanner(model.copy.offline, systemImage: "wifi.slash", color: .orange)
            if model.response?.markers.isEmpty == true, model.lastFailure != nil {
                statusBanner(model.copy.unavailable, systemImage: "exclamationmark.triangle", color: .red)
            }
        case .unauthorized:
            statusBanner(model.copy.unauthorized, systemImage: "person.crop.circle.badge.exclamationmark", color: .red)
        case .error:
            statusBanner(model.copy.unavailable, systemImage: "exclamationmark.triangle", color: .red)
        case .idle, .loading, .loaded:
            EmptyView()
        }
    }

    private func statusBanner(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .accessibilityIdentifier("calendar.status")
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(model.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .accessibilityHidden(true)
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(model.gridDays) { day in
                dayButton(day)
            }
        }
        .accessibilityIdentifier("calendar.monthGrid")
    }

    private func dayButton(_ day: CalendarGridDay) -> some View {
        let counts = model.counts(on: day.date)
        let isSelected = day.date == model.selectedDate
        let isToday = day.date == CalendarDateMath.today(timezoneIdentifier: model.accountTimezone)

        return Button {
            Task { await model.select(day.date) }
        } label: {
            VStack(spacing: 3) {
                Text(String(CalendarDateMath.dayNumber(day.date)))
                    .font(.subheadline.weight(isSelected ? .bold : .regular))
                    .frame(maxWidth: .infinity)

                if !counts.isEmpty {
                    HStack(spacing: 4) {
                        if counts.planned > 0 {
                            markerCount(counts.planned, kind: .planned)
                        }
                        if counts.deadlines > 0 {
                            markerCount(counts.deadlines, kind: .deadline)
                        }
                    }
                } else {
                    Color.clear.frame(height: 13)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .top)
            .foregroundStyle(day.isInVisibleMonth ? Color.primary : Color.secondary)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isSelected ? Color.accentColor : (isToday ? Color.secondary : Color.clear),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayAccessibilityLabel(day, counts: counts, selected: isSelected))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("calendar.day.\(day.date.rawValue)")
    }

    private func markerCount(_ count: Int, kind: CalendarMarkerKind) -> some View {
        HStack(spacing: 2) {
            Image(systemName: kind == .planned ? "circle.fill" : "diamond.fill")
                .font(.system(size: 7, weight: .bold))
            Text(String(count))
                .font(.caption2.monospacedDigit().weight(.semibold))
        }
        .foregroundStyle(kind == .planned ? Color.green : Color.red)
        .accessibilityHidden(true)
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.copy.agenda)
                    .font(.headline)
                Text(model.selectedDateTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if model.isLoading, model.response == nil {
                Text(model.copy.loading)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
                    .accessibilityIdentifier("calendar.agenda.loading")
            } else if model.phase == .unauthorized || model.phase == .error {
                Text(model.phase == .unauthorized ? model.copy.unauthorized : model.copy.unavailable)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
                    .accessibilityIdentifier("calendar.agenda.unavailable")
            } else if model.selectedMarkers.isEmpty {
                Text(model.copy.noTasks)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
                    .accessibilityIdentifier("calendar.agenda.empty")
            } else {
                ForEach(model.selectedMarkers) { marker in
                    agendaRow(marker)
                    if marker.id != model.selectedMarkers.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .accessibilityIdentifier("calendar.agenda")
    }

    private func agendaRow(_ marker: CalendarMarkerDTO) -> some View {
        let localTaskID = model.localTaskID(for: marker)
        Button {
            guard let localTaskID else { return }
            onOpenTask(localTaskID)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: marker.kind == .planned ? "circle.fill" : "diamond.fill")
                    .font(.caption)
                    .foregroundStyle(marker.kind == .planned ? Color.green : Color.red)
                    .frame(width: 18, height: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(marker.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        Text(marker.kind == .planned ? model.copy.planned : model.copy.deadline)
                        Text(model.markerTime(marker))
                        if marker.recurring {
                            Label(model.copy.recurring, systemImage: "repeat")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if localTaskID != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(localTaskID == nil)
        .accessibilityLabel(markerAccessibilityLabel(marker))
        .accessibilityHint(model.taskActionHint(for: marker))
        .accessibilityIdentifier("calendar.marker.\(marker.markerId.uuidString.lowercased())")
    }

    private func dayAccessibilityLabel(
        _ day: CalendarGridDay,
        counts: CalendarMarkerCounts,
        selected: Bool
    ) -> String {
        var parts = [CalendarDateMath.fullDateTitle(day.date, language: model.language)]
        if counts.planned > 0 { parts.append("\(model.copy.planned): \(counts.planned)") }
        if counts.deadlines > 0 { parts.append("\(model.copy.deadline): \(counts.deadlines)") }
        if selected { parts.append(model.copy.selected) }
        if !day.isInVisibleMonth { parts.append(model.copy.outsideMonth) }
        return parts.joined(separator: ", ")
    }

    private func markerAccessibilityLabel(_ marker: CalendarMarkerDTO) -> String {
        var parts = [
            marker.title,
            marker.kind == .planned ? model.copy.planned : model.copy.deadline,
            model.markerTime(marker)
        ]
        if marker.recurring { parts.append(model.copy.recurring) }
        return parts.joined(separator: ", ")
    }
}
