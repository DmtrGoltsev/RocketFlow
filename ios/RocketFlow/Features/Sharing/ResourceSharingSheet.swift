import SwiftUI

@MainActor
struct ResourceSharingSheet: View {
    @StateObject private var model: ResourceSharingViewModel
    @Environment(\.dismiss) private var dismiss

    init(model: ResourceSharingViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            List {
                stateSection
                accessSection
                if model.canManage {
                    invitationComposer
                    invitationList
                    linkComposer
                    createdTokenSection
                    linkList
                } else {
                    Section {
                        Label(model.copy.ownerOnly, systemImage: "lock")
                            .foregroundStyle(.secondary)
                    }
                }
                tokenAcceptanceSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(model.copy.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.copy.done) {
                        model.handleSheetDismissal()
                        dismiss()
                    }
                }
            }
            .task { await model.load() }
            .confirmationDialog(
                model.copy.confirmRevoke,
                isPresented: Binding(
                    get: { model.pendingRevocation != nil },
                    set: { if !$0 { model.cancelRevocation() } }
                ),
                titleVisibility: .visible
            ) {
                Button(model.copy.revoke, role: .destructive) {
                    Task { await model.confirmRevocation() }
                }
                .disabled(model.isBusy)
                Button(model.copy.cancel, role: .cancel) { model.cancelRevocation() }
            }
            .onDisappear { model.handleSheetDismissal() }
            .accessibilityIdentifier("sharing.screen")
        }
    }

    @ViewBuilder
    private var stateSection: some View {
        if model.phase == .loading {
            Section {
                HStack {
                    Spacer()
                    ProgressView(model.copy.loading)
                    Spacer()
                }
            }
        } else if let issue = model.issue {
            Section {
                Label(issueTitle(issue.kind), systemImage: issueSymbol(issue.kind))
                    .foregroundStyle(
                        issue.kind == .offline ? Color.secondary : Color.red
                    )
                if model.canManage && (issue.kind == .offline || issue.kind == .unavailable) {
                    Button(model.copy.retry) { Task { await model.load() } }
                }
            }
        }
    }

    private var accessSection: some View {
        Section(model.copy.access) {
            LabeledContent(
                model.context.title,
                value: model.copy.accessTitle(model.context.access)
            )
            Label(
                model.copy.accessTitle(model.context.access),
                systemImage: model.context.access == .full ? "pencil" : "eye"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var invitationComposer: some View {
        Section(model.copy.invite) {
            Picker(model.copy.recipient, selection: $model.recipientMode) {
                Text(model.copy.email).tag(SharingRecipientMode.email)
                Text(model.copy.userID).tag(SharingRecipientMode.userID)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("sharing.invite.mode")

            if model.recipientMode == .email {
                TextField(model.copy.email, text: $model.email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("sharing.invite.email")
            } else {
                TextField(model.copy.userID, text: $model.userIDText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("sharing.invite.userId")
            }

            accessPicker(selection: $model.invitationAccess)

            Button {
                Task { await model.invite() }
            } label: {
                Label(model.copy.invite, systemImage: "person.badge.plus")
            }
            .disabled(model.isBusy)
            .accessibilityIdentifier("sharing.invite.submit")
        }
        .disabled(model.isBusy)
    }

    private var invitationList: some View {
        Section(model.copy.invitations) {
            if model.invitations.isEmpty {
                Text(model.copy.emptyInvitations).foregroundStyle(.secondary)
            } else {
                ForEach(model.invitations) { invitation in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(invitation.targetEmail ?? invitation.targetUserId?.uuidString ?? model.copy.recipient)
                                .lineLimit(2)
                            Label(
                                model.copy.statusTitle(invitation.status),
                                systemImage: invitation.status == "accepted"
                                    ? "checkmark.circle"
                                    : "clock"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            model.requestRevokeInvitation(id: invitation.id)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isBusy)
                        .accessibilityLabel(model.copy.revoke)
                        .help(model.copy.revoke)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("sharing.invitation.\(invitation.id.uuidString.lowercased())")
                }
            }
        }
    }

    private var linkComposer: some View {
        Section(model.copy.createLink) {
            accessPicker(selection: $model.linkAccess)
            Toggle(model.copy.expires, isOn: $model.usesExpiry)
            if model.usesExpiry {
                DatePicker(
                    model.copy.expires,
                    selection: $model.expiryDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .accessibilityIdentifier("sharing.link.expiry")
            } else {
                Label(model.copy.noExpiry, systemImage: "infinity")
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await model.createShareLink() }
            } label: {
                Label(model.copy.createLink, systemImage: "link.badge.plus")
            }
            .disabled(!model.canCreateShareLink)
            .accessibilityIdentifier("sharing.link.create")
        }
        .disabled(model.isBusy)
    }

    @ViewBuilder
    private var createdTokenSection: some View {
        if let token = model.createdToken {
            Section(model.copy.createdToken) {
                Label(model.copy.tokenWarning, systemImage: "exclamationmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(token.token)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .accessibilityLabel(model.copy.createdToken)
                    .accessibilityValue(token.token)
                HStack {
                    Button {
                        model.copyCreatedToken()
                    } label: {
                        Label(model.copy.copyToken, systemImage: "doc.on.doc")
                    }
                    Spacer()
                    Button {
                        model.shareCreatedToken()
                    } label: {
                        Label(model.copy.shareToken, systemImage: "square.and.arrow.up")
                    }
                }
                Button(model.copy.dismiss) { model.dismissCreatedToken() }
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .accessibilityIdentifier("sharing.createdToken")
        }
    }

    private var linkList: some View {
        Section(model.copy.links) {
            if model.shareLinks.isEmpty {
                Text(model.copy.emptyLinks).foregroundStyle(.secondary)
            } else {
                ForEach(model.shareLinks) { link in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(
                                model.copy.accessTitle(link.fullAccess ? .full : .viewOnly),
                                systemImage: link.fullAccess ? "pencil" : "eye"
                            )
                            if let expiry = link.expiresAt {
                                Text(expiryText(expiry))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(model.copy.noExpiry)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            model.requestRevokeLink(id: link.id)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isBusy)
                        .accessibilityLabel(model.copy.revoke)
                        .help(model.copy.revoke)
                    }
                    .accessibilityIdentifier("sharing.link.\(link.id.uuidString.lowercased())")
                }
            }
        }
    }

    private var tokenAcceptanceSection: some View {
        Section(model.copy.token) {
            TextField(
                model.copy.token,
                text: Binding(
                    get: { model.tokenInput },
                    set: { model.updateTokenInput($0) }
                )
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .disabled(model.isBusy)
            .accessibilityIdentifier("sharing.token.input")

            Button {
                Task { await model.resolveToken() }
            } label: {
                Label(model.copy.resolve, systemImage: "checkmark.shield")
            }
            .disabled(model.isBusy)

            if let resolved = model.resolvedLink {
                Label(model.copy.resolved, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                LabeledContent(
                    model.copy.access,
                    value: model.copy.accessTitle(resolved.fullAccess ? .full : .viewOnly)
                )
                Button {
                    Task { await model.acceptResolvedToken() }
                } label: {
                    Label(model.copy.accept, systemImage: "person.badge.plus")
                }
                .disabled(model.isBusy)
                .accessibilityIdentifier("sharing.token.accept")
            }
        }
    }

    private func accessPicker(selection: Binding<SharingAccessChoice>) -> some View {
        Picker(model.copy.access, selection: selection) {
            ForEach(SharingAccessChoice.allCases, id: \.self) { access in
                Text(model.copy.accessTitle(access)).tag(access)
            }
        }
        .pickerStyle(.segmented)
    }

    private func issueTitle(_ kind: SharingIssueKind) -> String {
        switch kind {
        case .unauthorized: model.copy.unauthorized
        case .forbidden: model.copy.forbidden
        case .notFound: model.copy.notFound
        case .conflict: model.copy.conflict
        case .validation: model.issue?.message ?? model.copy.unavailable
        case .offline: model.copy.offline
        case .unavailable: model.copy.unavailable
        }
    }

    private func issueSymbol(_ kind: SharingIssueKind) -> String {
        switch kind {
        case .unauthorized: "person.crop.circle.badge.exclamationmark"
        case .forbidden: "lock"
        case .notFound: "questionmark.circle"
        case .conflict: "arrow.triangle.2.circlepath"
        case .validation: "exclamationmark.circle"
        case .offline: "wifi.slash"
        case .unavailable: "exclamationmark.triangle"
        }
    }

    private func expiryText(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(Locale(identifier: model.language == .ru ? "ru_RU" : "en_US"))
        )
    }
}
