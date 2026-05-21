export type TaskType = 'green' | 'red';
export type TaskStatus = 'todo' | 'in_progress' | 'done' | 'cancelled';
export type GoalStatus = 'todo' | 'in_progress' | 'done' | 'cancelled';
export type DayOfWeek = 'MONDAY' | 'TUESDAY' | 'WEDNESDAY' | 'THURSDAY' | 'FRIDAY' | 'SATURDAY' | 'SUNDAY';
export type TaskRecurrenceMode = 'daily' | 'weekly' | 'monthly';
export type TaskTimeAnchor = 'planned' | 'due';
export type LinkEntityType = 'goal' | 'task' | 'idea' | 'note';
export type EntityRelationType = 'related' | 'dependency';

export interface FolderDto {
  id: string;
  parentFolderId: string | null;
  ownerUserId?: string | null;
  name: string;
  description: string;
  displayOrder: number;
  archived: boolean;
  shared?: boolean;
  fullAccess?: boolean;
  canAccessFolderContent?: boolean;
  version: number;
  createdAt: string;
  updatedAt: string;
}

export interface GoalDto {
  id: string;
  folderId: string;
  ownerUserId?: string | null;
  name: string;
  description: string;
  status: GoalStatus;
  archived: boolean;
  shared: boolean;
  fullAccess?: boolean;
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
  ownerUserId?: string | null;
  title: string;
  description: string;
  type: TaskType;
  priority: number;
  status: TaskStatus;
  plannedTime: string | null;
  dueTime: string | null;
  archived: boolean;
  shared: boolean;
  fullAccess?: boolean;
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
  ownerUserId?: string | null;
  title: string;
  body: string;
  status: string;
  displayOrder: number;
  archived: boolean;
  allowAuthorNoteEdits: boolean;
  shared: boolean;
  fullAccess?: boolean;
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

export interface NoteDto {
  id: string;
  folderId: string;
  ownerUserId?: string | null;
  authorUserId: string | null;
  authorEmail: string | null;
  authorName: string | null;
  title: string;
  body: string;
  displayOrder: number;
  archived: boolean;
  shared: boolean;
  fullAccess?: boolean;
  version: number;
  createdAt: string;
  updatedAt: string;
}

export interface EntityRefDto {
  type: LinkEntityType | null;
  id: string | null;
  title: string | null;
  subtitle: string | null;
  status: string | null;
  path: string | null;
  archived: boolean | null;
  accessible?: boolean;
  redacted?: boolean;
}

export interface EntityLinkDto {
  id: string;
  source: EntityRefDto;
  target: EntityRefDto;
  relationType: EntityRelationType;
  createdByUserId: string | null;
  createdByName: string | null;
  createdAt: string;
  updatedAt: string;
  version: number;
}

export interface FolderUpsertPayload {
  name: string;
  description: string;
  parentFolderId?: string | null;
  displayOrder?: number;
  archived?: boolean;
  version?: number;
}

export interface GoalUpsertPayload {
  name: string;
  description: string;
  status?: GoalStatus;
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

export interface NoteUpsertPayload {
  title: string;
  body: string;
  displayOrder?: number;
  archived?: boolean;
  version?: number;
}

export interface EntityLinkCreatePayload {
  sourceType: LinkEntityType;
  sourceId: string;
  targetType: LinkEntityType;
  targetId: string;
  relationType: EntityRelationType;
}

export interface EntityLinkUpdatePayload {
  relationType: EntityRelationType;
  version: number;
}

export interface FolderMovePayload {
  targetFolderId: string | null;
  version: number;
}

export interface FolderClonePayload {
  targetFolderId: string | null;
  name?: string;
  includeChildren?: false;
}

export interface GoalMovePayload {
  targetFolderId: string;
  version: number;
}

export interface GoalClonePayload {
  targetFolderId: string;
  name?: string;
}

export interface TaskMoveToGoalPayload {
  targetGoalId: string;
  version: number;
}

export interface TaskClonePayload {
  targetGoalId: string;
  title?: string;
  includeTags?: false;
}

export interface IdeaMovePayload {
  targetFolderId: string;
  version: number;
}

export interface IdeaClonePayload {
  targetFolderId: string;
  title?: string;
}

export interface NoteMovePayload {
  targetFolderId: string;
  version: number;
}

export interface NoteClonePayload {
  targetFolderId: string;
  title?: string;
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
