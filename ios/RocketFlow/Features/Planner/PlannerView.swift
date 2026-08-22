import Combine
import SwiftUI
import UIKit

@MainActor
struct PlannerView: View {
    @StateObject private var model: PlannerViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingDeletion: PlannerItemViewData?

    init(model: PlannerViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            statusArea
            content
        }
        .navigationTitle(model.copy.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: Binding(
                get: { model.searchQuery },
                set: model.updateSearchQuery
            ),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: model.copy.searchPrompt
        )
        .toolbar { plannerToolbar }
        .task { await model.loadIfNeeded() }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                model.captureForBackground()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            model.captureForRotation()
        }
        .alert(
            model.copy.delete,
            isPresented: deletionPresented,
            presenting: pendingDeletion
        ) { item in
            Button(model.copy.cancel, role: .cancel) {}
            Button(model.copy.delete, role: .destructive) {
                Task { await model.delete(item) }
            }
        } message: { _ in
            Text(model.copy.deleteConfirmation)
        }
        .accessibilityIdentifier("planner.screen")
    }

    @ViewBuilder
    private var content: some View {
        if model.isInitialLoading {
            ProgressView(model.copy.loading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("planner.loading")
        } else if model.showsErrorState, model.snapshot == nil {
            unavailableState
        } else if model.tree.isEmpty {
            emptyState
        } else {
            plannerTree
        }
    }

    private var plannerTree: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(model.tree.sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            PlannerRowView(
                                row: row,
                                copy: model.copy,
                                actions: model.contextActions(for: row.item),
                                isBusy: model.isPerformingAction,
                                onOpen: { model.open(row.item) },
                                onToggleExpanded: { model.toggleExpanded(row) },
                                onToggleTaskStatus: {
                                    Task { await model.toggleTaskStatus(row.item) }
                                },
                                onAction: { handle($0, item: row.item) }
                            )
                            Divider()
                                .padding(.leading, CGFloat(row.depth) * 18 + 42)
                        }
                    } header: {
                        sectionHeader(section.kind)
                    }
                }
            }
            .plannerScrollContentCoordinateSpace()
            .onPlannerScrollRowsChange(perform: model.receiveVisibleRows)
            .background(alignment: .topLeading) {
                PlannerScrollViewBridge(
                    restorationRequest: model.restorationRequest,
                    onViewportChange: model.receiveViewport
                )
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.bottom, 28)
        }
        .refreshable { await model.refresh() }
        .accessibilityIdentifier("planner.tree")
    }

    private func sectionHeader(_ kind: PlannerSectionKind) -> some View {
        Text(kind == .owned ? model.copy.owned : model.copy.shared)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(uiColor: .systemBackground))
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("planner.section.\(kind.rawValue)")
    }

    @ViewBuilder
    private var statusArea: some View {
        if model.phase == .loading, model.snapshot != nil {
            ProgressView()
                .progressViewStyle(.linear)
                .accessibilityLabel(model.copy.loading)
        }
        if model.showsOfflineState {
            statusBanner(model.copy.offline, systemImage: "wifi.slash", color: .orange)
        } else if model.showsErrorState, model.snapshot != nil {
            statusBanner(model.copy.unavailable, systemImage: "exclamationmark.triangle", color: .red)
        }
        if let warning = model.warning, !warning.isEmpty {
            statusBanner(warning, systemImage: "exclamationmark.triangle", color: .orange)
        }
        if let actionError = model.actionError {
            statusBanner(actionError, systemImage: "xmark.circle", color: .red)
        }
    }

    private func statusBanner(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityIdentifier("planner.status")
    }

    private var unavailableState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(model.copy.unavailable)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await model.refresh() }
            } label: {
                Label(model.copy.retry, systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .accessibilityIdentifier("planner.error")
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: model.searchQuery.isEmpty ? "folder" : "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(model.searchQuery.isEmpty ? model.copy.empty : model.copy.noSearchResults)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if model.searchQuery.isEmpty {
                    Button {
                        model.create(.folder)
                    } label: {
                        Label(model.copy.createFolder, systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 280)
            .padding(24)
        }
        .refreshable { await model.refresh() }
        .accessibilityIdentifier("planner.empty")
    }

    @ToolbarContentBuilder
    private var plannerToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button(action: model.openSettings) {
                Image(systemName: "gearshape")
            }
            .disabled(model.isPerformingAction)
            .accessibilityLabel(model.copy.settings)
            .help(model.copy.settings)

            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(model.phase == .loading)
            .accessibilityLabel(model.copy.refresh)
            .help(model.copy.refresh)

            Menu {
                ForEach(PlannerCreateKind.allCases, id: \.self) { kind in
                    Button {
                        model.create(kind)
                    } label: {
                        Label(model.copy.createTitle(kind), systemImage: createSymbol(kind))
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(model.copy.create)
            .help(model.copy.create)
            .disabled(model.isPerformingAction)
        }
    }

    private var deletionPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented { pendingDeletion = nil }
            }
        )
    }

    private func handle(_ action: PlannerContextAction, item: PlannerItemViewData) {
        if action == .delete {
            pendingDeletion = item
        } else {
            model.handle(action, for: item)
        }
    }

    private func createSymbol(_ kind: PlannerCreateKind) -> String {
        switch kind {
        case .folder: "folder.badge.plus"
        case .goal: "target"
        case .task: "plus.circle"
        case .idea: "lightbulb"
        case .note: "square.and.pencil"
        }
    }
}
