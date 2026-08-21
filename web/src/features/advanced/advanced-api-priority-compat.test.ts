import { describe, expect, it, vi } from 'vitest';

import { getCalendar, moveTask, quickRescheduleTask } from './advanced-api';

describe('advanced task response compatibility', () => {
  it('falls back to priority 5 when V21 calendar responses omit the shadow field', async () => {
    const fetcher = vi.fn()
      .mockResolvedValueOnce(Response.json({
        timezone: 'UTC',
        from: '2026-08-01T00:00:00Z',
        toExclusive: '2026-09-01T00:00:00Z',
        markers: [],
        items: [{ id: 'unused', title: 'Task' }],
      }))
      .mockResolvedValueOnce(Response.json({ id: 'task-1', plannedTime: '2026-08-02T00:00:00Z', updatedAt: '2026-08-01T00:00:00Z' }))
      .mockResolvedValueOnce(Response.json({
        task: { id: 'task-1', plannedTime: '2026-08-03T00:00:00Z', updatedAt: '2026-08-01T00:00:00Z' },
        rescheduleEvent: {},
        priorityDecayApplied: false,
      }));

    await expect(getCalendar(fetcher, '2026-08-01T00:00:00Z', '2026-09-01T00:00:00Z'))
      .resolves.toMatchObject({ items: [{ priority: 5 }] });
    await expect(moveTask(fetcher, 'task-1', { plannedTime: '2026-08-02T00:00:00Z' }))
      .resolves.toMatchObject({ priority: 5 });
    await expect(quickRescheduleTask(fetcher, 'task-1', { preset: '24h' }))
      .resolves.toMatchObject({ task: { priority: 5 } });
  });
});
