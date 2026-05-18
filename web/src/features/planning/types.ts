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

export interface IdeaDto {
  id: string;
  folderId: string;
  title: string;
  body: string;
  status: string;
  displayOrder: number;
  archived: boolean;
  allowAuthorNoteEdits: boolean;
  shared: boolean;
  creatorUserId: string | null;
  creatorEmail: string | null;
  creatorName: string | null;
  version: number;
  createdAt: string;
  updatedAt: string;
}

export interface IdeaNoteDto {
  id: string;
  ideaId: string;
  eventType: string;
  authorUserId: string | null;
  authorEmail: string | null;
  authorName: string | null;
  body: string;
  metadata: Record<string, unknown>;
  version: number;
  createdAt: string;
  updatedAt: string;
}

export type FolderNoteKind = 'note' | 'list';

export interface FolderNoteItemDto {
  id: string;
  folderNoteId: string;
  text: string;
  checked: boolean;
  displayOrder: number;
  version: number;
  createdAt: string;
  updatedAt: string;
}

export interface FolderNoteDto {
  id: string;
  folderId: string;
  kind: FolderNoteKind;
  title: string;
  body: string;
  displayOrder: number;
  archived: boolean;
  shared: boolean;
  authorUserId: string | null;
  authorEmail: string | null;
  authorName: string | null;
  version: number;
  items: FolderNoteItemDto[];
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

export interface IdeaUpsertPayload {
  title: string;
  body: string;
  status?: string;
  displayOrder?: number;
  archived?: boolean;
  allowAuthorNoteEdits?: boolean;
  version?: number;
}

export interface IdeaNoteCreatePayload {
  eventType: string;
  body: string;
  metadata?: Record<string, unknown>;
}

export interface IdeaNoteUpdatePayload {
  eventType: string;
  body: string;
  metadata?: Record<string, unknown>;
  version: number;
}

export interface FolderNoteUpsertPayload {
  title: string;
  body: string;
  kind?: FolderNoteKind;
  displayOrder?: number;
  archived?: boolean;
  version?: number;
}

export interface FolderNoteItemCreatePayload {
  text: string;
  checked?: boolean;
}

export interface FolderNoteItemUpdatePayload {
  text: string;
  checked: boolean;
  displayOrder: number;
  version: number;
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
