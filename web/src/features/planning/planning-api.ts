import type {
  EntityLinkCreatePayload,
  EntityLinkDto,
  EntityLinkUpdatePayload,
  FolderClonePayload,
  FolderDto,
  FolderMovePayload,
  FolderUpsertPayload,
  GoalClonePayload,
  GoalDto,
  GoalMovePayload,
  GoalUpsertPayload,
  IdeaClonePayload,
  IdeaDto,
  IdeaMovePayload,
  IdeaNoteCreatePayload,
  IdeaNoteDto,
  IdeaNoteUpdatePayload,
  IdeaUpsertPayload,
  LinkEntityType,
  NoteClonePayload,
  NoteDto,
  NoteMovePayload,
  NoteUpsertPayload,
  PlanningApiErrorPayload,
  TaskClonePayload,
  TaskDto,
  TaskMoveToGoalPayload,
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

  if (init.body && !headers.has('Content-Type')) {
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

export async function createChildFolder(
  authorizedFetch: AuthorizedFetch,
  folderId: string,
  payload: FolderUpsertPayload,
) {
  return requestJson<FolderDto>(authorizedFetch, `/folders/${folderId}/folders`, {
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

export async function moveFolder(
  authorizedFetch: AuthorizedFetch,
  folderId: string,
  payload: FolderMovePayload,
) {
  return requestJson<FolderDto>(authorizedFetch, `/folders/${folderId}/move`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function cloneFolder(
  authorizedFetch: AuthorizedFetch,
  folderId: string,
  payload: FolderClonePayload,
) {
  return requestJson<FolderDto>(authorizedFetch, `/folders/${folderId}/clone`, {
    method: 'POST',
    body: JSON.stringify(payload),
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

export async function moveGoal(
  authorizedFetch: AuthorizedFetch,
  goalId: string,
  payload: GoalMovePayload,
) {
  return requestJson<GoalDto>(authorizedFetch, `/goals/${goalId}/move`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function cloneGoal(
  authorizedFetch: AuthorizedFetch,
  goalId: string,
  payload: GoalClonePayload,
) {
  return requestJson<GoalDto>(authorizedFetch, `/goals/${goalId}/clone`, {
    method: 'POST',
    body: JSON.stringify(payload),
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

export async function moveTaskToGoal(
  authorizedFetch: AuthorizedFetch,
  taskId: string,
  payload: TaskMoveToGoalPayload,
) {
  return requestJson<TaskDto>(authorizedFetch, `/tasks/${taskId}/move-to-goal`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function cloneTask(
  authorizedFetch: AuthorizedFetch,
  taskId: string,
  payload: TaskClonePayload,
) {
  return requestJson<TaskDto>(authorizedFetch, `/tasks/${taskId}/clone`, {
    method: 'POST',
    body: JSON.stringify(payload),
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

export async function moveIdea(
  authorizedFetch: AuthorizedFetch,
  ideaId: string,
  payload: IdeaMovePayload,
) {
  return requestJson<IdeaDto>(authorizedFetch, `/ideas/${ideaId}/move`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function cloneIdea(
  authorizedFetch: AuthorizedFetch,
  ideaId: string,
  payload: IdeaClonePayload,
) {
  return requestJson<IdeaDto>(authorizedFetch, `/ideas/${ideaId}/clone`, {
    method: 'POST',
    body: JSON.stringify(payload),
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

export async function listNotes(authorizedFetch: AuthorizedFetch, folderId: string) {
  const response = await requestJson<ListResponse<NoteDto>>(authorizedFetch, `/folders/${folderId}/notes`, {
    method: 'GET',
  });

  return response.items;
}

export async function createNote(
  authorizedFetch: AuthorizedFetch,
  folderId: string,
  payload: NoteUpsertPayload,
) {
  return requestJson<NoteDto>(authorizedFetch, `/folders/${folderId}/notes`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function getNote(authorizedFetch: AuthorizedFetch, noteId: string) {
  return requestJson<NoteDto>(authorizedFetch, `/notes/${noteId}`, {
    method: 'GET',
  });
}

export async function updateNote(
  authorizedFetch: AuthorizedFetch,
  noteId: string,
  payload: NoteUpsertPayload,
) {
  return requestJson<NoteDto>(authorizedFetch, `/notes/${noteId}`, {
    method: 'PATCH',
    body: JSON.stringify(payload),
  });
}

export async function deleteNote(authorizedFetch: AuthorizedFetch, noteId: string) {
  return requestJson<void>(authorizedFetch, `/notes/${noteId}`, {
    method: 'DELETE',
  });
}

export async function moveNote(
  authorizedFetch: AuthorizedFetch,
  noteId: string,
  payload: NoteMovePayload,
) {
  return requestJson<NoteDto>(authorizedFetch, `/notes/${noteId}/move`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function cloneNote(
  authorizedFetch: AuthorizedFetch,
  noteId: string,
  payload: NoteClonePayload,
) {
  return requestJson<NoteDto>(authorizedFetch, `/notes/${noteId}/clone`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function listEntityLinks(
  authorizedFetch: AuthorizedFetch,
  entityType: LinkEntityType,
  entityId: string,
) {
  const params = new URLSearchParams({ entityType, entityId });
  const response = await requestJson<ListResponse<EntityLinkDto>>(authorizedFetch, `/entity-links?${params.toString()}`, {
    method: 'GET',
  });

  return response.items;
}

export async function createEntityLink(
  authorizedFetch: AuthorizedFetch,
  payload: EntityLinkCreatePayload,
) {
  return requestJson<EntityLinkDto>(authorizedFetch, '/entity-links', {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function updateEntityLink(
  authorizedFetch: AuthorizedFetch,
  linkId: string,
  payload: EntityLinkUpdatePayload,
) {
  return requestJson<EntityLinkDto>(authorizedFetch, `/entity-links/${linkId}`, {
    method: 'PATCH',
    body: JSON.stringify(payload),
  });
}

export async function deleteEntityLink(authorizedFetch: AuthorizedFetch, linkId: string) {
  return requestJson<void>(authorizedFetch, `/entity-links/${linkId}`, {
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
