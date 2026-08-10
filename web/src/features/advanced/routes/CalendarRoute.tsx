import { CalendarDays, ChevronLeft, ChevronRight, RefreshCw } from 'lucide-react';
import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';

import { useAuth } from '../../auth';
import { taskDetailPath } from '../../focus/focus-utils';
import { useI18n } from '../../../i18n';
import { getCalendar } from '../advanced-api';
import type { CalendarMarkerDto, CalendarResponse } from '../types';

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

function isoDateUtc(date: Date) {
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}-${String(date.getUTCDate()).padStart(2, '0')}`;
}

function dateFromIso(value: string) {
  const [year, month, day] = value.split('-').map(Number);
  return new Date(Date.UTC(year, month - 1, day));
}

function addDays(value: string, days: number) {
  const date = dateFromIso(value);
  date.setUTCDate(date.getUTCDate() + days);
  return isoDateUtc(date);
}

function zonedParts(date: Date, timeZone: string) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    calendar: 'gregory',
    numberingSystem: 'latn',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
  }).formatToParts(date);
  const value = (type: string) => Number(parts.find((part) => part.type === type)?.value ?? 0);
  return { year: value('year'), month: value('month'), day: value('day'), hour: value('hour'), minute: value('minute'), second: value('second') };
}

function instantForLocalNoon(value: string, timeZone: string) {
  const [year, month, day] = value.split('-').map(Number);
  const desired = Date.UTC(year, month - 1, day, 12);
  let instant = desired;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const observed = zonedParts(new Date(instant), timeZone);
    instant += desired - Date.UTC(observed.year, observed.month - 1, observed.day, observed.hour, observed.minute, observed.second);
  }
  return new Date(instant);
}

export function todayInTimeZone(timeZone: string, now = new Date()) {
  const parts = zonedParts(now, timeZone);
  return `${parts.year}-${String(parts.month).padStart(2, '0')}-${String(parts.day).padStart(2, '0')}`;
}

export function shiftCalendarMonth(anchor: string, delta: number) {
  const date = dateFromIso(anchor);
  date.setUTCMonth(date.getUTCMonth() + delta, 1);
  return isoDateUtc(date);
}

export function buildMonthCells(anchor: string) {
  const anchorDate = dateFromIso(anchor);
  const year = anchorDate.getUTCFullYear();
  const month = anchorDate.getUTCMonth();
  const firstMondayOffset = (new Date(Date.UTC(year, month, 1)).getUTCDay() + 6) % 7;
  const gridStart = new Date(Date.UTC(year, month, 1 - firstMondayOffset));

  return Array.from({ length: 42 }, (_, index) => {
    const date = new Date(gridStart);
    date.setUTCDate(gridStart.getUTCDate() + index);
    return { date: isoDateUtc(date), inMonth: date.getUTCMonth() === month };
  });
}

export function calendarGridRange(cells: ReturnType<typeof buildMonthCells>) {
  return { from: cells[0].date, toExclusive: addDays(cells[cells.length - 1].date, 1) };
}

export function localDateInTimeZone(value: string, timeZone: string) {
  return todayInTimeZone(timeZone, new Date(value));
}

export function groupCalendarMarkers(markers: CalendarMarkerDto[]) {
  return markers.reduce<Record<string, CalendarMarkerDto[]>>((groups, marker) => {
    if (!groups[marker.localDate]) groups[marker.localDate] = [];
    groups[marker.localDate].push(marker);
    return groups;
  }, {});
}

export function groupAgendaMarkers(markers: CalendarMarkerDto[]) {
  const entries = new Map<string, CalendarMarkerDto[]>();
  markers.forEach((marker) => {
    const key = `${marker.occurrenceId}:${marker.taskId}`;
    entries.set(key, [...(entries.get(key) ?? []), marker]);
  });
  return [...entries.values()];
}

export function isLatestCalendarRequest(requestId: number, currentRequestId: number) {
  return requestId === currentRequestId;
}

function legacyMarkers(response: CalendarResponse, timeZone: string): CalendarMarkerDto[] {
  if (response.markers) return response.markers;
  return (response.items ?? []).flatMap((item) => {
    const markers: CalendarMarkerDto[] = [{
      markerId: `${item.taskId}:planned`, occurrenceId: item.taskId, taskId: item.taskId, goalId: item.goalId,
      kind: 'planned', at: item.plannedTime, localDate: localDateInTimeZone(item.plannedTime, timeZone), title: item.title,
      status: item.status, recurring: false,
    }];
    if (item.dueTime) markers.push({
      markerId: `${item.taskId}:deadline`, occurrenceId: item.taskId, taskId: item.taskId, goalId: item.goalId,
      kind: 'deadline', at: item.dueTime, localDate: localDateInTimeZone(item.dueTime, timeZone), title: item.title,
      status: item.status, recurring: false,
    });
    return markers;
  });
}

export function CalendarRoute() {
  const { authorizedFetch, session } = useAuth();
  const { locale } = useI18n();
  const navigate = useNavigate();
  const initialTimeZone = session?.user.timezone || Intl.DateTimeFormat().resolvedOptions().timeZone;
  const initialToday = todayInTimeZone(initialTimeZone);
  const [timeZone, setTimeZone] = useState(initialTimeZone);
  const [anchor, setAnchor] = useState(() => `${initialToday.slice(0, 7)}-01`);
  const [selectedDate, setSelectedDate] = useState(initialToday);
  const [response, setResponse] = useState<CalendarResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const calendarRequestRef = useRef(0);
  const calendarAbortRef = useRef<AbortController | null>(null);
  const cells = useMemo(() => buildMonthCells(anchor), [anchor]);
  const range = useMemo(() => calendarGridRange(cells), [cells]);
  const markers = useMemo(
    () => legacyMarkers(response ?? { timezone: timeZone, from: range.from, toExclusive: range.toExclusive, markers: [] }, timeZone),
    [response, timeZone, range.from, range.toExclusive],
  );
  const grouped = useMemo(() => groupCalendarMarkers(markers), [markers]);
  const selected = grouped[selectedDate] ?? [];
  const agenda = useMemo(() => groupAgendaMarkers(selected), [selected]);
  const words = locale === 'ru' ? {
    title: 'Календарь', subtitle: 'Плановые даты и дедлайны задач', today: 'Сегодня', refresh: 'Обновить',
    planned: 'Плановая дата', deadline: 'Дедлайн', empty: 'На этот день задач нет', loading: 'Загрузка календаря...',
    error: 'Не удалось загрузить календарь.', weekdays: ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'],
  } : {
    title: 'Calendar', subtitle: 'Task dates and deadlines', today: 'Today', refresh: 'Refresh', planned: 'Planned',
    deadline: 'Deadline', empty: 'No tasks on this day', loading: 'Loading calendar...', error: 'Could not load calendar.',
    weekdays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
  };

  async function load() {
    const requestId = ++calendarRequestRef.current;
    calendarAbortRef.current?.abort();
    const controller = new AbortController();
    calendarAbortRef.current = controller;
    setLoading(true);
    setError(null);
    try {
      const nextResponse = await getCalendar(authorizedFetch, range.from, range.toExclusive, controller.signal);
      if (!isLatestCalendarRequest(requestId, calendarRequestRef.current)) return;
      setResponse(nextResponse);
      if (nextResponse.timezone) setTimeZone(nextResponse.timezone);
    } catch (loadError) {
      if (controller.signal.aborted || !isLatestCalendarRequest(requestId, calendarRequestRef.current)) return;
      setError(loadError instanceof Error ? loadError.message : words.error);
    } finally {
      if (isLatestCalendarRequest(requestId, calendarRequestRef.current)) {
        setLoading(false);
        if (calendarAbortRef.current === controller) calendarAbortRef.current = null;
      }
    }
  }

  useEffect(() => {
    void load();
    return () => {
      calendarRequestRef.current += 1;
      calendarAbortRef.current?.abort();
      calendarAbortRef.current = null;
    };
  }, [range.from, range.toExclusive]);

  function shiftMonth(delta: number) {
    const next = shiftCalendarMonth(anchor, delta);
    setAnchor(next);
    setSelectedDate(next);
  }

  function goToday() {
    const today = todayInTimeZone(timeZone);
    setAnchor(`${today.slice(0, 7)}-01`);
    setSelectedDate(today);
  }

  const localeName = locale === 'ru' ? 'ru-RU' : 'en-US';
  const monthLabel = new Intl.DateTimeFormat(localeName, { month: 'long', year: 'numeric', timeZone })
    .format(instantForLocalNoon(anchor, timeZone));
  const selectedLabel = ISO_DATE.test(selectedDate)
    ? new Intl.DateTimeFormat(localeName, { weekday: 'long', day: 'numeric', month: 'long', timeZone })
      .format(instantForLocalNoon(selectedDate, timeZone))
    : selectedDate;

  return <section className="calendar-page">
    <header className="calendar-header"><div><h1>{words.title}</h1><p>{words.subtitle}</p></div><button className="icon-button" type="button" title={words.refresh} aria-label={words.refresh} onClick={() => void load()}><RefreshCw size={18} /></button></header>
    <div className="calendar-toolbar"><button className="icon-button" type="button" aria-label="Previous month" onClick={() => shiftMonth(-1)}><ChevronLeft size={19} /></button><h2>{monthLabel}</h2><button className="icon-button" type="button" aria-label="Next month" onClick={() => shiftMonth(1)}><ChevronRight size={19} /></button><button className="button button--ghost" type="button" onClick={goToday}>{words.today}</button></div>
    {error ? <div className="focus-error" role="alert">{error}<button type="button" onClick={() => void load()}>{words.refresh}</button></div> : null}
    <div className="calendar-grid" aria-busy={loading}>
      {words.weekdays.map((day) => <div className="calendar-grid__weekday" key={day}>{day}</div>)}
      {cells.map((cell) => {
        const dayMarkers = grouped[cell.date] ?? [];
        const hasPlanned = dayMarkers.some((marker) => marker.kind === 'planned');
        const hasDeadline = dayMarkers.some((marker) => marker.kind === 'deadline');
        return <button type="button" className={`calendar-day${cell.inMonth ? '' : ' is-outside'}${selectedDate === cell.date ? ' is-selected' : ''}`} key={cell.date} onClick={() => setSelectedDate(cell.date)} aria-label={cell.date} aria-pressed={selectedDate === cell.date}>
          <span>{Number(cell.date.slice(-2))}</span><span className="calendar-day__dots" aria-hidden="true">{hasPlanned ? <i className="is-planned" /> : null}{hasDeadline ? <i className="is-deadline" /> : null}</span>
        </button>;
      })}
    </div>
    <section className="calendar-agenda"><h2>{selectedLabel}</h2>{loading ? <p>{words.loading}</p> : agenda.length === 0 ? <div className="calendar-empty"><CalendarDays size={25} /><p>{words.empty}</p></div> : <div className="calendar-agenda__list">{agenda.map((entry) => { const marker = entry[0]; return <button type="button" key={`${marker.occurrenceId}:${marker.taskId}`} onClick={() => navigate(taskDetailPath(marker.taskId))}><span className="calendar-marker-set" aria-hidden="true">{entry.some((item) => item.kind === 'planned') ? <i className="calendar-marker calendar-marker--planned" /> : null}{entry.some((item) => item.kind === 'deadline') ? <i className="calendar-marker calendar-marker--deadline" /> : null}</span><span><strong>{marker.title}</strong><small>{entry.map((item) => item.kind === 'deadline' ? words.deadline : words.planned).join(' · ')}{marker.recurring ? ' · ↻' : ''}</small></span><time>{entry.map((item) => new Intl.DateTimeFormat(localeName, { hour: '2-digit', minute: '2-digit', timeZone }).format(new Date(item.at))).join(' / ')}</time></button>; })}</div>}</section>
  </section>;
}
