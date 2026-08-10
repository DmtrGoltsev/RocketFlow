import { describe, expect, it, vi } from 'vitest';

import { readWebPushSubscriptionId } from './focus-utils';
import {
  cleanupWebPushLifecycle,
  readPendingWebPushCleanups,
  retryPendingWebPushCleanups,
  type WebPushCleanupReason,
  type WebPushCleanupStorage,
} from './web-push-lifecycle';

function memoryStorage(): WebPushCleanupStorage {
  const values = new Map<string, string>();
  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => { values.set(key, value); },
    removeItem: (key) => { values.delete(key); },
  };
}

describe('Web Push session cleanup', () => {
  it.each<WebPushCleanupReason>([
    'explicit_logout',
    'authorized_401',
    'bootstrap_invalidation',
    'storage_event',
  ])('uses the same server-and-browser cleanup for %s', async (reason) => {
    const storage = memoryStorage();
    const deactivateServer = vi.fn(async () => undefined);
    const unsubscribeBrowser = vi.fn(async () => undefined);

    const result = await cleanupWebPushLifecycle({
      reason,
      userId: 'user-1',
      subscriptionId: 'subscription-1',
      deactivateServer,
      unsubscribeBrowser,
      storage,
    });

    expect(result).toEqual({ completed: true, serverDeactivated: true, browserUnsubscribed: true });
    expect(deactivateServer).toHaveBeenCalledOnce();
    expect(unsubscribeBrowser).toHaveBeenCalledOnce();
    expect(readPendingWebPushCleanups(storage)).toEqual([]);
    expect(readWebPushSubscriptionId('user-1', storage)).toBeNull();
  });

  it('keeps account cleanup state after a double failure and retries it before enable', async () => {
    const storage = memoryStorage();
    const serverFailure = vi.fn(async () => { throw new Error('server unavailable'); });
    const browserFailure = vi.fn(async () => { throw new Error('provider unavailable'); });

    const first = await cleanupWebPushLifecycle({
      reason: 'explicit_logout',
      userId: 'user-1',
      subscriptionId: 'subscription-1',
      deactivateServer: serverFailure,
      unsubscribeBrowser: browserFailure,
      storage,
    });

    expect(first.completed).toBe(false);
    expect(readWebPushSubscriptionId('user-1', storage)).toBe('subscription-1');
    expect(readPendingWebPushCleanups(storage)).toEqual([
      { userId: 'user-1', subscriptionId: 'subscription-1' },
    ]);

    const browserSuccess = vi.fn(async () => undefined);
    const remaining = await retryPendingWebPushCleanups(
      'enable_retry',
      () => serverFailure,
      browserSuccess,
      storage,
    );

    expect(serverFailure).toHaveBeenCalledTimes(2);
    expect(browserSuccess).toHaveBeenCalledOnce();
    expect(remaining).toEqual([]);
    expect(readWebPushSubscriptionId('user-1', storage)).toBeNull();
  });

  it('always tries browser unsubscribe when no authenticated server call is available', async () => {
    const storage = memoryStorage();
    const unsubscribeBrowser = vi.fn(async () => undefined);

    await cleanupWebPushLifecycle({
      reason: 'storage_event',
      userId: 'user-1',
      subscriptionId: 'subscription-1',
      deactivateServer: null,
      unsubscribeBrowser,
      storage,
    });

    expect(unsubscribeBrowser).toHaveBeenCalledOnce();
    expect(readPendingWebPushCleanups(storage)).toEqual([]);
  });

  it('finishes local cleanup when server deactivation succeeds but browser unsubscribe fails', async () => {
    const storage = memoryStorage();

    const result = await cleanupWebPushLifecycle({
      reason: 'authorized_401',
      userId: 'user-1',
      subscriptionId: 'subscription-1',
      deactivateServer: async () => undefined,
      unsubscribeBrowser: async () => { throw new Error('browser unavailable'); },
      storage,
    });

    expect(result).toEqual({ completed: true, serverDeactivated: true, browserUnsubscribed: false });
    expect(readPendingWebPushCleanups(storage)).toEqual([]);
    expect(readWebPushSubscriptionId('user-1', storage)).toBeNull();
  });
});
