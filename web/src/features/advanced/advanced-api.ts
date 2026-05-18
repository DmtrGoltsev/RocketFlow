import type {
  AdvancedApiErrorPayload,
  CalendarResponse,
  MoveTaskPayload,
  MoveTaskResponse,
  QuickReschedulePayload,
  QuickRescheduleResponse,
  ShareInvitationActionResponse,
  ShareInvitationDto,
  ShareInvitationListResponse,
  ShareLinkAcceptResponse,
  ShareLinkResolveResponse,
  ShareRequestPayload,
  SharedResourcesResponse,
  UpdateSettingsPayload,
  UserSettingsResponse,
} from './types';

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? '/rocket-api';

type AuthorizedFetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export class AdvancedApiError extends Error {
  status: number;
  payload: AdvancedApiErrorPayload;

  constructor(status: number, payload: AdvancedApiErrorPayload) {
    super(payload.message);
    this.name = 'AdvancedApiError';
    this.status = status;
    this.payload = payload;
  }
}

function buildUrl(path: string) {
  return `${API_BASE_URL}${path}`;
}

async function parseError(response: Response): Promise<AdvancedApiErrorPayload> {
  try {
    const body = (await response.json()) as { error?: Partial<AdvancedApiErrorPayload> };

    if (body.error?.code && body.error.message) {
      return {
        code: body.error.code,
        message: body.error.message,
        details: body.error.details ?? [],
      };
    }
  } catch {
    return {
      code: 'internal_error',
      message: 'Request failed.',
      details: [],
    };
  }

  return {
    code: 'internal_error',
    message: 'Request failed.',
    details: [],
  };
}

async function requestJson<TResponse>(
  authorizedFetch: AuthorizedFetch,
  path: string,
  init: RequestInit,
): Promise<TResponse> {
  const headers = new Headers(init.headers);

  if (init.body && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }

  const response = await authorizedFetch(buildUrl(path), {
    ...init,
    headers,
  });

  if (!response.ok) {
    throw new AdvancedApiError(response.status, await parseError(response));
  }

  if (response.status === 204) {
    return undefined as TResponse;
  }

  return (await response.json()) as TResponse;
}

export async function getCalendar(
  authorizedFetch: AuthorizedFetch,
  from: string,
  to: string,
) {
  const params = new URLSearchParams({ from, to });
  return requestJson<CalendarResponse>(authorizedFetch, `/calendar?${params.toString()}`, {
    method: 'GET',
  });
}

export async function moveTask(
  authorizedFetch: AuthorizedFetch,
  taskId: string,
  payload: MoveTaskPayload,
) {
  return requestJson<MoveTaskResponse>(authorizedFetch, `/tasks/${taskId}/move`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function quickRescheduleTask(
  authorizedFetch: AuthorizedFetch,
  taskId: string,
  payload: QuickReschedulePayload,
) {
  return requestJson<QuickRescheduleResponse>(authorizedFetch, `/tasks/${taskId}/reschedule`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function getInvitations(authorizedFetch: AuthorizedFetch) {
  return requestJson<ShareInvitationListResponse>(authorizedFetch, '/shares/invitations', {
    method: 'GET',
  });
}

export async function createFolderInvitation(
  authorizedFetch: AuthorizedFetch,
  folderId: string,
  payload: ShareRequestPayload,
) {
  return requestJson<ShareInvitationDto>(authorizedFetch, `/folders/${folderId}/share`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function createGoalInvitation(
  authorizedFetch: AuthorizedFetch,
  goalId: string,
  payload: ShareRequestPayload,
) {
  return requestJson<ShareInvitationDto>(authorizedFetch, `/goals/${goalId}/share`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function createTaskInvitation(
  authorizedFetch: AuthorizedFetch,
  taskId: string,
  payload: ShareRequestPayload,
) {
  return requestJson<ShareInvitationDto>(authorizedFetch, `/tasks/${taskId}/share`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function acceptInvitation(authorizedFetch: AuthorizedFetch, invitationId: string) {
  return requestJson<ShareInvitationActionResponse>(
    authorizedFetch,
    `/shares/invitations/${invitationId}/accept`,
    { method: 'POST' },
  );
}

export async function declineInvitation(authorizedFetch: AuthorizedFetch, invitationId: string) {
  return requestJson<ShareInvitationActionResponse>(
    authorizedFetch,
    `/shares/invitations/${invitationId}/decline`,
    { method: 'POST' },
  );
}

export async function revokeInvitation(authorizedFetch: AuthorizedFetch, invitationId: string) {
  return requestJson<ShareInvitationActionResponse>(
    authorizedFetch,
    `/shares/invitations/${invitationId}/revoke`,
    { method: 'POST' },
  );
}

export async function resolveShareLink(authorizedFetch: AuthorizedFetch, token: string) {
  return requestJson<ShareLinkResolveResponse>(
    authorizedFetch,
    `/shares/links/${encodeURIComponent(token)}`,
    { method: 'GET' },
  );
}

export async function acceptShareLink(authorizedFetch: AuthorizedFetch, token: string) {
  return requestJson<ShareLinkAcceptResponse>(
    authorizedFetch,
    `/shares/links/${encodeURIComponent(token)}/accept`,
    { method: 'POST' },
  );
}

export async function getSharedResources(authorizedFetch: AuthorizedFetch) {
  return requestJson<SharedResourcesResponse>(authorizedFetch, '/shares/resources', {
    method: 'GET',
  });
}

export async function getSettings(authorizedFetch: AuthorizedFetch) {
  return requestJson<UserSettingsResponse>(authorizedFetch, '/me/settings', {
    method: 'GET',
  });
}

export async function updateSettings(
  authorizedFetch: AuthorizedFetch,
  payload: UpdateSettingsPayload,
) {
  return requestJson<UserSettingsResponse>(authorizedFetch, '/me/settings', {
    method: 'PATCH',
    body: JSON.stringify(payload),
  });
}
