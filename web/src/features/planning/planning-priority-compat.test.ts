import { describe, expect, it, vi } from 'vitest';

import tasksRouteSource from './routes/TasksRoute.tsx?raw';
import planningCopySource from './planning-copy.ts?raw';
import advancedCopySource from '../advanced/advanced-copy.ts?raw';
import {
  DEFAULT_TASK_PRIORITY,
  normalizeTaskResponse,
  sortTasksForPlan,
  toTaskEditorDraft,
  toTaskUpsertPayload,
} from './planning-utils';
import { createTask, listTasks, updateTask } from './planning-api';
import type { TaskApiDto, TaskDto } from './types';

const taskDraft = {
  title: '  Ship it  ',
  description: '  Notes  ',
  type: 'green' as const,
  status: 'todo' as const,
  effort: '3',
  plannedTime: '',
  dueTime: '',
  recurrence: {
    enabled: false,
    active: true,
    mode: 'weekly' as const,
    interval: '1',
    anchor: 'planned' as const,
    daysOfWeek: [],
    endAt: '',
  },
};

function task(overrides: Partial<TaskApiDto> = {}): TaskApiDto {
  return {
    id: 'task-1',
    goalId: 'goal-1',
    title: 'Task',
    description: '',
    type: 'green',
    effort: 0,
    status: 'todo',
    plannedTime: null,
    dueTime: null,
    archived: false,
    shared: false,
    creatorUserId: null,
    creatorEmail: null,
    creatorName: null,
    version: 1,
    tags: [],
    recurrence: null,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    ...overrides,
  };
}

describe('task priority compatibility shadow', () => {
  it('keeps priority out of editor state, controls, validation, copy, and sorting names', () => {
    expect(toTaskEditorDraft(normalizeTaskResponse(task()))).not.toHaveProperty('priority');
    expect(tasksRouteSource).not.toMatch(/draft\.priority|priorityLabel|copy\.priority|sortTasksByPriority/);
    expect(planningCopySource).not.toMatch(/priorityLabel|validationPriorityRange|Приоритет|Priority/);
    expect(advancedCopySource).not.toMatch(/Приоритет|Priority|greenPolicy|redPolicy/);
  });

  it('sends 5 for V20 creates and retains fetched priority for V20 updates', () => {
    expect(toTaskUpsertPayload(taskDraft)).toMatchObject({ priority: DEFAULT_TASK_PRIORITY });
    expect(toTaskUpsertPayload(taskDraft, task({ priority: 8 }))).toMatchObject({ priority: 8 });
    expect(toTaskUpsertPayload(taskDraft, task())).toMatchObject({ priority: DEFAULT_TASK_PRIORITY });
  });

  it('normalizes V21 responses without priority to 5', () => {
    expect(normalizeTaskResponse(task()).priority).toBe(DEFAULT_TASK_PRIORITY);
    expect(normalizeTaskResponse(task({ priority: 7 })).priority).toBe(7);
  });

  it('sorts by due time, creation time, then id without consulting priority', () => {
    const tasks = [
      normalizeTaskResponse(task({ id: 'c', priority: 10, dueTime: null, createdAt: '2026-01-02T00:00:00Z' })),
      normalizeTaskResponse(task({ id: 'b', priority: 1, dueTime: '2026-01-01T12:00:00Z', createdAt: '2026-01-01T00:00:00Z' })),
      normalizeTaskResponse(task({ id: 'a', priority: 9, dueTime: '2026-01-01T12:00:00Z', createdAt: '2026-01-01T00:00:00Z' })),
    ];

    expect(sortTasksForPlan(tasks).map((item) => item.id)).toEqual(['a', 'b', 'c']);
  });

  it('normalizes list/create/update responses and forwards compatibility payloads', async () => {
    const fetcher = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      if (init?.method === 'GET') {
        return Response.json({ items: [task()] });
      }
      return Response.json(task());
    });

    await expect(listTasks(fetcher, 'goal-1')).resolves.toMatchObject([{ priority: DEFAULT_TASK_PRIORITY }]);
    const createPayload = toTaskUpsertPayload(taskDraft);
    await expect(createTask(fetcher, 'goal-1', createPayload)).resolves.toMatchObject({ priority: DEFAULT_TASK_PRIORITY });
    const updatePayload = toTaskUpsertPayload(taskDraft, task({ priority: 9 }));
    await expect(updateTask(fetcher, 'task-1', updatePayload)).resolves.toMatchObject({ priority: DEFAULT_TASK_PRIORITY });

    const requestBodies = fetcher.mock.calls
      .map(([, init]) => init?.body)
      .filter(Boolean)
      .map((body) => JSON.parse(String(body)) as TaskDto);
    expect(requestBodies.map((body) => body.priority)).toEqual([5, 9]);
  });
});
