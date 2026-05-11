import { useEffect, useMemo, useState } from 'react';
import {
  CalendarClock,
  CheckCircle2,
  ChevronDown,
  Circle,
  Cloud,
  Folder,
  Flag,
  MoreHorizontal,
  PanelRightClose,
  Pencil,
  Plus,
  Search,
  Save,
  StickyNote,
  Target,
  Archive,
  UserCircle,
  X,
} from 'lucide-react';

import { useAuth } from '../../auth';
import { useI18n } from '../../../i18n';
import {
  createFolder,
  createGoal,
  createTask,
  deleteTask,
  listFolders,
  listGoals,
  listTasks,
  updateTask,
} from '../planning-api';
import { usePlanningCopy } from '../planning-copy';
import { mapPlanningError } from '../planning-errors';
import { formatDateTime, fromDateTimeInputValue, toDateTimeInputValue } from '../planning-utils';
import type { FolderDto, GoalDto, TaskDto, TaskStatus, TaskType } from '../types';

type GoalsByFolder = Record<string, GoalDto[]>;
type TasksByGoal = Record<string, TaskDto[]>;

interface VisibleGoal {
  goal: GoalDto;
  tasks: TaskDto[];
  allTasks: TaskDto[];
}

interface VisibleFolder {
  folder: FolderDto;
  goals: VisibleGoal[];
  allGoals: GoalDto[];
  allTasks: TaskDto[];
}

interface Selection {
  folderId: string | null;
  goalId: string | null;
  taskId: string | null;
}

interface TaskDraft {
  title: string;
  description: string;
  type: TaskType;
  status: TaskStatus;
  priority: string;
  plannedTime: string;
  dueTime: string;
}

type MarkerTone = 'green' | 'red' | 'blue' | 'amber' | 'gray';

function toDraft(task: TaskDto | null): TaskDraft {
  return {
    title: task?.title ?? '',
    description: task?.description ?? '',
    type: task?.type ?? 'green',
    status: task?.status ?? 'todo',
    priority: String(task?.priority ?? 2),
    plannedTime: toDateTimeInputValue(task?.plannedTime ?? null),
    dueTime: toDateTimeInputValue(task?.dueTime ?? null),
  };
}

function progress(tasks: TaskDto[]) {
  const done = tasks.filter((task) => task.status === 'done').length;
  return `${done}/${tasks.length}`;
}

function isComplete(task: TaskDto) {
  return task.status === 'done' || task.status === 'cancelled';
}

function progressPercent(tasks: TaskDto[]) {
  if (tasks.length === 0) {
    return 0;
  }

  return (tasks.filter(isComplete).length / tasks.length) * 100;
}

function markerToneForTask(task: TaskDto): MarkerTone {
  if (task.status === 'cancelled') {
    return 'red';
  }

  if (task.status === 'done') {
    return 'gray';
  }

  return task.type === 'red' ? 'red' : 'green';
}

function markerToneForPriority(priority: number): MarkerTone {
  if (priority <= 2) {
    return 'red';
  }

  if (priority <= 5) {
    return 'amber';
  }

  return 'gray';
}

function dayDeltaFromToday(value: string | null) {
  if (!value) {
    return null;
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return null;
  }

  const today = new Date();
  const startOfDay = (item: Date) => new Date(item.getFullYear(), item.getMonth(), item.getDate()).getTime();
  return Math.round((startOfDay(date) - startOfDay(today)) / 86_400_000);
}

function formatDueChip(value: string | null, locale: 'ru' | 'en') {
  const dayDelta = dayDeltaFromToday(value);
  if (dayDelta === null || !value) {
    return '';
  }

  if (dayDelta === 0) {
    return locale === 'ru' ? 'Сегодня' : 'Today';
  }

  if (dayDelta === 1) {
    return locale === 'ru' ? 'Завтра' : 'Tomorrow';
  }

  const date = new Date(value);
  return new Intl.DateTimeFormat(locale === 'ru' ? 'ru-RU' : 'en-US', {
    day: 'numeric',
    month: 'short',
  }).format(date);
}

function dueTone(value: string | null): MarkerTone {
  const dayDelta = dayDeltaFromToday(value);

  if (dayDelta === null) {
    return 'gray';
  }

  if (dayDelta < 0) {
    return 'red';
  }

  if (dayDelta === 0) {
    return 'amber';
  }

  return 'blue';
}

function matchesQuery(value: string | null | undefined, query: string, locale: 'ru' | 'en') {
  return value?.toLocaleLowerCase(locale === 'ru' ? 'ru-RU' : 'en-US').includes(query) ?? false;
}

function describeCreator(task: TaskDto) {
  return task.creatorName || task.creatorEmail || task.creatorUserId || null;
}

function usePlanCopy() {
  const { locale } = useI18n();

  return {
    plan: locale === 'ru' ? 'План' : 'Plan',
    folder: locale === 'ru' ? 'Папка' : 'Folder',
    goal: locale === 'ru' ? 'Цель' : 'Goal',
    task: locale === 'ru' ? 'Задача' : 'Task',
    search: locale === 'ru' ? 'Поиск' : 'Search',
    searchPlaceholder: locale === 'ru' ? 'Найти в плане' : 'Search plan',
    closeSearch: locale === 'ru' ? 'Закрыть поиск' : 'Close search',
    noSearchResults: locale === 'ru' ? 'Ничего не найдено' : 'No results found',
    collapse: locale === 'ru' ? 'Свернуть панель' : 'Close panel',
    add: locale === 'ru' ? 'Создать' : 'Create',
    more: locale === 'ru' ? 'Еще' : 'More',
    newFolder: locale === 'ru' ? 'Новая папка' : 'New folder',
    newGoal: locale === 'ru' ? 'Новая цель' : 'New goal',
    newTask: locale === 'ru' ? 'Новая задача' : 'New task',
    addGoal: locale === 'ru' ? 'Добавьте цель' : 'Add a goal',
    addTask: locale === 'ru' ? 'Добавьте задачу' : 'Add a task',
    emptyTitle: locale === 'ru' ? 'Пока пусто' : 'Nothing here yet',
    emptyBody: locale === 'ru'
      ? 'Создайте папку, затем добавьте цель и задачи.'
      : 'Create a folder, then add a goal and tasks.',
    selectTask: locale === 'ru' ? 'Выберите задачу' : 'Select a task',
    path: locale === 'ru' ? 'Путь' : 'Path',
    notes: locale === 'ru' ? 'Заметки' : 'Notes',
    details: locale === 'ru' ? 'Сведения' : 'Details',
    status: locale === 'ru' ? 'Статус' : 'Status',
    type: locale === 'ru' ? 'Тип' : 'Type',
    priority: locale === 'ru' ? 'Приоритет' : 'Priority',
    planned: locale === 'ru' ? 'План' : 'Planned',
    due: locale === 'ru' ? 'Срок' : 'Due',
    creator: locale === 'ru' ? 'Создатель' : 'Creator',
    archive: locale === 'ru' ? 'В архив' : 'Archive',
    archiveConfirm: locale === 'ru' ? 'Переместить задачу в архив?' : 'Archive this task?',
    synced: locale === 'ru' ? 'Синхронизировано' : 'Synced',
    savedOffline: locale === 'ru' ? 'Сохранено офлайн' : 'Saved offline',
    save: locale === 'ru' ? 'Сохранить' : 'Save',
    loading: locale === 'ru' ? 'Загружаем план' : 'Loading plan',
    loadError: locale === 'ru' ? 'Не удалось загрузить план' : 'Could not load the plan',
    retry: locale === 'ru' ? 'Повторить' : 'Retry',
    folderName: locale === 'ru' ? 'Запуск продукта' : 'Product launch',
    goalName: locale === 'ru' ? 'Мягкий релиз' : 'Soft release',
    taskName: locale === 'ru' ? 'Подготовить страницу входа' : 'Prepare the sign-in screen',
    notesText: locale === 'ru'
      ? 'Уточнить тексты, состояния ошибок и первый пустой экран.'
      : 'Review copy, error states, and the first empty screen.',
  };
}

export function TasksRoute() {
  const { authorizedFetch } = useAuth();
  const { locale } = useI18n();
  const planningCopy = usePlanningCopy();
  const copy = usePlanCopy();
  const [folders, setFolders] = useState<FolderDto[]>([]);
  const [goalsByFolder, setGoalsByFolder] = useState<GoalsByFolder>({});
  const [tasksByGoal, setTasksByGoal] = useState<TasksByGoal>({});
  const [selection, setSelection] = useState<Selection>({ folderId: null, goalId: null, taskId: null });
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [isPanelOpen, setIsPanelOpen] = useState(false);
  const [isCreateMenuOpen, setIsCreateMenuOpen] = useState(false);
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');

  const goals = useMemo(() => Object.values(goalsByFolder).flat(), [goalsByFolder]);
  const tasks = useMemo(() => Object.values(tasksByGoal).flat(), [tasksByGoal]);
  const selectedFolder = folders.find((folder) => folder.id === selection.folderId) ?? null;
  const selectedGoal = goals.find((goal) => goal.id === selection.goalId) ?? null;
  const selectedTask = tasks.find((task) => task.id === selection.taskId) ?? null;
  const [draft, setDraft] = useState<TaskDraft>(() => toDraft(null));
  const normalizedSearch = searchQuery.trim().toLocaleLowerCase(locale === 'ru' ? 'ru-RU' : 'en-US');
  const isSearching = normalizedSearch.length > 0;
  const selectedCreator = selectedTask ? describeCreator(selectedTask) : null;
  const canArchiveSelectedTask = selectedTask ? !selectedTask.shared : false;
  const visiblePlanTree = useMemo<VisibleFolder[]>(() => {
    return folders
      .map((folder) => {
        const allGoals = goalsByFolder[folder.id] ?? [];
        const folderMatches = isSearching && (
          matchesQuery(folder.name, normalizedSearch, locale) ||
          matchesQuery(folder.description, normalizedSearch, locale)
        );
        const visibleGoals = allGoals
          .map((goal) => {
            const allTasks = tasksByGoal[goal.id] ?? [];
            const goalMatches = isSearching && (
              matchesQuery(goal.name, normalizedSearch, locale) ||
              matchesQuery(goal.description, normalizedSearch, locale)
            );
            const visibleTasks = allTasks.filter((task) => {
              if (!isSearching || folderMatches || goalMatches) {
                return true;
              }

              return (
                matchesQuery(task.title, normalizedSearch, locale) ||
                matchesQuery(task.description, normalizedSearch, locale) ||
                matchesQuery(planningCopy.enums.taskStatus[task.status], normalizedSearch, locale) ||
                matchesQuery(planningCopy.enums.taskType[task.type], normalizedSearch, locale) ||
                matchesQuery(describeCreator(task), normalizedSearch, locale)
              );
            });

            return {
              goal,
              tasks: visibleTasks,
              allTasks,
              matches: goalMatches,
            };
          })
          .filter((goal) => !isSearching || folderMatches || goal.matches || goal.tasks.length > 0)
          .map(({ matches, ...goal }) => goal);

        const allTasks = allGoals.flatMap((goal) => tasksByGoal[goal.id] ?? []);

        return {
          folder,
          goals: visibleGoals,
          allGoals,
          allTasks,
          matches: folderMatches,
        };
      })
      .filter((folder) => !isSearching || folder.matches || folder.goals.length > 0)
      .map(({ matches, ...folder }) => folder);
  }, [folders, goalsByFolder, isSearching, locale, normalizedSearch, planningCopy.enums.taskStatus, planningCopy.enums.taskType, tasksByGoal]);
  const rowCopy = {
    complete: locale === 'ru' ? 'Отметить выполненной' : 'Mark complete',
    reopen: locale === 'ru' ? 'Вернуть в работу' : 'Mark active',
    editTask: locale === 'ru' ? 'Изменить задачу' : 'Edit task',
    type: locale === 'ru' ? 'Тип' : 'Type',
  };

  useEffect(() => {
    setDraft(toDraft(selectedTask));
    if (selectedTask) {
      setIsPanelOpen(true);
    }
  }, [selectedTask?.id]);

  async function loadPlan(preferred: Partial<Selection> = {}) {
    setLoading(true);
    setLoadError(null);

    try {
      const nextFolders = await listFolders(authorizedFetch);
      const nextGoalsEntries = await Promise.all(
        nextFolders.map(async (folder) => [folder.id, await listGoals(authorizedFetch, folder.id)] as const),
      );
      const nextGoalsByFolder = Object.fromEntries(nextGoalsEntries);
      const nextGoals = nextGoalsEntries.flatMap(([, folderGoals]) => folderGoals);
      const nextTaskEntries = await Promise.all(
        nextGoals.map(async (goal) => [goal.id, await listTasks(authorizedFetch, goal.id)] as const),
      );
      const nextTasksByGoal = Object.fromEntries(nextTaskEntries);
      const nextTasks = nextTaskEntries.flatMap(([, goalTasks]) => goalTasks);

      const nextFolderId = preferred.folderId ?? selection.folderId ?? nextFolders[0]?.id ?? null;
      const nextGoalId =
        preferred.goalId ??
        selection.goalId ??
        (nextFolderId ? nextGoalsByFolder[nextFolderId]?.[0]?.id : null) ??
        nextGoals[0]?.id ??
        null;
      const nextTaskId =
        preferred.taskId ??
        selection.taskId ??
        (nextGoalId ? nextTasksByGoal[nextGoalId]?.[0]?.id : null) ??
        nextTasks[0]?.id ??
        null;

      setFolders(nextFolders);
      setGoalsByFolder(nextGoalsByFolder);
      setTasksByGoal(nextTasksByGoal);
      setSelection({ folderId: nextFolderId, goalId: nextGoalId, taskId: nextTaskId });
    } catch (error) {
      const mapped = mapPlanningError(error, planningCopy);
      setLoadError(mapped.message);
      setFolders([]);
      setGoalsByFolder({});
      setTasksByGoal({});
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadPlan();
  }, []);

  async function handleCreateFolder() {
    setSaving(true);
    try {
      const folder = await createFolder(authorizedFetch, {
        name: copy.folderName,
        description: '',
      });
      await loadPlan({ folderId: folder.id, goalId: null, taskId: null });
    } finally {
      setSaving(false);
    }
  }

  async function handleCreateGoal(folderId = selection.folderId) {
    if (!folderId) {
      return;
    }

    setSaving(true);
    try {
      const goal = await createGoal(authorizedFetch, folderId, {
        name: copy.goalName,
        description: '',
      });
      await loadPlan({ folderId, goalId: goal.id, taskId: null });
    } finally {
      setSaving(false);
    }
  }

  async function handleCreateTask(goalId = selection.goalId) {
    if (!goalId) {
      return;
    }

    setSaving(true);
    try {
      const task = await createTask(authorizedFetch, goalId, {
        title: copy.taskName,
        description: copy.notesText,
        type: 'green',
        priority: 2,
        status: 'in_progress',
        plannedTime: null,
        dueTime: null,
      });
      const goal = goals.find((item) => item.id === goalId);
      await loadPlan({ folderId: goal?.folderId ?? selection.folderId, goalId, taskId: task.id });
    } finally {
      setSaving(false);
    }
  }

  async function handleSaveTask() {
    if (!selectedTask || !selectedGoal) {
      return;
    }

    const priority = Number(draft.priority);
    if (!draft.title.trim() || !Number.isInteger(priority) || priority < 1 || priority > 10) {
      return;
    }

    setSaving(true);
    try {
      const updated = await updateTask(authorizedFetch, selectedTask.id, {
        title: draft.title.trim(),
        description: draft.description.trim(),
        type: draft.type,
        priority,
        status: draft.status,
        plannedTime: fromDateTimeInputValue(draft.plannedTime),
        dueTime: fromDateTimeInputValue(draft.dueTime),
        archived: selectedTask.archived,
        version: selectedTask.version,
      });

      setTasksByGoal((current) => ({
        ...current,
        [selectedGoal.id]: (current[selectedGoal.id] ?? []).map((task) => (task.id === updated.id ? updated : task)),
      }));
      setSelection((current) => ({ ...current, taskId: updated.id }));
    } finally {
      setSaving(false);
    }
  }

  async function handleToggleTask(task: TaskDto, goal: GoalDto) {
    setSaving(true);
    try {
      const updated = await updateTask(authorizedFetch, task.id, {
        title: task.title,
        description: task.description,
        type: task.type,
        priority: task.priority,
        status: isComplete(task) ? 'todo' : 'done',
        plannedTime: task.plannedTime,
        dueTime: task.dueTime,
        archived: task.archived,
        version: task.version,
      });

      setTasksByGoal((current) => ({
        ...current,
        [goal.id]: (current[goal.id] ?? []).map((item) => (item.id === updated.id ? updated : item)),
      }));
      setSelection({ folderId: goal.folderId, goalId: goal.id, taskId: updated.id });
    } finally {
      setSaving(false);
    }
  }

  async function handleArchiveTask(task: TaskDto, goal: GoalDto) {
    if (!window.confirm(copy.archiveConfirm)) {
      return;
    }

    setSaving(true);
    try {
      await deleteTask(authorizedFetch, task.id);
      const nextGoalTasks = (tasksByGoal[goal.id] ?? []).filter((item) => item.id !== task.id);
      const nextTaskId = nextGoalTasks[0]?.id ?? null;

      setTasksByGoal((current) => ({
        ...current,
        [goal.id]: (current[goal.id] ?? []).filter((item) => item.id !== task.id),
      }));
      setSelection({ folderId: goal.folderId, goalId: goal.id, taskId: nextTaskId });
      if (!nextTaskId) {
        setIsPanelOpen(false);
      }
    } finally {
      setSaving(false);
    }
  }

  const totalTasks = tasks.length;
  const doneTasks = tasks.filter(isComplete).length;

  if (loading) {
    return (
      <div className="planner planner--center">
        <Cloud aria-hidden="true" size={24} strokeWidth={1.75} />
        <span>{copy.loading}</span>
      </div>
    );
  }

  if (loadError) {
    return (
      <div className="planner planner--center">
        <Folder aria-hidden="true" size={28} strokeWidth={1.75} />
        <h1>{copy.loadError}</h1>
        <p>{loadError}</p>
        <button className="button button--primary" type="button" onClick={() => void loadPlan()}>
          {copy.retry}
        </button>
      </div>
    );
  }

  const empty = folders.length === 0;

  return (
    <div className="planner">
      <section className="planner-canvas">
        <header className="planner-header">
          <div>
            <h1>{copy.plan}</h1>
            <div className="planner-header__meta">
              <span>{doneTasks}/{totalTasks}</span>
              <span>{copy.synced}</span>
            </div>
          </div>
          <div className="planner-toolbar">
            {isSearchOpen ? (
              <>
                <input
                  className="field__control"
                  type="search"
                  value={searchQuery}
                  aria-label={copy.search}
                  placeholder={copy.searchPlaceholder}
                  autoFocus
                  style={{ minHeight: 40, width: 'min(46vw, 220px)' }}
                  onChange={(event) => setSearchQuery(event.target.value)}
                />
                <button
                  className="icon-button"
                  type="button"
                  aria-label={copy.closeSearch}
                  title={copy.closeSearch}
                  onClick={() => {
                    setSearchQuery('');
                    setIsSearchOpen(false);
                  }}
                >
                  <X aria-hidden="true" size={18} strokeWidth={1.75} />
                </button>
              </>
            ) : (
              <button
                className="icon-button"
                type="button"
                aria-label={copy.search}
                title={copy.search}
                onClick={() => setIsSearchOpen(true)}
              >
                <Search aria-hidden="true" size={18} strokeWidth={1.75} />
              </button>
            )}
            <div className="create-menu">
              <button
                className="icon-button"
                type="button"
                aria-label={copy.add}
                title={copy.add}
                disabled={saving}
                aria-haspopup="menu"
                aria-expanded={isCreateMenuOpen}
                onClick={() => setIsCreateMenuOpen((current) => !current)}
              >
                <Plus aria-hidden="true" size={20} strokeWidth={1.75} />
              </button>
              {isCreateMenuOpen ? (
                <div className="create-menu__panel" role="menu">
                  <button type="button" role="menuitem" onClick={() => { setIsCreateMenuOpen(false); void handleCreateFolder(); }}>
                    <Folder aria-hidden="true" size={16} strokeWidth={1.75} />
                    <span>{copy.folder}</span>
                  </button>
                  <button type="button" role="menuitem" disabled={!selection.folderId} onClick={() => { setIsCreateMenuOpen(false); void handleCreateGoal(); }}>
                    <Target aria-hidden="true" size={16} strokeWidth={1.75} />
                    <span>{copy.goal}</span>
                  </button>
                  <button type="button" role="menuitem" disabled={!selection.goalId} onClick={() => { setIsCreateMenuOpen(false); void handleCreateTask(); }}>
                    <Circle aria-hidden="true" size={16} strokeWidth={1.75} />
                    <span>{copy.task}</span>
                  </button>
                </div>
              ) : null}
            </div>
          </div>
        </header>

        {empty ? (
          <div className="planner-empty">
            <Folder aria-hidden="true" size={34} strokeWidth={1.75} />
            <h2>{copy.emptyTitle}</h2>
            <p>{copy.emptyBody}</p>
            <button className="button button--primary" type="button" disabled={saving} onClick={() => void handleCreateFolder()}>
              {copy.newFolder}
            </button>
          </div>
        ) : isSearching && visiblePlanTree.length === 0 ? (
          <div className="planner-empty">
            <Search aria-hidden="true" size={34} strokeWidth={1.75} />
            <h2>{copy.noSearchResults}</h2>
          </div>
        ) : (
          <div className="plan-tree" role="tree" aria-label={copy.plan}>
            {visiblePlanTree.map(({ folder, goals: folderGoals, allGoals, allTasks: folderTasks }) => {
              const firstGoal = allGoals[0] ?? null;

              return (
                <div className="plan-tree__group" key={folder.id}>
                  <button
                    type="button"
                    className={`plan-row plan-row--folder${selection.folderId === folder.id && !selection.taskId ? ' is-selected' : ''}`}
                    onClick={() => setSelection({ folderId: folder.id, goalId: firstGoal?.id ?? null, taskId: null })}
                    role="treeitem"
                    aria-expanded="true"
                  >
                    <ChevronDown aria-hidden="true" size={16} strokeWidth={1.75} />
                    <Folder aria-hidden="true" size={18} strokeWidth={1.75} />
                    <span className="plan-row__title">{folder.name}</span>
                    <span className="plan-row__meta">{folderTasks.length ? progress(folderTasks) : '0'}</span>
                    <span className="plan-row__actions">
                      <span className="plan-row__icon" title={copy.newGoal}>
                        <Plus size={15} strokeWidth={1.75} />
                      </span>
                      <span className="plan-row__icon" title={copy.more}>
                        <MoreHorizontal size={15} strokeWidth={1.75} />
                      </span>
                    </span>
                  </button>

                  {allGoals.length === 0 ? (
                    <button type="button" className="plan-row plan-row--inline" onClick={() => void handleCreateGoal(folder.id)}>
                      <Plus aria-hidden="true" size={16} strokeWidth={1.75} />
                      <span>{copy.addGoal}</span>
                    </button>
                  ) : null}

                  {folderGoals.map(({ goal, tasks: goalTasks, allTasks: allGoalTasks }) => {
                    return (
                      <div className="plan-tree__group" key={goal.id}>
                        <button
                          type="button"
                          className={`plan-row plan-row--goal${selection.goalId === goal.id && !selection.taskId ? ' is-selected' : ''}`}
                          onClick={() => setSelection({ folderId: folder.id, goalId: goal.id, taskId: allGoalTasks[0]?.id ?? null })}
                          role="treeitem"
                          aria-expanded="true"
                        >
                          <ChevronDown aria-hidden="true" size={16} strokeWidth={1.75} />
                          <Target aria-hidden="true" size={18} strokeWidth={1.75} />
                          <span className="plan-row__main">
                            <span className="plan-row__title">{goal.name}</span>
                            <span className="plan-row__progress" aria-hidden="true">
                              <span style={{ width: `${progressPercent(allGoalTasks)}%` }} />
                            </span>
                          </span>
                          <span className="plan-row__meta">{progress(allGoalTasks)}</span>
                          <span className="plan-row__actions">
                            <span className="plan-row__icon" title={copy.newTask}>
                              <Plus size={15} strokeWidth={1.75} />
                            </span>
                            <span className="plan-row__icon" title={copy.more}>
                              <MoreHorizontal size={15} strokeWidth={1.75} />
                            </span>
                          </span>
                        </button>

                        {allGoalTasks.length === 0 ? (
                          <button type="button" className="plan-row plan-row--inline plan-row--task" onClick={() => void handleCreateTask(goal.id)}>
                            <Plus aria-hidden="true" size={16} strokeWidth={1.75} />
                            <span>{copy.addTask}</span>
                          </button>
                        ) : null}

                        {goalTasks.map((task) => {
                          const dueChip = formatDueChip(task.dueTime, locale);
                          const complete = isComplete(task);
                          const statusLabel = planningCopy.enums.taskStatus[task.status];
                          const typeLabel = planningCopy.enums.taskType[task.type];
                          const priorityLabel = `${copy.priority} ${task.priority}`;
                          const canArchiveTask = !task.shared;

                          return (
                            <div
                              key={task.id}
                              className={`plan-row plan-row--task${selection.taskId === task.id ? ' is-selected' : ''}${complete ? ' is-complete' : ''}`}
                              role="treeitem"
                              aria-selected={selection.taskId === task.id}
                            >
                              <button
                                type="button"
                                className="plan-row__check"
                                aria-label={complete ? rowCopy.reopen : rowCopy.complete}
                                title={complete ? rowCopy.reopen : rowCopy.complete}
                                disabled={saving}
                                onClick={() => void handleToggleTask(task, goal)}
                              >
                                {complete ? (
                                  <CheckCircle2 aria-hidden="true" size={17} strokeWidth={1.75} />
                                ) : (
                                  <Circle aria-hidden="true" size={17} strokeWidth={1.75} />
                                )}
                              </button>
                              <button
                                type="button"
                                className="plan-row__content"
                                onClick={() => setSelection({ folderId: folder.id, goalId: goal.id, taskId: task.id })}
                              >
                                <span
                                  className={`marker-dot marker-dot--${markerToneForTask(task)}`}
                                  aria-label={`${rowCopy.type}: ${typeLabel}. ${copy.status}: ${statusLabel}`}
                                  title={`${typeLabel} / ${statusLabel}`}
                                />
                                <span className="plan-row__title">{task.title}</span>
                              </button>
                              {dueChip ? (
                                <span className={`due-chip due-chip--${dueTone(task.dueTime)}`} title={formatDateTime(task.dueTime, locale)}>
                                  {dueChip}
                                </span>
                              ) : null}
                              <span
                                className={`priority-dot priority-dot--${markerToneForPriority(task.priority)}`}
                                aria-label={priorityLabel}
                                title={priorityLabel}
                              />
                              <span className="plan-row__actions">
                                <button
                                  type="button"
                                  className="plan-row__icon"
                                  aria-label={rowCopy.editTask}
                                  title={rowCopy.editTask}
                                  onClick={() => setSelection({ folderId: folder.id, goalId: goal.id, taskId: task.id })}
                                >
                                  <Pencil size={14} strokeWidth={1.75} />
                                </button>
                                {canArchiveTask ? (
                                  <button
                                    type="button"
                                    className="plan-row__icon"
                                    aria-label={copy.archive}
                                    title={copy.archive}
                                    disabled={saving}
                                    onClick={() => void handleArchiveTask(task, goal)}
                                  >
                                    <Archive size={15} strokeWidth={1.75} />
                                  </button>
                                ) : null}
                              </span>
                            </div>
                          );
                        })}
                      </div>
                    );
                  })}
                </div>
              );
            })}
          </div>
        )}
      </section>

      <aside className={`detail-panel${isPanelOpen ? ' is-open' : ''}`}>
        {selectedTask && selectedGoal && selectedFolder ? (
          <>
            <header className="detail-panel__header">
              <div>
                <h2>{selectedTask.title}</h2>
                <div className="detail-panel__badges" aria-label={copy.details}>
                  <span className="meta-chip" title={copy.status}>
                    <span className={`marker-dot marker-dot--${markerToneForTask(selectedTask)}`} aria-hidden="true" />
                    {planningCopy.enums.taskStatus[selectedTask.status]}
                  </span>
                  <span className="meta-chip" title={rowCopy.type}>
                    <span className={`marker-dot marker-dot--${selectedTask.type === 'red' ? 'red' : 'green'}`} aria-hidden="true" />
                    {planningCopy.enums.taskType[selectedTask.type]}
                  </span>
                  <span className="meta-chip" title={copy.priority}>
                    <Flag aria-hidden="true" size={14} strokeWidth={1.75} />
                    P{selectedTask.priority}
                  </span>
                  {selectedTask.dueTime ? (
                    <span className={`meta-chip meta-chip--${dueTone(selectedTask.dueTime)}`} title={copy.due}>
                      <CalendarClock aria-hidden="true" size={14} strokeWidth={1.75} />
                      {formatDateTime(selectedTask.dueTime, locale)}
                    </span>
                  ) : null}
                  {selectedTask.plannedTime ? (
                    <span className="meta-chip" title={copy.planned}>
                      <CalendarClock aria-hidden="true" size={14} strokeWidth={1.75} />
                      {formatDateTime(selectedTask.plannedTime, locale)}
                    </span>
                  ) : null}
                </div>
              </div>
              <div className="cluster" style={{ justifyContent: 'flex-end' }}>
                {canArchiveSelectedTask ? (
                  <button
                    className="icon-button"
                    type="button"
                    aria-label={copy.archive}
                    title={copy.archive}
                    disabled={saving}
                    onClick={() => void handleArchiveTask(selectedTask, selectedGoal)}
                  >
                    <Archive aria-hidden="true" size={18} strokeWidth={1.75} />
                  </button>
                ) : null}
                <button className="icon-button" type="button" aria-label={copy.collapse} title={copy.collapse} onClick={() => setIsPanelOpen(false)}>
                  <PanelRightClose aria-hidden="true" size={19} strokeWidth={1.75} />
                </button>
              </div>
            </header>

            <div className="detail-panel__body">
              <div className="detail-section">
                <div className="detail-label">{copy.path}</div>
                <div className="breadcrumb">
                  <Folder aria-hidden="true" size={15} strokeWidth={1.75} />
                  <span>{selectedFolder.name} / {selectedGoal.name}</span>
                </div>
              </div>

              {selectedCreator ? (
                <div className="detail-section">
                  <div className="detail-label">{copy.creator}</div>
                  <div className="breadcrumb">
                    <UserCircle aria-hidden="true" size={15} strokeWidth={1.75} />
                    <span>{selectedCreator}</span>
                  </div>
                </div>
              ) : null}

              <div className="detail-section">
                <div className="detail-label">{copy.notes}</div>
                <div className="detail-note">
                  <StickyNote aria-hidden="true" size={15} strokeWidth={1.75} />
                  <p>{selectedTask.description || planningCopy.common.noDescription}</p>
                </div>
              </div>

              <details className="detail-disclosure" open>
                <summary>{copy.details}</summary>
                <div className="detail-editor">
                  <label className="field detail-grid__wide">
                    <span>{copy.task}</span>
                    <input className="field__control" value={draft.title} onChange={(event) => setDraft((current) => ({ ...current, title: event.target.value }))} />
                  </label>
                  <label className="field detail-grid__wide">
                    <span>{copy.notes}</span>
                    <textarea className="field__control field__control--area" value={draft.description} onChange={(event) => setDraft((current) => ({ ...current, description: event.target.value }))} />
                  </label>
                  <label className="field">
                    <span>{copy.type}</span>
                    <select className="field__control" value={draft.type} onChange={(event) => setDraft((current) => ({ ...current, type: event.target.value as TaskType }))}>
                      <option value="green">{planningCopy.enums.taskType.green}</option>
                      <option value="red">{planningCopy.enums.taskType.red}</option>
                    </select>
                  </label>
                  <label className="field">
                    <span>{copy.status}</span>
                    <select className="field__control" value={draft.status} onChange={(event) => setDraft((current) => ({ ...current, status: event.target.value as TaskStatus }))}>
                      <option value="todo">{planningCopy.enums.taskStatus.todo}</option>
                      <option value="in_progress">{planningCopy.enums.taskStatus.in_progress}</option>
                      <option value="done">{planningCopy.enums.taskStatus.done}</option>
                      <option value="cancelled">{planningCopy.enums.taskStatus.cancelled}</option>
                    </select>
                  </label>
                  <label className="field">
                    <span>{copy.priority}</span>
                    <input className="field__control" type="number" min={1} max={10} value={draft.priority} onChange={(event) => setDraft((current) => ({ ...current, priority: event.target.value }))} />
                  </label>
                  <label className="field">
                    <span>{copy.planned}</span>
                    <input className="field__control" type="datetime-local" value={draft.plannedTime} onChange={(event) => setDraft((current) => ({ ...current, plannedTime: event.target.value }))} />
                  </label>
                  <label className="field detail-grid__wide">
                    <span>{copy.due}</span>
                    <input className="field__control" type="datetime-local" value={draft.dueTime} onChange={(event) => setDraft((current) => ({ ...current, dueTime: event.target.value }))} />
                  </label>
                  <div className="cluster detail-grid__wide">
                    <button className="button button--primary" type="button" disabled={saving} onClick={() => void handleSaveTask()}>
                      <Save aria-hidden="true" size={16} strokeWidth={1.75} />
                      <span>{copy.save}</span>
                    </button>
                    {canArchiveSelectedTask ? (
                      <button className="button button--ghost" type="button" disabled={saving} onClick={() => void handleArchiveTask(selectedTask, selectedGoal)}>
                        <Archive aria-hidden="true" size={16} strokeWidth={1.75} />
                        <span>{copy.archive}</span>
                      </button>
                    ) : null}
                  </div>
                </div>
                <dl>
                  <div>
                    <dt>{copy.synced}</dt>
                    <dd>{formatDateTime(selectedTask.updatedAt, locale)}</dd>
                  </div>
                  <div>
                    <dt>{planningCopy.common.createdAt}</dt>
                    <dd>{formatDateTime(selectedTask.createdAt, locale)}</dd>
                  </div>
                </dl>
              </details>
            </div>
          </>
        ) : (
          <div className="detail-empty">
            <Circle aria-hidden="true" size={28} strokeWidth={1.75} />
            <span>{copy.selectTask}</span>
          </div>
        )}
      </aside>
    </div>
  );
}
