import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { Link, useSearchParams } from 'react-router-dom';

import { useI18n } from '../../../i18n';
import { EmptyState } from '../../../ui/feedback/EmptyState';
import { ErrorState } from '../../../ui/feedback/ErrorState';
import { LoadingState } from '../../../ui/feedback/LoadingState';
import { RetroBadge } from '../../../ui/primitives/RetroBadge';
import { RetroButton } from '../../../ui/primitives/RetroButton';
import { RetroField } from '../../../ui/primitives/RetroField';
import { RetroPanel } from '../../../ui/primitives/RetroPanel';
import { useAuth } from '../../auth';
import {
  PlanningInlineNotice,
  PlanningMetaList,
  PlanningRecordButton,
  PlanningSplitLayout,
} from '../../planning/components/PlanningWorkspace';
import {
  formatDateTime,
  fromDateTimeInputValue,
  toDateTimeInputValue,
} from '../../planning/planning-utils';
import { AdvancedApiError, getCalendar, moveTask, quickRescheduleTask } from '../advanced-api';
import { useAdvancedCopy } from '../advanced-copy';
import type { CalendarItemDto, CalendarPreset } from '../types';

function buildRange(preset: CalendarPreset) {
  const start = new Date();
  start.setSeconds(0, 0);

  const end = new Date(start);
  const days = preset === 'day' ? 1 : preset === 'week' ? 7 : 31;
  end.setDate(end.getDate() + days);

  return {
    from: start.toISOString(),
    to: end.toISOString(),
  };
}

function mapError(error: unknown, copy: ReturnType<typeof useAdvancedCopy>) {
  if (error instanceof AdvancedApiError) {
    return {
      message: (copy.api as Record<string, string>)[error.payload.code] ?? copy.api.fallback,
      traceId: error.payload.traceId,
    };
  }

  return {
    message: copy.api.fallback,
    traceId: undefined,
  };
}

export function CalendarRoute() {
  const { authorizedFetch } = useAuth();
  const { locale } = useI18n();
  const copy = useAdvancedCopy();
  const [searchParams, setSearchParams] = useSearchParams();
  const [items, setItems] = useState<CalendarItemDto[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [traceId, setTraceId] = useState<string | undefined>();
  const [notice, setNotice] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [moveTime, setMoveTime] = useState('');

  const preset = (searchParams.get('range') as CalendarPreset | null) ?? 'week';
  const selectedTaskId = searchParams.get('task');
  const selectedItem = useMemo(
    () => items.find((item) => item.taskId === selectedTaskId) ?? null,
    [items, selectedTaskId],
  );

  function updateSearch(nextPreset: CalendarPreset, taskId: string | null) {
    const params = new URLSearchParams(searchParams);
    params.set('range', nextPreset);

    if (taskId) {
      params.set('task', taskId);
    } else {
      params.delete('task');
    }

    setSearchParams(params, { replace: true });
  }

  async function loadData(nextPreset: CalendarPreset, preferredTaskId?: string | null) {
    setLoading(true);
    setLoadError(null);
    setTraceId(undefined);

    try {
      const range = buildRange(nextPreset);
      const response = await getCalendar(authorizedFetch, range.from, range.to);
      setItems(response.items);

      const nextTaskId =
        preferredTaskId && response.items.some((item) => item.taskId === preferredTaskId)
          ? preferredTaskId
          : response.items[0]?.taskId ?? null;

      updateSearch(nextPreset, nextTaskId);
      setLoading(false);
    } catch (error) {
      const mapped = mapError(error, copy);
      setLoadError(mapped.message);
      setTraceId(mapped.traceId);
      setItems([]);
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadData(preset, selectedTaskId);
  }, [preset]);

  useEffect(() => {
    setMoveTime(toDateTimeInputValue(selectedItem?.plannedTime ?? null));
  }, [selectedItem?.taskId]);

  async function handleMove(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!selectedItem) {
      return;
    }

    const plannedTime = fromDateTimeInputValue(moveTime);

    if (!plannedTime) {
      setLoadError(copy.api.validation_error);
      return;
    }

    setSubmitting(true);
    setNotice(null);

    try {
      await moveTask(authorizedFetch, selectedItem.taskId, { plannedTime });
      await loadData(preset, selectedItem.taskId);
      setNotice(copy.calendar.movedNotice);
    } catch (error) {
      const mapped = mapError(error, copy);
      setLoadError(mapped.message);
      setTraceId(mapped.traceId);
    } finally {
      setSubmitting(false);
    }
  }

  async function handleQuickReschedule(nextPreset: '30m' | '1h' | '3h' | '24h') {
    if (!selectedItem) {
      return;
    }

    setSubmitting(true);
    setNotice(null);

    try {
      const response = await quickRescheduleTask(authorizedFetch, selectedItem.taskId, {
        preset: nextPreset,
      });
      await loadData(preset, selectedItem.taskId);
      setNotice(
        response.priorityDecayApplied
          ? `${copy.calendar.rescheduledNotice} ${copy.calendar.priorityDecayApplied}`
          : copy.calendar.rescheduledNotice,
      );
    } catch (error) {
      const mapped = mapError(error, copy);
      setLoadError(mapped.message);
      setTraceId(mapped.traceId);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="stack">
      <div className="surface-header">
        <div className="stack stack--tight">
          <div className="caps">{copy.common.title}</div>
          <div className="surface-title">{copy.calendar.title}</div>
          <div className="surface-subtitle">{copy.calendar.subtitle}</div>
        </div>
      </div>

      <PlanningSplitLayout
        sidebar={(
          <RetroPanel
            title={copy.calendar.listTitle}
            aside={(
              <RetroButton type="button" size="small" onClick={() => void loadData(preset, selectedTaskId)}>
                {copy.common.refresh}
              </RetroButton>
            )}
          >
            <div className="stack stack--tight">
              <RetroField label={copy.calendar.rangeLabel}>
                <select
                  className="retro-select"
                  value={preset}
                  onChange={(event) => updateSearch(event.target.value as CalendarPreset, null)}
                >
                  <option value="day">{copy.calendar.rangeDay}</option>
                  <option value="week">{copy.calendar.rangeWeek}</option>
                  <option value="month">{copy.calendar.rangeMonth}</option>
                </select>
              </RetroField>

              {loading ? (
                <LoadingState title={copy.common.loadingTitle} description={copy.common.loadingDescription} />
              ) : loadError ? (
                <ErrorState title={copy.common.errorTitle} description={loadError} />
              ) : items.length === 0 ? (
                <EmptyState
                  title={copy.calendar.listEmptyTitle}
                  description={copy.calendar.listEmptyDescription}
                />
              ) : (
                <div className="planning-record-list">
                  {items.map((item) => (
                    <PlanningRecordButton
                      key={item.taskId}
                      active={item.taskId === selectedTaskId}
                      title={item.title}
                      subtitle={formatDateTime(item.plannedTime, locale)}
                      meta={<span>{`${copy.common.priority}: ${item.priority}`}</span>}
                      onClick={() => updateSearch(preset, item.taskId)}
                    />
                  ))}
                </div>
              )}
            </div>
          </RetroPanel>
        )}
        detail={selectedItem ? (
          <RetroPanel
            title={copy.calendar.detailTitle}
            aside={(
              <RetroBadge tone={selectedItem.type === 'green' ? 'success' : 'danger'}>
                {copy.enums.type[selectedItem.type]}
              </RetroBadge>
            )}
          >
            <div className="stack stack--tight">
              <div className="surface-header">
                <div className="stack stack--tight">
                  <div className="surface-title">{selectedItem.title}</div>
                  <div className="surface-subtitle">{copy.common.goal}: {selectedItem.goalId}</div>
                </div>
                <div className="surface-meta">
                  <RetroBadge tone="info">{copy.enums.status[selectedItem.status]}</RetroBadge>
                </div>
              </div>

              {notice ? <PlanningInlineNotice tone="info">{notice}</PlanningInlineNotice> : null}
              {loadError ? <PlanningInlineNotice tone="error">{loadError}</PlanningInlineNotice> : null}
              {traceId ? <PlanningInlineNotice tone="info">{copy.common.traceId}: {traceId}</PlanningInlineNotice> : null}

              <PlanningMetaList
                items={[
                  { label: copy.common.plannedTime, value: formatDateTime(selectedItem.plannedTime, locale) },
                  { label: copy.common.dueTime, value: formatDateTime(selectedItem.dueTime, locale) },
                  { label: copy.common.priority, value: selectedItem.priority },
                  { label: copy.common.status, value: copy.enums.status[selectedItem.status] },
                ]}
              />

              <form className="stack stack--tight" onSubmit={handleMove}>
                <RetroField label={copy.calendar.moveTitle}>
                  <input
                    className="retro-input"
                    type="datetime-local"
                    value={moveTime}
                    onChange={(event) => setMoveTime(event.target.value)}
                  />
                </RetroField>
                <div className="cluster">
                  <RetroButton type="submit" variant="primary" disabled={submitting}>
                    {copy.calendar.moveAction}
                  </RetroButton>
                </div>
              </form>

              <RetroPanel title={copy.calendar.quickRescheduleTitle}>
                <div className="cluster">
                  {(['30m', '1h', '3h', '24h'] as const).map((presetValue) => (
                    <RetroButton
                      key={presetValue}
                      type="button"
                      variant="ghost"
                      disabled={submitting}
                      onClick={() => void handleQuickReschedule(presetValue)}
                    >
                      {copy.enums.quickPreset[presetValue]}
                    </RetroButton>
                  ))}
                </div>
              </RetroPanel>

              <div className="cluster">
                <RetroButton as={Link} to={`/app/tasks?task=${selectedItem.taskId}`} variant="ghost">
                  {copy.common.openTask}
                </RetroButton>
              </div>
            </div>
          </RetroPanel>
        ) : (
          <EmptyState title={copy.calendar.detailTitle} description={copy.calendar.missingSelection} />
        )}
      />
    </div>
  );
}

