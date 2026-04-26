import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { Link, useSearchParams } from 'react-router-dom';

import { useAuth } from '../../auth';
import { useI18n } from '../../../i18n';
import { ConflictState } from '../../../ui/feedback/ConflictState';
import { EmptyState } from '../../../ui/feedback/EmptyState';
import { ErrorState } from '../../../ui/feedback/ErrorState';
import { LoadingState } from '../../../ui/feedback/LoadingState';
import { RetroBadge } from '../../../ui/primitives/RetroBadge';
import { RetroButton } from '../../../ui/primitives/RetroButton';
import { RetroDialogFrame } from '../../../ui/primitives/RetroDialogFrame';
import { RetroField } from '../../../ui/primitives/RetroField';
import { RetroPanel } from '../../../ui/primitives/RetroPanel';
import {
  createTask,
  deleteTask,
  getTask,
  listFolders,
  listGoals,
  listTasks,
  replaceTaskReminders,
  updateTask,
  upsertTaskRecurrence,
} from '../planning-api';
import { usePlanningCopy } from '../planning-copy';
import { isPlanningApiError, mapPlanningError } from '../planning-errors';
import {
  createDefaultReminderDraft,
  describeRecurrence,
  describeReminders,
  describeTags,
  findById,
  formatDateTime,
  normalizeSelection,
  resolveTaskAnchorTime,
  toTaskEditorDraft,
  toTaskRecurrenceUpsertPayload,
  toTaskRemindersReplacePayload,
  toTaskUpsertPayload,
  type TaskEditorDraft,
} from '../planning-utils';
import type {
  DayOfWeek,
  FolderDto,
  GoalDto,
  TaskDto,
  TaskRecurrenceDraft,
  TaskReminderDraft,
  TaskStatus,
  TaskType,
} from '../types';
import {
  PlanningFieldError,
  PlanningInlineNotice,
  PlanningMetaList,
  PlanningRecordButton,
  PlanningSplitLayout,
} from '../components/PlanningWorkspace';

type FormMode = 'create' | 'edit' | null;

const WEEKDAYS: DayOfWeek[] = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];

export function TasksRoute() {
  const { authorizedFetch } = useAuth();
  const { locale } = useI18n();
  const copy = usePlanningCopy();
  const [searchParams, setSearchParams] = useSearchParams();
  const [folders, setFolders] = useState<FolderDto[]>([]);
  const [goals, setGoals] = useState<GoalDto[]>([]);
  const [tasks, setTasks] = useState<TaskDto[]>([]);
  const [selectedTask, setSelectedTask] = useState<TaskDto | null>(null);
  const [loadingFolders, setLoadingFolders] = useState(true);
  const [loadingGoals, setLoadingGoals] = useState(false);
  const [loadingTasks, setLoadingTasks] = useState(false);
  const [loadingDetail, setLoadingDetail] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [formMode, setFormMode] = useState<FormMode>(null);
  const [draft, setDraft] = useState<TaskEditorDraft>(toTaskEditorDraft(null));
  const [formError, setFormError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [traceId, setTraceId] = useState<string | undefined>();
  const [submitting, setSubmitting] = useState(false);
  const [showConflict, setShowConflict] = useState(false);

  const selectedFolderId = searchParams.get('folder');
  const selectedGoalId = searchParams.get('goal');
  const selectedTaskId = searchParams.get('task');
  const selectedFolder = useMemo(() => findById(folders, selectedFolderId), [folders, selectedFolderId]);
  const selectedGoal = useMemo(() => findById(goals, selectedGoalId), [goals, selectedGoalId]);

  function updateSelection(nextFolderId: string | null, nextGoalId: string | null, nextTaskId: string | null) {
    const nextParams = new URLSearchParams(searchParams);

    if (nextFolderId) {
      nextParams.set('folder', nextFolderId);
    } else {
      nextParams.delete('folder');
    }

    if (nextGoalId) {
      nextParams.set('goal', nextGoalId);
    } else {
      nextParams.delete('goal');
    }

    if (nextTaskId) {
      nextParams.set('task', nextTaskId);
    } else {
      nextParams.delete('task');
    }

    setSearchParams(nextParams, { replace: true });
  }

  async function loadFolderList() {
    setLoadingFolders(true);
    setLoadError(null);

    try {
      const nextFolders = await listFolders(authorizedFetch);
      const nextSelectedFolderId = normalizeSelection(nextFolders, selectedFolderId);

      setFolders(nextFolders);
      setLoadingFolders(false);
      updateSelection(nextSelectedFolderId, null, null);
    } catch (error) {
      const mappedError = mapPlanningError(error, copy);
      setLoadError(mappedError.message);
      setLoadingFolders(false);
    }
  }

  async function loadGoalList(folderId: string, preferredGoalId?: string | null) {
    setLoadingGoals(true);
    setLoadError(null);

    try {
      const nextGoals = await listGoals(authorizedFetch, folderId);
      const nextSelectedGoalId = normalizeSelection(nextGoals, preferredGoalId ?? selectedGoalId);

      setGoals(nextGoals);
      setLoadingGoals(false);
      updateSelection(folderId, nextSelectedGoalId, null);

      return nextGoals;
    } catch (error) {
      const mappedError = mapPlanningError(error, copy);
      setLoadError(mappedError.message);
      setGoals([]);
      setLoadingGoals(false);
      return null;
    }
  }

  async function loadTaskList(goalId: string, preferredTaskId?: string | null) {
    setLoadingTasks(true);
    setLoadError(null);

    try {
      const nextTasks = await listTasks(authorizedFetch, goalId);
      const nextSelectedTaskId = normalizeSelection(nextTasks, preferredTaskId ?? selectedTaskId);

      setTasks(nextTasks);
      setLoadingTasks(false);
      updateSelection(selectedFolderId, goalId, nextSelectedTaskId);

      return nextTasks;
    } catch (error) {
      const mappedError = mapPlanningError(error, copy);
      setLoadError(mappedError.message);
      setTasks([]);
      setLoadingTasks(false);
      return null;
    }
  }

  async function loadTaskDetail(taskId: string) {
    setLoadingDetail(true);

    try {
      const detail = await getTask(authorizedFetch, taskId);
      setSelectedTask(detail);
      return detail;
    } catch (error) {
      const mappedError = mapPlanningError(error, copy);
      setLoadError(mappedError.message);
      setSelectedTask(null);
      return null;
    } finally {
      setLoadingDetail(false);
    }
  }

  useEffect(() => {
    void loadFolderList();
  }, []);

  useEffect(() => {
    if (!selectedFolderId) {
      setGoals([]);
      setTasks([]);
      setSelectedTask(null);
      return;
    }

    void loadGoalList(selectedFolderId);
  }, [selectedFolderId]);

  useEffect(() => {
    if (!selectedGoalId) {
      setTasks([]);
      setSelectedTask(null);
      return;
    }

    void loadTaskList(selectedGoalId);
  }, [selectedGoalId]);

  useEffect(() => {
    if (!selectedTaskId) {
      setSelectedTask(null);
      return;
    }

    void loadTaskDetail(selectedTaskId);
  }, [selectedTaskId]);

  useEffect(() => {
    setDraft((current) => {
      if (current.recurrence.anchor === 'planned' && !current.plannedTime && current.dueTime) {
        return {
          ...current,
          recurrence: {
            ...current.recurrence,
            anchor: 'due',
          },
        };
      }

      if (current.recurrence.anchor === 'due' && !current.dueTime && current.plannedTime) {
        return {
          ...current,
          recurrence: {
            ...current.recurrence,
            anchor: 'planned',
          },
        };
      }

      return current;
    });
  }, [draft.plannedTime, draft.dueTime]);

  function resetForm(nextMode: FormMode, task: TaskDto | null) {
    setFormMode(nextMode);
    setDraft(toTaskEditorDraft(task));
    setFormError(null);
    setFieldErrors({});
    setTraceId(undefined);
    setShowConflict(false);
  }

  function getAnchorOptions() {
    const options: Array<{ value: 'planned' | 'due'; label: string }> = [];

    if (draft.plannedTime) {
      options.push({ value: 'planned', label: copy.tasks.anchorPlanned });
    }

    if (draft.dueTime) {
      options.push({ value: 'due', label: copy.tasks.anchorDue });
    }

    return options;
  }

  function weekdayLabel(day: DayOfWeek) {
    const labels: Record<DayOfWeek, string> = {
      MONDAY: copy.tasks.weekdayMonday,
      TUESDAY: copy.tasks.weekdayTuesday,
      WEDNESDAY: copy.tasks.weekdayWednesday,
      THURSDAY: copy.tasks.weekdayThursday,
      FRIDAY: copy.tasks.weekdayFriday,
      SATURDAY: copy.tasks.weekdaySaturday,
      SUNDAY: copy.tasks.weekdaySunday,
    };

    return labels[day];
  }

  function normalizeFieldErrors(nextFieldErrors: Record<string, string>) {
    const normalized: Record<string, string> = {};

    for (const [field, message] of Object.entries(nextFieldErrors)) {
      if (field.startsWith('reminders[')) {
        const match = /^reminders\[(\d+)\]\.(.+)$/.exec(field);
        if (match) {
          normalized[`reminders.${match[1]}.${match[2]}`] = message;
          continue;
        }
      }

      if (field === 'mode') {
        normalized['recurrence.mode'] = message;
        continue;
      }

      if (field === 'interval') {
        normalized['recurrence.interval'] = message;
        continue;
      }

      if (field === 'daysOfWeek') {
        normalized['recurrence.daysOfWeek'] = message;
        continue;
      }

      if (field === 'dayOfMonth' || field === 'startAt') {
        normalized['recurrence.anchor'] = message;
        continue;
      }

      if (field === 'endAt') {
        normalized['recurrence.endAt'] = message;
        continue;
      }

      if (field === 'offsetMinutes') {
        normalized['reminders.0.offsetMinutes'] = message;
        continue;
      }

      normalized[field] = message;
    }

    return normalized;
  }

  function validateDraft() {
    const nextFieldErrors: Record<string, string> = {};
    const priority = Number(draft.priority);
    const anchorTime = resolveTaskAnchorTime(draft);
    const anchorDate = anchorTime ? new Date(anchorTime) : null;

    if (!draft.title.trim()) {
      nextFieldErrors.title = copy.tasks.validationRequired;
    }

    if (!Number.isInteger(priority) || priority < 1 || priority > 10) {
      nextFieldErrors.priority = copy.tasks.validationPriorityRange;
    }

    if (draft.recurrence.enabled) {
      const interval = Number(draft.recurrence.interval);

      if (!anchorTime) {
        nextFieldErrors['recurrence.anchor'] = copy.tasks.validationRecurrenceAnchor;
      }

      if (!Number.isInteger(interval) || interval < 1) {
        nextFieldErrors['recurrence.interval'] = copy.tasks.validationRecurrenceInterval;
      }

      if (draft.recurrence.mode === 'weekly') {
        if (!anchorDate || Number.isNaN(anchorDate.getTime())) {
          nextFieldErrors['recurrence.anchor'] = copy.tasks.validationRecurrenceAnchor;
        } else {
          const anchorWeekday = WEEKDAYS[(anchorDate.getDay() + 6) % 7];
          if (!draft.recurrence.daysOfWeek.includes(anchorWeekday)) {
            nextFieldErrors['recurrence.daysOfWeek'] = copy.tasks.validationRecurrenceWeekday;
          }
        }
      }

      if (draft.recurrence.endAt && anchorDate && !Number.isNaN(anchorDate.getTime())) {
        const endDate = new Date(draft.recurrence.endAt);
        if (Number.isNaN(endDate.getTime()) || endDate.getTime() <= anchorDate.getTime()) {
          nextFieldErrors['recurrence.endAt'] = copy.tasks.validationRecurrenceEndAt;
        }
      }
    }

    const reminderKeys = new Set<string>();
    draft.reminders.forEach((reminder, index) => {
      const offset = Number(reminder.offsetMinutes);

      if (!Number.isInteger(offset) || offset < 1) {
        nextFieldErrors[`reminders.${index}.offsetMinutes`] = copy.tasks.validationReminderOffset;
      }

      if (reminder.mode === 'before_planned_time' && !draft.plannedTime) {
        nextFieldErrors[`reminders.${index}.offsetMinutes`] = copy.tasks.validationReminderAnchor;
      }

      if (reminder.mode === 'before_due_time' && !draft.dueTime) {
        nextFieldErrors[`reminders.${index}.offsetMinutes`] = copy.tasks.validationReminderAnchor;
      }

      const key = `${reminder.mode}:${offset}`;
      if (!nextFieldErrors[`reminders.${index}.offsetMinutes`]) {
        if (reminderKeys.has(key)) {
          nextFieldErrors[`reminders.${index}.offsetMinutes`] = copy.tasks.validationReminderDuplicate;
        } else {
          reminderKeys.add(key);
        }
      }
    });

    setFieldErrors(nextFieldErrors);
    return Object.keys(nextFieldErrors).length === 0;
  }

  async function syncScheduling(task: TaskDto, previousTask: TaskDto | null) {
    if (draft.recurrence.enabled) {
      const recurrencePayload = toTaskRecurrenceUpsertPayload(draft);
      if (!recurrencePayload) {
        throw new Error('recurrence_anchor_missing');
      }
      await upsertTaskRecurrence(authorizedFetch, task.id, recurrencePayload);
    } else if (previousTask?.recurrence?.active) {
      const recurrencePayload = toTaskRecurrenceUpsertPayload({
        ...draft,
        recurrence: {
          ...draft.recurrence,
          enabled: true,
          active: false,
        },
      });

      if (!recurrencePayload) {
        throw new Error('recurrence_anchor_missing');
      }

      await upsertTaskRecurrence(authorizedFetch, task.id, recurrencePayload);
    }

    if (draft.reminders.length > 0 || previousTask?.reminders.length) {
      await replaceTaskReminders(authorizedFetch, task.id, toTaskRemindersReplacePayload(draft));
    }
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!selectedGoalId || !validateDraft()) {
      return;
    }

    const payload = toTaskUpsertPayload(draft);

    setSubmitting(true);
    setFormError(null);
    setTraceId(undefined);

    try {
      let persistedTask: TaskDto | null = null;

      if (formMode === 'create') {
        persistedTask = await createTask(authorizedFetch, selectedGoalId, payload);
        await syncScheduling(persistedTask, null);
        await loadTaskList(selectedGoalId, persistedTask.id);
        await loadTaskDetail(persistedTask.id);
        resetForm(null, null);
      }

      if (formMode === 'edit' && selectedTask) {
        persistedTask = await updateTask(authorizedFetch, selectedTask.id, {
          ...payload,
          archived: selectedTask.archived,
          version: selectedTask.version,
        });

        await syncScheduling(persistedTask, selectedTask);
        await loadTaskList(selectedGoalId, selectedTask.id);
        await loadTaskDetail(selectedTask.id);
        resetForm(null, null);
      }
    } catch (error) {
      if (isPlanningApiError(error) && error.status === 409 && selectedTask && selectedGoalId) {
        await loadTaskList(selectedGoalId, selectedTask.id);
        const freshTask = await loadTaskDetail(selectedTask.id);
        resetForm('edit', freshTask);
        setShowConflict(true);
      } else if (error instanceof Error && error.message === 'recurrence_anchor_missing') {
        const message = copy.tasks.validationRecurrenceAnchor;
        setFormError(message);
        setFieldErrors({ 'recurrence.anchor': message });
      } else {
        const mappedError = mapPlanningError(error, copy);
        setFormError(mappedError.message);
        setFieldErrors(normalizeFieldErrors(mappedError.fieldErrors));
        setTraceId(mappedError.traceId);
      }
    } finally {
      setSubmitting(false);
    }
  }

  async function handleDelete() {
    if (!selectedTask || !selectedGoalId || !window.confirm(copy.tasks.deleteConfirm)) {
      return;
    }

    try {
      await deleteTask(authorizedFetch, selectedTask.id);
      await loadTaskList(selectedGoalId);
      setSelectedTask(null);
      resetForm(null, null);
    } catch (error) {
      const mappedError = mapPlanningError(error, copy);
      setLoadError(mappedError.message);
    }
  }

  function updateRecurrence(updater: (current: TaskRecurrenceDraft) => TaskRecurrenceDraft) {
    setDraft((current) => ({ ...current, recurrence: updater(current.recurrence) }));
  }

  function updateReminder(index: number, updater: (current: TaskReminderDraft) => TaskReminderDraft) {
    setDraft((current) => ({
      ...current,
      reminders: current.reminders.map((reminder, reminderIndex) =>
        reminderIndex === index ? updater(reminder) : reminder),
    }));
  }

  function addReminder() {
    setDraft((current) => ({
      ...current,
      reminders: [...current.reminders, createDefaultReminderDraft(current.reminders.length)],
    }));
  }

  function removeReminder(index: number) {
    setDraft((current) => ({
      ...current,
      reminders: current.reminders.filter((_, reminderIndex) => reminderIndex !== index),
    }));
  }

  const listPanelContent = loadingFolders ? (
    <LoadingState title={copy.common.loadingTitle} description={copy.common.loadingDescription} />
  ) : loadError ? (
    <div className="stack stack--tight">
      <ErrorState title={copy.common.errorTitle} description={loadError} />
      <RetroButton type="button" onClick={() => void loadFolderList()}>
        {copy.common.retry}
      </RetroButton>
    </div>
  ) : folders.length === 0 ? (
    <EmptyState title={copy.tasks.noFoldersTitle} description={copy.tasks.noFoldersDescription} />
  ) : (
    <div className="stack stack--tight">
      <RetroField label={copy.tasks.folderLabel}>
        <select
          className="retro-select"
          value={selectedFolderId ?? ''}
          onChange={(event) => updateSelection(event.target.value || null, null, null)}
        >
          {folders.map((folder) => (
            <option key={folder.id} value={folder.id}>
              {folder.name}
            </option>
          ))}
        </select>
      </RetroField>
      {goals.length > 0 ? (
        <RetroField label={copy.tasks.goalLabel}>
          <select
            className="retro-select"
            value={selectedGoalId ?? ''}
            onChange={(event) => updateSelection(selectedFolderId, event.target.value || null, null)}
          >
            {goals.map((goal) => (
              <option key={goal.id} value={goal.id}>
                {goal.name}
              </option>
            ))}
          </select>
        </RetroField>
      ) : null}
      {loadingGoals || loadingTasks ? (
        <LoadingState title={copy.common.loadingTitle} description={copy.common.loadingDescription} />
      ) : selectedFolder && goals.length === 0 ? (
        <div className="stack stack--tight">
          <EmptyState title={copy.tasks.noGoalsTitle} description={copy.tasks.noGoalsDescription} />
          <RetroButton as={Link} to={`/app/goals?folder=${selectedFolder.id}`}>
            {copy.common.openGoals}
          </RetroButton>
        </div>
      ) : tasks.length === 0 ? (
        <EmptyState title={copy.tasks.listEmptyTitle} description={copy.tasks.listEmptyDescription} />
      ) : (
        <div className="planning-record-list">
          {tasks.map((task) => (
            <PlanningRecordButton
              key={task.id}
              active={task.id === selectedTaskId}
              title={task.title}
              subtitle={`${copy.enums.taskStatus[task.status]} / ${copy.enums.taskType[task.type]}`}
              meta={<span>{`${copy.tasks.priorityLabel}: ${task.priority}`}</span>}
              onClick={() => updateSelection(selectedFolderId, selectedGoalId, task.id)}
            />
          ))}
        </div>
      )}
    </div>
  );

  const detailPanel = formMode ? (
    <RetroDialogFrame
      title={formMode === 'create' ? copy.tasks.createTitle : copy.tasks.editTitle}
      footer={(
        <div className="cluster">
          <RetroButton type="submit" form="task-form" variant="primary" disabled={submitting}>
            {submitting ? copy.common.loadingTitle : copy.common.save}
          </RetroButton>
          <RetroButton type="button" onClick={() => resetForm(null, null)} disabled={submitting}>
            {copy.common.cancel}
          </RetroButton>
        </div>
      )}
    >
      {showConflict ? (
        <ConflictState
          title={copy.common.conflictTitle}
          description={copy.common.conflictDescription}
        />
      ) : null}
      {formError ? <PlanningInlineNotice tone="error">{formError}</PlanningInlineNotice> : null}
      {traceId ? (
        <PlanningInlineNotice tone="info">
          {copy.common.serverTrace}: {traceId}
        </PlanningInlineNotice>
      ) : null}
      <form id="task-form" className="stack stack--tight" onSubmit={handleSubmit}>
        <RetroField label={copy.tasks.titleLabel}>
          <input
            className="retro-input"
            value={draft.title}
            onChange={(event) => setDraft((current) => ({ ...current, title: event.target.value }))}
          />
          <PlanningFieldError message={fieldErrors.title} />
        </RetroField>
        <RetroField label={copy.tasks.descriptionLabel}>
          <textarea
            className="retro-textarea"
            value={draft.description}
            onChange={(event) => setDraft((current) => ({ ...current, description: event.target.value }))}
          />
        </RetroField>
        <div className="planning-form-grid">
          <RetroField label={copy.tasks.typeLabel}>
            <select
              className="retro-select"
              value={draft.type}
              onChange={(event) =>
                setDraft((current) => ({ ...current, type: event.target.value as TaskType }))
              }
            >
              <option value="green">{copy.enums.taskType.green}</option>
              <option value="red">{copy.enums.taskType.red}</option>
            </select>
          </RetroField>
          <RetroField label={copy.tasks.statusLabel}>
            <select
              className="retro-select"
              value={draft.status}
              onChange={(event) =>
                setDraft((current) => ({ ...current, status: event.target.value as TaskStatus }))
              }
            >
              <option value="todo">{copy.enums.taskStatus.todo}</option>
              <option value="in_progress">{copy.enums.taskStatus.in_progress}</option>
              <option value="done">{copy.enums.taskStatus.done}</option>
              <option value="cancelled">{copy.enums.taskStatus.cancelled}</option>
            </select>
          </RetroField>
          <RetroField label={copy.tasks.priorityLabel}>
            <input
              className="retro-input"
              type="number"
              min={1}
              max={10}
              value={draft.priority}
              onChange={(event) => setDraft((current) => ({ ...current, priority: event.target.value }))}
            />
            <PlanningFieldError message={fieldErrors.priority} />
          </RetroField>
          <RetroField label={copy.tasks.plannedTimeLabel}>
            <input
              className="retro-input"
              type="datetime-local"
              value={draft.plannedTime}
              onChange={(event) =>
                setDraft((current) => ({ ...current, plannedTime: event.target.value }))
              }
            />
          </RetroField>
          <RetroField label={copy.tasks.dueTimeLabel}>
            <input
              className="retro-input"
              type="datetime-local"
              value={draft.dueTime}
              onChange={(event) => setDraft((current) => ({ ...current, dueTime: event.target.value }))}
            />
          </RetroField>
        </div>

        <div className="stack stack--tight">
          <div className="surface-title">{copy.tasks.schedulingSectionTitle}</div>
          <PlanningInlineNotice tone="info">{copy.tasks.schedulingHelp}</PlanningInlineNotice>
          <RetroField label={copy.tasks.recurrenceLabel}>
            <label className="cluster">
              <input
                type="checkbox"
                checked={draft.recurrence.enabled}
                onChange={(event) =>
                  updateRecurrence((current) => ({
                    ...current,
                    enabled: event.target.checked,
                    active: event.target.checked ? current.active : false,
                  }))
                }
              />
              <span>{copy.tasks.recurrenceEnabledLabel}</span>
            </label>
          </RetroField>

          {draft.recurrence.enabled ? (
            <div className="stack stack--tight">
              <PlanningInlineNotice tone="info">{copy.tasks.recurrenceHint}</PlanningInlineNotice>
              <div className="planning-form-grid">
                <RetroField label={copy.tasks.recurrenceModeLabel}>
                  <select
                    className="retro-select"
                    value={draft.recurrence.mode}
                    onChange={(event) =>
                      updateRecurrence((current) => ({
                        ...current,
                        mode: event.target.value as TaskRecurrenceDraft['mode'],
                        daysOfWeek: event.target.value === 'weekly' ? current.daysOfWeek : [],
                      }))
                    }
                  >
                    <option value="daily">{copy.tasks.recurrenceModeDaily}</option>
                    <option value="weekly">{copy.tasks.recurrenceModeWeekly}</option>
                    <option value="monthly">{copy.tasks.recurrenceModeMonthly}</option>
                  </select>
                  <PlanningFieldError message={fieldErrors['recurrence.mode']} />
                </RetroField>
                <RetroField label={copy.tasks.recurrenceIntervalLabel}>
                  <input
                    className="retro-input"
                    type="number"
                    min={1}
                    value={draft.recurrence.interval}
                    onChange={(event) =>
                      updateRecurrence((current) => ({ ...current, interval: event.target.value }))
                    }
                  />
                  <PlanningFieldError message={fieldErrors['recurrence.interval']} />
                </RetroField>
                <RetroField label={copy.tasks.recurrenceAnchorLabel}>
                  <select
                    className="retro-select"
                    value={draft.recurrence.anchor}
                    onChange={(event) =>
                      updateRecurrence((current) => ({ ...current, anchor: event.target.value as 'planned' | 'due' }))
                    }
                  >
                    {getAnchorOptions().map((option) => (
                      <option key={option.value} value={option.value}>
                        {option.label}
                      </option>
                    ))}
                  </select>
                  <PlanningFieldError message={fieldErrors['recurrence.anchor']} />
                </RetroField>
                <RetroField label={copy.tasks.recurrenceEndAtLabel}>
                  <input
                    className="retro-input"
                    type="datetime-local"
                    value={draft.recurrence.endAt}
                    onChange={(event) =>
                      updateRecurrence((current) => ({ ...current, endAt: event.target.value }))
                    }
                  />
                  <PlanningFieldError message={fieldErrors['recurrence.endAt']} />
                </RetroField>
              </div>

              <RetroField label={copy.tasks.recurrenceActiveLabel}>
                <label className="cluster">
                  <input
                    type="checkbox"
                    checked={draft.recurrence.active}
                    onChange={(event) =>
                      updateRecurrence((current) => ({ ...current, active: event.target.checked }))
                    }
                  />
                  <span>{copy.tasks.recurrenceActiveLabel}</span>
                </label>
              </RetroField>

              {draft.recurrence.mode === 'weekly' ? (
                <RetroField label={copy.tasks.recurrenceWeekdaysLabel}>
                  <div className="cluster">
                    {WEEKDAYS.map((weekday) => (
                      <label key={weekday} className="cluster">
                        <input
                          type="checkbox"
                          checked={draft.recurrence.daysOfWeek.includes(weekday)}
                          onChange={(event) =>
                            updateRecurrence((current) => ({
                              ...current,
                              daysOfWeek: event.target.checked
                                ? [...current.daysOfWeek, weekday]
                                : current.daysOfWeek.filter((currentDay) => currentDay !== weekday),
                            }))
                          }
                        />
                        <span>{weekdayLabel(weekday)}</span>
                      </label>
                    ))}
                  </div>
                  <PlanningFieldError message={fieldErrors['recurrence.daysOfWeek']} />
                </RetroField>
              ) : null}
            </div>
          ) : null}

          <div className="stack stack--tight">
            <div className="surface-title">{copy.tasks.remindersLabel}</div>
            <PlanningInlineNotice tone="info">{copy.tasks.remindersHint}</PlanningInlineNotice>
            {draft.reminders.map((reminder, index) => (
              <div key={reminder.clientId} className="planning-form-grid">
                <RetroField label={copy.tasks.reminderModeLabel}>
                  <select
                    className="retro-select"
                    value={reminder.mode}
                    onChange={(event) =>
                      updateReminder(index, (current) => ({
                        ...current,
                        mode: event.target.value as TaskReminderDraft['mode'],
                      }))
                    }
                  >
                    <option value="before_planned_time">{copy.tasks.reminderModeBeforePlanned}</option>
                    <option value="before_due_time">{copy.tasks.reminderModeBeforeDue}</option>
                  </select>
                </RetroField>
                <RetroField label={copy.tasks.reminderOffsetLabel}>
                  <input
                    className="retro-input"
                    type="number"
                    min={1}
                    value={reminder.offsetMinutes}
                    onChange={(event) =>
                      updateReminder(index, (current) => ({ ...current, offsetMinutes: event.target.value }))
                    }
                  />
                  <PlanningFieldError message={fieldErrors[`reminders.${index}.offsetMinutes`]} />
                </RetroField>
                <RetroField label={copy.tasks.reminderActiveLabel}>
                  <label className="cluster">
                    <input
                      type="checkbox"
                      checked={reminder.active}
                      onChange={(event) =>
                        updateReminder(index, (current) => ({ ...current, active: event.target.checked }))
                      }
                    />
                    <span>{copy.tasks.reminderActiveLabel}</span>
                  </label>
                </RetroField>
                <div className="cluster">
                  <RetroButton type="button" variant="ghost" onClick={() => removeReminder(index)}>
                    {copy.tasks.reminderRemove}
                  </RetroButton>
                </div>
              </div>
            ))}
            <RetroButton type="button" variant="ghost" onClick={addReminder}>
              {copy.tasks.reminderAdd}
            </RetroButton>
          </div>
        </div>
      </form>
    </RetroDialogFrame>
  ) : loadingDetail ? (
    <LoadingState title={copy.common.loadingTitle} description={copy.common.loadingDescription} />
  ) : selectedTask ? (
    <RetroPanel
      title={copy.tasks.detailTitle}
      aside={<RetroBadge tone={selectedTask.shared ? 'warning' : 'info'}>{copy.common.details}</RetroBadge>}
    >
      <div className="stack">
        <div className="surface-header">
          <div className="stack stack--tight">
            <div className="surface-title">{selectedTask.title}</div>
            <div className="surface-subtitle">
              {selectedTask.description || copy.common.noDescription}
            </div>
          </div>
          <div className="surface-meta">
            <RetroBadge tone={selectedTask.type === 'green' ? 'success' : 'danger'}>
              {copy.enums.taskType[selectedTask.type]}
            </RetroBadge>
            <RetroBadge tone="info">{copy.enums.taskStatus[selectedTask.status]}</RetroBadge>
          </div>
        </div>
        <PlanningMetaList
          items={[
            { label: copy.tasks.goalLabel, value: selectedGoal?.name ?? '-' },
            { label: copy.tasks.priorityLabel, value: selectedTask.priority },
            { label: copy.tasks.plannedTimeLabel, value: formatDateTime(selectedTask.plannedTime, locale) },
            { label: copy.tasks.dueTimeLabel, value: formatDateTime(selectedTask.dueTime, locale) },
            { label: copy.tasks.tagsLabel, value: describeTags(selectedTask) },
            {
              label: copy.tasks.recurrenceLabel,
              value: selectedTask.recurrence ? describeRecurrence(selectedTask.recurrence, locale) : copy.tasks.recurrenceLater,
            },
            {
              label: copy.tasks.remindersLabel,
              value: selectedTask.reminders.length > 0 ? describeReminders(selectedTask.reminders, locale) : copy.tasks.remindersLater,
            },
            { label: copy.common.createdAt, value: formatDateTime(selectedTask.createdAt, locale) },
            { label: copy.common.updatedAt, value: formatDateTime(selectedTask.updatedAt, locale) },
          ]}
        />
        <div className="cluster">
          <RetroButton type="button" variant="primary" onClick={() => resetForm('edit', selectedTask)}>
            {copy.common.edit}
          </RetroButton>
          <RetroButton type="button" variant="danger" onClick={handleDelete}>
            {copy.common.delete}
          </RetroButton>
          <RetroButton
            as={Link}
            to={`/app/sharing?folder=${selectedFolderId ?? ''}&goal=${selectedGoalId ?? ''}&task=${selectedTask.id}`}
            variant="ghost"
          >
            Share
          </RetroButton>
          {selectedGoal ? (
            <RetroButton
              as={Link}
              to={`/app/goals?folder=${selectedGoal.folderId}&goal=${selectedGoal.id}`}
              variant="ghost"
            >
              {copy.common.openGoals}
            </RetroButton>
          ) : null}
        </div>
      </div>
    </RetroPanel>
  ) : (
    <EmptyState title={copy.tasks.detailTitle} description={copy.tasks.noFoldersDescription} />
  );

  return (
    <div className="stack">
      <div className="surface-header">
        <div className="stack stack--tight">
          <div className="caps">Planning / F3</div>
          <div className="surface-title">{copy.tasks.title}</div>
          <div className="surface-subtitle">{copy.tasks.subtitle}</div>
        </div>
      </div>

      <PlanningSplitLayout
        sidebar={(
          <RetroPanel
            title={copy.tasks.listTitle}
            aside={(
              <RetroButton
                type="button"
                size="small"
                variant="primary"
                disabled={!selectedGoalId}
                onClick={() => resetForm('create', null)}
              >
                {copy.common.create}
              </RetroButton>
            )}
          >
            {listPanelContent}
          </RetroPanel>
        )}
        detail={detailPanel}
      />
    </div>
  );
}
