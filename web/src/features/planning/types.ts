export type TaskType = 'green' | 'red';
export type TaskStatus = 'todo' | 'in_progress' | 'done' | 'cancelled';
export type DayOfWeek = 'MONDAY' | 'TUESDAY' | 'WEDNESDAY' | 'THURSDAY' | 'FRIDAY' | 'SATURDAY' | 'SUNDAY';
export type TaskRecurrenceMode = 'daily' | 'weekly' | 'monthly';
export type TaskTimeAnchor = 'planned' | 'due';

export interface FolderDto {
  id: string;
  name: string;
  description: string;
  displayOrder: number;
  archived: boolean;
  version: number;
  createdAt: string;
  updatedAt: string;
}

export interface GoalDto {
  id: string;
  folderId: string;
  name: string;
  description: string;
  archived: boolean;
  shared: boolean;
  version: number;
  createdAt: string;
  updatedAt: string;
}

export interface TaskTagDto {
  id: string;
  name: string;
  color: string;
}

export interface TaskRecurrenceDto {
  mode: TaskRecurrenceMode;
  interval: number;
  daysOfWeek: DayOfWeek[];
  dayOfMonth: number | null;
  startAt: string;
  endAt: string | null;
  active: boolean;
}

export interface TaskDto {
  id: string;
  goalId: string;
  title: string;
  description: string;
  type: TaskType;
  priority: number;
  status: TaskStatus;
  plannedTime: string | null;
  dueTime: string | null;
  archived: boolean;
  shared: boolean;
  creatorUserId: string | null;
  creatorEmail: string | null;
  creatorName: string | null;
  version: number;
  tags: TaskTagDto[];
  recurrence: TaskRecurrenceDto | null;
  createdAt: string;
  updatedAt: string;
}

export interface FolderUpsertPayload {
  name: string;
  description: string;
  displayOrder?: number;
  archived?: boolean;
  version?: number;
}

export interface GoalUpsertPayload {
  name: string;
  description: string;
  archived?: boolean;
  version?: number;
}

export interface TaskUpsertPayload {
  title: string;
  description: string;
  type: TaskType;
  priority: number;
  status: TaskStatus;
  plannedTime: string | null;
  dueTime: string | null;
  archived?: boolean;
  version?: number;
}

export interface TaskRecurrenceUpsertPayload {
  mode: TaskRecurrenceMode;
  interval: number;
  daysOfWeek: DayOfWeek[];
  dayOfMonth: number | null;
  startAt: string;
  endAt: string | null;
  active: boolean;
}

export interface TaskRecurrenceDraft {
  enabled: boolean;
  active: boolean;
  mode: TaskRecurrenceMode;
  interval: string;
  anchor: TaskTimeAnchor;
  daysOfWeek: DayOfWeek[];
  endAt: string;
}

export interface ApiErrorDetail {
  field?: string;
  message: string;
}

export interface PlanningApiErrorPayload {
  code: string;
  message: string;
  details: ApiErrorDetail[];
}
