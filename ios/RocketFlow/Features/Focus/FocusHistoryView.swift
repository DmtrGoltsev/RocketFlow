import SwiftUI

@MainActor
struct FocusHistoryView: View {
    @ObservedObject var model: FocusViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let period = model.selectedHistoryPeriod {
                    detail(period)
                } else {
                    historyList
                }
            }
            .navigationTitle(model.copy.history)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if model.selectedHistoryPeriod == nil {
                        Button(model.copy.cancel) { dismiss() }
                    } else {
                        Button {
                            model.closeHistoryDetail()
                        } label: {
                            Label(model.copy.back, systemImage: "chevron.left")
                        }
                    }
                }
            }
            .task {
                if model.history.isEmpty { await model.loadHistory() }
            }
            .accessibilityIdentifier("focus.history.screen")
        }
    }

    private var historyList: some View {
        List {
            stateContent
            ForEach(model.history) { summary in
                Button {
                    Task { await model.loadHistoryDetail(periodID: summary.id) }
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(
                                FocusFormatting.week(
                                    start: summary.weekStart,
                                    endExclusive: summary.weekEndExclusive,
                                    language: model.language
                                )
                            )
                            .font(.headline)
                            Spacer()
                            Text("\(summary.progress.percent)%")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                        }
                        ProgressView(value: Double(summary.progress.percent), total: 100)
                        Text(
                            "\(summary.progress.completedWeight) / \(summary.progress.totalWeight) · "
                            + "\(summary.progress.completedCount) / \(summary.progress.totalCount)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(FocusFormatting.week(start: summary.weekStart, endExclusive: summary.weekEndExclusive, language: model.language)), "
                    + "\(model.copy.completed): \(summary.progress.percent)%"
                )
                .accessibilityIdentifier("focus.history.\(summary.id.uuidString.lowercased())")
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var stateContent: some View {
        if model.historyPhase == .loading {
            HStack {
                Spacer()
                ProgressView(model.copy.loading)
                Spacer()
            }
            .listRowSeparator(.hidden)
        } else if model.historyPhase == .offline {
            Label(model.copy.offline, systemImage: "wifi.slash")
                .foregroundStyle(.orange)
                .listRowSeparator(.hidden)
        } else if model.historyPhase == .error {
            Label(model.copy.unavailable, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .listRowSeparator(.hidden)
        } else if model.historyPhase == .loaded, model.history.isEmpty {
            Text(model.copy.empty)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 88)
                .listRowSeparator(.hidden)
        }
    }

    private func detail(_ period: FocusPeriodDTO) -> some View {
        let items = period.items.sorted { lhs, rhs in
            lhs.position == rhs.position
                ? lhs.taskId.uuidString.lowercased() < rhs.taskId.uuidString.lowercased()
                : lhs.position < rhs.position
        }
        let progress = FocusProgressCalculator.history(items)

        return List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.copy.completed)
                        Spacer()
                        Text("\(progress.percent)%")
                            .monospacedDigit()
                    }
                    ProgressView(value: Double(progress.percent), total: 100)
                    Text("\(progress.completedWeight) / \(progress.totalWeight)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } header: {
                Text(
                    FocusFormatting.week(
                        start: period.weekStart,
                        endExclusive: period.weekEndExclusive,
                        language: model.language
                    )
                )
            }

            Section {
                ForEach(items) { item in
                    let localTaskID = model.localTaskID(for: item.taskId)
                    Button {
                        model.openTask(item.taskId)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .foregroundStyle(.primary)
                            Text(FocusFormatting.path(folder: item.folderTitle, goal: item.goalTitle))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(localTaskID == nil)
                    .accessibilityLabel(FocusAccessibility.itemLabel(item, copy: model.copy))
                    .accessibilityHint(model.taskNavigationHint(for: item.taskId))
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("focus.history.detail")
    }
}
