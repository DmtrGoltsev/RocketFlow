import SwiftUI

@MainActor
struct FocusView: View {
    @StateObject private var model: FocusViewModel
    @State private var showsCandidates = false
    @State private var showsHistory = false
    @State private var showsSettings = false

    init(model: FocusViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                statusContent
                progressContent
                rolloverContent
                currentItems
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable { await model.reloadCurrent() }
        .navigationTitle(model.copy.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadIfNeeded() }
        .sheet(isPresented: $showsCandidates) {
            FocusCandidatePickerView(model: model)
        }
        .sheet(isPresented: $showsHistory) {
            FocusHistoryView(model: model)
        }
        .sheet(isPresented: $showsSettings) {
            FocusCadenceSettingsView(model: model)
        }
        .accessibilityIdentifier("focus.screen")
    }

    private var header: some View {
        HStack(spacing: 4) {
            if let period = model.period {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.copy.currentWeek)
                        .font(.headline)
                    Text(
                        FocusFormatting.week(
                            start: period.weekStart,
                            endExclusive: period.weekEndExclusive,
                            language: model.language
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }

            Spacer()

            headerButton(systemImage: "plus", label: model.copy.add) {
                showsCandidates = true
            }
            headerButton(systemImage: "clock.arrow.circlepath", label: model.copy.history) {
                showsHistory = true
            }
            headerButton(systemImage: "bell.badge", label: model.copy.settings) {
                showsSettings = true
            }
        }
    }

    private func headerButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    @ViewBuilder
    private var statusContent: some View {
        if model.phase == .loading {
            ProgressView(model.copy.loading)
                .progressViewStyle(.linear)
                .accessibilityIdentifier("focus.loading")
        }
        if model.isOffline {
            statusBanner(model.copy.offline, systemImage: "wifi.slash", color: .orange)
        }
        if model.phase == .error {
            statusBanner(model.copy.unavailable, systemImage: "exclamationmark.triangle", color: .red)
        }
        if model.phase == .unauthorized {
            statusBanner(
                model.copy.unauthorized,
                systemImage: "person.crop.circle.badge.exclamationmark",
                color: .red
            )
        }
        if model.pendingCount > 0 {
            HStack {
                statusBanner(
                    "\(model.copy.pending): \(model.pendingCount)",
                    systemImage: "arrow.triangle.2.circlepath",
                    color: .orange
                )
                Button {
                    Task { await model.retryPending() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(model.isMutating)
                .accessibilityLabel(model.copy.retry)
            }
        }
        if !model.terminalIssues.isEmpty {
            statusBanner(
                "\(model.copy.terminalIssue): \(model.terminalIssues.count)",
                systemImage: "exclamationmark.octagon",
                color: .red
            )
        }
    }

    private func statusBanner(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .accessibilityIdentifier("focus.status")
    }

    @ViewBuilder
    private var progressContent: some View {
        if model.period != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.copy.completed)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(model.progress.percent)%")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
                ProgressView(value: Double(model.progress.percent), total: 100)
                    .tint(.green)
                Text(
                    "\(model.progress.completedWeight) / \(model.progress.totalWeight) · "
                    + "\(model.progress.completedCount) / \(model.progress.totalCount)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(model.copy.completed): \(model.progress.percent)%, "
                + "\(model.progress.completedWeight) / \(model.progress.totalWeight)"
            )
            .accessibilityIdentifier("focus.progress")
        }
    }

    @ViewBuilder
    private var rolloverContent: some View {
        if let offer = model.period?.rolloverOffer {
            VStack(alignment: .leading, spacing: 8) {
                Label(model.copy.rollover, systemImage: "arrow.turn.down.right")
                    .font(.headline)
                ForEach(offer.items.sorted(by: { $0.position < $1.position })) { item in
                    Button {
                        model.toggleRollover(taskID: item.taskId)
                    } label: {
                        HStack(spacing: 10) {
                            Image(
                                systemName: model.rolloverSelection.contains(item.taskId)
                                    ? "checkmark.square.fill"
                                    : "square"
                            )
                            .foregroundStyle(
                                model.rolloverSelection.contains(item.taskId) ? Color.accentColor : Color.secondary
                            )
                            Text(item.title)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityValue(
                        model.rolloverSelection.contains(item.taskId)
                            ? model.copy.selectedState
                            : model.copy.notSelectedState
                    )
                }
                Button {
                    Task { await model.resolveRollover() }
                } label: {
                    Label(model.copy.carryOver, systemImage: "arrow.right.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isMutating)
            }
            .accessibilityIdentifier("focus.rollover")
        }
    }

    private var currentItems: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.activeItems.isEmpty {
                if model.phase != .loading && model.phase != .unauthorized {
                    VStack(spacing: 10) {
                        Image(systemName: "scope")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(model.copy.empty)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .accessibilityIdentifier("focus.empty")
                }
            } else {
                ForEach(Array(model.activeItems.enumerated()), id: \.element.id) { index, item in
                    focusRow(item, index: index)
                    if index < model.activeItems.count - 1 { Divider() }
                }
            }
        }
        .accessibilityIdentifier("focus.items")
    }

    private func focusRow(_ item: FocusItemDTO, index: Int) -> some View {
        let localTaskID = model.localTaskID(for: item.taskId)
        return HStack(alignment: .center, spacing: 8) {
            Button {
                model.openTask(item.taskId)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.status == .done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.status == .done ? Color.green : Color.secondary)
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(FocusFormatting.path(folder: item.folderTitle, goal: item.goalTitle))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Label("\(max(item.effectiveWeight, 1))", systemImage: "gauge")
                            if item.shared { Label(model.copy.shared, systemImage: "person.2") }
                            if !item.canWrite { Label(model.copy.readOnly, systemImage: "lock") }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(localTaskID == nil)
            .accessibilityLabel(FocusAccessibility.itemLabel(item, copy: model.copy))
            .accessibilityHint(model.taskNavigationHint(for: item.taskId))

            VStack(spacing: 0) {
                rowAction("arrow.up", label: model.copy.moveUp, disabled: index == 0) {
                    Task { await model.move(taskID: item.taskId, by: -1) }
                }
                rowAction(
                    "arrow.down",
                    label: model.copy.moveDown,
                    disabled: index == model.activeItems.count - 1
                ) {
                    Task { await model.move(taskID: item.taskId, by: 1) }
                }
            }

            rowAction("xmark", label: model.copy.remove, disabled: false) {
                Task { await model.remove(taskID: item.taskId) }
            }
        }
        .padding(.vertical, 6)
    }

    private func rowAction(
        _ systemImage: String,
        label: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(disabled || model.isMutating)
        .accessibilityLabel(label)
        .help(label)
    }

}
