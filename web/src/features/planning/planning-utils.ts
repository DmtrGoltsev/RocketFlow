import type {
  DayOfWeek,
  FolderDto,
  GoalDto,
  TaskDto,
  TaskRecurrenceDraft,
  TaskRecurrenceDto,
  TaskRecurrenceUpsertPayload,
  TaskStatus,
  TaskTimeAnchor,
  TaskType,
  TaskUpsertPayload,
} from './types';

type NamedEntity = FolderDto | GoalDto;

const EMPTY_VALUE = '-';
const WEEKDAYS: DayOfWeek[] = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];

export interface TaskEditorDraft {
  title: string;
  description: string;
  type: TaskType;
  status: TaskStatus;
  priority: string;
  plannedTime: string;
  dueTime: string;
  recurrence: TaskRecurrenceDraft;
}

export function toDateTimeInputValue(value: string | null) {
  if (!value) {
    return '';
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return '';
  }

  const pad = (segment: number) => String(segment).padStart(2, '0');

  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function fromDateTimeInputValue(value: string) {
  if (!value) {
    return null;
  }

  const parsed = new Date(value);

  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

export function formatDateTime(value: string | null, locale: 'ru' | 'en') {
  if (!value) {
    return EMPTY_VALUE;
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return EMPTY_VALUE;
  }

  return new Intl.DateTimeFormat(locale === 'ru' ? 'ru-RU' : 'en-US', {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
}

export function normalizeSelection<TItem extends { id: string }>(items: TItem[], preferredId: string | null) {
  if (items.length === 0) {
    return null;
  }

  if (preferredId && items.some((item) => item.id === preferredId)) {
    return preferredId;
  }

  return items[0].id;
}

export function findById<TItem extends { id: string }>(items: TItem[], id: string | null) {
  if (!id) {
    return null;
  }

  return items.find((item) => item.id === id) ?? null;
}

export function describeTags(task: TaskDto) {
  if (task.tags.length === 0) {
    return EMPTY_VALUE;
  }

  return task.tags.map((tag) => tag.name).join(', ');
}

export function namedEntityMap<TItem extends NamedEntity>(items: TItem[]) {
  return new Map(items.map((item) => [item.id, item.name]));
}

function detectAnchor(plannedTime: string | null, dueTime: string | null, startAt?: string | null): TaskTimeAnchor {
  if (startAt && dueTime && startAt === dueTime) {
    return 'due';
  }

  if (startAt && plannedTime && startAt === plannedTime) {
    return 'planned';
  }

  if (!plannedTime && dueTime) {
    return 'due';
  }

  return 'planned';
}

export function createDefaultRecurrenceDraft(plannedTime: string | null, dueTime: string | null): TaskRecurrenceDraft {
  return {
    enabled: false,
    active: true,
    mode: 'weekly',
    interval: '1',
    anchor: !plannedTime && dueTime ? 'due' : 'planned',
    daysOfWeek: [],
    endAt: '',
  };
}

export function toTaskRecurrenceDraft(task: TaskDto | null): TaskRecurrenceDraft {
  if (!task || !task.recurrence) {
    return createDefaultRecurrenceDraft(task?.plannedTime ?? null, task?.dueTime ?? null);
  }

  return {
    enabled: task.recurrence.active,
    active: task.recurrence.active,
    mode: task.recurrence.mode,
    interval: String(task.recurrence.interval),
    anchor: detectAnchor(task.plannedTime, task.dueTime, task.recurrence.startAt),
    daysOfWeek: task.recurrence.daysOfWeek,
    endAt: toDateTimeInputValue(task.recurrence.endAt),
  };
}

export function toTaskEditorDraft(task: TaskDto | null): TaskEditorDraft {
  return {
    title: task?.title ?? '',
    description: task?.description ?? '',
    type: task?.type ?? 'green',
    status: task?.status ?? 'todo',
    priority: String(task?.priority ?? 5),
    plannedTime: toDateTimeInputValue(task?.plannedTime ?? null),
    dueTime: toDateTimeInputValue(task?.dueTime ?? null),
    recurrence: toTaskRecurrenceDraft(task),
  };
}

export function toTaskUpsertPayload(draft: TaskEditorDraft): TaskUpsertPayload {
  return {
    title: draft.title.trim(),
    description: draft.description.trim(),
    type: draft.type,
    status: draft.status,
    priority: Number(draft.priority),
    plannedTime: fromDateTimeInputValue(draft.plannedTime),
    dueTime: fromDateTimeInputValue(draft.dueTime),
  };
}

export function resolveTaskAnchorTime(draft: TaskEditorDraft) {
  return draft.recurrence.anchor === 'due'
    ? fromDateTimeInputValue(draft.dueTime)
    : fromDateTimeInputValue(draft.plannedTime);
}

export function toTaskRecurrenceUpsertPayload(draft: TaskEditorDraft): TaskRecurrenceUpsertPayload | null {
  const startAt = resolveTaskAnchorTime(draft);

  if (!startAt) {
    return null;
  }

  const startDate = new Date(startAt);
  const dayOfMonth = draft.recurrence.mode === 'monthly' && !Number.isNaN(startDate.getTime())
    ? startDate.getDate()
    : null;

  return {
    mode: draft.recurrence.mode,
    interval: Number(draft.recurrence.interval),
    daysOfWeek: draft.recurrence.mode === 'weekly' ? draft.recurrence.daysOfWeek : [],
    dayOfMonth,
    startAt,
    endAt: fromDateTimeInputValue(draft.recurrence.endAt),
    active: draft.recurrence.enabled && draft.recurrence.active,
  };
}

function formatWeekdays(daysOfWeek: DayOfWeek[], locale: 'ru' | 'en') {
  if (daysOfWeek.length === 0) {
    return locale === 'ru' ? 'дни не выбраны' : 'no weekdays selected';
  }

  const formatter = new Intl.DateTimeFormat(locale === 'ru' ? 'ru-RU' : 'en-US', { weekday: 'short' });
  const mondayUtc = Date.UTC(2026, 0, 5);

  return daysOfWeek.map((day) => {
    const index = WEEKDAYS.indexOf(day);
    return formatter.format(new Date(mondayUtc + index * 24 * 60 * 60 * 1000));
  }).join(', ');
}

export function describeRecurrence(recurrence: TaskRecurrenceDto | null, locale: 'ru' | 'en') {
  if (!recurrence || !recurrence.active) {
    return locale === 'ru' ? 'Не настроен' : 'Not configured';
  }

  const start = formatDateTime(recurrence.startAt, locale);
  const end = recurrence.endAt ? formatDateTime(recurrence.endAt, locale) : locale === 'ru' ? 'без окончания' : 'no end';

  if (recurrence.mode === 'daily') {
    return locale === 'ru'
      ? `Ежедневно, каждые ${recurrence.interval}, старт ${start}, ${end}`
      : `Daily, every ${recurrence.interval}, starts ${start}, ${end}`;
  }

  if (recurrence.mode === 'weekly') {
    return locale === 'ru'
      ? `Еженедельно: ${formatWeekdays(recurrence.daysOfWeek, locale)}, каждые ${recurrence.interval}, старт ${start}, ${end}`
      : `Weekly: ${formatWeekdays(recurrence.daysOfWeek, locale)}, every ${recurrence.interval}, starts ${start}, ${end}`;
  }

  return locale === 'ru'
    ? `Ежемесячно: день ${recurrence.dayOfMonth ?? '?'}, каждые ${recurrence.interval}, старт ${start}, ${end}`
    : `Monthly: day ${recurrence.dayOfMonth ?? '?'}, every ${recurrence.interval}, starts ${start}, ${end}`;
}
