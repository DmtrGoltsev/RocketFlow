import SwiftUI

@MainActor
struct SettingsView: View {
    @StateObject private var model: SettingsViewModel

    init(model: SettingsViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        Form {
            statusSection
            languageSection
            notificationSection
            defaultReminderSection
            currentReminderSection
            focusSection
            registrationSection
        }
        .navigationTitle(model.copy.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(model.copy.save) {
                    Task { _ = await model.save() }
                }
                .disabled(model.phase == .loading)
                .accessibilityIdentifier("settings.save")
            }
        }
        .task { if model.phase == .idle { await model.load() } }
        .accessibilityIdentifier("settings.screen")
    }

    @ViewBuilder
    private var statusSection: some View {
        if model.phase == .loading {
            Section {
                ProgressView(model.copy.loading)
                    .accessibilityIdentifier("settings.loading")
            }
        }
        if model.phase == .offline {
            status(model.copy.offline, symbol: "wifi.slash", color: .orange)
        }
        if model.phase == .pending {
            Section {
                HStack {
                    Label(model.copy.pending, systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button {
                        Task { await model.retry() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(model.copy.retry)
                }
            }
        }
        if model.phase == .error || model.phase == .unauthorized {
            status(model.copy.unavailable, symbol: "exclamationmark.triangle", color: .red)
        }
        if let validation = model.validationMessage {
            status(validation, symbol: "exclamationmark.circle", color: .red)
        }
    }

    private func status(_ text: String, symbol: String, color: Color) -> some View {
        Section {
            Label(text, systemImage: symbol)
                .foregroundStyle(color)
                .accessibilityIdentifier("settings.status")
        }
    }

    private var languageSection: some View {
        Section(model.copy.language) {
            Picker(model.copy.language, selection: $model.language) {
                Text(model.copy.russian).tag(AppLanguage.ru)
                Text(model.copy.english).tag(AppLanguage.en)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.language")
        }
    }

    private var notificationSection: some View {
        Section(model.copy.notifications) {
            Toggle(
                model.copy.notifications,
                isOn: Binding(
                    get: { model.notificationsEnabled },
                    set: { value in Task { await model.setNotificationsEnabled(value) } }
                )
            )
            .accessibilityIdentifier("settings.notifications.enabled")

            LabeledContent(model.copy.notificationPermission) {
                Label(authorizationText, systemImage: authorizationSymbol)
                    .foregroundStyle(authorizationColor)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var defaultReminderSection: some View {
        Section(model.copy.defaultReminder) {
            Toggle(model.copy.defaultReminder, isOn: $model.defaultReminderEnabled)
                .accessibilityIdentifier("settings.reminder.default.enabled")
            HStack {
                Text(model.copy.reminderOffset)
                Spacer()
                TextField(
                    model.copy.minutes,
                    value: $model.defaultOffsetMinutes,
                    format: .number
                )
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
                .disabled(!model.defaultReminderEnabled)
                .accessibilityIdentifier("settings.reminder.default.offset")
            }
            Picker(model.copy.repeatRule, selection: $model.defaultRepeatRule) {
                ForEach(TaskReminderRepeat.allCases, id: \.self) { value in
                    Text(model.copy.repeatLabel(value)).tag(value)
                }
            }
            .disabled(!model.defaultReminderEnabled)
            .accessibilityIdentifier("settings.reminder.default.repeat")
        }
    }

    private var currentReminderSection: some View {
        Section(model.copy.currentReminders) {
            if model.currentReminders.isEmpty {
                Text(model.copy.none)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.currentReminders) { reminder in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reminder.taskTitle)
                        Text(
                            reminder.triggerAt.formatted(date: .abbreviated, time: .shortened)
                                + " · " + model.copy.repeatLabel(reminder.repeatRule)
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(
                        "settings.reminder.\(reminder.id.uuidString.lowercased())"
                    )
                }
            }
        }
    }

    private var focusSection: some View {
        Section {
            Button {
                model.openFocusCadence()
            } label: {
                Label(model.copy.focusCadence, systemImage: "bell.badge")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("settings.focusCadence")
        }
    }

    private var registrationSection: some View {
        Section(model.copy.deviceRegistration) {
            Label(registrationText, systemImage: registrationSymbol)
                .foregroundStyle(registrationColor)
                .accessibilityIdentifier("settings.registration.state")
                .accessibilityHint(model.deviceRegistrationExplanation ?? "")
            if let explanation = model.deviceRegistrationExplanation {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.registration.unavailable.explanation")
            }
            Button {
                Task {
                    if case .registered = model.registrationState {
                        await model.unregisterDevice()
                    } else {
                        await model.syncDeviceRegistration()
                    }
                }
            } label: {
                Label(registrationAction, systemImage: registrationActionSymbol)
                    .frame(minHeight: 44)
            }
            .disabled(!model.canChangeDeviceRegistration)
            .accessibilityIdentifier("settings.registration.action")
            .accessibilityHint(model.deviceRegistrationExplanation ?? "")
        }
    }

    private var authorizationText: String {
        switch model.authorization {
        case .notDetermined: model.copy.permissionNotDetermined
        case .denied: model.copy.permissionDenied
        case .authorized, .provisional, .ephemeral: model.copy.permissionAllowed
        }
    }

    private var authorizationSymbol: String {
        switch model.authorization {
        case .notDetermined: "questionmark.circle"
        case .denied: "bell.slash"
        case .authorized, .provisional, .ephemeral: "bell"
        }
    }

    private var authorizationColor: Color {
        model.authorization == .denied ? .red : .secondary
    }

    private var registrationText: String {
        switch model.registrationState {
        case .registered: model.copy.registered
        case .syncing: model.copy.loading
        case .failed: model.copy.unavailable
        case .unavailable: model.copy.pushUnavailable
        case .unregistered: model.copy.notRegistered
        }
    }

    private var registrationSymbol: String {
        switch model.registrationState {
        case .registered: "checkmark.circle"
        case .syncing: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle"
        case .unavailable, .unregistered: "iphone.slash"
        }
    }

    private var registrationColor: Color {
        switch model.registrationState {
        case .registered: .green
        case .failed: .red
        default: .secondary
        }
    }

    private var registrationAction: String {
        if case .registered = model.registrationState {
            return model.copy.unregister
        }
        return model.copy.register
    }

    private var registrationActionSymbol: String {
        if case .registered = model.registrationState { return "xmark.circle" }
        return "arrow.clockwise"
    }
}
