import { describe, expect, it } from 'vitest';

import {
  base64UrlToUint8Array,
  calculateFocusProgress,
  groupFocusCandidates,
  invalidateWebPushSessionOperations,
  isCurrentWebPushSessionOperation,
  isLatestFocusCandidateRequest,
  isLatestFocusHistoryRequest,
  mergeFocusCandidatePages,
  readWebPushSubscriptionId,
  taskDetailPath,
  updateCandidateFocusAfterMutation,
  webPushExpirationTimeToIso,
  webPushSubscriptionStorageKey,
  writeWebPushSubscriptionId,
} from './focus-utils';
import type { FocusCandidateDto, FocusItemDto } from './types';

function item(overrides: Partial<FocusItemDto>): FocusItemDto {
  return {
    id: crypto.randomUUID(), taskId: crypto.randomUUID(), title: 'Task', status: 'todo', effort: null,
    effectiveWeight: 0, position: 0, ...overrides,
  };
}

describe('calculateFocusProgress', () => {
  it('uses one for missing or zero effort and counts only done tasks', () => {
    const progress = calculateFocusProgress([
      item({ status: 'done', effort: 0 }),
      item({ status: 'in_progress', effort: 3, effectiveWeight: 3 }),
      item({ status: 'cancelled', effort: null }),
    ]);
    expect(progress).toEqual({ completedWeight: 1, totalWeight: 5, percent: 20 });
  });
});

describe('push and deep-link helpers', () => {
  it('decodes an unpadded base64url VAPID key', () => {
    expect([...base64UrlToUint8Array('AQID-_8')]).toEqual([1, 2, 3, 251, 255]);
  });

  it('creates an encoded task detail URL', () => {
    expect(taskDetailPath('task/a b')).toBe('/app/tasks?taskId=task%2Fa%20b');
  });

  it('scopes server subscription ids to the authenticated account', () => {
    const values = new Map<string, string>();
    const storage = {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => values.set(key, value),
    };
    writeWebPushSubscriptionId('user/a', 'subscription-a', storage);
    writeWebPushSubscriptionId('user/b', 'subscription-b', storage);
    expect(webPushSubscriptionStorageKey('user/a')).not.toBe(webPushSubscriptionStorageKey('user/b'));
    expect(readWebPushSubscriptionId('user/a', storage)).toBe('subscription-a');
    expect(readWebPushSubscriptionId('user/b', storage)).toBe('subscription-b');
  });

  it('invalidates an async push operation on logout or account change', () => {
    const operation = invalidateWebPushSessionOperations();
    expect(isCurrentWebPushSessionOperation(operation, 'user-a', 'user-a')).toBe(true);
    invalidateWebPushSessionOperations();
    expect(isCurrentWebPushSessionOperation(operation, 'user-a', 'user-a')).toBe(false);

    const nextOperation = invalidateWebPushSessionOperations();
    expect(isCurrentWebPushSessionOperation(nextOperation, 'user-a', 'user-b')).toBe(false);
  });

  it('converts browser Web Push expiration milliseconds to the backend Instant contract', () => {
    expect(webPushExpirationTimeToIso(Date.UTC(2030, 0, 2, 3, 4, 5))).toBe('2030-01-02T03:04:05.000Z');
    expect(webPushExpirationTimeToIso(null)).toBeNull();
  });

});

describe('candidate result helpers', () => {
  const candidate = (taskId: string, inFocus = false): FocusCandidateDto => ({
    taskId, title: taskId, status: 'todo', effort: 1, effectiveWeight: 1, inFocus,
  });

  it('merges cursor pages without duplicates and keeps the latest payload', () => {
    expect(mergeFocusCandidatePages([candidate('a'), candidate('b')], [candidate('b', true), candidate('c')], true))
      .toEqual([candidate('a'), candidate('b', true), candidate('c')]);
  });

  it('rejects a stale search response after a newer request starts', () => {
    expect(isLatestFocusCandidateRequest(4, 5)).toBe(false);
    expect(isLatestFocusCandidateRequest(5, 5)).toBe(true);
  });

  it('rejects stale history details after switching weeks or returning to current', () => {
    expect(isLatestFocusHistoryRequest(7, 8)).toBe(false);
    expect(isLatestFocusHistoryRequest(8, 8)).toBe(true);
    expect(isLatestFocusHistoryRequest(8, 9)).toBe(false);
  });

  it('does not mark a candidate focused after a failed mutation', () => {
    const items = [candidate('a')];
    expect(updateCandidateFocusAfterMutation(items, 'a', false)).toBe(items);
    expect(updateCandidateFocusAfterMutation(items, 'a', true)[0].inFocus).toBe(true);
  });

  it('groups equal titles by stable folder and goal ids', () => {
    const first = { ...candidate('a'), folderId: 'folder-1', folderTitle: 'Work', goalId: 'goal-1', goalTitle: 'Launch' };
    const second = { ...candidate('b'), folderId: 'folder-2', folderTitle: 'Work', goalId: 'goal-2', goalTitle: 'Launch' };
    const groups = groupFocusCandidates([first, second]);

    expect(groups).toHaveLength(2);
    expect(groups.map((folder) => folder.id)).toEqual(['folder-1', 'folder-2']);
    expect(groups.map((folder) => folder.goals[0].id)).toEqual(['goal-1', 'goal-2']);
  });
});
