import SwiftUI

@MainActor
struct EntityLinkPickerView: View {
    @ObservedObject var model: EntityLinksViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(model.copy.relation) {
                    Picker(model.copy.relation, selection: $model.selectedRelation) {
                        ForEach(availableRelations, id: \.self) { relation in
                            Text(model.copy.relationTitle(relation)).tag(relation)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("links.picker.relation")
                }

                stateContent

                Section {
                    ForEach(model.candidates) { candidate in
                        Button {
                            Task { await model.createLink(to: candidate) }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: symbol(candidate.type))
                                    .frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.title)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    HStack(spacing: 6) {
                                        Text(model.copy.typeTitle(candidate.type))
                                        if let path = candidate.path, !path.isEmpty {
                                            Text(path)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Color.accentColor)
                            }
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isBusy || !canChoose(candidate))
                        .accessibilityLabel(
                            "\(candidate.title), \(model.copy.typeTitle(candidate.type))"
                        )
                        .accessibilityHint(
                            canChoose(candidate)
                                ? model.copy.choose
                                : model.copy.dependencyRequiresTasks
                        )
                        .accessibilityIdentifier(
                            "links.candidate.\(candidate.type.rawValue).\(candidate.id.uuidString.lowercased())"
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(
                text: Binding(
                    get: { model.query },
                    set: { model.scheduleSearch($0) }
                ),
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: model.copy.search
            )
            .navigationTitle(model.copy.add)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.copy.cancel) {
                        model.dismissPicker()
                        dismiss()
                    }
                }
            }
            .task {
                if model.candidatePhase == .idle { await model.searchNow() }
            }
            .accessibilityIdentifier("links.picker")
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        if model.candidatePhase == .loading, model.candidates.isEmpty {
            Section {
                HStack {
                    Spacer()
                    ProgressView(model.copy.loading)
                    Spacer()
                }
            }
        } else if model.candidatePhase == .loaded, model.candidates.isEmpty {
            Section {
                Text(model.copy.noResults)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            }
        } else if model.candidatePhase == .offline {
            Section {
                Label(model.copy.offline, systemImage: "wifi.slash")
                    .foregroundStyle(.secondary)
            }
        } else if model.candidatePhase == .unauthorized {
            Section {
                Label(
                    model.copy.unauthorized,
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
                .foregroundStyle(.red)
            }
        } else if model.candidatePhase == .error {
            Section {
                Label(model.copy.unavailable, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    private func symbol(_ type: LinkedEntityType) -> String {
        switch type {
        case .goal: "target"
        case .task: "checkmark.circle"
        case .idea: "lightbulb"
        case .note: "note.text"
        }
    }

    private var availableRelations: [EntityRelationType] {
        model.context.type == .task ? EntityRelationType.allCases : [.related]
    }

    private func canChoose(_ candidate: EntityLinkCandidate) -> Bool {
        model.selectedRelation != .dependency || candidate.type == .task
    }
}
