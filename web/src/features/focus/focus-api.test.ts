import { describe, expect, it, vi } from 'vitest';

import {
  createWebPushSubscription,
  saveFocusNotificationSettings,
  updateFocusNotificationSettings,
} from './focus-api';
import type { FocusNotificationSettingsDto } from './types';

const settings: FocusNotificationSettingsDto = {
  interval: '1h',
  quietHoursStart: '22:00',
  quietHoursEnd: '07:00',
  version: 7,
};

describe('Focus notification settings contract', () => {
  it('sends the optimistic version in PATCH', async () => {
    const fetcher = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      expect(init?.method).toBe('PATCH');
      expect(JSON.parse(String(init?.body))).toEqual({
        intervalMinutes: 60,
        quietHoursStart: '22:00',
        quietHoursEnd: '07:00',
        version: 7,
      });
      return new Response(JSON.stringify({
        intervalMinutes: 60,
        quietHoursStart: '22:00',
        quietHoursEnd: '07:00',
        version: 8,
      }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    });

    await expect(updateFocusNotificationSettings(fetcher, settings)).resolves.toMatchObject({
      interval: '1h',
      version: 8,
    });
  });

  it('refreshes current settings after a 409 conflict', async () => {
    const fetcher = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ message: 'conflict' }), {
        status: 409,
        headers: { 'Content-Type': 'application/json' },
      }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        intervalMinutes: 120,
        quietHoursStart: null,
        quietHoursEnd: null,
        version: 9,
      }), { status: 200, headers: { 'Content-Type': 'application/json' } }));

    await expect(saveFocusNotificationSettings(fetcher, settings)).resolves.toEqual({
      settings: {
        intervalMinutes: 120,
        quietHoursStart: null,
        quietHoursEnd: null,
        version: 9,
        interval: '2h',
      },
      conflict: true,
    });
    expect(fetcher).toHaveBeenCalledTimes(2);
  });
});

describe('Web Push subscription contract', () => {
  it('sends an ISO expiration Instant or null', async () => {
    const fetcher = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      expect(JSON.parse(String(init?.body))).toMatchObject({
        expirationTime: '2030-01-02T03:04:05.000Z',
      });
      return new Response(JSON.stringify({ id: 'subscription-1' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    });

    await createWebPushSubscription(fetcher, {
      endpoint: 'https://push.example.test/subscription',
      expirationTime: '2030-01-02T03:04:05.000Z',
      keys: { p256dh: 'key', auth: 'auth' },
      installationId: 'installation-1',
    });

    expect(fetcher).toHaveBeenCalledOnce();
  });
});
