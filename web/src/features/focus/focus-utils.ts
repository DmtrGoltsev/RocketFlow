import type { FocusCandidateDto, FocusItemDto, FocusProgressDto } from './types';

const WEB_PUSH_SUBSCRIPTION_PREFIX = 'rocketflow.web-push.subscription-id';
let webPushSessionGeneration = 0;

export function invalidateWebPushSessionOperations() {
  webPushSessionGeneration += 1;
  return webPushSessionGeneration;
}

export function isCurrentWebPushSessionOperation(
  operationGeneration: number,
  operationUserId: string,
  currentUserId: string | null,
) {
  return operationGeneration === webPushSessionGeneration && operationUserId === currentUserId;
}

export function effectiveFocusWeight(item: Pick<FocusItemDto, 'effort' | 'effectiveWeight'>) {
  if (Number.isFinite(item.effectiveWeight) && item.effectiveWeight > 0) {
    return item.effectiveWeight;
  }

  return item.effort && item.effort > 0 ? item.effort : 1;
}

export function calculateFocusProgress(items: FocusItemDto[]): FocusProgressDto {
  const totalWeight = items.reduce((sum, item) => sum + effectiveFocusWeight(item), 0);
  const completedWeight = items
    .filter((item) => item.status === 'done')
    .reduce((sum, item) => sum + effectiveFocusWeight(item), 0);

  return {
    completedWeight,
    totalWeight,
    percent: totalWeight === 0 ? 0 : Math.round((completedWeight / totalWeight) * 100),
  };
}

export function base64UrlToUint8Array(value: string) {
  const padding = '='.repeat((4 - (value.length % 4)) % 4);
  const binary = globalThis.atob((value + padding).replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

export function webPushExpirationTimeToIso(expirationTime: number | null) {
  if (expirationTime === null) return null;
  const date = new Date(expirationTime);
  if (Number.isNaN(date.getTime())) throw new Error('Invalid Web Push expiration time.');
  return date.toISOString();
}

export function browserInstallationId() {
  const key = 'rocketflow.web-push.installation-id';
  const existing = window.localStorage.getItem(key);
  if (existing) {
    return existing;
  }

  const next = crypto.randomUUID();
  window.localStorage.setItem(key, next);
  return next;
}

export function webPushSubscriptionStorageKey(userId: string) {
  return `${WEB_PUSH_SUBSCRIPTION_PREFIX}:${encodeURIComponent(userId)}`;
}

export function readWebPushSubscriptionId(userId: string, storage: Pick<Storage, 'getItem'> = window.localStorage) {
  return storage.getItem(webPushSubscriptionStorageKey(userId));
}

export function writeWebPushSubscriptionId(
  userId: string,
  subscriptionId: string,
  storage: Pick<Storage, 'setItem'> = window.localStorage,
) {
  storage.setItem(webPushSubscriptionStorageKey(userId), subscriptionId);
}

export function removeWebPushSubscriptionId(userId: string, storage: Pick<Storage, 'removeItem'> = window.localStorage) {
  storage.removeItem(webPushSubscriptionStorageKey(userId));
}

export function readLegacyWebPushSubscriptionId(storage: Pick<Storage, 'getItem'> = window.localStorage) {
  return storage.getItem(WEB_PUSH_SUBSCRIPTION_PREFIX);
}

export function removeLegacyWebPushSubscriptionId(storage: Pick<Storage, 'removeItem'> = window.localStorage) {
  storage.removeItem(WEB_PUSH_SUBSCRIPTION_PREFIX);
}

export function mergeFocusCandidatePages(
  current: FocusCandidateDto[],
  incoming: FocusCandidateDto[],
  append: boolean,
) {
  if (!append) {
    return incoming;
  }

  const merged = new Map(current.map((item) => [item.taskId, item]));
  incoming.forEach((item) => merged.set(item.taskId, item));
  return [...merged.values()];
}

export function isLatestFocusCandidateRequest(requestId: number, currentRequestId: number) {
  return requestId === currentRequestId;
}

export function isLatestFocusHistoryRequest(requestId: number, currentRequestId: number) {
  return requestId === currentRequestId;
}

export function updateCandidateFocusAfterMutation(
  items: FocusCandidateDto[],
  taskId: string,
  succeeded: boolean,
) {
  return succeeded
    ? items.map((item) => item.taskId === taskId ? { ...item, inFocus: true } : item)
    : items;
}

export interface FocusCandidateGoalGroup {
  id: string;
  title: string;
  items: FocusCandidateDto[];
}

export interface FocusCandidateFolderGroup {
  id: string;
  title: string;
  goals: FocusCandidateGoalGroup[];
}

export function groupFocusCandidates(items: FocusCandidateDto[]): FocusCandidateFolderGroup[] {
  const folders = new Map<string, {
    id: string;
    title: string;
    goals: Map<string, FocusCandidateGoalGroup>;
  }>();

  items.forEach((item) => {
    const folderId = item.folderId ?? '__no_folder__';
    const goalId = item.goalId ?? `__no_goal__:${folderId}`;
    let folder = folders.get(folderId);
    if (!folder) {
      folder = { id: folderId, title: item.folderTitle || 'Без папки', goals: new Map() };
      folders.set(folderId, folder);
    }
    let goal = folder.goals.get(goalId);
    if (!goal) {
      goal = { id: goalId, title: item.goalTitle || 'Без цели', items: [] };
      folder.goals.set(goalId, goal);
    }
    goal.items.push(item);
  });

  return [...folders.values()].map((folder) => ({
    id: folder.id,
    title: folder.title,
    goals: [...folder.goals.values()],
  }));
}

export function taskDetailPath(taskId: string) {
  return `/app/tasks?taskId=${encodeURIComponent(taskId)}`;
}
