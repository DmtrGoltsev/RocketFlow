import { describe, expect, it } from 'vitest';

import {
  buildMonthCells,
  calendarGridRange,
  groupAgendaMarkers,
  groupCalendarMarkers,
  isLatestCalendarRequest,
  localDateInTimeZone,
  todayInTimeZone,
} from './CalendarRoute';
import type { CalendarMarkerDto } from '../types';

function marker(kind: CalendarMarkerDto['kind']): CalendarMarkerDto {
  return {
    markerId: kind, occurrenceId: 'occurrence', taskId: 'task', kind, at: '2026-08-09T10:00:00Z',
    localDate: '2026-08-09', title: 'Task', status: 'todo',
  };
}

describe('calendar model', () => {
  it('builds a stable six-week Monday-first grid', () => {
    const cells = buildMonthCells('2026-08-01');
    expect(cells).toHaveLength(42);
    expect(cells[0].date).toBe('2026-07-27');
    expect(cells[41].date).toBe('2026-09-06');
    expect(calendarGridRange(cells)).toEqual({ from: '2026-07-27', toExclusive: '2026-09-07' });
  });

  it('derives today and marker dates in the account timezone, not the runtime timezone', () => {
    const instant = new Date('2026-08-09T23:30:00Z');
    expect(todayInTimeZone('Europe/Moscow', instant)).toBe('2026-08-10');
    expect(todayInTimeZone('America/Los_Angeles', instant)).toBe('2026-08-09');
    expect(localDateInTimeZone(instant.toISOString(), 'Europe/Moscow')).toBe('2026-08-10');
  });

  it('keeps planned and deadline markers on the same day', () => {
    const grouped = groupCalendarMarkers([marker('planned'), marker('deadline')]);
    expect(grouped['2026-08-09'].map((item) => item.kind)).toEqual(['planned', 'deadline']);
    expect(groupAgendaMarkers(grouped['2026-08-09'])).toHaveLength(1);
  });

  it('rejects a stale month response after a newer grid request starts', () => {
    expect(isLatestCalendarRequest(7, 8)).toBe(false);
    expect(isLatestCalendarRequest(8, 8)).toBe(true);
  });
});
