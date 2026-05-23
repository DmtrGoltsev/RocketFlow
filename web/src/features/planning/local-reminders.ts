import type { TaskDto } from './types';

export type LocalReminderRepeat = 'none' | 'hourly';

export interface LocalTaskReminder {
  id: string;
  fireAt: string;
  repeat: LocalReminderRepeat;
  note: string;
  completedAt?: string | null;
}

const STORAGE_PREFIX = 'rocketflow.local-reminders';

function storageKey(userId: string, taskId: string) {
  return `${STORAGE_PREFIX}:${userId}:${taskId}`;
}

function parseReminders(value: string | null): LocalTaskReminder[] {
  if (!value) {
    return [];
  }

  try {
    const parsed = JSON.parse(value) as LocalTaskReminder[];
    return Array.isArray(parsed)
      ? parsed.filter((item) => typeof item.id === 'string' && typeof item.fireAt === 'string')
      : [];
  } catch {
    return [];
  }
}

function readRaw(userId: string, taskId: string) {
  if (typeof window === 'undefined') {
    return [];
  }

  return parseReminders(window.localStorage.getItem(storageKey(userId, taskId)));
}

function writeRaw(userId: string, taskId: string, reminders: LocalTaskReminder[]) {
  if (typeof window === 'undefined') {
    return;
  }

  const key = storageKey(userId, taskId);
  if (reminders.length === 0) {
    window.localStorage.removeItem(key);
    return;
  }

  window.localStorage.setItem(key, JSON.stringify(reminders));
}

export function createLocalReminderDraft(): LocalTaskReminder {
  return {
    id: typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`,
    fireAt: '',
    repeat: 'none',
    note: '',
    completedAt: null,
  };
}

export function loadLocalTaskReminders(userId: string, taskId: string) {
  return readRaw(userId, taskId).sort((left, right) => new Date(left.fireAt).getTime() - new Date(right.fireAt).getTime());
}

export function saveLocalTaskReminders(userId: string, taskId: string, reminders: LocalTaskReminder[]) {
  writeRaw(userId, taskId, reminders);
}

export function deleteLocalTaskReminders(userId: string, taskId: string) {
  writeRaw(userId, taskId, []);
}

export function listLocalTaskRemindersForUser(userId: string) {
  if (typeof window === 'undefined') {
    return [];
  }

  const prefix = `${STORAGE_PREFIX}:${userId}:`;
  const items: Array<{ taskId: string; reminders: LocalTaskReminder[] }> = [];

  for (let index = 0; index < window.localStorage.length; index += 1) {
    const key = window.localStorage.key(index);
    if (!key?.startsWith(prefix)) {
      continue;
    }

    items.push({
      taskId: key.slice(prefix.length),
      reminders: parseReminders(window.localStorage.getItem(key)),
    });
  }

  return items;
}

function nextHourlyFireAt(fireAt: string, now: Date) {
  const next = new Date(fireAt);
  if (Number.isNaN(next.getTime())) {
    return fireAt;
  }

  while (next <= now) {
    next.setHours(next.getHours() + 1);
  }

  return next.toISOString();
}

function showNotification(title: string, body: string) {
  if (typeof window === 'undefined' || !('Notification' in window) || Notification.permission !== 'granted') {
    return false;
  }

  if (document.visibilityState !== 'visible') {
    return false;
  }

  try {
    new Notification(title, { body });
    return true;
  } catch {
    return false;
  }
}

export function tickLocalReminderNotifications(userId: string, tasks: TaskDto[], locale: 'ru' | 'en') {
  const taskById = new Map(tasks.map((task) => [task.id, task]));
  const now = new Date();

  listLocalTaskRemindersForUser(userId).forEach(({ taskId, reminders }) => {
    const task = taskById.get(taskId);
    if (!task) {
      return;
    }

    let changed = false;
    const nextReminders = reminders.map((reminder) => {
      const fireAt = new Date(reminder.fireAt);
      if (Number.isNaN(fireAt.getTime()) || fireAt > now || reminder.completedAt) {
        return reminder;
      }

      const delivered = showNotification(
        locale === 'ru' ? 'Локальное напоминание RocketFlow' : 'RocketFlow local reminder',
        reminder.note.trim() || task.title,
      );

      if (!delivered) {
        return reminder;
      }

      changed = true;
      if (reminder.repeat === 'hourly') {
        return { ...reminder, fireAt: nextHourlyFireAt(reminder.fireAt, now), completedAt: null };
      }

      return { ...reminder, completedAt: now.toISOString() };
    });

    if (changed) {
      saveLocalTaskReminders(userId, taskId, nextReminders);
    }
  });
}
