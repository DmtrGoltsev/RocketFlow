import SwiftUI

@MainActor
struct FocusCandidatePickerView: View {
    @ObservedObject var model: FocusViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                stateContent

                ForEach(model.candidateGroups) { folder in
                    Section {
                        ForEach(folder.goals) { goal in
                            Text(goal.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(goal.candidates) { candidate in
                                candidateRow(candidate)
                            }
                        }
                    } header: {
                        Label(folder.title, systemImage: "folder")
                    }
                }

                if model.candidateCursor != nil {
                    Button {
                        Task { await model.loadMoreCandidates() }
                    } label: {
                        HStack {
                            Spacer()
                            if model.candidatePhase == .loading { ProgressView() }
                            Text(model.copy.loadMore)
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(model.candidatePhase == .loading)
                    .accessibilityIdentifier("focus.candidates.more")
                }
            }
            .listStyle(.plain)
            .searchable(
                text: Binding(
                    get: { model.candidateQuery },
                    set: { model.scheduleCandidateSearch($0) }
                ),
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: model.copy.search
            )
            .navigationTitle(model.copy.add)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.copy.cancel) { dismiss() }
                }
            }
            .task {
                if model.candidates.isEmpty { await model.reloadCandidates() }
            }
            .accessibilityIdentifier("focus.candidates.screen")
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        if model.candidatePhase == .loading, model.candidates.isEmpty {
            HStack {
                Spacer()
                ProgressView(model.copy.loading)
                Spacer()
            }
            .listRowSeparator(.hidden)
        } else if model.candidatePhase == .error {
            Label(model.copy.unavailable, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .listRowSeparator(.hidden)
        } else if model.candidatePhase == .unauthorized {
            Label(model.copy.unauthorized, systemImage: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.red)
                .listRowSeparator(.hidden)
        } else if model.candidatePhase == .loaded, model.candidates.isEmpty {
            Text(model.copy.noCandidates)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 88)
                .listRowSeparator(.hidden)
        }
    }

    private func candidateRow(_ candidate: FocusCandidateDTO) -> some View {
        Button {
            Task { await model.add(candidate) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "plus.circle")
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.title)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(
                        FocusFormatting.path(
                            folder: candidate.folderTitle,
                            goal: candidate.goalTitle
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Label("\(max(candidate.effectiveWeight, 1))", systemImage: "gauge")
                        if candidate.shared { Label(model.copy.shared, systemImage: "person.2") }
                        if !candidate.canWrite { Label(model.copy.readOnly, systemImage: "lock") }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isMutating)
        .accessibilityLabel(FocusAccessibility.candidateLabel(candidate, copy: model.copy))
        .accessibilityHint(model.copy.add)
        .accessibilityIdentifier("focus.candidate.\(candidate.taskId.uuidString.lowercased())")
    }

}
