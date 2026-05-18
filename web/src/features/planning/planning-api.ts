import type {
  FolderDto,
  FolderNoteDto,
  FolderNoteItemCreatePayload,
  FolderNoteItemDto,
  FolderNoteItemUpdatePayload,
  FolderNoteUpsertPayload,
  FolderUpsertPayload,
  GoalDto,
  GoalUpsertPayload,
  IdeaDto,
  IdeaNoteCreatePayload,
  IdeaNoteDto,
  IdeaNoteUpdatePayload,
  IdeaUpsertPayload,
  PlanningApiErrorPayload,
  TaskDto,
  TaskRecurrenceUpsertPayload,
  TaskUpsertPayload,
} from './types';

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? '/api';

type AuthorizedFetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

interface ListResponse<TItem> {
  items: TItem[];
}

export class PlanningApiError extends Error {
  status: number;
  payload: PlanningApiErrorPayload;

  constructor(status: number, payload: PlanningApiErrorPayload) {
    super(payload.message);
    this.name = 'PlanningApiError';
    this.status = status;
    this.payload = payload;
  }
}

function buildUrl(path: string) {
  return `${API_BASE_URL}${path}`;
}

async function parseError(response: Response): Promise<PlanningApiErrorPayload> {
  try {
    const body = (await response.json()) as { error?: Partial<PlanningApiErrorPayload> };

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

  if (!headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }

  const response = await authorizedFetch(buildUrl(path), {
    ...init,
    headers,
  });

  if (!response.ok) {
    throw new PlanningApiError(response.status, await parseError(response));
  }

  if (response.status === 204) {
    return undefined as TResponse;
  }

  return (await response.json()) as TResponse;
}

export async function listFolders(authorizedFetch: AuthorizedFetch) {
  const response = await requestJson<ListResponse<FolderDto>>(authorizedFetch, '/folders', {
    method: 'GET',
  });

  return response.items;
}

export async function createFolder(authorizedFetch: AuthorizedFetch, payload: FolderUpsertPayload) {
  return requestJson<FolderDto>(authorizedFetch, '/folders', {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function updateFolder(
  authorizedFetch: AuthorizedFetch,
  folderId: string,
  payload: FolderUpsertPayload,
) {
  return requestJson<FolderDto>(authorizedFetch, `/folders/${folderId}`, {
    method: 'PATCH',
    body: JSON.stringify(payload),
  });
}

export async function archiveFolder(authorizedFetch: AuthorizedFetch, folderId: string) {
  return requestJson<void>(authorizedFetch, `/folders/${folderId}`, {
    method: 'DELETE',
  });
}

export async function listGoals(authorizedFetch: AuthorizedFetch, folderId: string) {
  const response = await requestJson<ListResponse<GoalDto>>(authorizedFetch, `/folders/${folderId}/goals`, {
    method: 'GET',
  });

  return response.items;
}

export async function getGoal(authorizedFetch: AuthorizedFetch, goalId: string) {
  return requestJson<GoalDto>(authorizedFetch, `/goals/${goalId}`, {
    method: 'GET',
  });
}

export async function createGoal(
  authorizedFetch: AuthorizedFetch,
  folderId: string,
  payload: GoalUpsertPayload,
) {
  return requestJson<GoalDto>(authorizedFetch, `/folders/${folderId}/goals`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function updateGoal(
  authorizedFetch: AuthorizedFetch,
  goalId: string,
  payload: GoalUpsertPayload,
) {
  return requestJson<GoalDto>(authorizedFetch, `/goals/${goalId}`, {
    method: 'PATCH',
    body: JSON.stringify(payload),
  });
}

export async function archiveGoal(authorizedFetch: AuthorizedFetch, goalId: string) {
  return requestJson<void>(authorizedFetch, `/goals/${goalId}`, {
    method: 'DELETE',
  });
}

export async function listTasks(authorizedFetch: AuthorizedFetch, goalId: string) {
  const response = await requestJson<ListResponse<TaskDto>>(authorizedFetch, `/goals/${goalId}/tasks`, {
    method: 'GET',
  });

  return response.items;
}

export async function getTask(authorizedFetch: AuthorizedFetch, taskId: string) {
  return requestJson<TaskDto>(authorizedFetch, `/tasks/${taskId}`, {
    method: 'GET',
  });
}

export async function createTask(
  authorizedFetch: AuthorizedFetch,
  goalId: string,
  payload: TaskUpsertPayload,
) {
  return requestJson<TaskDto>(authorizedFetch, `/goals/${goalId}/tasks`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function updateTask(
  authorizedFetch: AuthorizedFetch,
  taskId: string,
  payload: TaskUpsertPayload,
) {
  return requestJson<TaskDto>(authorizedFetch, `/tasks/${taskId}`, {
    method: 'PATCH',
    body: JSON.stringify(payload),
  });
}

export async function deleteTask(authorizedFetch: AuthorizedFetch, taskId: string) {
  return requestJson<void>(authorizedFetch, `/tasks/${taskId}`, {
    method: 'DELETE',
  });
}

export async function listIdeas(authorizedFetch: AuthorizedFetch, folderId: string) {
  const response = await requestJson<ListResponse<IdeaDto>>(authorizedFetch, `/folders/${folderId}/ideas`, {
    method: 'GET',
  });

  return response.items;
}

export async function createIdea(
  authorizedFetch: AuthorizedFetch,
  folderId: string,
  payload: IdeaUpsertPayload,
) {
  return requestJson<IdeaDto>(authorizedFetch, `/folders/${folderId}/ideas`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function getIdea(authorizedFetch: AuthorizedFetch, ideaId: string) {
  return requestJson<IdeaDto>(authorizedFetch, `/ideas/${ideaId}`, {
    method: 'GET',
  });
}

export async function updateIdea(
  authorizedFetch: AuthorizedFetch,
  ideaId: string,
  payload: IdeaUpsertPayload,
) {
  return requestJson<IdeaDto>(authorizedFetch, `/ideas/${ideaId}`, {
    method: 'PATCH',
    body: JSON.stringify(payload),
  });
}

export async function deleteIdea(authorizedFetch: AuthorizedFetch, ideaId: string) {
  return requestJson<void>(authorizedFetch, `/ideas/${ideaId}`, {
    method: 'DELETE',
  });
}

export async function listIdeaNotes(authorizedFetch: AuthorizedFetch, ideaId: string) {
  const response = await requestJson<ListResponse<IdeaNoteDto>>(authorizedFetch, `/ideas/${ideaId}/notes`, {
    method: 'GET',
  });

  return response.items;
}

export async function createIdeaNote(
  authorizedFetch: AuthorizedFetch,
  ideaId: string,
  payload: IdeaNoteCreatePayload,
) {
  return requestJson<IdeaNoteDto>(authorizedFetch, `/ideas/${ideaId}/notes`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function updateIdeaNote(
  authorizedFetch: AuthorizedFetch,
  noteId: string,
  payload: IdeaNoteUpdatePayload,
) {
  return requestJson<IdeaNoteDto>(authorizedFetch, `/idea-notes/${noteId}`, {
    method: 'PATCH',
    body: JSON.stringify(payload),
  });
}

export async function listFolderNotes(authorizedFetch: AuthorizedFetch, folderId: string) {
  const response = await requestJson<ListResponse<FolderNoteDto>>(authorizedFetch, `/folders/${folderId}/notes`, {
    method: 'GET',
  });

  return response.items;
}

export async function createFolderNote(
  authorizedFetch: AuthorizedFetch,
  folderId: string,
  payload: FolderNoteUpsertPayload,
) {
  return requestJson<FolderNoteDto>(authorizedFetch, `/folders/${folderId}/notes`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function updateFolderNote(
  authorizedFetch: AuthorizedFetch,
  noteId: string,
  payload: FolderNoteUpsertPayload,
) {
  return requestJson<FolderNoteDto>(authorizedFetch, `/folder-notes/${noteId}`, {
    method: 'PATCH',
    body: JSON.stringify(payload),
  });
}

export async function deleteFolderNote(authorizedFetch: AuthorizedFetch, noteId: string) {
  return requestJson<void>(authorizedFetch, `/folder-notes/${noteId}`, {
    method: 'DELETE',
  });
}

export async function createFolderNoteItem(
  authorizedFetch: AuthorizedFetch,
  noteId: string,
  payload: FolderNoteItemCreatePayload,
) {
  return requestJson<FolderNoteItemDto>(authorizedFetch, `/folder-notes/${noteId}/items`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function updateFolderNoteItem(
  authorizedFetch: AuthorizedFetch,
  itemId: string,
  payload: FolderNoteItemUpdatePayload,
) {
  return requestJson<FolderNoteItemDto>(authorizedFetch, `/folder-note-items/${itemId}`, {
    method: 'PATCH',
    body: JSON.stringify(payload),
  });
}

export async function deleteFolderNoteItem(authorizedFetch: AuthorizedFetch, itemId: string) {
  return requestJson<void>(authorizedFetch, `/folder-note-items/${itemId}`, {
    method: 'DELETE',
  });
}

export async function upsertTaskRecurrence(
  authorizedFetch: AuthorizedFetch,
  taskId: string,
  payload: TaskRecurrenceUpsertPayload,
) {
  return requestJson<{ taskId: string; recurrence: TaskDto['recurrence'] }>(authorizedFetch, `/tasks/${taskId}/recurrence`, {
    method: 'PUT',
    body: JSON.stringify(payload),
  });
}
