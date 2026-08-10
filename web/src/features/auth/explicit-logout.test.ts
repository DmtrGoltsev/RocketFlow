import { describe, expect, it, vi } from 'vitest';

import { noRefreshAuthorizedFetch, runExplicitLogoutProtocol } from './explicit-logout';
import type { AuthSession } from './types';

const expiredSession: AuthSession = {
  user: {
    id: 'user-1',
    email: 'user-1@example.test',
    displayName: 'User 1',
    timezone: 'Europe/Moscow',
    language: 'ru',
  },
  tokens: {
    accessToken: 'expired-access',
    refreshToken: 'current-refresh',
    expiresAt: '2020-01-01T00:00:00Z',
  },
};

describe('explicit logout protocol', () => {
  it('deletes server Push before auth revoke, then clears browser and local auth', async () => {
    const events: string[] = [];

    await runExplicitLogoutProtocol({
      deactivatePushServer: async () => { events.push('delete-push'); },
      revokeAuthSession: async () => { events.push('revoke-auth'); },
      cleanupPushBrowser: async (serverDeactivated) => {
        expect(serverDeactivated).toBe(true);
        events.push('unsubscribe-browser');
      },
      finalizeLocalAuth: () => { events.push('clear-and-broadcast'); },
    });

    expect(events).toEqual([
      'delete-push',
      'revoke-auth',
      'unsubscribe-browser',
      'clear-and-broadcast',
    ]);
  });

  it('uses the captured access token once and never rotates a session on 401', async () => {
    const request = vi.fn(async (_input: RequestInfo | URL, _init?: RequestInit) => (
      new Response(null, { status: 401 })
    ));
    const fetcher = noRefreshAuthorizedFetch(expiredSession, request);

    const response = await fetcher('/rocket-api/notifications/web-push/subscriptions/sub-1', {
      method: 'DELETE',
    });

    expect(response.status).toBe(401);
    expect(request).toHaveBeenCalledOnce();
    const [, init] = request.mock.calls[0];
    expect(new Headers(init?.headers).get('Authorization')).toBe('Bearer expired-access');
  });

  it('always revokes auth and continues browser cleanup when server Push deletion fails', async () => {
    const events: string[] = [];
    const finalizeLocalAuth = vi.fn();

    await runExplicitLogoutProtocol({
      deactivatePushServer: async () => {
        events.push('delete-push');
        throw new Error('expired access');
      },
      revokeAuthSession: async () => { events.push('revoke-auth'); },
      cleanupPushBrowser: async (serverDeactivated) => {
        expect(serverDeactivated).toBe(false);
        events.push('unsubscribe-browser');
      },
      finalizeLocalAuth,
    });

    expect(events).toEqual(['delete-push', 'revoke-auth', 'unsubscribe-browser']);
    expect(finalizeLocalAuth).toHaveBeenCalledOnce();
  });

  it('still performs browser cleanup and local invalidation when auth revocation fails', async () => {
    const cleanupPushBrowser = vi.fn(async () => undefined);
    const finalizeLocalAuth = vi.fn();

    await runExplicitLogoutProtocol({
      deactivatePushServer: async () => undefined,
      revokeAuthSession: async () => { throw new Error('offline'); },
      cleanupPushBrowser,
      finalizeLocalAuth,
    });

    expect(cleanupPushBrowser).toHaveBeenCalledWith(true);
    expect(finalizeLocalAuth).toHaveBeenCalledOnce();
  });

  it('finalizes a multi-tab browser-only invalidation without a server request', async () => {
    const serverRequest = vi.fn();
    const unsubscribeBrowser = vi.fn(async () => undefined);
    const finalizeLocalAuth = vi.fn();

    await runExplicitLogoutProtocol({
      deactivatePushServer: async () => undefined,
      revokeAuthSession: async () => undefined,
      cleanupPushBrowser: async () => unsubscribeBrowser(),
      finalizeLocalAuth,
    });

    expect(serverRequest).not.toHaveBeenCalled();
    expect(unsubscribeBrowser).toHaveBeenCalledOnce();
    expect(finalizeLocalAuth).toHaveBeenCalledOnce();
  });
});
