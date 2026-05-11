import { useEffect, useMemo, useState } from 'react';
import { CalendarClock, Clock3, RefreshCw } from 'lucide-react';

import { useAuth } from '../../auth';
import { useI18n } from '../../../i18n';
import { EmptyState } from '../../../ui/feedback/EmptyState';
import { ErrorState } from '../../../ui/feedback/ErrorState';
import { LoadingState } from '../../../ui/feedback/LoadingState';
import { formatDateTime } from '../../planning/planning-utils';
import { getCalendar, quickRescheduleTask } from '../advanced-api';
import { mapAdvancedError } from '../advanced-errors';
import { useAdvancedCopy } from '../advanced-copy';
import type { CalendarItemDto, CalendarPreset, QuickReschedulePayload } from '../types';

const quickPresets: Required<QuickReschedulePayload>['preset'][] = ['30m', '1h', '3h', '24h'];

function addDays(date: Date, days: number) {
  const nextDate = new Date(date);
  nextDate.setDate(date.getDate() + days);
  return nextDate;
}

function rangeForPreset(preset: CalendarPreset) {
  const from = new Date();
  from.setHours(0, 0, 0, 0);

  if (preset === 'day') {
    return { from, to: addDays(from, 1) };
  }

  if (preset === 'week') {
    return { from, to: addDays(from, 7) };
  }

  return { from, to: addDays(from, 31) };
}

function sortCalendarItems(items: CalendarItemDto[]) {
  return [...items].sort((left, right) => {
    const leftTime = new Date(left.plannedTime).getTime();
    const rightTime = new Date(right.plannedTime).getTime();
    return leftTime - rightTime;
  });
}

export function CalendarRoute() {
  const { authorizedFetch } = useAuth();
  const { locale } = useI18n();
  const copy = useAdvancedCopy();
  const [preset, setPreset] = useState<CalendarPreset>('week');
  const [items, setItems] = useState<CalendarItemDto[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [savingTaskId, setSavingTaskId] = useState<string | null>(null);

  const sortedItems = useMemo(() => sortCalendarItems(items), [items]);

  async function loadCalendar(nextPreset = preset) {
    const range = rangeForPreset(nextPreset);
    setLoading(true);
    setError(null);

    try {
      const response = await getCalendar(authorizedFetch, range.from.toISOString(), range.to.toISOString());
      setItems(response.items);
    } catch (loadError) {
      setError(mapAdvancedError(loadError, copy).formError);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadCalendar(preset);
  }, [preset]);

  async function handleQuickReschedule(taskId: string, quickPreset: Required<QuickReschedulePayload>['preset']) {
    setSavingTaskId(taskId);
    setError(null);
    setNotice(null);

    try {
      const response = await quickRescheduleTask(authorizedFetch, taskId, { preset: quickPreset });
      setNotice(response.priorityDecayApplied
        ? `${copy.calendar.rescheduledNotice} ${copy.calendar.priorityDecayApplied}`
        : copy.calendar.rescheduledNotice);
      await loadCalendar(preset);
    } catch (rescheduleError) {
      setError(mapAdvancedError(rescheduleError, copy).formError);
    } finally {
      setSavingTaskId(null);
    }
  }

  if (loading) {
    return (
      <section className="planner planner--center">
        <LoadingState title={copy.common.loadingTitle} description={copy.common.loadingDescription} />
      </section>
    );
  }

  return (
    <section className="planner">
      <div className="planner-canvas">
        <header className="planner-header">
          <div>
            <h1>{copy.calendar.title}</h1>
            <div className="planner-header__meta">
              <span>{copy.calendar.subtitle}</span>
              <span>
                {copy.calendar.rangeLabel}: {copy.calendar[preset === 'day' ? 'rangeDay' : preset === 'week' ? 'rangeWeek' : 'rangeMonth']}
              </span>
            </div>
          </div>
          <div className="planner-toolbar">
            {(['day', 'week', 'month'] as const).map((rangePreset) => (
              <button
                key={rangePreset}
                className={rangePreset === preset ? 'button button--primary' : 'button button--ghost'}
                type="button"
                onClick={() => setPreset(rangePreset)}
              >
                {copy.calendar[rangePreset === 'day' ? 'rangeDay' : rangePreset === 'week' ? 'rangeWeek' : 'rangeMonth']}
              </button>
            ))}
            <button className="icon-button" type="button" aria-label={copy.common.refresh} title={copy.common.refresh} onClick={() => void loadCalendar()}>
              <RefreshCw size={18} aria-hidden="true" />
            </button>
          </div>
        </header>

        <div className="detail-panel__body">
          {notice ? <div className="state-box state-box--loading">{notice}</div> : null}
          {error ? (
            <div className="stack stack--tight">
              <ErrorState title={copy.common.errorTitle} description={error} />
              <button className="button button--primary" type="button" onClick={() => void loadCalendar()}>
                {copy.common.retry}
              </button>
            </div>
          ) : null}

          {!error && sortedItems.length === 0 ? (
            <EmptyState title={copy.calendar.listEmptyTitle} description={copy.calendar.listEmptyDescription} />
          ) : null}

          {!error && sortedItems.length > 0 ? (
            <section className="detail-section">
              <div className="detail-label">{copy.calendar.listTitle}</div>
              <div className="stack stack--tight" role="list">
                {sortedItems.map((item) => (
                  <article className="detail-disclosure" key={item.taskId} role="listitem">
                    <div className="breadcrumb">
                      <span className={`marker-dot marker-dot--${item.type}`} aria-hidden="true" />
                      <CalendarClock size={16} aria-hidden="true" />
                      <strong>{item.title}</strong>
                    </div>
                    <div className="detail-panel__badges">
                      <span className="meta-chip">{copy.common.plannedTime}: {formatDateTime(item.plannedTime, locale)}</span>
                      <span className="meta-chip">{copy.common.dueTime}: {formatDateTime(item.dueTime, locale)}</span>
                      <span className={`meta-chip meta-chip--${item.priority <= 2 ? 'red' : item.priority <= 5 ? 'amber' : 'blue'}`}>
                        {copy.common.priority}: {item.priority}
                      </span>
                      <span className="meta-chip">{copy.enums.status[item.status]}</span>
                    </div>
                    <div className="cluster">
                      {quickPresets.map((quickPreset) => (
                        <button
                          key={quickPreset}
                          className="button button--ghost"
                          type="button"
                          title={`${copy.calendar.quickRescheduleTitle} ${copy.enums.quickPreset[quickPreset]}`}
                          disabled={savingTaskId === item.taskId}
                          onClick={() => void handleQuickReschedule(item.taskId, quickPreset)}
                        >
                          <Clock3 size={14} aria-hidden="true" />
                          {copy.enums.quickPreset[quickPreset]}
                        </button>
                      ))}
                    </div>
                  </article>
                ))}
              </div>
            </section>
          ) : null}
        </div>
      </div>
    </section>
  );
}
