import {
  invalidateWebPushSessionOperations,
  readLegacyWebPushSubscriptionId,
  readWebPushSubscriptionId,
  removeLegacyWebPushSubscriptionId,
  removeWebPushSubscriptionId,
  writeWebPushSubscriptionId,
} from './focus-utils';

const WEB_PUSH_PENDING_CLEANUP_KEY = 'rocketflow.web-push.pending-cleanup';

export type WebPushCleanupReason =
  | 'explicit_logout'
  | 'authorized_401'
  | 'bootstrap_invalidation'
  | 'storage_event'
  | 'broadcast_event'
  | 'explicit_disable'
  | 'stale_enable'
  | 'bootstrap_retry'
  | 'session_retry'
  | 'enable_retry';

export interface PendingWebPushCleanup {
  userId: string;
  subscriptionId: string | null;
}

export interface WebPushCleanupStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

export interface WebPushCleanupResult {
  completed: boolean;
  serverDeactivated: boolean;
  browserUnsubscribed: boolean;
}

interface CleanupOptions extends PendingWebPushCleanup {
  reason: WebPushCleanupReason;
  deactivateServer?: (() => Promise<void>) | null;
  unsubscribeBrowser: () => Promise<void>;
  storage?: WebPushCleanupStorage;
}

function defaultStorage() {
  return window.localStorage;
}

function isPendingCleanup(value: unknown): value is PendingWebPushCleanup {
  if (!value || typeof value !== 'object') return false;
  const candidate = value as Record<string, unknown>;
  return typeof candidate.userId === 'string'
    && candidate.userId.length > 0
    && (candidate.subscriptionId === null || typeof candidate.subscriptionId === 'string');
}

function sameCleanup(left: PendingWebPushCleanup, right: PendingWebPushCleanup) {
  return left.userId === right.userId && left.subscriptionId === right.subscriptionId;
}

export function readPendingWebPushCleanups(
  storage: WebPushCleanupStorage = defaultStorage(),
): PendingWebPushCleanup[] {
  try {
    const raw = storage.getItem(WEB_PUSH_PENDING_CLEANUP_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as unknown;
    return Array.isArray(parsed) ? parsed.filter(isPendingCleanup) : [];
  } catch {
    return [];
  }
}

function writePendingWebPushCleanups(
  pending: PendingWebPushCleanup[],
  storage: WebPushCleanupStorage,
) {
  try {
    if (pending.length === 0) {
      storage.removeItem(WEB_PUSH_PENDING_CLEANUP_KEY);
      return;
    }
    storage.setItem(WEB_PUSH_PENDING_CLEANUP_KEY, JSON.stringify(pending));
  } catch {
    // Restricted browser storage must not prevent local session invalidation.
  }
}

function rememberPendingCleanup(target: PendingWebPushCleanup, storage: WebPushCleanupStorage) {
  const pending = readPendingWebPushCleanups(storage);
  if (!pending.some((item) => sameCleanup(item, target))) pending.push(target);
  writePendingWebPushCleanups(pending, storage);
  try {
    if (target.subscriptionId) writeWebPushSubscriptionId(target.userId, target.subscriptionId, storage);
  } catch {
    // Pending cleanup is best effort when persistent storage is unavailable.
  }
}

function finishPendingCleanup(target: PendingWebPushCleanup, storage: WebPushCleanupStorage) {
  writePendingWebPushCleanups(
    readPendingWebPushCleanups(storage).filter((item) => !sameCleanup(item, target)),
    storage,
  );
  try {
    removeWebPushSubscriptionId(target.userId, storage);
    removeLegacyWebPushSubscriptionId(storage);
  } catch {
    // Delivery is already disabled by at least one channel.
  }
}

export async function unsubscribeCurrentBrowserPush() {
  if (!('serviceWorker' in navigator)) return;
  const registration = await navigator.serviceWorker.getRegistration();
  if (!registration) return;
  const subscription = await registration.pushManager.getSubscription();
  if (subscription && !(await subscription.unsubscribe())) {
    throw new Error('Browser push unsubscribe was rejected.');
  }
}

export async function cleanupWebPushLifecycle({
  userId,
  subscriptionId,
  deactivateServer,
  unsubscribeBrowser,
  storage = defaultStorage(),
}: CleanupOptions): Promise<WebPushCleanupResult> {
  invalidateWebPushSessionOperations();
  const target = { userId, subscriptionId };
  rememberPendingCleanup(target, storage);

  let serverDeactivated = false;
  let browserUnsubscribed = false;

  if (subscriptionId && deactivateServer) {
    try {
      await deactivateServer();
      serverDeactivated = true;
    } catch {
      // The browser path is still attempted; a double failure remains pending.
    }
  }

  try {
    await unsubscribeBrowser();
    browserUnsubscribed = true;
  } catch {
    // Pending state intentionally survives until a later bootstrap or enable.
  }

  const completed = serverDeactivated || browserUnsubscribed;
  if (completed) finishPendingCleanup(target, storage);
  return { completed, serverDeactivated, browserUnsubscribed };
}

export async function cleanupWebPushForUser(
  options: Omit<CleanupOptions, 'subscriptionId'> & { subscriptionId?: string | null },
) {
  const storage = options.storage ?? defaultStorage();
  const subscriptionId = options.subscriptionId
    ?? readWebPushSubscriptionId(options.userId, storage)
    ?? readLegacyWebPushSubscriptionId(storage);
  return cleanupWebPushLifecycle({ ...options, storage, subscriptionId });
}

export async function retryPendingWebPushCleanups(
  reason: Extract<WebPushCleanupReason, 'bootstrap_retry' | 'session_retry' | 'enable_retry'>,
  deactivateServer: (pending: PendingWebPushCleanup) => (() => Promise<void>) | null,
  unsubscribeBrowser: () => Promise<void>,
  storage: WebPushCleanupStorage = defaultStorage(),
) {
  for (const pending of readPendingWebPushCleanups(storage)) {
    await cleanupWebPushLifecycle({
      ...pending,
      reason,
      deactivateServer: deactivateServer(pending),
      unsubscribeBrowser,
      storage,
    });
  }
  return readPendingWebPushCleanups(storage);
}

export { WEB_PUSH_PENDING_CLEANUP_KEY };
