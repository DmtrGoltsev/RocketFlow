import type { UpdateSettingsPayload, UserSettingsResponse } from './types';

export function toSettingsUpdatePayload(settings: UserSettingsResponse): UpdateSettingsPayload {
  return {
    language: settings.language,
    greenPriorityDecayPolicy: {
      enabled: settings.greenPriorityDecayPolicy.enabled,
      thresholdPreset: settings.greenPriorityDecayPolicy.thresholdPreset,
      decayAmount: settings.greenPriorityDecayPolicy.decayAmount,
    },
    redPriorityDecayPolicy: {
      enabled: settings.redPriorityDecayPolicy.enabled,
      thresholdPreset: settings.redPriorityDecayPolicy.thresholdPreset,
      decayAmount: settings.redPriorityDecayPolicy.decayAmount,
    },
    notificationsEnabled: settings.notificationsEnabled,
    version: settings.version,
  };
}
