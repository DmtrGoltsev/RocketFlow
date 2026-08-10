import { describe, expect, it, vi } from 'vitest';

import {
  pendingCleanupMatchesSession,
  restoreSessionBeforePendingCleanup,
} from './auth-bootstrap';
import type { AuthSession } from './types';

function session(accessToken: string, refreshToken: string, userId = 'user-1'): AuthSession {
  return {
    user: {
      id: userId,
      email: `${userId}@example.test`,
      displayName: userId,
      timezone: 'Europe/Moscow',
      language: 'ru',
    },
    tokens: {
      accessToken,
      refreshToken,
      expiresAt: '2030-01-01T00:00:00Z',
    },
  };
}

describe('auth bootstrap with pending Web Push cleanup', () => {
  it('commits refreshed tokens before cleanup and never consumes the stale refresh twice', async () => {
    const stored = session('expired-access', 'stale-refresh');
    const refreshed = session('fresh-access', 'rotated-refresh');
    const events: string[] = [];
    let committed: AuthSession | null = null;
    let refreshCalls = 0;
    const cleanupAfterRestoreFailure = vi.fn(async () => undefined);

    const result = await restoreSessionBeforePendingCleanup({
      storedSession: stored,
      restoreSession: async (candidate) => {
        events.push('restore');
        expect(candidate.tokens.refreshToken).toBe('stale-refresh');
        refreshCalls += 1;
        return refreshed;
      },
      commitSession: (nextSession) => {
        events.push('commit');
        committed = nextSession;
        return nextSession;
      },
      retryPendingCleanup: async (currentSession) => {
        events.push('cleanup');
        expect(currentSession).toBe(committed);
        expect(currentSession?.tokens).toEqual(refreshed.tokens);
      },
      cleanupAfterRestoreFailure,
      isCurrent: () => true,
    });

    expect(result).toEqual({ status: 'authenticated', session: refreshed });
    expect(events).toEqual(['restore', 'commit', 'cleanup']);
    expect(refreshCalls).toBe(1);
    expect(cleanupAfterRestoreFailure).not.toHaveBeenCalled();
  });

  it('allows server cleanup only for the restored account', () => {
    expect(pendingCleanupMatchesSession(session('access', 'refresh'), 'user-1')).toBe(true);
    expect(pendingCleanupMatchesSession(session('access', 'refresh'), 'user-2')).toBe(false);
    expect(pendingCleanupMatchesSession(null, 'user-1')).toBe(false);
  });

  it('uses browser-only cleanup after restore failure', async () => {
    const stored = session('expired-access', 'invalid-refresh');
    const retryPendingCleanup = vi.fn(async () => undefined);
    const cleanupAfterRestoreFailure = vi.fn(async () => undefined);

    const result = await restoreSessionBeforePendingCleanup({
      storedSession: stored,
      restoreSession: async () => { throw new Error('refresh rejected'); },
      commitSession: (nextSession) => nextSession,
      retryPendingCleanup,
      cleanupAfterRestoreFailure,
      isCurrent: () => true,
    });

    expect(result.status).toBe('restore_failed');
    expect(cleanupAfterRestoreFailure).toHaveBeenCalledWith(stored);
    expect(retryPendingCleanup).not.toHaveBeenCalled();
  });
});
