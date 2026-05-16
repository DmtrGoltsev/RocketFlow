import { useEffect, useMemo, useState } from 'react';
import {
  CalendarClock,
  CheckCircle2,
  ChevronDown,
  Circle,
  Cloud,
  Folder,
  Flag,
  Lightbulb,
  ListChecks,
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
  createFolderNote,
  createFolderNoteItem,
  createGoal,
  createIdea,
  createIdeaNote,
  createTask,
  deleteIdea,
  deleteTask,
  listFolderNotes,
  listFolders,
  listGoals,
  listIdeaNotes,
  listIdeas,
  listTasks,
  updateFolderNote,
  updateFolderNoteItem,
  updateIdea,
  updateTask,
} from '../planning-api';
import { getSharedResources } from '../../advanced/advanced-api';
import { usePlanningCopy } from '../planning-copy';
import { mapPlanningError } from '../planning-errors';
import { formatDateTime, fromDateTimeInputValue, toDateTimeInputValue } from '../planning-utils';
import type { FolderDto, FolderNoteDto, GoalDto, IdeaDto, IdeaNoteDto, TaskDto, TaskStatus, TaskType } from '../types';
import type { SharedResourcesResponse } from '../../advanced/types';

type PlanFolder = FolderDto & { shared?: boolean };
type GoalsByFolder = Record<string, GoalDto[]>;
type TasksByGoal = Record<string, TaskDto[]>;
type IdeasByFolder = Record<string, IdeaDto[]>;
type FolderNotesByFolder = Record<string, FolderNoteDto[]>;
type IdeaNotesByIdea = Record<string, IdeaNoteDto[]>;

interface VisibleGoal {
  goal: GoalDto;
  tasks: TaskDto[];
  allTasks: TaskDto[];
}

interface VisibleFolder {
  folder: PlanFolder;
  goals: VisibleGoal[];
  ideas: IdeaDto[];
  folderNotes: FolderNoteDto[];
  allGoals: GoalDto[];
  allTasks: TaskDto[];
  allIdeas: IdeaDto[];
  allFolderNotes: FolderNoteDto[];
}

interface Selection {
  folderId: string | null;
  goalId: string | null;
  taskId: string | null;
  ideaId: string | null;
  folderNoteId: string | null;
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

interface IdeaDraft {
  title: string;
  description: string;
}

interface FolderNoteDraft {
  title: string;
  body: string;
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

function toIdeaDraft(idea: IdeaDto | null): IdeaDraft {
  return {
    title: idea?.title ?? '',
    description: idea?.body ?? '',
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

function mergeById<TItem extends { id: string }>(primary: TItem[], secondary: TItem[]) {
  const merged = new Map<string, TItem>();
  [...primary, ...secondary].forEach((item) => merged.set(item.id, item));
  return Array.from(merged.values());
}

function groupGoalsByFolder(goals: GoalDto[]) {
  return goals.reduce<GoalsByFolder>((groups, goal) => {
    groups[goal.folderId] = [...(groups[goal.folderId] ?? []), goal];
    return groups;
  }, {});
}

function groupTasksByGoal(tasks: TaskDto[]) {
  return tasks.reduce<TasksByGoal>((groups, task) => {
    groups[task.goalId] = [...(groups[task.goalId] ?? []), task];
    return groups;
  }, {});
}

function groupIdeasByFolder(ideas: IdeaDto[]) {
  return ideas.reduce<IdeasByFolder>((groups, idea) => {
    groups[idea.folderId] = [...(groups[idea.folderId] ?? []), idea];
    return groups;
  }, {});
}

function groupFolderNotesByFolder(notes: FolderNoteDto[]) {
  return notes.reduce<FolderNotesByFolder>((groups, note) => {
    groups[note.folderId] = [...(groups[note.folderId] ?? []), note];
    return groups;
  }, {});
}

function describeIdeaAuthor(note: IdeaNoteDto) {
  return note.authorName || note.authorEmail || note.authorUserId || null;
}

function usePlanCopy() {
  const { locale } = useI18n();

  return {
    plan: locale === 'ru' ? 'План' : 'Plan',
    folder: locale === 'ru' ? 'Папка' : 'Folder',
    goal: locale === 'ru' ? 'Цель' : 'Goal',
    task: locale === 'ru' ? 'Задача' : 'Task',
    idea: locale === 'ru' ? 'Идея' : 'Idea',
    folderNote: locale === 'ru' ? 'Заметка папки' : 'Folder note',
    folderList: locale === 'ru' ? 'Список папки' : 'Folder list',
    ideas: locale === 'ru' ? 'Идеи' : 'Ideas',
    folderNotes: locale === 'ru' ? 'Заметки и списки папки' : 'Folder notes and lists',
    ideaHistory: locale === 'ru' ? 'История мыслей' : 'Thought history',
    search: locale === 'ru' ? 'Поиск' : 'Search',
    searchPlaceholder: locale === 'ru' ? 'Найти в плане' : 'Search plan',
    closeSearch: locale === 'ru' ? 'Закрыть поиск' : 'Close search',
    noSearchResults: locale === 'ru' ? 'Ничего не найдено' : 'No results found',
    collapse: locale === 'ru' ? 'Свернуть панель' : 'Close panel',
    add: locale === 'ru' ? 'Создать' : 'Create',
    shared: locale === 'ru' ? 'Общие' : 'Shared',
    sharedResource: locale === 'ru' ? 'Общий доступ' : 'Shared',
    more: locale === 'ru' ? 'Еще' : 'More',
    newFolder: locale === 'ru' ? 'Новая папка' : 'New folder',
    newGoal: locale === 'ru' ? 'Новая цель' : 'New goal',
    newTask: locale === 'ru' ? 'Новая задача' : 'New task',
    newIdea: locale === 'ru' ? 'Новая идея' : 'New idea',
    newFolderNote: locale === 'ru' ? 'Новая заметка' : 'New note',
    newFolderList: locale === 'ru' ? 'Новый список' : 'New list',
    addGoal: locale === 'ru' ? 'Добавьте цель' : 'Add a goal',
    addTask: locale === 'ru' ? 'Добавьте задачу' : 'Add a task',
    emptyTitle: locale === 'ru' ? 'Пока пусто' : 'Nothing here yet',
    emptyBody: locale === 'ru'
      ? 'Создайте папку, затем добавьте цель и задачи.'
      : 'Create a folder, then add a goal and tasks.',
    selectTask: locale === 'ru' ? 'Выберите задачу' : 'Select a task',
    selectItem: locale === 'ru' ? 'Выберите задачу, идею или папку' : 'Select a task, idea, or folder',
    path: locale === 'ru' ? 'Путь' : 'Path',
    notes: locale === 'ru' ? 'Заметки' : 'Notes',
    details: locale === 'ru' ? 'Сведения' : 'Details',
    status: locale === 'ru' ? 'Статус' : 'Status',
    type: locale === 'ru' ? 'Тип' : 'Type',
    priority: locale === 'ru' ? 'Приоритет' : 'Priority',
    planned: locale === 'ru' ? 'Когда делать' : 'Planned',
    due: locale === 'ru' ? 'Дедлайн' : 'Due',
    creator: locale === 'ru' ? 'Создатель' : 'Creator',
    archive: locale === 'ru' ? 'В архив' : 'Archive',
    archiveConfirm: locale === 'ru' ? 'Переместить задачу в архив?' : 'Archive this task?',
    archiveIdeaConfirm: locale === 'ru' ? 'Удалить идею?' : 'Delete this idea?',
    synced: locale === 'ru' ? 'Синхронизировано' : 'Synced',
    savedOffline: locale === 'ru' ? 'Сохранено офлайн' : 'Saved offline',
    save: locale === 'ru' ? 'Сохранить' : 'Save',
    loading: locale === 'ru' ? 'Загружаем план' : 'Loading plan',
    loadError: locale === 'ru' ? 'Не удалось загрузить план' : 'Could not load the plan',
    retry: locale === 'ru' ? 'Повторить' : 'Retry',
    folderName: locale === 'ru' ? 'Запуск продукта' : 'Product launch',
    goalName: locale === 'ru' ? 'Мягкий релиз' : 'Soft release',
    taskName: locale === 'ru' ? 'Подготовить страницу входа' : 'Prepare the sign-in screen',
    ideaName: locale === 'ru' ? 'Новая идея' : 'New idea',
    folderNoteName: locale === 'ru' ? 'Общая заметка' : 'Shared note',
    folderListName: locale === 'ru' ? 'Новый список' : 'New list',
    notePlaceholder: locale === 'ru' ? 'Запишите мысль или контекст' : 'Write a thought or context',
    listItemPlaceholder: locale === 'ru' ? 'Новый пункт списка' : 'New list item',
    addNote: locale === 'ru' ? 'Добавить заметку' : 'Add note',
    addListItem: locale === 'ru' ? 'Добавить пункт' : 'Add item',
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
  const [folders, setFolders] = useState<PlanFolder[]>([]);
  const [goalsByFolder, setGoalsByFolder] = useState<GoalsByFolder>({});
  const [tasksByGoal, setTasksByGoal] = useState<TasksByGoal>({});
  const [ideasByFolder, setIdeasByFolder] = useState<IdeasByFolder>({});
  const [folderNotesByFolder, setFolderNotesByFolder] = useState<FolderNotesByFolder>({});
  const [ideaNotesByIdea, setIdeaNotesByIdea] = useState<IdeaNotesByIdea>({});
  const [createTaskGoalIds, setCreateTaskGoalIds] = useState<Set<string>>(() => new Set());
  const [selection, setSelection] = useState<Selection>({
    folderId: null,
    goalId: null,
    taskId: null,
    ideaId: null,
    folderNoteId: null,
  });
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [isPanelOpen, setIsPanelOpen] = useState(false);
  const [createTaskGoalId, setCreateTaskGoalId] = useState<string | null>(null);
  const [isCreateMenuOpen, setIsCreateMenuOpen] = useState(false);
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [ideaDraft, setIdeaDraft] = useState<IdeaDraft>(() => toIdeaDraft(null));
  const [ideaNoteDraft, setIdeaNoteDraft] = useState('');
  const [folderNoteDraft, setFolderNoteDraft] = useState<FolderNoteDraft>({ title: '', body: '' });
  const [folderNoteItemDraft, setFolderNoteItemDraft] = useState('');

  const goals = useMemo(() => Object.values(goalsByFolder).flat(), [goalsByFolder]);
  const tasks = useMemo(() => Object.values(tasksByGoal).flat(), [tasksByGoal]);
  const ideas = useMemo(() => Object.values(ideasByFolder).flat(), [ideasByFolder]);
  const folderNotes = useMemo(() => Object.values(folderNotesByFolder).flat(), [folderNotesByFolder]);
  const selectedFolder = folders.find((folder) => folder.id === selection.folderId) ?? null;
  const selectedGoal = goals.find((goal) => goal.id === selection.goalId) ?? null;
  const selectedTask = tasks.find((task) => task.id === selection.taskId) ?? null;
  const selectedIdea = ideas.find((idea) => idea.id === selection.ideaId) ?? null;
  const selectedFolderNote = folderNotes.find((note) => note.id === selection.folderNoteId) ?? null;
  const selectedIdeaNotes = selectedIdea ? ideaNotesByIdea[selectedIdea.id] ?? [] : [];
  const [draft, setDraft] = useState<TaskDraft>(() => toDraft(null));
  const taskCreationGoal = goals.find((goal) => goal.id === createTaskGoalId) ?? null;
  const taskCreationFolder = taskCreationGoal
    ? folders.find((folder) => folder.id === taskCreationGoal.folderId) ?? null
    : null;
  const isCreatingTask = Boolean(createTaskGoalId);
  const panelGoal = isCreatingTask ? taskCreationGoal : selectedGoal;
  const panelFolder = isCreatingTask ? taskCreationFolder : selectedFolder;
  const normalizedSearch = searchQuery.trim().toLocaleLowerCase(locale === 'ru' ? 'ru-RU' : 'en-US');
  const isSearching = normalizedSearch.length > 0;
  const selectedCreator = !isCreatingTask && selectedTask ? describeCreator(selectedTask) : null;
  const canArchiveSelectedTask = !isCreatingTask && selectedTask ? !selectedTask.shared : false;
  const canEditSelectedTaskFields = isCreatingTask || (selectedTask ? !selectedTask.shared : false);
  const canEditSelectedIdea = selectedIdea ? !selectedIdea.shared : false;
  const canCreateGoalInFolder = (folder: PlanFolder | null) => Boolean(folder && !folder.shared);
  const canCreateTaskInGoal = (goal: GoalDto | null) => Boolean(goal && (!goal.shared || createTaskGoalIds.has(goal.id)));
  const canCreateFolderResource = (folder: PlanFolder | null) => Boolean(folder && !folder.shared);
  const visiblePlanTree = useMemo<VisibleFolder[]>(() => {
    return folders
      .map((folder) => {
        const allGoals = goalsByFolder[folder.id] ?? [];
        const allIdeas = ideasByFolder[folder.id] ?? [];
        const allFolderNotes = folderNotesByFolder[folder.id] ?? [];
        const folderMatches = isSearching && (
          matchesQuery(folder.name, normalizedSearch, locale) ||
          matchesQuery(folder.description, normalizedSearch, locale)
        );
        const visibleIdeas = allIdeas.filter((idea) => {
          if (!isSearching || folderMatches) {
            return true;
          }

          return (
            matchesQuery(idea.title, normalizedSearch, locale) ||
            matchesQuery(idea.body, normalizedSearch, locale)
          );
        });
        const visibleFolderNotes = allFolderNotes.filter((note) => {
          if (!isSearching || folderMatches) {
            return true;
          }

          return (
            matchesQuery(note.title, normalizedSearch, locale) ||
            matchesQuery(note.body, normalizedSearch, locale) ||
            note.items.some((item) => matchesQuery(item.text, normalizedSearch, locale))
          );
        });
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
          ideas: visibleIdeas,
          folderNotes: visibleFolderNotes,
          allGoals,
          allTasks,
          allIdeas,
          allFolderNotes,
          matches: folderMatches,
        };
      })
      .filter((folder) => (
        !isSearching ||
        folder.matches ||
        folder.goals.length > 0 ||
        folder.ideas.length > 0 ||
        folder.folderNotes.length > 0
      ))
      .map(({ matches, ...folder }) => folder);
  }, [
    folderNotesByFolder,
    folders,
    goalsByFolder,
    ideasByFolder,
    isSearching,
    locale,
    normalizedSearch,
    planningCopy.enums.taskStatus,
    planningCopy.enums.taskType,
    tasksByGoal,
  ]);
  const rowCopy = {
    complete: locale === 'ru' ? 'Отметить выполненной' : 'Mark complete',
    reopen: locale === 'ru' ? 'Вернуть в работу' : 'Mark active',
    editTask: locale === 'ru' ? 'Изменить задачу' : 'Edit task',
    type: locale === 'ru' ? 'Тип' : 'Type',
  };

  useEffect(() => {
    if (!isCreatingTask) {
      setDraft(toDraft(selectedTask));
    }
  }, [isCreatingTask, selectedTask?.id]);

  useEffect(() => {
    setIdeaDraft(toIdeaDraft(selectedIdea));
    setIdeaNoteDraft('');
  }, [selectedIdea?.id]);

  useEffect(() => {
    setFolderNoteDraft({
      title: selectedFolderNote?.title ?? '',
      body: selectedFolderNote?.body ?? '',
    });
    setFolderNoteItemDraft('');
  }, [selectedFolderNote?.id]);

  async function loadPlan(preferred: Partial<Selection> = {}) {
    setLoading(true);
    setLoadError(null);

    try {
      const [ownedFolders, sharedResources] = await Promise.all([
        listFolders(authorizedFetch),
        getSharedResources(authorizedFetch).catch((): SharedResourcesResponse => ({
          folders: [],
          goals: [],
          tasks: [],
          createTaskGoalIds: [],
        })),
      ]);
      const nextGoalsEntries = await Promise.all(
        ownedFolders.map(async (folder) => [folder.id, await listGoals(authorizedFetch, folder.id)] as const),
      );
      const ownedGoals = nextGoalsEntries.flatMap(([, folderGoals]) => folderGoals);
      const nextTaskEntries = await Promise.all(
        ownedGoals.map(async (goal) => [goal.id, await listTasks(authorizedFetch, goal.id)] as const),
      );
      const ownedTasks = nextTaskEntries.flatMap(([, goalTasks]) => goalTasks);
      const nextFolders = mergeById<PlanFolder>(
        ownedFolders.map((folder) => ({ ...folder, shared: false })),
        (sharedResources.folders ?? []).map((folder) => ({ ...folder, shared: true })),
      );
      const [nextIdeaEntries, nextFolderNoteEntries] = await Promise.all([
        Promise.all(
          nextFolders.map(async (folder) => [
            folder.id,
            await listIdeas(authorizedFetch, folder.id).catch(() => []),
          ] as const),
        ),
        Promise.all(
          nextFolders.map(async (folder) => [
            folder.id,
            await listFolderNotes(authorizedFetch, folder.id).catch(() => []),
          ] as const),
        ),
      ]);
      const nextGoals = mergeById(ownedGoals, sharedResources.goals ?? []);
      const nextTasks = mergeById(ownedTasks, sharedResources.tasks ?? []);
      const nextIdeas = nextIdeaEntries.flatMap(([, folderIdeas]) => folderIdeas);
      const nextFolderNotes = nextFolderNoteEntries.flatMap(([, notes]) => notes);
      const nextGoalsByFolder = groupGoalsByFolder(nextGoals);
      const nextTasksByGoal = groupTasksByGoal(nextTasks);
      const nextIdeasByFolder = groupIdeasByFolder(nextIdeas);
      const nextFolderNotesByFolder = groupFolderNotesByFolder(nextFolderNotes);

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
      const nextIdeaId = preferred.ideaId ?? (preferred.taskId !== undefined ? null : selection.ideaId) ?? null;
      const nextFolderNoteId = preferred.folderNoteId ?? (
        preferred.taskId !== undefined || preferred.ideaId !== undefined ? null : selection.folderNoteId
      ) ?? null;

      setFolders(nextFolders);
      setGoalsByFolder(nextGoalsByFolder);
      setTasksByGoal(nextTasksByGoal);
      setIdeasByFolder(nextIdeasByFolder);
      setFolderNotesByFolder(nextFolderNotesByFolder);
      setCreateTaskGoalIds(new Set(sharedResources.createTaskGoalIds ?? []));
      setSelection({
        folderId: nextFolderId,
        goalId: nextGoalId,
        taskId: preferred.ideaId !== undefined || preferred.folderNoteId !== undefined ? null : nextTaskId,
        ideaId: nextIdeaId,
        folderNoteId: nextFolderNoteId,
      });
    } catch (error) {
      const mapped = mapPlanningError(error, planningCopy);
      setLoadError(mapped.message);
      setFolders([]);
      setGoalsByFolder({});
      setTasksByGoal({});
      setIdeasByFolder({});
      setFolderNotesByFolder({});
      setIdeaNotesByIdea({});
      setCreateTaskGoalIds(new Set());
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadPlan();
  }, []);

  useEffect(() => {
    if (!selectedIdea || ideaNotesByIdea[selectedIdea.id]) {
      return;
    }

    void listIdeaNotes(authorizedFetch, selectedIdea.id)
      .then((notes) => {
        setIdeaNotesByIdea((current) => ({ ...current, [selectedIdea.id]: notes }));
      })
      .catch(() => {
        setIdeaNotesByIdea((current) => ({ ...current, [selectedIdea.id]: [] }));
      });
  }, [authorizedFetch, ideaNotesByIdea, selectedIdea]);

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
    const targetFolder = folders.find((folder) => folder.id === folderId) ?? null;
    if (!folderId || !canCreateGoalInFolder(targetFolder)) {
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
    const targetGoal = goals.find((goal) => goal.id === goalId) ?? null;
    if (!goalId || !targetGoal || !canCreateTaskInGoal(targetGoal)) {
      return;
    }

    setCreateTaskGoalId(goalId);
    setSelection({ folderId: targetGoal.folderId, goalId, taskId: null, ideaId: null, folderNoteId: null });
    setDraft(toDraft(null));
    setIsPanelOpen(true);
  }

  async function handleCreateIdea(folderId = selection.folderId) {
    const targetFolder = folders.find((folder) => folder.id === folderId) ?? null;
    if (!folderId || !canCreateFolderResource(targetFolder)) {
      return;
    }

    setSaving(true);
    try {
      const idea = await createIdea(authorizedFetch, folderId, {
        title: copy.ideaName,
        body: '',
      });

      setIdeasByFolder((current) => ({
        ...current,
        [folderId]: [...(current[folderId] ?? []), idea],
      }));
      setSelection({ folderId, goalId: null, taskId: null, ideaId: idea.id, folderNoteId: null });
      setIsPanelOpen(true);
    } finally {
      setSaving(false);
    }
  }

  async function handleSaveIdea() {
    if (!selectedIdea || !canEditSelectedIdea || !ideaDraft.title.trim()) {
      return;
    }

    setSaving(true);
    try {
      const updated = await updateIdea(authorizedFetch, selectedIdea.id, {
        title: ideaDraft.title.trim(),
        body: ideaDraft.description.trim(),
        status: selectedIdea.status,
        displayOrder: selectedIdea.displayOrder,
        archived: selectedIdea.archived,
        version: selectedIdea.version,
      });

      setIdeasByFolder((current) => ({
        ...current,
        [updated.folderId]: (current[updated.folderId] ?? []).map((idea) => (idea.id === updated.id ? updated : idea)),
      }));
      setSelection({ folderId: updated.folderId, goalId: null, taskId: null, ideaId: updated.id, folderNoteId: null });
    } finally {
      setSaving(false);
    }
  }

  async function handleArchiveIdea() {
    if (!selectedIdea || selectedIdea.shared || !window.confirm(copy.archiveIdeaConfirm)) {
      return;
    }

    setSaving(true);
    try {
      await deleteIdea(authorizedFetch, selectedIdea.id);
      const nextIdeas = (ideasByFolder[selectedIdea.folderId] ?? []).filter((idea) => idea.id !== selectedIdea.id);
      setIdeasByFolder((current) => ({
        ...current,
        [selectedIdea.folderId]: nextIdeas,
      }));
      setSelection({
        folderId: selectedIdea.folderId,
        goalId: null,
        taskId: null,
        ideaId: nextIdeas[0]?.id ?? null,
        folderNoteId: null,
      });
      if (nextIdeas.length === 0) {
        setIsPanelOpen(false);
      }
    } finally {
      setSaving(false);
    }
  }

  async function handleCreateIdeaNote() {
    if (!selectedIdea || !ideaNoteDraft.trim()) {
      return;
    }

    setSaving(true);
    try {
      const note = await createIdeaNote(authorizedFetch, selectedIdea.id, {
        eventType: 'note',
        body: ideaNoteDraft.trim(),
        metadata: {},
      });
      setIdeaNotesByIdea((current) => ({
        ...current,
        [selectedIdea.id]: [...(current[selectedIdea.id] ?? []), note],
      }));
      setIdeaNoteDraft('');
    } finally {
      setSaving(false);
    }
  }

  async function handleCreateFolderNote(kind: FolderNoteDto['kind']) {
    if (!selectedFolder || !canCreateFolderResource(selectedFolder)) {
      return;
    }

    setSaving(true);
    try {
      const note = await createFolderNote(authorizedFetch, selectedFolder.id, {
        title: kind === 'list' ? copy.folderListName : copy.folderNoteName,
        body: '',
        kind,
      });
      setFolderNotesByFolder((current) => ({
        ...current,
        [selectedFolder.id]: [...(current[selectedFolder.id] ?? []), note],
      }));
      setSelection({ folderId: selectedFolder.id, goalId: null, taskId: null, ideaId: null, folderNoteId: note.id });
      setFolderNoteDraft({ title: note.title, body: note.body });
      setIsPanelOpen(true);
    } finally {
      setSaving(false);
    }
  }

  async function handleSaveFolderNote() {
    if (!selectedFolderNote || !folderNoteDraft.title.trim()) {
      return;
    }

    setSaving(true);
    try {
      const updated = await updateFolderNote(authorizedFetch, selectedFolderNote.id, {
        title: folderNoteDraft.title.trim(),
        body: folderNoteDraft.body.trim(),
        displayOrder: selectedFolderNote.displayOrder,
        archived: selectedFolderNote.archived,
        version: selectedFolderNote.version,
      });
      setFolderNotesByFolder((current) => ({
        ...current,
        [updated.folderId]: (current[updated.folderId] ?? []).map((note) => (note.id === updated.id ? updated : note)),
      }));
      setSelection({ folderId: updated.folderId, goalId: null, taskId: null, ideaId: null, folderNoteId: updated.id });
    } finally {
      setSaving(false);
    }
  }

  async function handleAddFolderNoteItem(note: FolderNoteDto) {
    if (!folderNoteItemDraft.trim()) {
      return;
    }

    setSaving(true);
    try {
      const item = await createFolderNoteItem(authorizedFetch, note.id, {
        text: folderNoteItemDraft.trim(),
        checked: false,
      });
      setFolderNotesByFolder((current) => ({
        ...current,
        [note.folderId]: (current[note.folderId] ?? []).map((folderNote) => (
          folderNote.id === note.id ? { ...folderNote, items: [...folderNote.items, item] } : folderNote
        )),
      }));
      setFolderNoteItemDraft('');
    } finally {
      setSaving(false);
    }
  }

  async function handleToggleFolderNoteItem(note: FolderNoteDto, itemId: string) {
    const item = note.items.find((candidate) => candidate.id === itemId);
    if (!item) {
      return;
    }

    setSaving(true);
    try {
      const updated = await updateFolderNoteItem(authorizedFetch, item.id, {
        text: item.text,
        checked: !item.checked,
        displayOrder: item.displayOrder,
        version: item.version,
      });
      setFolderNotesByFolder((current) => ({
        ...current,
        [note.folderId]: (current[note.folderId] ?? []).map((folderNote) => (
          folderNote.id === note.id
            ? { ...folderNote, items: folderNote.items.map((candidate) => (candidate.id === updated.id ? updated : candidate)) }
            : folderNote
        )),
      }));
    } finally {
      setSaving(false);
    }
  }

  async function handleSaveTask() {
    const targetGoal = isCreatingTask ? taskCreationGoal : selectedGoal;
    if (!targetGoal || (!isCreatingTask && !selectedTask)) {
      return;
    }

    const priority = Number(draft.priority);
    if (!draft.title.trim() || !Number.isInteger(priority) || priority < 1 || priority > 10) {
      return;
    }

    setSaving(true);
    try {
      if (isCreatingTask) {
        const task = await createTask(authorizedFetch, targetGoal.id, {
          title: draft.title.trim(),
          description: draft.description.trim(),
          type: draft.type,
          priority,
          status: draft.status,
          plannedTime: fromDateTimeInputValue(draft.plannedTime),
          dueTime: fromDateTimeInputValue(draft.dueTime),
        });

        setCreateTaskGoalId(null);
        await loadPlan({ folderId: targetGoal.folderId, goalId: targetGoal.id, taskId: task.id });
        setIsPanelOpen(true);
        return;
      }

      if (!selectedTask || !selectedGoal) {
        return;
      }

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
      setSelection((current) => ({ ...current, taskId: updated.id, ideaId: null, folderNoteId: null }));
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

      if (task.shared) {
        await loadPlan({ folderId: goal.folderId, goalId: goal.id, taskId: updated.id });
        return;
      }

      setTasksByGoal((current) => ({
        ...current,
        [goal.id]: (current[goal.id] ?? []).map((item) => (item.id === updated.id ? updated : item)),
      }));
      setSelection({ folderId: goal.folderId, goalId: goal.id, taskId: updated.id, ideaId: null, folderNoteId: null });
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
      setSelection({ folderId: goal.folderId, goalId: goal.id, taskId: nextTaskId, ideaId: null, folderNoteId: null });
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
                  <button type="button" role="menuitem" disabled={!canCreateGoalInFolder(selectedFolder)} onClick={() => { setIsCreateMenuOpen(false); void handleCreateGoal(); }}>
                    <Target aria-hidden="true" size={16} strokeWidth={1.75} />
                    <span>{copy.goal}</span>
                  </button>
                  <button type="button" role="menuitem" disabled={!canCreateTaskInGoal(selectedGoal)} onClick={() => { setIsCreateMenuOpen(false); void handleCreateTask(); }}>
                    <Circle aria-hidden="true" size={16} strokeWidth={1.75} />
                    <span>{copy.task}</span>
                  </button>
                  <button type="button" role="menuitem" disabled={!canCreateFolderResource(selectedFolder)} onClick={() => { setIsCreateMenuOpen(false); void handleCreateIdea(); }}>
                    <Lightbulb aria-hidden="true" size={16} strokeWidth={1.75} />
                    <span>{copy.idea}</span>
                  </button>
                  <button type="button" role="menuitem" disabled={!canCreateFolderResource(selectedFolder)} onClick={() => { setIsCreateMenuOpen(false); void handleCreateFolderNote('note'); }}>
                    <StickyNote aria-hidden="true" size={16} strokeWidth={1.75} />
                    <span>{copy.folderNote}</span>
                  </button>
                  <button type="button" role="menuitem" disabled={!canCreateFolderResource(selectedFolder)} onClick={() => { setIsCreateMenuOpen(false); void handleCreateFolderNote('list'); }}>
                    <ListChecks aria-hidden="true" size={16} strokeWidth={1.75} />
                    <span>{copy.folderList}</span>
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
            {visiblePlanTree.map(({
              folder,
              goals: folderGoals,
              ideas: folderIdeas,
              folderNotes: visibleFolderNotes,
              allGoals,
              allTasks: folderTasks,
              allIdeas,
              allFolderNotes,
            }, index) => {
              const firstGoal = allGoals[0] ?? null;
              const startsSharedSection = folder.shared && !visiblePlanTree[index - 1]?.folder.shared;

              return (
                <div className="plan-tree__group" key={folder.id}>
                  {startsSharedSection ? (
                    <div className="plan-section-label">{copy.shared}</div>
                  ) : null}
                  <button
                    type="button"
                    className={`plan-row plan-row--folder${selection.folderId === folder.id && !selection.taskId && !selection.ideaId && !selection.folderNoteId ? ' is-selected' : ''}`}
                    onClick={() => {
                      setCreateTaskGoalId(null);
                      setSelection({ folderId: folder.id, goalId: firstGoal?.id ?? null, taskId: null, ideaId: null, folderNoteId: null });
                      setIsPanelOpen(true);
                    }}
                    role="treeitem"
                    aria-expanded="true"
                  >
                    <ChevronDown aria-hidden="true" size={16} strokeWidth={1.75} />
                    <Folder aria-hidden="true" size={18} strokeWidth={1.75} />
                    <span className="plan-row__title">{folder.name}</span>
                    <span className="plan-row__meta">{folderTasks.length ? progress(folderTasks) : `${allIdeas.length}/${allFolderNotes.length}`}</span>
                    {folder.shared ? <span className="plan-row__shared">{copy.sharedResource}</span> : null}
                    <span className="plan-row__actions">
                      {!folder.shared ? (
                        <span className="plan-row__icon" title={copy.newGoal}>
                          <Plus size={15} strokeWidth={1.75} />
                        </span>
                      ) : null}
                      <span className="plan-row__icon" title={copy.more}>
                        <MoreHorizontal size={15} strokeWidth={1.75} />
                      </span>
                    </span>
                  </button>

                  {allGoals.length === 0 && !folder.shared ? (
                    <button type="button" className="plan-row plan-row--inline" onClick={() => void handleCreateGoal(folder.id)}>
                      <Plus aria-hidden="true" size={16} strokeWidth={1.75} />
                      <span>{copy.addGoal}</span>
                    </button>
                  ) : null}

                  {folderIdeas.map((idea) => (
                    <button
                      type="button"
                      key={idea.id}
                      className={`plan-row plan-row--task${selection.ideaId === idea.id ? ' is-selected' : ''}`}
                      style={{ marginLeft: 30, borderLeft: '3px solid #2563eb' }}
                      onClick={() => {
                        setCreateTaskGoalId(null);
                        setSelection({ folderId: folder.id, goalId: null, taskId: null, ideaId: idea.id, folderNoteId: null });
                        setIsPanelOpen(true);
                      }}
                      role="treeitem"
                    >
                      <Lightbulb aria-hidden="true" size={16} strokeWidth={1.75} />
                      <span className="marker-dot marker-dot--blue" aria-hidden="true" />
                      <span className="plan-row__title">{idea.title}</span>
                      <span className="plan-row__meta">{copy.idea}</span>
                    </button>
                  ))}

                  {visibleFolderNotes.map((note) => (
                    <button
                      type="button"
                      key={note.id}
                      className={`plan-row plan-row--task${selection.folderNoteId === note.id ? ' is-selected' : ''}`}
                      style={{ marginLeft: 30, borderLeft: '3px solid #94a3b8' }}
                      onClick={() => {
                        setCreateTaskGoalId(null);
                        setSelection({ folderId: folder.id, goalId: null, taskId: null, ideaId: null, folderNoteId: note.id });
                        setIsPanelOpen(true);
                      }}
                      role="treeitem"
                    >
                      {note.kind === 'list' ? (
                        <ListChecks aria-hidden="true" size={16} strokeWidth={1.75} />
                      ) : (
                        <StickyNote aria-hidden="true" size={16} strokeWidth={1.75} />
                      )}
                      <span className="plan-row__title">{note.title}</span>
                      <span className="plan-row__meta">{note.kind === 'list' ? note.items.length : copy.folderNote}</span>
                    </button>
                  ))}

                  {folderGoals.map(({ goal, tasks: goalTasks, allTasks: allGoalTasks }) => {
                    return (
                      <div className="plan-tree__group" key={goal.id}>
                        <button
                          type="button"
                          className={`plan-row plan-row--goal${selection.goalId === goal.id && !selection.taskId && !selection.ideaId && !selection.folderNoteId ? ' is-selected' : ''}`}
                          onClick={() => {
                            setCreateTaskGoalId(null);
                            setSelection({ folderId: folder.id, goalId: goal.id, taskId: allGoalTasks[0]?.id ?? null, ideaId: null, folderNoteId: null });
                          }}
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
                          {goal.shared ? <span className="plan-row__shared">{copy.sharedResource}</span> : null}
                          <span className="plan-row__actions">
                            {canCreateTaskInGoal(goal) ? (
                              <span className="plan-row__icon" title={copy.newTask}>
                                <Plus size={15} strokeWidth={1.75} />
                              </span>
                            ) : null}
                            <span className="plan-row__icon" title={copy.more}>
                              <MoreHorizontal size={15} strokeWidth={1.75} />
                            </span>
                          </span>
                        </button>

                        {allGoalTasks.length === 0 && canCreateTaskInGoal(goal) ? (
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
                                onClick={() => {
                                  setCreateTaskGoalId(null);
                                  setSelection({ folderId: folder.id, goalId: goal.id, taskId: task.id, ideaId: null, folderNoteId: null });
                                  setIsPanelOpen(true);
                                }}
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
                                  onClick={() => {
                                    setCreateTaskGoalId(null);
                                    setSelection({ folderId: folder.id, goalId: goal.id, taskId: task.id, ideaId: null, folderNoteId: null });
                                    setIsPanelOpen(true);
                                  }}
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
        {selectedIdea && selectedFolder ? (
          <>
            <header className="detail-panel__header">
              <div>
                <h2>{selectedIdea.title}</h2>
                <div className="detail-panel__badges" aria-label={copy.details}>
                  <span className="meta-chip">
                    <Lightbulb aria-hidden="true" size={14} strokeWidth={1.75} />
                    {copy.idea}
                  </span>
                  {selectedIdea.shared ? <span className="meta-chip">{copy.sharedResource}</span> : null}
                </div>
              </div>
              <div className="cluster" style={{ justifyContent: 'flex-end' }}>
                {canEditSelectedIdea ? (
                  <button className="icon-button" type="button" aria-label={copy.archive} title={copy.archive} disabled={saving} onClick={() => void handleArchiveIdea()}>
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
                  <span>{selectedFolder.name}</span>
                </div>
              </div>

              <details className="detail-disclosure" open>
                <summary>{copy.details}</summary>
                <div className="detail-editor">
                  <label className="field detail-grid__wide">
                    <span>{copy.idea}</span>
                    <input className="field__control" disabled={!canEditSelectedIdea} value={ideaDraft.title} onChange={(event) => setIdeaDraft((current) => ({ ...current, title: event.target.value }))} />
                  </label>
                  <label className="field detail-grid__wide">
                    <span>{copy.notes}</span>
                    <textarea className="field__control field__control--area" disabled={!canEditSelectedIdea} value={ideaDraft.description} onChange={(event) => setIdeaDraft((current) => ({ ...current, description: event.target.value }))} />
                  </label>
                  <div className="cluster detail-grid__wide">
                    <button className="button button--primary" type="button" disabled={saving || !canEditSelectedIdea} onClick={() => void handleSaveIdea()}>
                      <Save aria-hidden="true" size={16} strokeWidth={1.75} />
                      <span>{copy.save}</span>
                    </button>
                  </div>
                </div>
              </details>

              <details className="detail-disclosure" open>
                <summary>{copy.ideaHistory}</summary>
                <div className="detail-section">
                  <label className="field">
                    <span>{copy.addNote}</span>
                    <textarea className="field__control field__control--area" placeholder={copy.notePlaceholder} value={ideaNoteDraft} onChange={(event) => setIdeaNoteDraft(event.target.value)} />
                  </label>
                  <button className="button button--primary" type="button" disabled={saving || !ideaNoteDraft.trim()} onClick={() => void handleCreateIdeaNote()}>
                    <Plus aria-hidden="true" size={16} strokeWidth={1.75} />
                    <span>{copy.addNote}</span>
                  </button>
                </div>
                <dl>
                  {selectedIdeaNotes.map((note) => (
                    <div key={note.id}>
                      <dt>{describeIdeaAuthor(note) ?? copy.creator}</dt>
                      <dd>{formatDateTime(note.createdAt, locale)} · {note.body}</dd>
                    </div>
                  ))}
                </dl>
              </details>
            </div>
          </>
        ) : selectedFolderNote && selectedFolder ? (
          <>
            <header className="detail-panel__header">
              <div>
                <h2>{selectedFolderNote.title}</h2>
                <div className="detail-panel__badges" aria-label={copy.details}>
                  <span className="meta-chip">
                    {selectedFolderNote.kind === 'list' ? <ListChecks aria-hidden="true" size={14} strokeWidth={1.75} /> : <StickyNote aria-hidden="true" size={14} strokeWidth={1.75} />}
                    {selectedFolderNote.kind === 'list' ? copy.folderList : copy.folderNote}
                  </span>
                </div>
              </div>
              <button className="icon-button" type="button" aria-label={copy.collapse} title={copy.collapse} onClick={() => setIsPanelOpen(false)}>
                <PanelRightClose aria-hidden="true" size={19} strokeWidth={1.75} />
              </button>
            </header>

            <div className="detail-panel__body">
              <div className="detail-section">
                <div className="detail-label">{copy.path}</div>
                <div className="breadcrumb">
                  <Folder aria-hidden="true" size={15} strokeWidth={1.75} />
                  <span>{selectedFolder.name}</span>
                </div>
              </div>
              <details className="detail-disclosure" open>
                <summary>{copy.details}</summary>
                <div className="detail-editor">
                  <label className="field detail-grid__wide">
                    <span>{copy.folderNote}</span>
                    <input className="field__control" value={folderNoteDraft.title} onChange={(event) => setFolderNoteDraft((current) => ({ ...current, title: event.target.value }))} />
                  </label>
                  <label className="field detail-grid__wide">
                    <span>{copy.notes}</span>
                    <textarea className="field__control field__control--area" value={folderNoteDraft.body} onChange={(event) => setFolderNoteDraft((current) => ({ ...current, body: event.target.value }))} />
                  </label>
                  <div className="cluster detail-grid__wide">
                    <button className="button button--primary" type="button" disabled={saving} onClick={() => void handleSaveFolderNote()}>
                      <Save aria-hidden="true" size={16} strokeWidth={1.75} />
                      <span>{copy.save}</span>
                    </button>
                  </div>
                </div>
              </details>

              {selectedFolderNote.kind === 'list' ? (
                <details className="detail-disclosure" open>
                  <summary>{copy.folderList}</summary>
                  <div className="detail-section">
                    {selectedFolderNote.items.map((item) => (
                      <label className="breadcrumb" key={item.id} style={{ cursor: 'pointer' }}>
                        <input type="checkbox" checked={item.checked} disabled={saving} onChange={() => void handleToggleFolderNoteItem(selectedFolderNote, item.id)} />
                        <span style={{ textDecoration: item.checked ? 'line-through' : 'none' }}>{item.text}</span>
                      </label>
                    ))}
                    <label className="field">
                      <span>{copy.addListItem}</span>
                      <input className="field__control" placeholder={copy.listItemPlaceholder} value={folderNoteItemDraft} onChange={(event) => setFolderNoteItemDraft(event.target.value)} />
                    </label>
                    <button className="button button--primary" type="button" disabled={saving || !folderNoteItemDraft.trim()} onClick={() => void handleAddFolderNoteItem(selectedFolderNote)}>
                      <Plus aria-hidden="true" size={16} strokeWidth={1.75} />
                      <span>{copy.addListItem}</span>
                    </button>
                  </div>
                </details>
              ) : null}
            </div>
          </>
        ) : !isCreatingTask && !selectedTask && selectedFolder ? (
          <>
            <header className="detail-panel__header">
              <div>
                <h2>{selectedFolder.name}</h2>
                <div className="detail-panel__badges" aria-label={copy.details}>
                  <span className="meta-chip">{copy.ideas}: {(ideasByFolder[selectedFolder.id] ?? []).length}</span>
                  <span className="meta-chip">{copy.folderNotes}: {(folderNotesByFolder[selectedFolder.id] ?? []).length}</span>
                </div>
              </div>
              <button className="icon-button" type="button" aria-label={copy.collapse} title={copy.collapse} onClick={() => setIsPanelOpen(false)}>
                <PanelRightClose aria-hidden="true" size={19} strokeWidth={1.75} />
              </button>
            </header>
            <div className="detail-panel__body">
              <div className="detail-section">
                <div className="detail-label">{copy.folderNotes}</div>
                <div className="cluster">
                  <button className="button button--primary" type="button" disabled={saving || !canCreateFolderResource(selectedFolder)} onClick={() => void handleCreateIdea(selectedFolder.id)}>
                    <Lightbulb aria-hidden="true" size={16} strokeWidth={1.75} />
                    <span>{copy.newIdea}</span>
                  </button>
                  <button className="button button--ghost" type="button" disabled={saving || !canCreateFolderResource(selectedFolder)} onClick={() => void handleCreateFolderNote('note')}>
                    <StickyNote aria-hidden="true" size={16} strokeWidth={1.75} />
                    <span>{copy.newFolderNote}</span>
                  </button>
                  <button className="button button--ghost" type="button" disabled={saving || !canCreateFolderResource(selectedFolder)} onClick={() => void handleCreateFolderNote('list')}>
                    <ListChecks aria-hidden="true" size={16} strokeWidth={1.75} />
                    <span>{copy.newFolderList}</span>
                  </button>
                </div>
              </div>
            </div>
          </>
        ) : (isCreatingTask || selectedTask) && panelGoal && panelFolder ? (
          <>
            <header className="detail-panel__header">
              <div>
                <h2>{isCreatingTask ? copy.newTask : selectedTask?.title}</h2>
                {!isCreatingTask && selectedTask ? (
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
                ) : null}
              </div>
              <div className="cluster" style={{ justifyContent: 'flex-end' }}>
                {canArchiveSelectedTask && selectedTask && selectedGoal ? (
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
                <button className="icon-button" type="button" aria-label={copy.collapse} title={copy.collapse} onClick={() => {
                  setCreateTaskGoalId(null);
                  setIsPanelOpen(false);
                }}>
                  <PanelRightClose aria-hidden="true" size={19} strokeWidth={1.75} />
                </button>
              </div>
            </header>

            <div className="detail-panel__body">
              <div className="detail-section">
                <div className="detail-label">{copy.path}</div>
                <div className="breadcrumb">
                  <Folder aria-hidden="true" size={15} strokeWidth={1.75} />
                  <span>{panelFolder.name} / {panelGoal.name}</span>
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
                  <p>{selectedTask?.description || planningCopy.common.noDescription}</p>
                </div>
              </div>

              <details className="detail-disclosure" open>
                <summary>{copy.details}</summary>
                <div className="detail-editor">
                  <label className="field detail-grid__wide">
                    <span>{copy.task}</span>
                    <input className="field__control" disabled={!canEditSelectedTaskFields} value={draft.title} onChange={(event) => setDraft((current) => ({ ...current, title: event.target.value }))} />
                  </label>
                  <label className="field detail-grid__wide">
                    <span>{copy.notes}</span>
                    <textarea className="field__control field__control--area" disabled={!canEditSelectedTaskFields} value={draft.description} onChange={(event) => setDraft((current) => ({ ...current, description: event.target.value }))} />
                  </label>
                  <label className="field">
                    <span>{copy.type}</span>
                    <select className="field__control" disabled={!canEditSelectedTaskFields} value={draft.type} onChange={(event) => setDraft((current) => ({ ...current, type: event.target.value as TaskType }))}>
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
                    <input className="field__control" type="number" min={1} max={10} disabled={!canEditSelectedTaskFields} value={draft.priority} onChange={(event) => setDraft((current) => ({ ...current, priority: event.target.value }))} />
                  </label>
                  <label className="field">
                    <span>{copy.planned}</span>
                    <input className="field__control" type="datetime-local" disabled={!canEditSelectedTaskFields} value={draft.plannedTime} onChange={(event) => setDraft((current) => ({ ...current, plannedTime: event.target.value }))} />
                  </label>
                  <label className="field detail-grid__wide">
                    <span>{copy.due}</span>
                    <input className="field__control" type="datetime-local" disabled={!canEditSelectedTaskFields} value={draft.dueTime} onChange={(event) => setDraft((current) => ({ ...current, dueTime: event.target.value }))} />
                  </label>
                  <div className="cluster detail-grid__wide">
                    <button className="button button--primary" type="button" disabled={saving} onClick={() => void handleSaveTask()}>
                      <Save aria-hidden="true" size={16} strokeWidth={1.75} />
                      <span>{copy.save}</span>
                    </button>
                    {canArchiveSelectedTask && selectedTask && selectedGoal ? (
                      <button className="button button--ghost" type="button" disabled={saving} onClick={() => void handleArchiveTask(selectedTask, selectedGoal)}>
                        <Archive aria-hidden="true" size={16} strokeWidth={1.75} />
                        <span>{copy.archive}</span>
                      </button>
                    ) : null}
                  </div>
                </div>
                {!isCreatingTask && selectedTask ? (
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
                ) : null}
              </details>
            </div>
          </>
        ) : (
          <div className="detail-empty">
            <Circle aria-hidden="true" size={28} strokeWidth={1.75} />
            <span>{copy.selectItem}</span>
          </div>
        )}
      </aside>
    </div>
  );
}
