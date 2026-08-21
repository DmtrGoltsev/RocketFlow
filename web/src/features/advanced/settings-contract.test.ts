import { describe, expect, it } from 'vitest';

import { toSettingsUpdatePayload } from './settings-contract';
import type { UserSettingsResponse } from './types';

describe('hidden settings compatibility policies', () => {
  it('roundtrips both fetched policy objects without exposing editor-specific state', () => {
    const settings: UserSettingsResponse = {
      language: 'en',
      notificationsEnabled: true,
      version: 12,
      greenPriorityDecayPolicy: {
        taskType: 'green',
        enabled: false,
        thresholdPreset: 'month',
        decayAmount: 3,
      },
      redPriorityDecayPolicy: {
        taskType: 'red',
        enabled: true,
        thresholdPreset: 'day',
        decayAmount: 2,
      },
    };

    expect(toSettingsUpdatePayload(settings)).toEqual({
      language: 'en',
      notificationsEnabled: true,
      version: 12,
      greenPriorityDecayPolicy: {
        enabled: false,
        thresholdPreset: 'month',
        decayAmount: 3,
      },
      redPriorityDecayPolicy: {
        enabled: true,
        thresholdPreset: 'day',
        decayAmount: 2,
      },
    });
  });
});
