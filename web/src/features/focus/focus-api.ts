import type {
  CreateWebPushSubscriptionPayload,
  FocusCandidatesResponse,
  FocusHistoryResponse,
  FocusInterval,
  FocusNotificationSettingsDto,
  FocusPeriodDto,
  WebPushConfigDto,
  WebPushSubscriptionDto,
} from './types';

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? '/rocket-api';
type AuthorizedFetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export class FocusApiError extends Error {
  constructor(public status: number, message: string) {
    super(message);
    this.name = 'FocusApiError';
  }
}

async function requestJson<T>(authorizedFetch: AuthorizedFetch, path: string, init: RequestInit = {}) {
  const headers = new Headers(init.headers);
  if (init.body) headers.set('Content-Type', 'application/json');
  const response = await authorizedFetch(`${API_BASE_URL}${path}`, { ...init, headers });
  if (!response.ok) {
    let message = 'Не удалось выполнить запрос.';
    try {
      const body = await response.json() as { error?: { message?: string }; message?: string };
      message = body.error?.message ?? body.message ?? message;
    } catch { /* keep the neutral fallback */ }
    throw new FocusApiError(response.status, message);
  }
  return response.status === 204 ? undefined as T : await response.json() as T;
}

export const getCurrentFocus = (fetcher: AuthorizedFetch, signal?: AbortSignal) =>
  requestJson<FocusPeriodDto>(fetcher, '/focus/current', { signal });

export function getFocusCandidates(fetcher: AuthorizedFetch, query = '', cursor?: string, signal?: AbortSignal) {
  const params = new URLSearchParams({ limit: '100' });
  if (query.trim()) params.set('q', query.trim());
  if (cursor) params.set('cursor', cursor);
  return requestJson<FocusCandidatesResponse>(fetcher, `/focus/candidates?${params}`, { signal });
}

export const addCurrentFocusItem = (fetcher: AuthorizedFetch, taskId: string, version?: number) =>
  requestJson<FocusPeriodDto>(fetcher, `/focus/current/items/${encodeURIComponent(taskId)}`, {
    method: 'PUT',
    body: JSON.stringify({ periodVersion: version, idempotencyKey: crypto.randomUUID() }),
  });

export const removeCurrentFocusItem = (fetcher: AuthorizedFetch, taskId: string, version: number) =>
  requestJson<FocusPeriodDto>(fetcher, `/focus/current/items/${encodeURIComponent(taskId)}`, {
    method: 'DELETE',
    body: JSON.stringify({ periodVersion: version, idempotencyKey: crypto.randomUUID() }),
  });

export const reorderCurrentFocusItems = (fetcher: AuthorizedFetch, taskIds: string[], version: number) =>
  requestJson<FocusPeriodDto>(fetcher, '/focus/current/items/order', {
    method: 'PATCH',
    body: JSON.stringify({ taskIds, periodVersion: version, idempotencyKey: crypto.randomUUID() }),
  });

export const resolveFocusRollover = (
  fetcher: AuthorizedFetch,
  sourcePeriodId: string,
  taskIds: string[],
  version: number,
) => requestJson<FocusPeriodDto>(fetcher, `/focus/rollovers/${sourcePeriodId}/resolve`, {
  method: 'POST',
  body: JSON.stringify({ taskIds, periodVersion: version, idempotencyKey: crypto.randomUUID() }),
});

export const getFocusHistory = (fetcher: AuthorizedFetch, signal?: AbortSignal) =>
  requestJson<FocusHistoryResponse>(fetcher, '/focus/history', { signal });

export const getFocusHistoryPeriod = (
  fetcher: AuthorizedFetch,
  periodId: string,
  signal?: AbortSignal,
) => requestJson<FocusPeriodDto>(fetcher, `/focus/history/${periodId}`, { signal });

function intervalFromMinutes(value: number | null): FocusInterval {
  return value === null ? 'off' : value === 30 ? '30m' : value === 60 ? '1h' : value === 120 ? '2h' : '4h';
}

function intervalToMinutes(value: FocusInterval) {
  return value === 'off' ? null : value === '30m' ? 30 : value === '1h' ? 60 : value === '2h' ? 120 : 240;
}

export async function getFocusNotificationSettings(fetcher: AuthorizedFetch, signal?: AbortSignal) {
  const response = await requestJson<{ intervalMinutes: number | null; quietHoursStart: string | null; quietHoursEnd: string | null; version: number }>(fetcher, '/focus/notification-settings', { signal });
  return { ...response, interval: intervalFromMinutes(response.intervalMinutes) } satisfies FocusNotificationSettingsDto;
}

export const updateFocusNotificationSettings = (
  fetcher: AuthorizedFetch,
  payload: { interval: FocusInterval; quietHoursStart: string | null; quietHoursEnd: string | null; version: number },
) => requestJson<{ intervalMinutes: number | null; quietHoursStart: string | null; quietHoursEnd: string | null; version: number }>(fetcher, '/focus/notification-settings', {
  method: 'PATCH',
  body: JSON.stringify({
    intervalMinutes: intervalToMinutes(payload.interval),
    quietHoursStart: payload.quietHoursStart,
    quietHoursEnd: payload.quietHoursEnd,
    version: payload.version,
  }),
}).then((response) => ({ ...response, interval: intervalFromMinutes(response.intervalMinutes) }));

export async function saveFocusNotificationSettings(
  fetcher: AuthorizedFetch,
  payload: FocusNotificationSettingsDto,
) {
  try {
    return {
      settings: await updateFocusNotificationSettings(fetcher, payload),
      conflict: false,
    };
  } catch (error) {
    if (!(error instanceof FocusApiError) || error.status !== 409) throw error;
    return {
      settings: await getFocusNotificationSettings(fetcher),
      conflict: true,
    };
  }
}

export const getWebPushConfig = (fetcher: AuthorizedFetch, signal?: AbortSignal) =>
  requestJson<WebPushConfigDto>(fetcher, '/notifications/web-push/config', { signal });

export const createWebPushSubscription = (fetcher: AuthorizedFetch, payload: CreateWebPushSubscriptionPayload, signal?: AbortSignal) =>
  requestJson<WebPushSubscriptionDto>(fetcher, '/notifications/web-push/subscriptions', {
    method: 'POST',
    body: JSON.stringify(payload),
    signal,
  });

export const deleteWebPushSubscription = (fetcher: AuthorizedFetch, id: string, signal?: AbortSignal) =>
  requestJson<void>(fetcher, `/notifications/web-push/subscriptions/${encodeURIComponent(id)}`, {
    method: 'DELETE',
    signal,
  });
