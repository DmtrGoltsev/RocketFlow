export type FocusInterval = 'off' | '30m' | '1h' | '2h' | '4h';

export interface FocusItemDto {
  id: string;
  taskId: string;
  title: string;
  status: 'todo' | 'in_progress' | 'done' | 'cancelled';
  effort: number | null;
  effectiveWeight: number;
  position: number;
  path?: string | null;
  folderTitle?: string | null;
  goalTitle?: string | null;
  plannedTime?: string | null;
  dueTime?: string | null;
  historyOnly?: boolean;
  shared?: boolean;
}

export interface FocusProgressDto {
  completedWeight: number;
  totalWeight: number;
  percent: number;
}

export interface FocusRolloverOfferDto {
  sourcePeriodId: string;
  items: FocusItemDto[];
}

export interface FocusPeriodDto {
  id: string;
  weekStart: string;
  weekEndExclusive: string;
  timezone: string;
  status: 'active' | 'completed';
  version: number;
  items: FocusItemDto[];
  progress?: FocusProgressDto;
  rolloverOffer?: FocusRolloverOfferDto | null;
}

export interface FocusCandidateDto {
  taskId: string;
  title: string;
  status: 'todo' | 'in_progress' | 'done' | 'cancelled';
  effort: number | null;
  effectiveWeight: number;
  plannedTime?: string | null;
  dueTime?: string | null;
  folderId?: string | null;
  folderTitle?: string | null;
  goalId?: string | null;
  goalTitle?: string | null;
  shared?: boolean;
  canWrite?: boolean;
  inFocus: boolean;
}

export interface FocusCandidatesResponse {
  items: FocusCandidateDto[];
  nextCursor?: string | null;
}

export interface FocusHistoryResponse {
  items: Array<Omit<FocusPeriodDto, 'items' | 'rolloverOffer'> & { items?: FocusItemDto[] }>;
}

export interface FocusNotificationSettingsDto {
  interval: FocusInterval;
  quietHoursStart: string | null;
  quietHoursEnd: string | null;
  version: number;
}

export interface WebPushConfigDto {
  enabled: boolean;
  publicKey: string | null;
}

export interface WebPushSubscriptionDto {
  id: string;
}

export interface CreateWebPushSubscriptionPayload {
  endpoint: string;
  expirationTime: string | null;
  keys: Record<string, string> | undefined;
  installationId: string;
}
