import SwiftUI

@MainActor
struct FocusCadenceSettingsView: View {
    @ObservedObject var model: FocusViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var intervalMinutes: Int? = FocusCadenceValues.defaults.intervalMinutes
    @State private var quietHoursEnabled = true
    @State private var quietStart = FocusCadenceValues.defaults.quietHoursStart ?? "22:00"
    @State private var quietEnd = FocusCadenceValues.defaults.quietHoursEnd ?? "08:00"
    @State private var didApplyLoadedSettings = false

    var body: some View {
        NavigationStack {
            Form {
                if model.settingsPhase == .offline {
                    Label(model.copy.offline, systemImage: "wifi.slash")
                        .foregroundStyle(.orange)
                } else if model.settingsPhase == .error {
                    Label(model.copy.unavailable, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }

                Section(model.copy.cadence) {
                    Picker(model.copy.cadence, selection: $intervalMinutes) {
                        Text(FocusFormatting.cadence(nil, language: model.language)).tag(Int?.none)
                        ForEach([30, 60, 120, 240], id: \.self) { value in
                            Text(FocusFormatting.cadence(value, language: model.language)).tag(Int?.some(value))
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section(model.copy.quietHours) {
                    Toggle(model.copy.quietHours, isOn: $quietHoursEnabled)
                    if quietHoursEnabled {
                        HStack {
                            Text(model.copy.quietStart)
                            Spacer()
                            TextField("22:00", text: $quietStart)
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 88)
                                .accessibilityLabel(model.copy.quietStart)
                                .accessibilityIdentifier("focus.settings.quietStart")
                        }
                        HStack {
                            Text(model.copy.quietEnd)
                            Spacer()
                            TextField("08:00", text: $quietEnd)
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 88)
                                .accessibilityLabel(model.copy.quietEnd)
                                .accessibilityIdentifier("focus.settings.quietEnd")
                        }
                    }
                    Text(model.timezone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let validation = model.cadenceValidationMessage {
                    Section {
                        Label(validation, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("focus.settings.validation")
                    }
                }
            }
            .navigationTitle(model.copy.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.copy.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.copy.save) {
                        Task {
                            let saved = await model.saveSettings(values)
                            if saved { dismiss() }
                        }
                    }
                    .disabled(model.settingsPhase == .loading)
                }
            }
            .task {
                if model.settings == nil { await model.loadSettings() }
                applyLoadedSettingsIfNeeded()
            }
            .onChange(of: model.settings) { _ in
                applyLoadedSettingsIfNeeded()
            }
            .accessibilityIdentifier("focus.settings.screen")
        }
    }

    private var values: FocusCadenceValues {
        FocusCadenceValues(
            intervalMinutes: intervalMinutes,
            quietHoursStart: quietHoursEnabled
                ? quietStart.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            quietHoursEnd: quietHoursEnabled
                ? quietEnd.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
        )
    }

    private func applyLoadedSettingsIfNeeded() {
        guard !didApplyLoadedSettings, let settings = model.settings else { return }
        intervalMinutes = settings.intervalMinutes
        quietHoursEnabled = settings.quietHoursStart != nil || settings.quietHoursEnd != nil
        quietStart = settings.quietHoursStart ?? FocusCadenceValues.defaults.quietHoursStart ?? "22:00"
        quietEnd = settings.quietHoursEnd ?? FocusCadenceValues.defaults.quietHoursEnd ?? "08:00"
        didApplyLoadedSettings = true
    }
}
