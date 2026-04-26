import type { GoalDto, TaskDto } from '../planning/types';

export type CalendarPreset = 'day' | 'week' | 'month';
export type ShareTargetType = 'goal' | 'task';
export type InvitationStatus = 'pending' | 'accepted' | 'declined' | 'revoked';
export type ThresholdPreset = 'day' | 'week' | 'month';
export type Locale = 'ru' | 'en';

export interface CalendarItemDto {
  taskId: string;
  goalId: string;
  title: string;
  type: 'green' | 'red';
  priority: number;
  status: 'todo' | 'in_progress' | 'done' | 'cancelled';
  plannedTime: string;
  dueTime: string | null;
}

export interface CalendarResponse {
  items: CalendarItemDto[];
}

export interface MoveTaskPayload {
  plannedTime: string;
}

export interface MoveTaskResponse {
  id: string;
  plannedTime: string;
  priority: number;
  updatedAt: string;
}

export interface QuickReschedulePayload {
  preset?: '30m' | '1h' | '3h' | '24h';
  minutes?: number;
}

export interface QuickRescheduleResponse {
  task: {
    id: string;
    plannedTime: string;
    priority: number;
    updatedAt: string;
  };
  rescheduleEvent: {
    id: string;
    previousPlannedTime: string;
    newPlannedTime: string;
    createdAt: string;
  };
  priorityDecayApplied: boolean;
}

export interface ShareInvitationDto {
  id: string;
  targetType: ShareTargetType;
  targetId: string;
  targetEmail: string;
  status: InvitationStatus;
  createdAt: string;
  expiresAt: string;
}

export interface SharedResourcesResponse {
  goals: GoalDto[];
  tasks: TaskDto[];
}

export interface ShareInvitationListResponse {
  items: ShareInvitationDto[];
}

export interface ShareInvitationActionResponse {
  id: string;
  status: InvitationStatus;
}

export interface ShareRequestPayload {
  email: string;
}

export interface PriorityDecayPolicyDto {
  taskType: 'green' | 'red';
  enabled: boolean;
  thresholdPreset: ThresholdPreset;
  decayAmount: number;
}

export interface UserSettingsResponse {
  language: Locale;
  greenPriorityDecayPolicy: PriorityDecayPolicyDto;
  redPriorityDecayPolicy: PriorityDecayPolicyDto;
  notificationsEnabled: boolean;
  version: number;
}

export interface UpdatePriorityDecayPolicyRequest {
  enabled: boolean;
  thresholdPreset: ThresholdPreset;
  decayAmount: number;
}

export interface UpdateSettingsPayload {
  language: Locale;
  greenPriorityDecayPolicy: UpdatePriorityDecayPolicyRequest;
  redPriorityDecayPolicy: UpdatePriorityDecayPolicyRequest;
  notificationsEnabled: boolean;
  version: number;
}

export interface AdvancedApiErrorPayload {
  code: string;
  message: string;
  details: Array<{
    field?: string;
    message: string;
  }>;
  traceId?: string;
}

