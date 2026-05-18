import { type DragEvent, useEffect, useMemo, useState } from 'react';
import {
  Archive,
  CalendarClock,
  CheckCircle2,
  ChevronDown,
  Circle,
  Cloud,
  Copy,
  Folder,
  GitBranch,
  Lightbulb,
  Link2,
  MoreHorizontal,
  Move,
  PanelRightClose,
  Pencil,
  Plus,
  Save,
  Search,
  StickyNote,
  Target,
  Trash2,
  UserCircle,
  X,
} from 'lucide-react';

import { useAuth } from '../../auth';
import { useI18n } from '../../../i18n';
import {
  archiveFolder,
  archiveGoal,
  cloneFolder,
  cloneGoal,
  cloneIdea,
  cloneNote,
  cloneTask,
  createChildFolder,
  createEntityLink,
  createFolder,
  createGoal,
  createIdea,
  createIdeaNote,
  createNote,
  createTask,
  deleteEntityLink,
  deleteIdea,
  deleteNote,
  deleteTask,
  listEntityLinks,
  listFolders,
  listGoals,
  listIdeaNotes,
  listIdeas,
  listNotes,
  listTasks,
  moveFolder,
  moveGoal,
  moveIdea,
  moveNote,
  moveTaskToGoal,
  updateFolder,
  updateGoal,
  updateIdea,
  updateIdeaNote,
  updateNote,
  updateTask,
  upsertTaskRecurrence,
} from '../planning-api';
import {
  createFolderInvitation,
  createGoalInvitation,
  createTaskInvitation,
  getSharedResources,
} from '../../advanced/advanced-api';
import { usePlanningCopy } from '../planning-copy';
import { mapPlanningError } from '../planning-errors';
import {
  createDefaultRecurrenceDraft,
  describeRecurrence,
  formatDateTime,
  fromDateTimeInputValue,
  toDateTimeInputValue,
  toTaskRecurrenceDraft,
  toTaskRecurrenceUpsertPayload,
} from '../planning-utils';
import type {
  DayOfWeek,
  EntityLinkDto,
  EntityRefDto,
  EntityRelationType,
  FolderDto,
  GoalDto,
  GoalStatus,
  IdeaDto,
  IdeaNoteDto,
  LinkEntityType,
  NoteDto,
  TaskDto,
  TaskStatus,
  TaskType,
} from '../types';
import type { SharedResourcesResponse } from '../../advanced/types';

type PlanFolder = FolderDto & { shared?: boolean; canAccessFolderContent?: boolean; fullAccess?: boolean };
type GoalsByFolder = Record<string, GoalDto[]>;
type TasksByGoal = Record<string, TaskDto[]>;
type IdeasByFolder = Record<string, IdeaDto[]>;
type NotesByFolder = Record<string, NoteDto[]>;
type IdeaNotesByIdea = Record<string, IdeaNoteDto[]>;
type LinksByEntity = Record<string, EntityLinkDto[]>;
type MarkerTone = 'green' | 'red' | 'blue' | 'amber' | 'gray';

interface Selection {
  folderId: string | null;
  goalId: string | null;
  taskId: string | null;
  ideaId: string | null;
  noteId: string | null;
}

interface TaskDraft {
  title: string;
  description: string;
  type: TaskType;
  status: TaskStatus;
  priority: string;
  plannedTime: string;
  dueTime: string;
  recurrence: ReturnType<typeof createDefaultRecurrenceDraft>;
}

interface IdeaDraft {
  title: string;
  description: string;
  status: string;
  allowAuthorNoteEdits: boolean;
}

interface FolderDraft {
  name: string;
  description: string;
}

interface GoalDraft {
  name: string;
  description: string;
  status: GoalStatus;
}

interface NoteDraft {
  title: string;
  body: string;
}

interface EntitySelection {
  type: 'folder' | LinkEntityType;
  id: string;
}

interface MoveCloneOperation {
  mode: 'move' | 'clone';
  entity: EntitySelection;
}

const WEEKDAYS: DayOfWeek[] = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];
const DEFAULT_ALLOW_AUTHOR_NOTE_EDITS = false;
const ROOT_PARENT_KEY = '__root__';
const GOAL_STATUSES: GoalStatus[] = ['todo', 'in_progress', 'done', 'cancelled'];
const TASK_STATUSES: TaskStatus[] = ['todo', 'in_progress', 'done', 'cancelled'];

function toDraft(task: TaskDto | null): TaskDraft {
  return {
    title: task?.title ?? '',
    description: task?.description ?? '',
    type: task?.type ?? 'green',
    status: task?.status ?? 'todo',
    priority: String(task?.priority ?? 2),
    plannedTime: toDateTimeInputValue(task?.plannedTime ?? null),
    dueTime: toDateTimeInputValue(task?.dueTime ?? null),
    recurrence: toTaskRecurrenceDraft(task),
  };
}

function toIdeaDraft(idea: IdeaDto | null, fallbackStatus: string): IdeaDraft {
  return {
    title: idea?.title ?? '',
    description: idea?.body ?? '',
    status: idea?.status ?? fallbackStatus,
    allowAuthorNoteEdits: idea?.allowAuthorNoteEdits ?? DEFAULT_ALLOW_AUTHOR_NOTE_EDITS,
  };
}

function toFolderDraft(folder: PlanFolder | null): FolderDraft {
  return {
    name: folder?.name ?? '',
    description: folder?.description ?? '',
  };
}

function toGoalDraft(goal: GoalDto | null): GoalDraft {
  return {
    name: goal?.name ?? '',
    description: goal?.description ?? '',
    status: goal?.status ?? 'todo',
  };
}

function toNoteDraft(note: NoteDto | null): NoteDraft {
  return {
    title: note?.title ?? '',
    body: note?.body ?? '',
  };
}

function recurrenceStartInput(draft: TaskDraft) {
  return draft.recurrence.anchor === 'due' ? draft.dueTime : draft.plannedTime;
}

function recurrenceError(draft: TaskDraft, copy: ReturnType<typeof usePlanningCopy>['tasks']) {
  if (!draft.recurrence.enabled) {
    return null;
  }

  const interval = Number(draft.recurrence.interval);
  const start = recurrenceStartInput(draft);

  if (!start) {
    return copy.validationRecurrenceAnchor;
  }

  if (!Number.isInteger(interval) || interval < 1) {
    return copy.validationRecurrenceInterval;
  }

  if (draft.recurrence.mode === 'weekly' && draft.recurrence.daysOfWeek.length === 0) {
    return copy.validationRecurrenceWeekday;
  }

  if (draft.recurrence.endAt) {
    const startDate = new Date(start);
    const endDate = new Date(draft.recurrence.endAt);

    if (Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime()) || endDate <= startDate) {
      return copy.validationRecurrenceEndAt;
    }
  }

  return null;
}

function weekdayLabel(day: DayOfWeek, copy: ReturnType<typeof usePlanningCopy>['tasks']) {
  const labels: Record<DayOfWeek, string> = {
    MONDAY: copy.weekdayMonday,
    TUESDAY: copy.weekdayTuesday,
    WEDNESDAY: copy.weekdayWednesday,
    THURSDAY: copy.weekdayThursday,
    FRIDAY: copy.weekdayFriday,
    SATURDAY: copy.weekdaySaturday,
    SUNDAY: copy.weekdaySunday,
  };

  return labels[day];
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

function describeIdeaAuthor(note: IdeaNoteDto) {
  return note.authorName || note.authorEmail || note.authorUserId || null;
}

function mergeById<TItem extends { id: string }>(primary: TItem[], secondary: TItem[]) {
  const merged = new Map<string, TItem>();
  [...primary, ...secondary].forEach((item) => merged.set(item.id, item));
  return Array.from(merged.values());
}

function entityKey(type: LinkEntityType, id: string) {
  return `${type}:${id}`;
}

function parentKey(folder: FolderDto) {
  return folder.parentFolderId ?? ROOT_PARENT_KEY;
}

function canAccessFolderContent(folder: PlanFolder | null) {
  return Boolean(folder && (!folder.shared || folder.fullAccess || folder.canAccessFolderContent === true));
}

function canMutateShared(item: { shared?: boolean; fullAccess?: boolean } | null) {
  return Boolean(item && (!item.shared || item.fullAccess === true));
}

function groupFoldersByParent(folders: PlanFolder[]) {
  return folders.reduce<Record<string, PlanFolder[]>>((groups, folder) => {
    const key = parentKey(folder);
    groups[key] = [...(groups[key] ?? []), folder];
    return groups;
  }, {});
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

function groupNotesByFolder(notes: NoteDto[]) {
  return notes.reduce<NotesByFolder>((groups, note) => {
    groups[note.folderId] = [...(groups[note.folderId] ?? []), note];
    return groups;
  }, {});
}

function otherLinkRef(link: EntityLinkDto, type: LinkEntityType, id: string) {
  return link.source.type === type && link.source.id === id ? link.target : link.source;
}

function usePlanCopy() {
  const { locale } = useI18n();

  return {
    plan: locale === 'ru' ? 'План' : 'Plan',
    folder: locale === 'ru' ? 'Папка' : 'Folder',
    goal: locale === 'ru' ? 'Цель' : 'Goal',
    task: locale === 'ru' ? 'Задача' : 'Task',
    idea: locale === 'ru' ? 'Идея' : 'Idea',
    note: locale === 'ru' ? 'Заметка' : 'Note',
    ideas: locale === 'ru' ? 'Идеи' : 'Ideas',
    notes: locale === 'ru' ? 'Заметки' : 'Notes',
    childFolders: locale === 'ru' ? 'Вложенные папки' : 'Nested folders',
    ideaHistory: locale === 'ru' ? 'История мыслей' : 'Thought history',
    search: locale === 'ru' ? 'Поиск' : 'Search',
    searchPlaceholder: locale === 'ru' ? 'Найти в плане' : 'Search plan',
    closeSearch: locale === 'ru' ? 'Закрыть поиск' : 'Close search',
    noSearchResults: locale === 'ru' ? 'Ничего не найдено' : 'No results found',
    collapse: locale === 'ru' ? 'Свернуть панель' : 'Close panel',
    add: locale === 'ru' ? 'Добавить' : 'Add',
    create: locale === 'ru' ? 'Создать' : 'Create',
    shared: locale === 'ru' ? 'Общие' : 'Shared',
    sharedResource: locale === 'ru' ? 'Общий доступ' : 'Shared',
    fullAccess: locale === 'ru' ? 'Полный доступ' : 'Full access',
    more: locale === 'ru' ? 'Еще' : 'More',
    newFolder: locale === 'ru' ? 'Новая папка' : 'New folder',
    newGoal: locale === 'ru' ? 'Новая цель' : 'New goal',
    newTask: locale === 'ru' ? 'Новая задача' : 'New task',
    newIdea: locale === 'ru' ? 'Новая идея' : 'New idea',
    newNote: locale === 'ru' ? 'Новая заметка' : 'New note',
    addGoal: locale === 'ru' ? 'Добавить цель' : 'Add a goal',
    addTask: locale === 'ru' ? 'Добавить задачу' : 'Add a task',
    emptyTitle: locale === 'ru' ? 'Пока пусто' : 'Nothing here yet',
    emptyBody: locale === 'ru'
      ? 'Создайте папку, затем добавьте вложенные папки, цели, идеи и заметки.'
      : 'Create a folder, then add nested folders, goals, ideas, and notes.',
    selectItem: locale === 'ru'
      ? 'Выберите папку, цель, задачу, идею или заметку'
      : 'Select a folder, goal, task, idea, or note',
    path: locale === 'ru' ? 'Путь' : 'Path',
    details: locale === 'ru' ? 'Сведения' : 'Details',
    status: locale === 'ru' ? 'Статус' : 'Status',
    type: locale === 'ru' ? 'Тип' : 'Type',
    priority: locale === 'ru' ? 'Приоритет' : 'Priority',
    planned: locale === 'ru' ? 'Когда делать' : 'Planned',
    due: locale === 'ru' ? 'Дедлайн' : 'Due',
    creator: locale === 'ru' ? 'Создатель' : 'Creator',
    archive: locale === 'ru' ? 'В архив' : 'Archive',
    archiveConfirm: locale === 'ru' ? 'Переместить задачу в архив?' : 'Archive this task?',
    archiveFolderConfirm: locale === 'ru' ? 'Переместить папку в архив?' : 'Archive this folder?',
    archiveGoalConfirm: locale === 'ru' ? 'Переместить цель в архив?' : 'Archive this goal?',
    archiveIdeaConfirm: locale === 'ru' ? 'Удалить идею?' : 'Delete this idea?',
    deleteNoteConfirm: locale === 'ru' ? 'Удалить заметку?' : 'Delete this note?',
    synced: locale === 'ru' ? 'Синхронизировано' : 'Synced',
    save: locale === 'ru' ? 'Сохранить' : 'Save',
    cancel: locale === 'ru' ? 'Отмена' : 'Cancel',
    edit: locale === 'ru' ? 'Изменить' : 'Edit',
    loading: locale === 'ru' ? 'Загружаем план' : 'Loading plan',
    loadError: locale === 'ru' ? 'Не удалось загрузить план' : 'Could not load the plan',
    retry: locale === 'ru' ? 'Повторить' : 'Retry',
    folderName: locale === 'ru' ? 'Новая папка' : 'New folder',
    goalName: locale === 'ru' ? 'Новая цель' : 'New goal',
    taskName: locale === 'ru' ? 'Новая задача' : 'New task',
    noteName: locale === 'ru' ? 'Новая заметка' : 'New note',
    notePlaceholder: locale === 'ru' ? 'Запишите мысль или контекст' : 'Write a thought or context',
    addNote: locale === 'ru' ? 'Добавить заметку' : 'Add note',
    linkedNotes: locale === 'ru' ? 'Связанные заметки' : 'Linked notes',
    noLinkedNotes: locale === 'ru' ? 'Связанных заметок нет.' : 'No linked notes yet.',
    links: locale === 'ru' ? 'Связи' : 'Links',
    dependencies: locale === 'ru' ? 'Зависимости' : 'Dependencies',
    dependency: locale === 'ru' ? 'Зависимость' : 'Dependency',
    related: locale === 'ru' ? 'Связь' : 'Related',
    addLink: locale === 'ru' ? 'Добавить связь' : 'Add link',
    deleteLink: locale === 'ru' ? 'Удалить связь' : 'Delete link',
    linkTarget: locale === 'ru' ? 'С чем связать' : 'Link target',
    relationType: locale === 'ru' ? 'Тип связи' : 'Relation type',
    noLinks: locale === 'ru' ? 'Связей пока нет.' : 'No links yet.',
    dependencyHint: locale === 'ru'
      ? 'Зависимость доступна только между задачами.'
      : 'Dependencies are available only between tasks.',
    open: locale === 'ru' ? 'Открыть' : 'Open',
    move: locale === 'ru' ? 'Переместить' : 'Move',
    clone: locale === 'ru' ? 'Клонировать' : 'Clone',
    target: locale === 'ru' ? 'Куда' : 'Target',
    cloneName: locale === 'ru' ? 'Новое название' : 'New name',
    share: locale === 'ru' ? 'Поделиться' : 'Share',
    shareEmail: locale === 'ru' ? 'Email пользователя' : 'User email',
    shareDone: locale === 'ru' ? 'Доступ отправлен.' : 'Access sent.',
    dragHint: locale === 'ru'
      ? 'Можно перетащить сущность на допустимую цель или использовать меню "Переместить".'
      : 'You can drag an entity onto a valid target or use the Move menu.',
  };
}

export function TasksRoute() {
  const { authorizedFetch, session } = useAuth();
  const { locale } = useI18n();
  const planningCopy = usePlanningCopy();
  const copy = usePlanCopy();
  const [folders, setFolders] = useState<PlanFolder[]>([]);
  const [goalsByFolder, setGoalsByFolder] = useState<GoalsByFolder>({});
  const [tasksByGoal, setTasksByGoal] = useState<TasksByGoal>({});
  const [ideasByFolder, setIdeasByFolder] = useState<IdeasByFolder>({});
  const [notesByFolder, setNotesByFolder] = useState<NotesByFolder>({});
  const [ideaNotesByIdea, setIdeaNotesByIdea] = useState<IdeaNotesByIdea>({});
  const [linksByEntity, setLinksByEntity] = useState<LinksByEntity>({});
  const [createTaskGoalIds, setCreateTaskGoalIds] = useState<Set<string>>(() => new Set());
  const [selection, setSelection] = useState<Selection>({
    folderId: null,
    goalId: null,
    taskId: null,
    ideaId: null,
    noteId: null,
  });
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [isPanelOpen, setIsPanelOpen] = useState(false);
  const [createTaskGoalId, setCreateTaskGoalId] = useState<string | null>(null);
  const [createIdeaFolderId, setCreateIdeaFolderId] = useState<string | null>(null);
  const [isCreateMenuOpen, setIsCreateMenuOpen] = useState(false);
  const [detailAddOpen, setDetailAddOpen] = useState(false);
  const [detailMenuOpen, setDetailMenuOpen] = useState(false);
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [draft, setDraft] = useState<TaskDraft>(() => toDraft(null));
  const [folderDraft, setFolderDraft] = useState<FolderDraft>(() => toFolderDraft(null));
  const [goalDraft, setGoalDraft] = useState<GoalDraft>(() => toGoalDraft(null));
  const [ideaDraft, setIdeaDraft] = useState<IdeaDraft>(() => toIdeaDraft(null, planningCopy.ideas.defaultStatus));
  const [noteDraft, setNoteDraft] = useState<NoteDraft>(() => toNoteDraft(null));
  const [ideaNoteDraft, setIdeaNoteDraft] = useState('');
  const [ideaNoteEdits, setIdeaNoteEdits] = useState<Record<string, string>>({});
  const [editingEntity, setEditingEntity] = useState<EntitySelection | null>(null);
  const [operation, setOperation] = useState<MoveCloneOperation | null>(null);
  const [operationTargetId, setOperationTargetId] = useState('');
  const [operationName, setOperationName] = useState('');
  const [dragEntity, setDragEntity] = useState<EntitySelection | null>(null);
  const [linkTargetKey, setLinkTargetKey] = useState('');
  const [linkRelationType, setLinkRelationType] = useState<EntityRelationType>('related');
  const [shareEmail, setShareEmail] = useState('');
  const [shareFullAccess, setShareFullAccess] = useState(true);

  const goals = useMemo(() => Object.values(goalsByFolder).flat(), [goalsByFolder]);
  const tasks = useMemo(() => Object.values(tasksByGoal).flat(), [tasksByGoal]);
  const ideas = useMemo(() => Object.values(ideasByFolder).flat(), [ideasByFolder]);
  const notes = useMemo(() => Object.values(notesByFolder).flat(), [notesByFolder]);
  const childFoldersByParent = useMemo(() => groupFoldersByParent(folders), [folders]);
  const selectedFolder = folders.find((folder) => folder.id === selection.folderId) ?? null;
  const selectedGoal = goals.find((goal) => goal.id === selection.goalId) ?? null;
  const selectedTask = tasks.find((task) => task.id === selection.taskId) ?? null;
  const selectedIdea = ideas.find((idea) => idea.id === selection.ideaId) ?? null;
  const selectedNote = notes.find((note) => note.id === selection.noteId) ?? null;
  const selectedIdeaNotes = selectedIdea ? ideaNotesByIdea[selectedIdea.id] ?? [] : [];
  const selectedFolderGoals = selectedFolder ? goals.filter((goal) => goal.folderId === selectedFolder.id) : [];
  const selectedFolderTasks = selectedFolderGoals.flatMap((goal) => tasksByGoal[goal.id] ?? []);
  const selectedGoalTasks = selectedGoal ? tasksByGoal[selectedGoal.id] ?? [] : [];
  const ideaCreationFolder = createIdeaFolderId ? folders.find((folder) => folder.id === createIdeaFolderId) ?? null : null;
  const taskCreationGoal = goals.find((goal) => goal.id === createTaskGoalId) ?? null;
  const taskCreationFolder = taskCreationGoal
    ? folders.find((folder) => folder.id === taskCreationGoal.folderId) ?? null
    : null;
  const isCreatingTask = Boolean(createTaskGoalId);
  const isCreatingIdea = Boolean(createIdeaFolderId);
  const panelGoal = isCreatingTask ? taskCreationGoal : selectedGoal;
  const panelFolder = isCreatingTask ? taskCreationFolder : selectedFolder;
  const normalizedSearch = searchQuery.trim().toLocaleLowerCase(locale === 'ru' ? 'ru-RU' : 'en-US');
  const isSearching = normalizedSearch.length > 0;
  const selectedCreator = !isCreatingTask && selectedTask ? describeCreator(selectedTask) : null;
  const currentRecurrenceError = recurrenceError(draft, planningCopy.tasks);
  const canArchiveSelectedTask = !isCreatingTask && selectedTask ? canMutateShared(selectedTask) : false;
  const canEditSelectedTaskFields = isCreatingTask || canMutateShared(selectedTask);
  const canEditSelectedIdea = canMutateShared(selectedIdea);
  const canEditSelectedNote = canMutateShared(selectedNote);
  const canEditSelectedFolder = canMutateShared(selectedFolder);
  const canEditSelectedGoal = canMutateShared(selectedGoal);
  const canCreateGoalInFolder = (folder: PlanFolder | null) => canMutateShared(folder);
  const canCreateTaskInGoal = (goal: GoalDto | null) => Boolean(goal && (!goal.shared || goal.fullAccess || createTaskGoalIds.has(goal.id)));
  const canCreateFolderResource = (folder: PlanFolder | null) => canMutateShared(folder);
  const canEditIdeaNote = (note: IdeaNoteDto) => Boolean(
    selectedIdea &&
    (
      canEditSelectedIdea ||
      (
        selectedIdea.allowAuthorNoteEdits &&
        (
          note.authorUserId === session?.user.id ||
          (note.authorEmail !== null && note.authorEmail === session?.user.email)
        )
      )
    )
  );
  const selectedLinkEntity = selectedTask
    ? { type: 'task' as const, id: selectedTask.id }
    : selectedGoal
      ? { type: 'goal' as const, id: selectedGoal.id }
      : selectedIdea
        ? { type: 'idea' as const, id: selectedIdea.id }
        : selectedNote
          ? { type: 'note' as const, id: selectedNote.id }
          : null;
  const selectedLinks = selectedLinkEntity ? linksByEntity[entityKey(selectedLinkEntity.type, selectedLinkEntity.id)] ?? [] : [];
  const currentLinkCandidates = useMemo(() => {
    const refs: EntityRefDto[] = [
      ...goals.map((goal) => ({
        type: 'goal' as const,
        id: goal.id,
        title: goal.name,
        subtitle: folders.find((folder) => folder.id === goal.folderId)?.name ?? null,
        status: goal.status,
        path: folders.find((folder) => folder.id === goal.folderId)?.name ?? null,
        archived: goal.archived,
      })),
      ...tasks.map((task) => {
        const goal = goals.find((candidate) => candidate.id === task.goalId) ?? null;
        const folder = goal ? folders.find((candidate) => candidate.id === goal.folderId) ?? null : null;
        return {
          type: 'task' as const,
          id: task.id,
          title: task.title,
          subtitle: goal?.name ?? null,
          status: task.status,
          path: [folder?.name, goal?.name].filter(Boolean).join(' / ') || null,
          archived: task.archived,
        };
      }),
      ...ideas.map((idea) => ({
        type: 'idea' as const,
        id: idea.id,
        title: idea.title,
        subtitle: folders.find((folder) => folder.id === idea.folderId)?.name ?? null,
        status: idea.status,
        path: folders.find((folder) => folder.id === idea.folderId)?.name ?? null,
        archived: idea.archived,
      })),
      ...notes.map((note) => ({
        type: 'note' as const,
        id: note.id,
        title: note.title,
        subtitle: folders.find((folder) => folder.id === note.folderId)?.name ?? null,
        status: null,
        path: folders.find((folder) => folder.id === note.folderId)?.name ?? null,
        archived: note.archived,
      })),
    ];

    if (!selectedLinkEntity) {
      return refs;
    }

    return refs.filter((ref) => !(ref.type === selectedLinkEntity.type && ref.id === selectedLinkEntity.id));
  }, [folders, goals, ideas, notes, selectedLinkEntity, tasks]);
  const linkedNotes = selectedLinkEntity && selectedLinkEntity.type !== 'note'
    ? selectedLinks.map((link) => otherLinkRef(link, selectedLinkEntity.type, selectedLinkEntity.id)).filter((ref) => ref.type === 'note')
    : [];
  const totalTasks = tasks.length;
  const doneTasks = tasks.filter(isComplete).length;

  useEffect(() => {
    if (!isCreatingTask) {
      setDraft(toDraft(selectedTask));
    }
  }, [isCreatingTask, selectedTask?.id]);

  useEffect(() => {
    setFolderDraft(toFolderDraft(selectedFolder));
  }, [selectedFolder?.id]);

  useEffect(() => {
    setGoalDraft(toGoalDraft(selectedGoal));
  }, [selectedGoal?.id]);

  useEffect(() => {
    if (createIdeaFolderId) {
      return;
    }

    setIdeaDraft(toIdeaDraft(selectedIdea, planningCopy.ideas.defaultStatus));
    setIdeaNoteDraft('');
    setIdeaNoteEdits({});
  }, [createIdeaFolderId, planningCopy.ideas.defaultStatus, selectedIdea?.id]);

  useEffect(() => {
    setNoteDraft(toNoteDraft(selectedNote));
  }, [selectedNote?.id]);

  useEffect(() => {
    if (!selectedIdea || ideaNotesByIdea[selectedIdea.id]) {
      return;
    }

    void listIdeaNotes(authorizedFetch, selectedIdea.id)
      .then((history) => {
        setIdeaNotesByIdea((current) => ({ ...current, [selectedIdea.id]: history }));
      })
      .catch(() => {
        setIdeaNotesByIdea((current) => ({ ...current, [selectedIdea.id]: [] }));
      });
  }, [authorizedFetch, ideaNotesByIdea, selectedIdea]);

  useEffect(() => {
    if (!selectedLinkEntity) {
      return;
    }

    const key = entityKey(selectedLinkEntity.type, selectedLinkEntity.id);
    if (linksByEntity[key]) {
      return;
    }

    void listEntityLinks(authorizedFetch, selectedLinkEntity.type, selectedLinkEntity.id)
      .then((links) => setLinksByEntity((current) => ({ ...current, [key]: links })))
      .catch(() => setLinksByEntity((current) => ({ ...current, [key]: [] })));
  }, [authorizedFetch, linksByEntity, selectedLinkEntity]);

  function resetTransientState() {
    setActionError(null);
    setNotice(null);
    setDetailAddOpen(false);
    setDetailMenuOpen(false);
    setOperation(null);
  }

  function clearCreation() {
    setCreateTaskGoalId(null);
    setCreateIdeaFolderId(null);
  }

  async function runAction(action: () => Promise<void>) {
    setSaving(true);
    setActionError(null);
    setNotice(null);

    try {
      await action();
    } catch (error) {
      setActionError(mapPlanningError(error, planningCopy).message);
    } finally {
      setSaving(false);
    }
  }

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
      const nextFolders = mergeById<PlanFolder>(
        ownedFolders.map((folder) => ({
          ...folder,
          shared: folder.shared ?? false,
          fullAccess: folder.fullAccess ?? true,
          canAccessFolderContent: folder.canAccessFolderContent ?? true,
        })),
        (sharedResources.folders ?? []).map((folder) => ({
          ...folder,
          shared: true,
          fullAccess: folder.fullAccess === true,
          canAccessFolderContent: folder.canAccessFolderContent === true || folder.fullAccess === true,
        })),
      );
      const folderContentFolders = nextFolders.filter(canAccessFolderContent);
      const nextGoalsEntries = await Promise.all(
        folderContentFolders.map(async (folder) => [folder.id, await listGoals(authorizedFetch, folder.id).catch(() => [])] as const),
      );
      const loadedGoals = nextGoalsEntries.flatMap(([, folderGoals]) => folderGoals);
      const nextGoals = mergeById(loadedGoals, sharedResources.goals ?? []);
      const nextTaskEntries = await Promise.all(
        nextGoals.map(async (goal) => [goal.id, await listTasks(authorizedFetch, goal.id).catch(() => [])] as const),
      );
      const loadedTasks = nextTaskEntries.flatMap(([, goalTasks]) => goalTasks);
      const nextTasks = mergeById(loadedTasks, sharedResources.tasks ?? []);
      const [nextIdeaEntries, nextNoteEntries] = await Promise.all([
        Promise.all(
          folderContentFolders.map(async (folder) => [
            folder.id,
            await listIdeas(authorizedFetch, folder.id).catch(() => []),
          ] as const),
        ),
        Promise.all(
          folderContentFolders.map(async (folder) => [
            folder.id,
            await listNotes(authorizedFetch, folder.id).catch(() => []),
          ] as const),
        ),
      ]);

      const nextGoalsByFolder = groupGoalsByFolder(nextGoals);
      const nextTasksByGoal = groupTasksByGoal(nextTasks);
      const nextIdeasByFolder = groupIdeasByFolder(nextIdeaEntries.flatMap(([, folderIdeas]) => folderIdeas));
      const nextNotesByFolder = groupNotesByFolder(nextNoteEntries.flatMap(([, notesResult]) => notesResult));
      const nextFolderId = preferred.folderId !== undefined ? preferred.folderId : selection.folderId ?? nextFolders[0]?.id ?? null;
      const nextGoalId = preferred.goalId !== undefined ? preferred.goalId : selection.goalId;
      const nextTaskId = preferred.taskId !== undefined ? preferred.taskId : selection.taskId;
      const nextIdeaId = preferred.ideaId !== undefined ? preferred.ideaId : selection.ideaId;
      const nextNoteId = preferred.noteId !== undefined ? preferred.noteId : selection.noteId;

      setFolders(nextFolders);
      setGoalsByFolder(nextGoalsByFolder);
      setTasksByGoal(nextTasksByGoal);
      setIdeasByFolder(nextIdeasByFolder);
      setNotesByFolder(nextNotesByFolder);
      setCreateTaskGoalIds(new Set(sharedResources.createTaskGoalIds ?? []));
      setLinksByEntity({});
      setSelection({
        folderId: nextFolderId,
        goalId: nextGoalId,
        taskId: nextTaskId,
        ideaId: nextIdeaId,
        noteId: nextNoteId,
      });
    } catch (error) {
      const mapped = mapPlanningError(error, planningCopy);
      setLoadError(mapped.message);
      setFolders([]);
      setGoalsByFolder({});
      setTasksByGoal({});
      setIdeasByFolder({});
      setNotesByFolder({});
      setIdeaNotesByIdea({});
      setLinksByEntity({});
      setCreateTaskGoalIds(new Set());
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadPlan();
  }, []);

  function selectFolder(folderId: string) {
    clearCreation();
    resetTransientState();
    setSelection({ folderId, goalId: null, taskId: null, ideaId: null, noteId: null });
    setIsPanelOpen(true);
  }

  function selectGoal(goal: GoalDto) {
    clearCreation();
    resetTransientState();
    setSelection({ folderId: goal.folderId, goalId: goal.id, taskId: null, ideaId: null, noteId: null });
    setIsPanelOpen(true);
  }

  function selectTask(task: TaskDto) {
    const goal = goals.find((candidate) => candidate.id === task.goalId) ?? null;
    if (!goal) {
      return;
    }

    clearCreation();
    resetTransientState();
    setSelection({ folderId: goal.folderId, goalId: goal.id, taskId: task.id, ideaId: null, noteId: null });
    setIsPanelOpen(true);
  }

  function selectIdea(idea: IdeaDto) {
    clearCreation();
    resetTransientState();
    setSelection({ folderId: idea.folderId, goalId: null, taskId: null, ideaId: idea.id, noteId: null });
    setIsPanelOpen(true);
  }

  function selectNote(note: NoteDto) {
    clearCreation();
    resetTransientState();
    setSelection({ folderId: note.folderId, goalId: null, taskId: null, ideaId: null, noteId: note.id });
    setIsPanelOpen(true);
  }

  function openEntity(ref: EntityRefDto) {
    if (ref.type === 'goal') {
      const goal = goals.find((item) => item.id === ref.id);
      if (goal) {
        selectGoal(goal);
      }
      return;
    }

    if (ref.type === 'task') {
      const task = tasks.find((item) => item.id === ref.id);
      if (task) {
        selectTask(task);
      }
      return;
    }

    if (ref.type === 'idea') {
      const idea = ideas.find((item) => item.id === ref.id);
      if (idea) {
        selectIdea(idea);
      }
      return;
    }

    const note = notes.find((item) => item.id === ref.id);
    if (note) {
      selectNote(note);
    }
  }

  async function handleCreateFolder(parentFolderId: string | null = null) {
    await runAction(async () => {
      const parentFolder = parentFolderId ? folders.find((folder) => folder.id === parentFolderId) ?? null : null;
      if (parentFolderId && !canCreateFolderResource(parentFolder)) {
        return;
      }

      const folder = parentFolderId
        ? await createChildFolder(authorizedFetch, parentFolderId, {
          name: copy.folderName,
          description: '',
        })
        : await createFolder(authorizedFetch, {
          name: copy.folderName,
          description: '',
          parentFolderId: null,
        });
      await loadPlan({ folderId: folder.id, goalId: null, taskId: null, ideaId: null, noteId: null });
      setIsPanelOpen(true);
    });
  }

  async function handleCreateGoal(folderId = selection.folderId) {
    const targetFolder = folders.find((folder) => folder.id === folderId) ?? null;
    if (!folderId || !canCreateGoalInFolder(targetFolder)) {
      return;
    }

    await runAction(async () => {
      const goal = await createGoal(authorizedFetch, folderId, {
        name: copy.goalName,
        description: '',
        status: 'todo',
      });
      await loadPlan({ folderId, goalId: goal.id, taskId: null, ideaId: null, noteId: null });
      setIsPanelOpen(true);
    });
  }

  function handleCreateTask(goalId = selection.goalId) {
    const targetGoal = goals.find((goal) => goal.id === goalId) ?? null;
    if (!goalId || !targetGoal || !canCreateTaskInGoal(targetGoal)) {
      return;
    }

    resetTransientState();
    setCreateIdeaFolderId(null);
    setCreateTaskGoalId(goalId);
    setSelection({ folderId: targetGoal.folderId, goalId, taskId: null, ideaId: null, noteId: null });
    setDraft(toDraft(null));
    setIsPanelOpen(true);
  }

  function handleCreateIdea(folderId = selection.folderId) {
    const targetFolder = folders.find((folder) => folder.id === folderId) ?? null;
    if (!folderId || !canCreateFolderResource(targetFolder)) {
      return;
    }

    resetTransientState();
    setCreateTaskGoalId(null);
    setCreateIdeaFolderId(folderId);
    setSelection({ folderId, goalId: null, taskId: null, ideaId: null, noteId: null });
    setIdeaDraft({
      title: planningCopy.ideas.createTitle,
      description: '',
      status: planningCopy.ideas.defaultStatus,
      allowAuthorNoteEdits: DEFAULT_ALLOW_AUTHOR_NOTE_EDITS,
    });
    setIsPanelOpen(true);
  }

  async function handleCreateNote(folderId = selection.folderId) {
    const targetFolder = folders.find((folder) => folder.id === folderId) ?? null;
    if (!folderId || !canCreateFolderResource(targetFolder)) {
      return;
    }

    await runAction(async () => {
      clearCreation();
      const note = await createNote(authorizedFetch, folderId, {
        title: planningCopy.notes.defaultTitle,
        body: '',
      });
      setNotesByFolder((current) => ({
        ...current,
        [folderId]: [...(current[folderId] ?? []), note],
      }));
      setSelection({ folderId, goalId: null, taskId: null, ideaId: null, noteId: note.id });
      setNoteDraft(toNoteDraft(note));
      setEditingEntity({ type: 'note', id: note.id });
      setIsPanelOpen(true);
    });
  }

  async function handleSaveFolder() {
    if (!selectedFolder || !canEditSelectedFolder || !folderDraft.name.trim()) {
      return;
    }

    await runAction(async () => {
      const updated = await updateFolder(authorizedFetch, selectedFolder.id, {
        name: folderDraft.name.trim(),
        description: folderDraft.description.trim(),
        parentFolderId: selectedFolder.parentFolderId,
        displayOrder: selectedFolder.displayOrder,
        archived: selectedFolder.archived,
        version: selectedFolder.version,
      });
      setFolders((current) => current.map((folder) => folder.id === updated.id ? { ...folder, ...updated } : folder));
      setEditingEntity(null);
    });
  }

  async function handleArchiveFolder() {
    if (!selectedFolder || !canEditSelectedFolder || !window.confirm(copy.archiveFolderConfirm)) {
      return;
    }

    await runAction(async () => {
      await archiveFolder(authorizedFetch, selectedFolder.id);
      await loadPlan({ folderId: null, goalId: null, taskId: null, ideaId: null, noteId: null });
      setIsPanelOpen(false);
    });
  }

  async function handleSaveGoal() {
    if (!selectedGoal || !canEditSelectedGoal || !goalDraft.name.trim()) {
      return;
    }

    await runAction(async () => {
      const updated = await updateGoal(authorizedFetch, selectedGoal.id, {
        name: goalDraft.name.trim(),
        description: goalDraft.description.trim(),
        status: goalDraft.status,
        archived: selectedGoal.archived,
        version: selectedGoal.version,
      });
      setGoalsByFolder((current) => ({
        ...current,
        [updated.folderId]: (current[updated.folderId] ?? []).map((goal) => goal.id === updated.id ? updated : goal),
      }));
      setEditingEntity(null);
    });
  }

  async function handleArchiveGoal() {
    if (!selectedGoal || !canEditSelectedGoal || !window.confirm(copy.archiveGoalConfirm)) {
      return;
    }

    await runAction(async () => {
      await archiveGoal(authorizedFetch, selectedGoal.id);
      await loadPlan({ folderId: selectedGoal.folderId, goalId: null, taskId: null, ideaId: null, noteId: null });
      setIsPanelOpen(false);
    });
  }

  async function handleSaveNewIdea() {
    if (!createIdeaFolderId || !ideaDraft.title.trim()) {
      return;
    }

    await runAction(async () => {
      const idea = await createIdea(authorizedFetch, createIdeaFolderId, {
        title: ideaDraft.title.trim(),
        body: ideaDraft.description.trim(),
        status: ideaDraft.status.trim() || planningCopy.ideas.defaultStatus,
        allowAuthorNoteEdits: ideaDraft.allowAuthorNoteEdits,
      });

      setIdeasByFolder((current) => ({
        ...current,
        [createIdeaFolderId]: [...(current[createIdeaFolderId] ?? []), idea],
      }));
      setCreateIdeaFolderId(null);
      setSelection({ folderId: createIdeaFolderId, goalId: null, taskId: null, ideaId: idea.id, noteId: null });
      setIsPanelOpen(true);
    });
  }

  async function handleSaveIdea() {
    if (!selectedIdea || !canEditSelectedIdea || !ideaDraft.title.trim()) {
      return;
    }

    await runAction(async () => {
      const updated = await updateIdea(authorizedFetch, selectedIdea.id, {
        title: ideaDraft.title.trim(),
        body: ideaDraft.description.trim(),
        status: ideaDraft.status.trim() || selectedIdea.status,
        displayOrder: selectedIdea.displayOrder,
        archived: selectedIdea.archived,
        allowAuthorNoteEdits: ideaDraft.allowAuthorNoteEdits,
        version: selectedIdea.version,
      });
      setIdeasByFolder((current) => ({
        ...current,
        [updated.folderId]: (current[updated.folderId] ?? []).map((idea) => idea.id === updated.id ? updated : idea),
      }));
      setEditingEntity(null);
    });
  }

  async function handleArchiveIdea() {
    if (!selectedIdea || !canEditSelectedIdea || !window.confirm(copy.archiveIdeaConfirm)) {
      return;
    }

    await runAction(async () => {
      await deleteIdea(authorizedFetch, selectedIdea.id);
      const nextIdeas = (ideasByFolder[selectedIdea.folderId] ?? []).filter((idea) => idea.id !== selectedIdea.id);
      setIdeasByFolder((current) => ({
        ...current,
        [selectedIdea.folderId]: nextIdeas,
      }));
      setSelection({ folderId: selectedIdea.folderId, goalId: null, taskId: null, ideaId: nextIdeas[0]?.id ?? null, noteId: null });
      if (nextIdeas.length === 0) {
        setIsPanelOpen(false);
      }
    });
  }

  async function handleCreateIdeaNote() {
    if (!selectedIdea || !ideaNoteDraft.trim()) {
      return;
    }

    await runAction(async () => {
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
    });
  }

  async function handleSaveIdeaNote(note: IdeaNoteDto) {
    if (!selectedIdea || !canEditIdeaNote(note)) {
      return;
    }

    const body = (ideaNoteEdits[note.id] ?? note.body).trim();
    if (!body) {
      return;
    }

    await runAction(async () => {
      const updated = await updateIdeaNote(authorizedFetch, note.id, {
        eventType: note.eventType,
        body,
        metadata: note.metadata,
        version: note.version,
      });
      setIdeaNotesByIdea((current) => ({
        ...current,
        [selectedIdea.id]: (current[selectedIdea.id] ?? []).map((item) => item.id === updated.id ? updated : item),
      }));
      setIdeaNoteEdits((current) => ({ ...current, [updated.id]: updated.body }));
    });
  }

  async function handleSaveNote() {
    if (!selectedNote || !canEditSelectedNote || !noteDraft.title.trim()) {
      return;
    }

    await runAction(async () => {
      const updated = await updateNote(authorizedFetch, selectedNote.id, {
        title: noteDraft.title.trim(),
        body: noteDraft.body.trim(),
        displayOrder: selectedNote.displayOrder,
        archived: selectedNote.archived,
        version: selectedNote.version,
      });
      setNotesByFolder((current) => ({
        ...current,
        [updated.folderId]: (current[updated.folderId] ?? []).map((note) => note.id === updated.id ? updated : note),
      }));
      setEditingEntity(null);
    });
  }

  async function handleDeleteNote() {
    if (!selectedNote || !canEditSelectedNote || !window.confirm(copy.deleteNoteConfirm)) {
      return;
    }

    await runAction(async () => {
      await deleteNote(authorizedFetch, selectedNote.id);
      const nextNotes = (notesByFolder[selectedNote.folderId] ?? []).filter((note) => note.id !== selectedNote.id);
      setNotesByFolder((current) => ({
        ...current,
        [selectedNote.folderId]: nextNotes,
      }));
      setSelection({ folderId: selectedNote.folderId, goalId: null, taskId: null, ideaId: null, noteId: nextNotes[0]?.id ?? null });
      if (nextNotes.length === 0) {
        setIsPanelOpen(false);
      }
    });
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

    if (currentRecurrenceError) {
      return;
    }

    await runAction(async () => {
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

        const recurrencePayload = toTaskRecurrenceUpsertPayload(draft);
        if (recurrencePayload) {
          await upsertTaskRecurrence(authorizedFetch, task.id, recurrencePayload);
        }

        setCreateTaskGoalId(null);
        await loadPlan({ folderId: targetGoal.folderId, goalId: targetGoal.id, taskId: task.id, ideaId: null, noteId: null });
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

      const recurrencePayload = toTaskRecurrenceUpsertPayload(draft);
      let nextTask = updated;
      if (recurrencePayload) {
        const recurrenceResult = await upsertTaskRecurrence(authorizedFetch, selectedTask.id, recurrencePayload);
        nextTask = { ...updated, recurrence: recurrenceResult.recurrence };
      }

      setTasksByGoal((current) => ({
        ...current,
        [selectedGoal.id]: (current[selectedGoal.id] ?? []).map((task) => task.id === nextTask.id ? nextTask : task),
      }));
      setSelection((current) => ({ ...current, taskId: nextTask.id, ideaId: null, noteId: null }));
    });
  }

  async function handleToggleTask(task: TaskDto, goal: GoalDto) {
    await runAction(async () => {
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
        await loadPlan({ folderId: goal.folderId, goalId: goal.id, taskId: updated.id, ideaId: null, noteId: null });
        return;
      }

      setTasksByGoal((current) => ({
        ...current,
        [goal.id]: (current[goal.id] ?? []).map((item) => item.id === updated.id ? updated : item),
      }));
      setSelection({ folderId: goal.folderId, goalId: goal.id, taskId: updated.id, ideaId: null, noteId: null });
    });
  }

  async function handleArchiveTask(task: TaskDto, goal: GoalDto) {
    if (!window.confirm(copy.archiveConfirm)) {
      return;
    }

    await runAction(async () => {
      await deleteTask(authorizedFetch, task.id);
      const nextGoalTasks = (tasksByGoal[goal.id] ?? []).filter((item) => item.id !== task.id);
      setTasksByGoal((current) => ({
        ...current,
        [goal.id]: nextGoalTasks,
      }));
      setSelection({ folderId: goal.folderId, goalId: goal.id, taskId: nextGoalTasks[0]?.id ?? null, ideaId: null, noteId: null });
      if (nextGoalTasks.length === 0) {
        setIsPanelOpen(false);
      }
    });
  }

  async function handleCreateEntityLink() {
    if (!selectedLinkEntity || !linkTargetKey) {
      return;
    }

    const [targetType, targetId] = linkTargetKey.split(':') as [LinkEntityType, string];
    const relationType = selectedLinkEntity.type === 'task' && targetType === 'task' ? linkRelationType : 'related';

    await runAction(async () => {
      const link = await createEntityLink(authorizedFetch, {
        sourceType: selectedLinkEntity.type,
        sourceId: selectedLinkEntity.id,
        targetType,
        targetId,
        relationType,
      });
      const key = entityKey(selectedLinkEntity.type, selectedLinkEntity.id);
      setLinksByEntity((current) => ({
        ...current,
        [key]: [...(current[key] ?? []), link],
      }));
      setLinkTargetKey('');
      setLinkRelationType('related');
    });
  }

  async function handleDeleteEntityLink(link: EntityLinkDto) {
    if (!selectedLinkEntity || !window.confirm(copy.deleteLink)) {
      return;
    }

    await runAction(async () => {
      await deleteEntityLink(authorizedFetch, link.id);
      const key = entityKey(selectedLinkEntity.type, selectedLinkEntity.id);
      setLinksByEntity((current) => ({
        ...current,
        [key]: (current[key] ?? []).filter((item) => item.id !== link.id),
      }));
    });
  }

  function startOperation(mode: MoveCloneOperation['mode'], entity: EntitySelection) {
    setOperation({ mode, entity });
    setDetailMenuOpen(false);
    setOperationName(defaultEntityName(entity));
    const firstTarget = operationTargets(entity)[0]?.id ?? '';
    setOperationTargetId(firstTarget);
  }

  function defaultEntityName(entity: EntitySelection) {
    if (entity.type === 'folder') {
      return folders.find((item) => item.id === entity.id)?.name ?? '';
    }

    if (entity.type === 'goal') {
      return goals.find((item) => item.id === entity.id)?.name ?? '';
    }

    if (entity.type === 'task') {
      return tasks.find((item) => item.id === entity.id)?.title ?? '';
    }

    if (entity.type === 'idea') {
      return ideas.find((item) => item.id === entity.id)?.title ?? '';
    }

    return notes.find((item) => item.id === entity.id)?.title ?? '';
  }

  function operationTargets(entity: EntitySelection) {
    if (entity.type === 'task') {
      return goals.map((goal) => ({ id: goal.id, label: `${folders.find((folder) => folder.id === goal.folderId)?.name ?? ''} / ${goal.name}` }));
    }

    const folderTargets = folders
      .filter((folder) => entity.type !== 'folder' || folder.id !== entity.id)
      .map((folder) => ({ id: folder.id, label: folderPath(folder.id) }));

    return folderTargets;
  }

  async function executeOperation(currentOperation = operation, explicitTargetId = operationTargetId) {
    if (!currentOperation || !explicitTargetId) {
      return;
    }

    await runAction(async () => {
      const entity = currentOperation.entity;
      const targetId = explicitTargetId;

      if (entity.type === 'folder') {
        const folder = folders.find((item) => item.id === entity.id);
        if (!folder) {
          return;
        }
        const result = currentOperation.mode === 'move'
          ? await moveFolder(authorizedFetch, entity.id, { targetFolderId: targetId, version: folder.version })
          : await cloneFolder(authorizedFetch, entity.id, { targetFolderId: targetId, name: operationName.trim() || undefined, includeChildren: false });
        await loadPlan({ folderId: result.id, goalId: null, taskId: null, ideaId: null, noteId: null });
      } else if (entity.type === 'goal') {
        const goal = goals.find((item) => item.id === entity.id);
        if (!goal) {
          return;
        }
        const result = currentOperation.mode === 'move'
          ? await moveGoal(authorizedFetch, entity.id, { targetFolderId: targetId, version: goal.version })
          : await cloneGoal(authorizedFetch, entity.id, { targetFolderId: targetId, name: operationName.trim() || undefined });
        await loadPlan({ folderId: result.folderId, goalId: result.id, taskId: null, ideaId: null, noteId: null });
      } else if (entity.type === 'task') {
        const task = tasks.find((item) => item.id === entity.id);
        if (!task) {
          return;
        }
        const result = currentOperation.mode === 'move'
          ? await moveTaskToGoal(authorizedFetch, entity.id, { targetGoalId: targetId, version: task.version })
          : await cloneTask(authorizedFetch, entity.id, { targetGoalId: targetId, title: operationName.trim() || undefined, includeTags: false });
        const goal = goals.find((item) => item.id === result.goalId);
        await loadPlan({ folderId: goal?.folderId ?? null, goalId: result.goalId, taskId: result.id, ideaId: null, noteId: null });
      } else if (entity.type === 'idea') {
        const idea = ideas.find((item) => item.id === entity.id);
        if (!idea) {
          return;
        }
        const result = currentOperation.mode === 'move'
          ? await moveIdea(authorizedFetch, entity.id, { targetFolderId: targetId, version: idea.version })
          : await cloneIdea(authorizedFetch, entity.id, { targetFolderId: targetId, title: operationName.trim() || undefined });
        await loadPlan({ folderId: result.folderId, goalId: null, taskId: null, ideaId: result.id, noteId: null });
      } else {
        const note = notes.find((item) => item.id === entity.id);
        if (!note) {
          return;
        }
        const result = currentOperation.mode === 'move'
          ? await moveNote(authorizedFetch, entity.id, { targetFolderId: targetId, version: note.version })
          : await cloneNote(authorizedFetch, entity.id, { targetFolderId: targetId, title: operationName.trim() || undefined });
        await loadPlan({ folderId: result.folderId, goalId: null, taskId: null, ideaId: null, noteId: result.id });
      }

      setOperation(null);
    });
  }

  async function handleDropOnFolder(event: DragEvent, targetFolderId: string) {
    event.preventDefault();
    if (!dragEntity || (dragEntity.type === 'task')) {
      return;
    }

    const entity = dragEntity;
    const previousTargets = operationTargets(entity);
    if (!previousTargets.some((target) => target.id === targetFolderId)) {
      return;
    }

    setDragEntity(null);
    await executeOperation({ mode: 'move', entity }, targetFolderId);
  }

  async function handleDropOnGoal(event: DragEvent, targetGoalId: string) {
    event.preventDefault();
    if (!dragEntity || dragEntity.type !== 'task') {
      return;
    }

    const previousTargets = operationTargets(dragEntity);
    if (!previousTargets.some((target) => target.id === targetGoalId)) {
      return;
    }

    await executeOperation({ mode: 'move', entity: dragEntity }, targetGoalId);
    setDragEntity(null);
  }

  async function handleShareCurrent() {
    if (!shareEmail.trim()) {
      return;
    }

    await runAction(async () => {
      if (selectedFolder && !selectedFolder.shared) {
        await createFolderInvitation(authorizedFetch, selectedFolder.id, {
          email: shareEmail.trim(),
          fullAccess: shareFullAccess,
        });
      } else if (selectedGoal && !selectedGoal.shared) {
        await createGoalInvitation(authorizedFetch, selectedGoal.id, {
          email: shareEmail.trim(),
          fullAccess: shareFullAccess,
        });
      } else if (selectedTask && !selectedTask.shared) {
        await createTaskInvitation(authorizedFetch, selectedTask.id, {
          email: shareEmail.trim(),
          fullAccess: shareFullAccess,
        });
      }

      setShareEmail('');
      setNotice(copy.shareDone);
    });
  }

  function folderPath(folderId: string | null) {
    if (!folderId) {
      return '';
    }

    const names: string[] = [];
    const visited = new Set<string>();
    let current = folders.find((folder) => folder.id === folderId) ?? null;

    while (current && !visited.has(current.id)) {
      names.unshift(current.name);
      visited.add(current.id);
      current = current.parentFolderId ? folders.find((folder) => folder.id === current?.parentFolderId) ?? null : null;
    }

    return names.join(' / ');
  }

  function renderAddMenu(folder: PlanFolder | null, goal: GoalDto | null = null) {
    return (
      <div className="create-menu">
        <button
          className="button button--primary"
          type="button"
          disabled={saving}
          aria-haspopup="menu"
          aria-expanded={detailAddOpen}
          onClick={() => setDetailAddOpen((current) => !current)}
        >
          <Plus aria-hidden="true" size={16} strokeWidth={1.75} />
          <span>{copy.add}</span>
        </button>
        {detailAddOpen ? (
          <div className="create-menu__panel create-menu__panel--center" role="menu">
            {folder ? (
              <>
                <button type="button" role="menuitem" disabled={!canCreateFolderResource(folder)} onClick={() => { setDetailAddOpen(false); void handleCreateFolder(folder.id); }}>
                  <Folder aria-hidden="true" size={16} strokeWidth={1.75} />
                  <span>{copy.folder}</span>
                </button>
                <button type="button" role="menuitem" disabled={!canCreateGoalInFolder(folder)} onClick={() => { setDetailAddOpen(false); void handleCreateGoal(folder.id); }}>
                  <Target aria-hidden="true" size={16} strokeWidth={1.75} />
                  <span>{copy.goal}</span>
                </button>
                <button type="button" role="menuitem" disabled={!canCreateFolderResource(folder)} onClick={() => { setDetailAddOpen(false); handleCreateIdea(folder.id); }}>
                  <Lightbulb aria-hidden="true" size={16} strokeWidth={1.75} />
                  <span>{copy.idea}</span>
                </button>
                <button type="button" role="menuitem" disabled={!canCreateFolderResource(folder)} onClick={() => { setDetailAddOpen(false); void handleCreateNote(folder.id); }}>
                  <StickyNote aria-hidden="true" size={16} strokeWidth={1.75} />
                  <span>{copy.note}</span>
                </button>
              </>
            ) : null}
            {goal ? (
              <button type="button" role="menuitem" disabled={!canCreateTaskInGoal(goal)} onClick={() => { setDetailAddOpen(false); handleCreateTask(goal.id); }}>
                <Circle aria-hidden="true" size={16} strokeWidth={1.75} />
                <span>{copy.task}</span>
              </button>
            ) : null}
          </div>
        ) : null}
      </div>
    );
  }

  function renderDetailHeader(title: string, addMenu: JSX.Element | null, editEntity: EntitySelection | null) {
    const canEdit = editEntity
      ? editEntity.type === 'folder'
        ? canEditSelectedFolder
        : editEntity.type === 'goal'
          ? canEditSelectedGoal
          : editEntity.type === 'idea'
            ? canEditSelectedIdea
            : editEntity.type === 'note'
              ? canEditSelectedNote
              : canEditSelectedTaskFields
      : false;

    return (
      <header className="detail-panel__header detail-panel__header--centered">
        <button className="button button--ghost" type="button" onClick={() => setIsPanelOpen(false)}>
          {copy.cancel}
        </button>
        <div className="detail-panel__header-title">
          <h2>{title}</h2>
          {addMenu}
        </div>
        <div className="cluster" style={{ justifyContent: 'flex-end' }}>
          {editEntity ? (
            <button
              className="button button--ghost"
              type="button"
              disabled={!canEdit}
              onClick={() => setEditingEntity(editingEntity?.type === editEntity.type && editingEntity.id === editEntity.id ? null : editEntity)}
            >
              <Pencil aria-hidden="true" size={15} strokeWidth={1.75} />
              <span>{copy.edit}</span>
            </button>
          ) : null}
          {editEntity ? renderMoreMenu(editEntity) : null}
        </div>
      </header>
    );
  }

  function renderMoreMenu(entity: EntitySelection) {
    return (
      <div className="create-menu">
        <button
          className="icon-button"
          type="button"
          aria-label={copy.more}
          title={copy.more}
          aria-haspopup="menu"
          aria-expanded={detailMenuOpen}
          onClick={() => setDetailMenuOpen((current) => !current)}
        >
          <MoreHorizontal aria-hidden="true" size={18} strokeWidth={1.75} />
        </button>
        {detailMenuOpen ? (
          <div className="create-menu__panel" role="menu">
            <button type="button" role="menuitem" onClick={() => startOperation('move', entity)}>
              <Move aria-hidden="true" size={16} strokeWidth={1.75} />
              <span>{copy.move}</span>
            </button>
            <button type="button" role="menuitem" onClick={() => startOperation('clone', entity)}>
              <Copy aria-hidden="true" size={16} strokeWidth={1.75} />
              <span>{copy.clone}</span>
            </button>
          </div>
        ) : null}
      </div>
    );
  }

  function renderOperationPanel() {
    if (!operation) {
      return null;
    }

    const targets = operationTargets(operation.entity);

    return (
      <section className="detail-disclosure operation-panel">
        <div className="breadcrumb">
          {operation.mode === 'move' ? <Move size={16} aria-hidden="true" /> : <Copy size={16} aria-hidden="true" />}
          <strong>{operation.mode === 'move' ? copy.move : copy.clone}</strong>
        </div>
        <div className="detail-editor">
          {operation.mode === 'clone' ? (
            <label className="field detail-grid__wide">
              <span>{copy.cloneName}</span>
              <input className="field__control" value={operationName} onChange={(event) => setOperationName(event.target.value)} />
            </label>
          ) : null}
          <label className="field detail-grid__wide">
            <span>{copy.target}</span>
            <select className="field__control" value={operationTargetId} onChange={(event) => setOperationTargetId(event.target.value)}>
              <option value="" disabled>{copy.target}</option>
              {targets.map((target) => (
                <option key={target.id} value={target.id}>{target.label}</option>
              ))}
            </select>
          </label>
          <div className="cluster detail-grid__wide detail-editor__actions">
            <button className="button button--ghost" type="button" disabled={saving} onClick={() => setOperation(null)}>
              {copy.cancel}
            </button>
            <button className="button button--primary" type="button" disabled={saving || !operationTargetId} onClick={() => void executeOperation()}>
              {operation.mode === 'move' ? <Move aria-hidden="true" size={16} strokeWidth={1.75} /> : <Copy aria-hidden="true" size={16} strokeWidth={1.75} />}
              <span>{operation.mode === 'move' ? copy.move : copy.clone}</span>
            </button>
          </div>
        </div>
      </section>
    );
  }

  function renderSharingPanel() {
    const shareable = (selectedFolder && !selectedFolder.shared) || (selectedGoal && !selectedGoal.shared) || (selectedTask && !selectedTask.shared);

    if (!shareable) {
      return null;
    }

    return (
      <section className="detail-disclosure">
        <summary>{copy.share}</summary>
        <div className="detail-editor">
          <label className="field detail-grid__wide">
            <span>{copy.shareEmail}</span>
            <input className="field__control" type="email" value={shareEmail} onChange={(event) => setShareEmail(event.target.value)} />
          </label>
          <label className="switch-control detail-grid__wide">
            <input type="checkbox" checked={shareFullAccess} onChange={(event) => setShareFullAccess(event.target.checked)} />
            <span>{copy.fullAccess}</span>
          </label>
          <div className="cluster detail-grid__wide detail-editor__actions">
            <button className="button button--primary" type="button" disabled={saving || !shareEmail.trim()} onClick={() => void handleShareCurrent()}>
              <UserCircle aria-hidden="true" size={16} strokeWidth={1.75} />
              <span>{copy.share}</span>
            </button>
          </div>
        </div>
      </section>
    );
  }

  function renderLinksPanel() {
    if (!selectedLinkEntity) {
      return null;
    }

    const dependencyAvailable = selectedLinkEntity.type === 'task' && linkTargetKey.startsWith('task:');

    return (
      <section className="detail-disclosure">
        <summary>{copy.links}</summary>
        <div className="detail-section">
          {selectedLinks.length === 0 ? <p className="muted">{copy.noLinks}</p> : null}
          {selectedLinks.map((link) => {
            const ref = otherLinkRef(link, selectedLinkEntity.type, selectedLinkEntity.id);
            return (
              <article className="detail-note entity-link-card" key={link.id}>
                {link.relationType === 'dependency' ? <GitBranch size={16} aria-hidden="true" /> : <Link2 size={16} aria-hidden="true" />}
                <div>
                  <strong>{link.relationType === 'dependency' ? copy.dependency : copy.related}: {ref.title}</strong>
                  <p>{ref.path || ref.subtitle || copy.details}</p>
                  <div className="cluster">
                    <button className="button button--ghost" type="button" onClick={() => openEntity(ref)}>
                      {copy.open}
                    </button>
                    <button className="button button--ghost" type="button" disabled={saving} onClick={() => void handleDeleteEntityLink(link)}>
                      <Trash2 size={15} aria-hidden="true" />
                      <span>{copy.deleteLink}</span>
                    </button>
                  </div>
                </div>
              </article>
            );
          })}
        </div>
        <div className="detail-editor">
          <label className="field detail-grid__wide">
            <span>{copy.linkTarget}</span>
            <select className="field__control" value={linkTargetKey} onChange={(event) => setLinkTargetKey(event.target.value)}>
              <option value="">{copy.linkTarget}</option>
              {currentLinkCandidates.map((ref) => (
                <option key={`${ref.type}:${ref.id}`} value={`${ref.type}:${ref.id}`}>
                  {ref.title} · {ref.path || ref.subtitle || ref.type}
                </option>
              ))}
            </select>
          </label>
          <label className="field detail-grid__wide">
            <span>{copy.relationType}</span>
            <select
              className="field__control"
              value={dependencyAvailable ? linkRelationType : 'related'}
              disabled={!dependencyAvailable}
              onChange={(event) => setLinkRelationType(event.target.value as EntityRelationType)}
            >
              <option value="related">{copy.related}</option>
              <option value="dependency">{copy.dependency}</option>
            </select>
          </label>
          {!dependencyAvailable ? <p className="field__hint detail-grid__wide">{copy.dependencyHint}</p> : null}
          <div className="cluster detail-grid__wide detail-editor__actions">
            <button className="button button--primary" type="button" disabled={saving || !linkTargetKey} onClick={() => void handleCreateEntityLink()}>
              <Link2 aria-hidden="true" size={16} strokeWidth={1.75} />
              <span>{copy.addLink}</span>
            </button>
          </div>
        </div>
      </section>
    );
  }

  function renderLinkedNotesPanel() {
    if (!selectedLinkEntity || selectedLinkEntity.type === 'note') {
      return null;
    }

    return (
      <details className="detail-disclosure">
        <summary>{copy.linkedNotes}</summary>
        <div className="detail-section">
          {linkedNotes.length === 0 ? <p className="muted">{copy.noLinkedNotes}</p> : null}
          {linkedNotes.map((ref) => (
            <button className="detail-note detail-note--button" type="button" key={ref.id} onClick={() => openEntity(ref)}>
              <StickyNote size={16} aria-hidden="true" />
              <span>{ref.title}</span>
            </button>
          ))}
        </div>
      </details>
    );
  }

  const rowCopy = {
    complete: locale === 'ru' ? 'Отметить выполненной' : 'Mark complete',
    reopen: locale === 'ru' ? 'Вернуть в работу' : 'Mark active',
    editTask: locale === 'ru' ? 'Изменить задачу' : 'Edit task',
    type: locale === 'ru' ? 'Тип' : 'Type',
  };

  function folderMatches(folder: PlanFolder) {
    return (
      matchesQuery(folder.name, normalizedSearch, locale) ||
      matchesQuery(folder.description, normalizedSearch, locale)
    );
  }

  function renderFolderRows(folder: PlanFolder, depth: number): JSX.Element | null {
    const allGoals = goalsByFolder[folder.id] ?? [];
    const allIdeas = ideasByFolder[folder.id] ?? [];
    const allNotes = notesByFolder[folder.id] ?? [];
    const children = childFoldersByParent[folder.id] ?? [];
    const folderTasks = allGoals.flatMap((goal) => tasksByGoal[goal.id] ?? []);
    const currentFolderMatches = isSearching && folderMatches(folder);
    const visibleIdeas = allIdeas.filter((idea) => !isSearching || currentFolderMatches || matchesQuery(idea.title, normalizedSearch, locale) || matchesQuery(idea.body, normalizedSearch, locale));
    const visibleNotes = allNotes.filter((note) => !isSearching || currentFolderMatches || matchesQuery(note.title, normalizedSearch, locale) || matchesQuery(note.body, normalizedSearch, locale));
    const visibleGoals = allGoals
      .map((goal) => {
        const allTasks = tasksByGoal[goal.id] ?? [];
        const goalMatches = isSearching && (matchesQuery(goal.name, normalizedSearch, locale) || matchesQuery(goal.description, normalizedSearch, locale));
        const visibleTasks = allTasks.filter((task) => {
          if (!isSearching || currentFolderMatches || goalMatches) {
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

        return { goal, allTasks, tasks: visibleTasks, matches: goalMatches };
      })
      .filter((item) => !isSearching || currentFolderMatches || item.matches || item.tasks.length > 0);
    const visibleChildren = children.map((child) => renderFolderRows(child, depth + 1)).filter(Boolean);
    const shouldRender = !isSearching || currentFolderMatches || visibleIdeas.length > 0 || visibleNotes.length > 0 || visibleGoals.length > 0 || visibleChildren.length > 0;

    if (!shouldRender) {
      return null;
    }

    const indent = depth * 18;

    return (
      <div className="plan-tree__group" key={folder.id}>
        <button
          type="button"
          className={`plan-row plan-row--folder${selection.folderId === folder.id && !selection.goalId && !selection.taskId && !selection.ideaId && !selection.noteId ? ' is-selected' : ''}`}
          style={{ marginLeft: indent, width: `calc(100% - ${indent}px)` }}
          draggable
          onDragStart={() => setDragEntity({ type: 'folder', id: folder.id })}
          onDragEnd={() => setDragEntity(null)}
          onDragOver={(event) => dragEntity && dragEntity.type !== 'task' ? event.preventDefault() : undefined}
          onDrop={(event) => void handleDropOnFolder(event, folder.id)}
          onClick={() => selectFolder(folder.id)}
          role="treeitem"
          aria-expanded="true"
        >
          <ChevronDown aria-hidden="true" size={16} strokeWidth={1.75} />
          <Folder aria-hidden="true" size={18} strokeWidth={1.75} />
          <span className="plan-row__title">{folder.name}</span>
          <span className="plan-row__meta">{folderTasks.length ? progress(folderTasks) : `${allIdeas.length}/${allNotes.length}`}</span>
          {folder.shared ? <span className="plan-row__shared">{folder.fullAccess ? copy.fullAccess : copy.sharedResource}</span> : null}
          <span className="plan-row__actions">
            <span className="plan-row__icon" title={copy.more}><MoreHorizontal size={15} strokeWidth={1.75} /></span>
          </span>
        </button>

        {visibleChildren}

        {visibleIdeas.map((idea) => (
          <button
            type="button"
            key={idea.id}
            className={`plan-row plan-row--task${selection.ideaId === idea.id ? ' is-selected' : ''}`}
            style={{ marginLeft: 40 + indent, width: `calc(100% - ${40 + indent}px)`, borderLeft: '3px solid #2563eb' }}
            draggable
            onDragStart={() => setDragEntity({ type: 'idea', id: idea.id })}
            onDragEnd={() => setDragEntity(null)}
            onClick={() => selectIdea(idea)}
            role="treeitem"
          >
            <Lightbulb aria-hidden="true" size={16} strokeWidth={1.75} />
            <span className="marker-dot marker-dot--blue" aria-hidden="true" />
            <span className="plan-row__title">{idea.title}</span>
            <span className="plan-row__meta">{copy.idea}</span>
          </button>
        ))}

        {visibleNotes.map((note) => (
          <button
            type="button"
            key={note.id}
            className={`plan-row plan-row--task${selection.noteId === note.id ? ' is-selected' : ''}`}
            style={{ marginLeft: 40 + indent, width: `calc(100% - ${40 + indent}px)`, borderLeft: '3px solid #94a3b8' }}
            draggable
            onDragStart={() => setDragEntity({ type: 'note', id: note.id })}
            onDragEnd={() => setDragEntity(null)}
            onClick={() => selectNote(note)}
            role="treeitem"
          >
            <StickyNote aria-hidden="true" size={16} strokeWidth={1.75} />
            <span className="plan-row__title">{note.title}</span>
            <span className="plan-row__meta">{copy.note}</span>
          </button>
        ))}

        {visibleGoals.map(({ goal, allTasks, tasks: goalTasks }) => (
          <div className="plan-tree__group" key={goal.id}>
            <button
              type="button"
              className={`plan-row plan-row--goal${selection.goalId === goal.id && !selection.taskId && !selection.ideaId && !selection.noteId ? ' is-selected' : ''}`}
              style={{ marginLeft: 20 + indent, width: `calc(100% - ${20 + indent}px)` }}
              draggable
              onDragStart={() => setDragEntity({ type: 'goal', id: goal.id })}
              onDragEnd={() => setDragEntity(null)}
              onDragOver={(event) => dragEntity?.type === 'task' ? event.preventDefault() : undefined}
              onDrop={(event) => void handleDropOnGoal(event, goal.id)}
              onClick={() => selectGoal(goal)}
              role="treeitem"
              aria-expanded="true"
            >
              <ChevronDown aria-hidden="true" size={16} strokeWidth={1.75} />
              <Target aria-hidden="true" size={18} strokeWidth={1.75} />
              <span className="plan-row__main">
                <span className="plan-row__title">{goal.name}</span>
                <span className="plan-row__progress" aria-hidden="true"><span style={{ width: `${progressPercent(allTasks)}%` }} /></span>
              </span>
              <span className="plan-row__meta">{progress(allTasks)}</span>
              {goal.shared ? <span className="plan-row__shared">{goal.fullAccess ? copy.fullAccess : copy.sharedResource}</span> : null}
              <span className="plan-row__actions">
                <span className="plan-row__icon" title={copy.more}><MoreHorizontal size={15} strokeWidth={1.75} /></span>
              </span>
            </button>

            {allTasks.length === 0 && canCreateTaskInGoal(goal) ? (
              <button type="button" className="plan-row plan-row--inline plan-row--task" style={{ marginLeft: 40 + indent, width: `calc(100% - ${40 + indent}px)` }} onClick={() => handleCreateTask(goal.id)}>
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

              return (
                <div
                  key={task.id}
                  className={`plan-row plan-row--task${selection.taskId === task.id ? ' is-selected' : ''}${complete ? ' is-complete' : ''}`}
                  style={{ marginLeft: 40 + indent, width: `calc(100% - ${40 + indent}px)` }}
                  draggable
                  onDragStart={() => setDragEntity({ type: 'task', id: task.id })}
                  onDragEnd={() => setDragEntity(null)}
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
                    {complete ? <CheckCircle2 aria-hidden="true" size={17} strokeWidth={1.75} /> : <Circle aria-hidden="true" size={17} strokeWidth={1.75} />}
                  </button>
                  <button type="button" className="plan-row__content" onClick={() => selectTask(task)}>
                    <span className={`marker-dot marker-dot--${markerToneForTask(task)}`} aria-label={`${rowCopy.type}: ${typeLabel}. ${copy.status}: ${statusLabel}`} title={`${typeLabel} / ${statusLabel}`} />
                    <span className="plan-row__title">{task.title}</span>
                  </button>
                  {dueChip ? <span className={`due-chip due-chip--${dueTone(task.dueTime)}`} title={formatDateTime(task.dueTime, locale)}>{dueChip}</span> : null}
                  <span className={`priority-dot priority-dot--${markerToneForPriority(task.priority)}`} aria-label={priorityLabel} title={priorityLabel} />
                  <span className="plan-row__actions">
                    <button type="button" className="plan-row__icon" aria-label={rowCopy.editTask} title={rowCopy.editTask} onClick={() => selectTask(task)}>
                      <Pencil size={14} strokeWidth={1.75} />
                    </button>
                  </span>
                </div>
              );
            })}
          </div>
        ))}
      </div>
    );
  }

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
  const rootFolders = childFoldersByParent[ROOT_PARENT_KEY] ?? [];
  const renderedFolders = rootFolders.map((folder) => renderFolderRows(folder, 0)).filter(Boolean);
  const noSearchResults = isSearching && renderedFolders.length === 0;

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
                <button className="icon-button" type="button" aria-label={copy.closeSearch} title={copy.closeSearch} onClick={() => { setSearchQuery(''); setIsSearchOpen(false); }}>
                  <X aria-hidden="true" size={18} strokeWidth={1.75} />
                </button>
              </>
            ) : (
              <button className="icon-button" type="button" aria-label={copy.search} title={copy.search} onClick={() => setIsSearchOpen(true)}>
                <Search aria-hidden="true" size={18} strokeWidth={1.75} />
              </button>
            )}
            <div className="create-menu">
              <button className="icon-button" type="button" aria-label={copy.create} title={copy.create} disabled={saving} aria-haspopup="menu" aria-expanded={isCreateMenuOpen} onClick={() => setIsCreateMenuOpen((current) => !current)}>
                <Plus aria-hidden="true" size={20} strokeWidth={1.75} />
              </button>
              {isCreateMenuOpen ? (
                <div className="create-menu__panel" role="menu">
                  <button type="button" role="menuitem" onClick={() => { setIsCreateMenuOpen(false); void handleCreateFolder(); }}>
                    <Folder aria-hidden="true" size={16} strokeWidth={1.75} />
                    <span>{copy.folder}</span>
                  </button>
                  <button type="button" role="menuitem" disabled={!canCreateFolderResource(selectedFolder)} onClick={() => { setIsCreateMenuOpen(false); void handleCreateFolder(selection.folderId); }}>
                    <Folder aria-hidden="true" size={16} strokeWidth={1.75} />
                    <span>{copy.childFolders}</span>
                  </button>
                  <button type="button" role="menuitem" disabled={!canCreateGoalInFolder(selectedFolder)} onClick={() => { setIsCreateMenuOpen(false); void handleCreateGoal(); }}>
                    <Target aria-hidden="true" size={16} strokeWidth={1.75} />
                    <span>{copy.goal}</span>
                  </button>
                  <button type="button" role="menuitem" disabled={!canCreateTaskInGoal(selectedGoal)} onClick={() => { setIsCreateMenuOpen(false); handleCreateTask(); }}>
                    <Circle aria-hidden="true" size={16} strokeWidth={1.75} />
                    <span>{copy.task}</span>
                  </button>
                  <button type="button" role="menuitem" disabled={!canCreateFolderResource(selectedFolder)} onClick={() => { setIsCreateMenuOpen(false); handleCreateIdea(); }}>
                    <Lightbulb aria-hidden="true" size={16} strokeWidth={1.75} />
                    <span>{copy.idea}</span>
                  </button>
                  <button type="button" role="menuitem" disabled={!canCreateFolderResource(selectedFolder)} onClick={() => { setIsCreateMenuOpen(false); void handleCreateNote(); }}>
                    <StickyNote aria-hidden="true" size={16} strokeWidth={1.75} />
                    <span>{copy.note}</span>
                  </button>
                </div>
              ) : null}
            </div>
          </div>
        </header>

        {actionError ? <div className="state-box state-box--error">{actionError}</div> : null}
        {notice ? <div className="state-box state-box--loading">{notice}</div> : null}

        {empty ? (
          <div className="planner-empty">
            <Folder aria-hidden="true" size={34} strokeWidth={1.75} />
            <h2>{copy.emptyTitle}</h2>
            <p>{copy.emptyBody}</p>
            <button className="button button--primary" type="button" disabled={saving} onClick={() => void handleCreateFolder()}>
              {copy.newFolder}
            </button>
          </div>
        ) : noSearchResults ? (
          <div className="planner-empty">
            <Search aria-hidden="true" size={34} strokeWidth={1.75} />
            <h2>{copy.noSearchResults}</h2>
          </div>
        ) : (
          <div className="plan-tree" role="tree" aria-label={copy.plan}>
            {renderedFolders}
          </div>
        )}
      </section>

      <aside className={`detail-panel${isPanelOpen ? ' is-open' : ''}`}>
        {selectedIdea && selectedFolder ? (
          <>
            {renderDetailHeader(selectedIdea.title, null, { type: 'idea', id: selectedIdea.id })}
            <div className="detail-panel__body">
              <div className="detail-panel__badges" aria-label={copy.details}>
                <span className="meta-chip"><Lightbulb aria-hidden="true" size={14} strokeWidth={1.75} />{copy.idea}</span>
                <span className="meta-chip">{copy.status}: {selectedIdea.status}</span>
                {selectedIdea.shared ? <span className="meta-chip">{selectedIdea.fullAccess ? copy.fullAccess : copy.sharedResource}</span> : null}
              </div>
              <div className="detail-section">
                <div className="detail-label">{copy.path}</div>
                <div className="breadcrumb"><Folder aria-hidden="true" size={15} strokeWidth={1.75} /><span>{folderPath(selectedIdea.folderId)}</span></div>
              </div>
              <div className="detail-section">
                <div className="detail-label">{planningCopy.ideas.bodyLabel}</div>
                <div className="detail-note"><StickyNote aria-hidden="true" size={15} strokeWidth={1.75} /><p>{selectedIdea.body || planningCopy.common.noDescription}</p></div>
              </div>
              {editingEntity?.type === 'idea' && editingEntity.id === selectedIdea.id ? (
                <details className="detail-disclosure" open>
                  <summary>{copy.edit}</summary>
                  <div className="detail-editor">
                    <label className="field detail-grid__wide"><span>{planningCopy.ideas.titleLabel}</span><input className="field__control" disabled={!canEditSelectedIdea} value={ideaDraft.title} onChange={(event) => setIdeaDraft((current) => ({ ...current, title: event.target.value }))} /></label>
                    <label className="field detail-grid__wide"><span>{planningCopy.ideas.bodyLabel}</span><textarea className="field__control field__control--area" disabled={!canEditSelectedIdea} value={ideaDraft.description} onChange={(event) => setIdeaDraft((current) => ({ ...current, description: event.target.value }))} /></label>
                    <label className="field detail-grid__wide"><span>{planningCopy.ideas.statusLabel}</span><input className="field__control" disabled={!canEditSelectedIdea} value={ideaDraft.status} onChange={(event) => setIdeaDraft((current) => ({ ...current, status: event.target.value }))} /></label>
                    <label className="switch-control detail-grid__wide"><input type="checkbox" checked={ideaDraft.allowAuthorNoteEdits} disabled={!canEditSelectedIdea} onChange={(event) => setIdeaDraft((current) => ({ ...current, allowAuthorNoteEdits: event.target.checked }))} /><span>{planningCopy.ideas.allowAuthorNoteEditsLabel}</span></label>
                    <div className="cluster detail-grid__wide detail-editor__actions">
                      <button className="button button--primary" type="button" disabled={saving || !canEditSelectedIdea || !ideaDraft.title.trim()} onClick={() => void handleSaveIdea()}><Save aria-hidden="true" size={16} strokeWidth={1.75} /><span>{copy.save}</span></button>
                      <button className="button button--ghost" type="button" disabled={saving || !canEditSelectedIdea} onClick={() => void handleArchiveIdea()}><Archive aria-hidden="true" size={16} strokeWidth={1.75} /><span>{copy.archive}</span></button>
                    </div>
                  </div>
                </details>
              ) : null}
              <details className="detail-disclosure" open>
                <summary>{copy.ideaHistory}</summary>
                <div className="detail-editor">
                  <label className="field detail-grid__wide"><span>{copy.addNote}</span><textarea className="field__control field__control--area" placeholder={copy.notePlaceholder} value={ideaNoteDraft} onChange={(event) => setIdeaNoteDraft(event.target.value)} /></label>
                  <button className="button button--primary detail-grid__wide" type="button" disabled={saving || !ideaNoteDraft.trim()} onClick={() => void handleCreateIdeaNote()}><Plus aria-hidden="true" size={16} strokeWidth={1.75} /><span>{copy.addNote}</span></button>
                </div>
                <dl>
                  {selectedIdeaNotes.map((note) => {
                    const noteCanEdit = canEditIdeaNote(note);
                    const noteBody = ideaNoteEdits[note.id] ?? note.body;
                    return (
                      <div key={note.id}>
                        <dt>{describeIdeaAuthor(note) ?? copy.creator}</dt>
                        <dd>
                          <div className="idea-history-note">
                            <span className="muted">{formatDateTime(note.updatedAt, locale)}</span>
                            {noteCanEdit ? (
                              <>
                                <textarea className="field__control field__control--area" value={noteBody} onChange={(event) => setIdeaNoteEdits((current) => ({ ...current, [note.id]: event.target.value }))} />
                                <button className="button button--ghost" type="button" disabled={saving || !noteBody.trim()} onClick={() => void handleSaveIdeaNote(note)}><Save aria-hidden="true" size={16} strokeWidth={1.75} /><span>{planningCopy.ideas.saveHistoryNote}</span></button>
                              </>
                            ) : <p>{note.body}</p>}
                          </div>
                        </dd>
                      </div>
                    );
                  })}
                </dl>
              </details>
              {renderLinkedNotesPanel()}
              {renderLinksPanel()}
              {renderOperationPanel()}
            </div>
          </>
        ) : isCreatingIdea && ideaCreationFolder ? (
          <>
            {renderDetailHeader(planningCopy.ideas.createTitle, null, null)}
            <div className="detail-panel__body">
              <div className="detail-section"><div className="detail-label">{copy.path}</div><div className="breadcrumb"><Folder aria-hidden="true" size={15} strokeWidth={1.75} /><span>{folderPath(ideaCreationFolder.id)}</span></div></div>
              <details className="detail-disclosure" open>
                <summary>{copy.details}</summary>
                <div className="detail-editor">
                  <label className="field detail-grid__wide"><span>{planningCopy.ideas.titleLabel}</span><input className="field__control" value={ideaDraft.title} onChange={(event) => setIdeaDraft((current) => ({ ...current, title: event.target.value }))} /></label>
                  <label className="field detail-grid__wide"><span>{planningCopy.ideas.bodyLabel}</span><textarea className="field__control field__control--area" value={ideaDraft.description} onChange={(event) => setIdeaDraft((current) => ({ ...current, description: event.target.value }))} /></label>
                  <label className="switch-control detail-grid__wide"><input type="checkbox" checked={ideaDraft.allowAuthorNoteEdits} disabled={saving} onChange={(event) => setIdeaDraft((current) => ({ ...current, allowAuthorNoteEdits: event.target.checked }))} /><span>{planningCopy.ideas.allowAuthorNoteEditsLabel}</span></label>
                  <p className="field__hint detail-grid__wide">{planningCopy.ideas.allowAuthorNoteEditsHint}</p>
                  <label className="field detail-grid__wide"><span>{planningCopy.ideas.statusLabel}</span><input className="field__control" placeholder={planningCopy.ideas.statusPlaceholder} value={ideaDraft.status} onChange={(event) => setIdeaDraft((current) => ({ ...current, status: event.target.value }))} /></label>
                  <div className="cluster detail-grid__wide detail-editor__actions">
                    <button className="button button--ghost" type="button" disabled={saving} onClick={() => { setCreateIdeaFolderId(null); setIdeaDraft(toIdeaDraft(null, planningCopy.ideas.defaultStatus)); }}>{copy.cancel}</button>
                    <button className="button button--primary" type="button" disabled={saving || !ideaDraft.title.trim()} onClick={() => void handleSaveNewIdea()}><Save aria-hidden="true" size={16} strokeWidth={1.75} /><span>{copy.save}</span></button>
                  </div>
                </div>
              </details>
            </div>
          </>
        ) : selectedNote && selectedFolder ? (
          <>
            {renderDetailHeader(selectedNote.title, null, { type: 'note', id: selectedNote.id })}
            <div className="detail-panel__body">
              <div className="detail-panel__badges" aria-label={copy.details}>
                <span className="meta-chip"><StickyNote aria-hidden="true" size={14} strokeWidth={1.75} />{copy.note}</span>
                {selectedNote.shared ? <span className="meta-chip">{selectedNote.fullAccess ? copy.fullAccess : copy.sharedResource}</span> : null}
              </div>
              <div className="detail-section"><div className="detail-label">{copy.path}</div><div className="breadcrumb"><Folder aria-hidden="true" size={15} strokeWidth={1.75} /><span>{folderPath(selectedNote.folderId)}</span></div></div>
              <div className="detail-section"><div className="detail-label">{planningCopy.notes.bodyLabel}</div><div className="detail-note"><StickyNote aria-hidden="true" size={15} strokeWidth={1.75} /><p>{selectedNote.body || planningCopy.common.noDescription}</p></div></div>
              {editingEntity?.type === 'note' && editingEntity.id === selectedNote.id ? (
                <details className="detail-disclosure" open>
                  <summary>{copy.edit}</summary>
                  <div className="detail-editor">
                    <label className="field detail-grid__wide"><span>{planningCopy.notes.titleLabel}</span><input className="field__control" disabled={!canEditSelectedNote} value={noteDraft.title} onChange={(event) => setNoteDraft((current) => ({ ...current, title: event.target.value }))} /></label>
                    <label className="field detail-grid__wide"><span>{planningCopy.notes.bodyLabel}</span><textarea className="field__control field__control--area" disabled={!canEditSelectedNote} value={noteDraft.body} onChange={(event) => setNoteDraft((current) => ({ ...current, body: event.target.value }))} /></label>
                    <div className="cluster detail-grid__wide detail-editor__actions">
                      <button className="button button--primary" type="button" disabled={saving || !canEditSelectedNote || !noteDraft.title.trim()} onClick={() => void handleSaveNote()}><Save aria-hidden="true" size={16} strokeWidth={1.75} /><span>{copy.save}</span></button>
                      <button className="button button--ghost" type="button" disabled={saving || !canEditSelectedNote} onClick={() => void handleDeleteNote()}><Trash2 aria-hidden="true" size={16} strokeWidth={1.75} /><span>{planningCopy.common.delete}</span></button>
                    </div>
                  </div>
                </details>
              ) : null}
              {renderLinksPanel()}
              {renderOperationPanel()}
            </div>
          </>
        ) : !isCreatingTask && !selectedTask && selectedGoal && selectedFolder ? (
          <>
            {renderDetailHeader(selectedGoal.name, renderAddMenu(null, selectedGoal), { type: 'goal', id: selectedGoal.id })}
            <div className="detail-panel__body">
              <div className="detail-panel__badges" aria-label={copy.details}>
                <span className="meta-chip"><Target aria-hidden="true" size={14} strokeWidth={1.75} />{copy.goal}</span>
                <span className="meta-chip">{copy.status}: {planningCopy.enums.goalStatus[selectedGoal.status]}</span>
                <span className="meta-chip">{copy.task}: {selectedGoalTasks.length}</span>
                {selectedGoal.shared ? <span className="meta-chip">{selectedGoal.fullAccess ? copy.fullAccess : copy.sharedResource}</span> : null}
              </div>
              <div className="detail-section"><div className="detail-label">{copy.path}</div><div className="breadcrumb"><Folder aria-hidden="true" size={15} strokeWidth={1.75} /><span>{folderPath(selectedFolder.id)} / {selectedGoal.name}</span></div></div>
              <div className="detail-section"><div className="detail-label">{planningCopy.goals.description}</div><div className="detail-note"><StickyNote aria-hidden="true" size={15} strokeWidth={1.75} /><p>{selectedGoal.description || planningCopy.common.noDescription}</p></div></div>
              {editingEntity?.type === 'goal' && editingEntity.id === selectedGoal.id ? (
                <details className="detail-disclosure" open>
                  <summary>{copy.edit}</summary>
                  <div className="detail-editor">
                    <label className="field detail-grid__wide"><span>{planningCopy.goals.name}</span><input className="field__control" disabled={!canEditSelectedGoal} value={goalDraft.name} onChange={(event) => setGoalDraft((current) => ({ ...current, name: event.target.value }))} /></label>
                    <label className="field detail-grid__wide"><span>{planningCopy.goals.description}</span><textarea className="field__control field__control--area" disabled={!canEditSelectedGoal} value={goalDraft.description} onChange={(event) => setGoalDraft((current) => ({ ...current, description: event.target.value }))} /></label>
                    <label className="field detail-grid__wide"><span>{planningCopy.goals.statusLabel}</span><select className="field__control" disabled={!canEditSelectedGoal} value={goalDraft.status} onChange={(event) => setGoalDraft((current) => ({ ...current, status: event.target.value as GoalStatus }))}>{GOAL_STATUSES.map((status) => <option key={status} value={status}>{planningCopy.enums.goalStatus[status]}</option>)}</select></label>
                    <div className="cluster detail-grid__wide detail-editor__actions">
                      <button className="button button--primary" type="button" disabled={saving || !canEditSelectedGoal || !goalDraft.name.trim()} onClick={() => void handleSaveGoal()}><Save aria-hidden="true" size={16} strokeWidth={1.75} /><span>{copy.save}</span></button>
                      <button className="button button--ghost" type="button" disabled={saving || !canEditSelectedGoal} onClick={() => void handleArchiveGoal()}><Archive aria-hidden="true" size={16} strokeWidth={1.75} /><span>{copy.archive}</span></button>
                    </div>
                  </div>
                </details>
              ) : null}
              {renderLinkedNotesPanel()}
              {renderLinksPanel()}
              {renderSharingPanel()}
              {renderOperationPanel()}
            </div>
          </>
        ) : !isCreatingTask && !selectedTask && selectedFolder ? (
          <>
            {renderDetailHeader(selectedFolder.name, renderAddMenu(selectedFolder), { type: 'folder', id: selectedFolder.id })}
            <div className="detail-panel__body">
              <div className="detail-panel__badges" aria-label={copy.details}>
                <span className="meta-chip"><Folder aria-hidden="true" size={14} strokeWidth={1.75} />{copy.folder}</span>
                <span className="meta-chip">{copy.childFolders}: {(childFoldersByParent[selectedFolder.id] ?? []).length}</span>
                <span className="meta-chip">{copy.goal}: {selectedFolderGoals.length}</span>
                <span className="meta-chip">{copy.task}: {selectedFolderTasks.length}</span>
                <span className="meta-chip">{copy.ideas}: {(ideasByFolder[selectedFolder.id] ?? []).length}</span>
                <span className="meta-chip">{copy.notes}: {(notesByFolder[selectedFolder.id] ?? []).length}</span>
                {selectedFolder.shared ? <span className="meta-chip">{selectedFolder.fullAccess ? copy.fullAccess : copy.sharedResource}</span> : null}
              </div>
              <p className="field__hint">{copy.dragHint}</p>
              <div className="detail-section"><div className="detail-label">{planningCopy.folders.description}</div><div className="detail-note"><StickyNote aria-hidden="true" size={15} strokeWidth={1.75} /><p>{selectedFolder.description || planningCopy.common.noDescription}</p></div></div>
              {editingEntity?.type === 'folder' && editingEntity.id === selectedFolder.id ? (
                <details className="detail-disclosure" open>
                  <summary>{copy.edit}</summary>
                  <div className="detail-editor">
                    <label className="field detail-grid__wide"><span>{planningCopy.folders.name}</span><input className="field__control" disabled={!canEditSelectedFolder} value={folderDraft.name} onChange={(event) => setFolderDraft((current) => ({ ...current, name: event.target.value }))} /></label>
                    <label className="field detail-grid__wide"><span>{planningCopy.folders.description}</span><textarea className="field__control field__control--area" disabled={!canEditSelectedFolder} value={folderDraft.description} onChange={(event) => setFolderDraft((current) => ({ ...current, description: event.target.value }))} /></label>
                    <div className="cluster detail-grid__wide detail-editor__actions">
                      <button className="button button--primary" type="button" disabled={saving || !canEditSelectedFolder || !folderDraft.name.trim()} onClick={() => void handleSaveFolder()}><Save aria-hidden="true" size={16} strokeWidth={1.75} /><span>{copy.save}</span></button>
                      <button className="button button--ghost" type="button" disabled={saving || !canEditSelectedFolder} onClick={() => void handleArchiveFolder()}><Archive aria-hidden="true" size={16} strokeWidth={1.75} /><span>{copy.archive}</span></button>
                    </div>
                  </div>
                </details>
              ) : null}
              {renderSharingPanel()}
              {renderOperationPanel()}
            </div>
          </>
        ) : (isCreatingTask || selectedTask) && panelGoal && panelFolder ? (
          <>
            {renderDetailHeader(isCreatingTask ? copy.newTask : selectedTask?.title ?? copy.task, null, selectedTask ? { type: 'task', id: selectedTask.id } : null)}
            <div className="detail-panel__body">
              {!isCreatingTask && selectedTask ? (
                <div className="detail-panel__badges" aria-label={copy.details}>
                  <span className="meta-chip" title={copy.status}><span className={`marker-dot marker-dot--${markerToneForTask(selectedTask)}`} aria-hidden="true" />{planningCopy.enums.taskStatus[selectedTask.status]}</span>
                  <span className="meta-chip" title={rowCopy.type}><span className={`marker-dot marker-dot--${selectedTask.type === 'red' ? 'red' : 'green'}`} aria-hidden="true" />{planningCopy.enums.taskType[selectedTask.type]}</span>
                  <span className="meta-chip" title={copy.priority}>P{selectedTask.priority}</span>
                  {selectedTask.dueTime ? <span className={`meta-chip meta-chip--${dueTone(selectedTask.dueTime)}`} title={copy.due}><CalendarClock aria-hidden="true" size={14} strokeWidth={1.75} />{formatDateTime(selectedTask.dueTime, locale)}</span> : null}
                  {selectedTask.plannedTime ? <span className="meta-chip" title={copy.planned}><CalendarClock aria-hidden="true" size={14} strokeWidth={1.75} />{formatDateTime(selectedTask.plannedTime, locale)}</span> : null}
                  {selectedTask.recurrence?.active ? <span className="meta-chip" title={planningCopy.tasks.recurrenceLabel}><CalendarClock aria-hidden="true" size={14} strokeWidth={1.75} />{describeRecurrence(selectedTask.recurrence, locale)}</span> : null}
                </div>
              ) : null}
              <div className="detail-section"><div className="detail-label">{copy.path}</div><div className="breadcrumb"><Folder aria-hidden="true" size={15} strokeWidth={1.75} /><span>{folderPath(panelFolder.id)} / {panelGoal.name}</span></div></div>
              {selectedCreator ? <div className="detail-section"><div className="detail-label">{copy.creator}</div><div className="breadcrumb"><UserCircle aria-hidden="true" size={15} strokeWidth={1.75} /><span>{selectedCreator}</span></div></div> : null}
              <div className="detail-section"><div className="detail-label">{planningCopy.tasks.descriptionLabel}</div><div className="detail-note"><StickyNote aria-hidden="true" size={15} strokeWidth={1.75} /><p>{selectedTask?.description || planningCopy.common.noDescription}</p></div></div>
              <details className="detail-disclosure" open>
                <summary>{copy.details}</summary>
                <div className="detail-editor">
                  <label className="field detail-grid__wide"><span>{planningCopy.tasks.titleLabel}</span><input className="field__control" disabled={!canEditSelectedTaskFields} value={draft.title} onChange={(event) => setDraft((current) => ({ ...current, title: event.target.value }))} /></label>
                  <label className="field detail-grid__wide"><span>{planningCopy.tasks.descriptionLabel}</span><textarea className="field__control field__control--area" disabled={!canEditSelectedTaskFields} value={draft.description} onChange={(event) => setDraft((current) => ({ ...current, description: event.target.value }))} /></label>
                  <label className="field"><span>{planningCopy.tasks.typeLabel}</span><select className="field__control" disabled={!canEditSelectedTaskFields} value={draft.type} onChange={(event) => setDraft((current) => ({ ...current, type: event.target.value as TaskType }))}><option value="green">{planningCopy.enums.taskType.green}</option><option value="red">{planningCopy.enums.taskType.red}</option></select></label>
                  <label className="field"><span>{planningCopy.tasks.statusLabel}</span><select className="field__control" disabled={!canEditSelectedTaskFields} value={draft.status} onChange={(event) => setDraft((current) => ({ ...current, status: event.target.value as TaskStatus }))}>{TASK_STATUSES.map((status) => <option key={status} value={status}>{planningCopy.enums.taskStatus[status]}</option>)}</select></label>
                  <label className="field"><span>{planningCopy.tasks.priorityLabel}</span><input className="field__control" inputMode="numeric" disabled={!canEditSelectedTaskFields} value={draft.priority} onChange={(event) => setDraft((current) => ({ ...current, priority: event.target.value }))} /></label>
                  <label className="field"><span>{planningCopy.tasks.plannedTimeLabel}</span><input className="field__control" type="datetime-local" disabled={!canEditSelectedTaskFields} value={draft.plannedTime} onChange={(event) => setDraft((current) => ({ ...current, plannedTime: event.target.value }))} /></label>
                  <label className="field"><span>{planningCopy.tasks.dueTimeLabel}</span><input className="field__control" type="datetime-local" disabled={!canEditSelectedTaskFields} value={draft.dueTime} onChange={(event) => setDraft((current) => ({ ...current, dueTime: event.target.value }))} /></label>
                  <div className="recurrence-editor detail-grid__wide">
                    <div className="recurrence-editor__heading">
                      <div><strong>{planningCopy.tasks.recurrenceLabel}</strong><p>{planningCopy.tasks.schedulingHelp}</p></div>
                      <label className="switch-control"><input type="checkbox" checked={draft.recurrence.enabled} disabled={!canEditSelectedTaskFields} onChange={(event) => setDraft((current) => ({ ...current, recurrence: { ...current.recurrence, enabled: event.target.checked } }))} /><span>{planningCopy.tasks.recurrenceEnabledLabel}</span></label>
                    </div>
                    {draft.recurrence.enabled ? (
                      <div className="recurrence-editor__grid">
                        <label className="field"><span>{planningCopy.tasks.recurrenceModeLabel}</span><select className="field__control" value={draft.recurrence.mode} disabled={!canEditSelectedTaskFields} onChange={(event) => setDraft((current) => ({ ...current, recurrence: { ...current.recurrence, mode: event.target.value as TaskDraft['recurrence']['mode'] } }))}><option value="daily">{planningCopy.tasks.recurrenceModeDaily}</option><option value="weekly">{planningCopy.tasks.recurrenceModeWeekly}</option><option value="monthly">{planningCopy.tasks.recurrenceModeMonthly}</option></select></label>
                        <label className="field"><span>{planningCopy.tasks.recurrenceIntervalLabel}</span><input className="field__control" inputMode="numeric" value={draft.recurrence.interval} disabled={!canEditSelectedTaskFields} onChange={(event) => setDraft((current) => ({ ...current, recurrence: { ...current.recurrence, interval: event.target.value } }))} /></label>
                        <label className="field"><span>{planningCopy.tasks.recurrenceAnchorLabel}</span><select className="field__control" value={draft.recurrence.anchor} disabled={!canEditSelectedTaskFields} onChange={(event) => setDraft((current) => ({ ...current, recurrence: { ...current.recurrence, anchor: event.target.value as TaskDraft['recurrence']['anchor'] } }))}><option value="planned">{planningCopy.tasks.anchorPlanned}</option><option value="due">{planningCopy.tasks.anchorDue}</option></select></label>
                        <label className="field"><span>{planningCopy.tasks.recurrenceEndAtLabel}</span><input className="field__control" type="datetime-local" value={draft.recurrence.endAt} disabled={!canEditSelectedTaskFields} onChange={(event) => setDraft((current) => ({ ...current, recurrence: { ...current.recurrence, endAt: event.target.value } }))} /></label>
                        {draft.recurrence.mode === 'weekly' ? (
                          <fieldset className="weekday-picker detail-grid__wide">
                            <legend>{planningCopy.tasks.recurrenceWeekdaysLabel}</legend>
                            {WEEKDAYS.map((day) => (
                              <label className="weekday-picker__item" key={day}><input type="checkbox" checked={draft.recurrence.daysOfWeek.includes(day)} disabled={!canEditSelectedTaskFields} onChange={(event) => setDraft((current) => ({ ...current, recurrence: { ...current.recurrence, daysOfWeek: event.target.checked ? [...current.recurrence.daysOfWeek, day] : current.recurrence.daysOfWeek.filter((item) => item !== day) } }))} /><span>{weekdayLabel(day, planningCopy.tasks)}</span></label>
                            ))}
                          </fieldset>
                        ) : null}
                        {currentRecurrenceError ? <div className="field__error detail-grid__wide">{currentRecurrenceError}</div> : null}
                      </div>
                    ) : null}
                  </div>
                  <div className="cluster detail-grid__wide detail-editor__actions">
                    <button className="button button--primary" type="button" disabled={saving || !canEditSelectedTaskFields || !draft.title.trim() || Boolean(currentRecurrenceError)} onClick={() => void handleSaveTask()}><Save aria-hidden="true" size={16} strokeWidth={1.75} /><span>{copy.save}</span></button>
                    {canArchiveSelectedTask && selectedTask && selectedGoal ? <button className="button button--ghost" type="button" disabled={saving} onClick={() => void handleArchiveTask(selectedTask, selectedGoal)}><Archive aria-hidden="true" size={16} strokeWidth={1.75} /><span>{copy.archive}</span></button> : null}
                  </div>
                </div>
              </details>
              {renderLinkedNotesPanel()}
              {renderLinksPanel()}
              {renderSharingPanel()}
              {renderOperationPanel()}
            </div>
          </>
        ) : (
          <div className="detail-empty">
            <Target aria-hidden="true" size={30} strokeWidth={1.75} />
            <p>{copy.selectItem}</p>
            <button className="icon-button" type="button" aria-label={copy.collapse} title={copy.collapse} onClick={() => setIsPanelOpen(false)}><PanelRightClose aria-hidden="true" size={19} strokeWidth={1.75} /></button>
          </div>
        )}
      </aside>
    </div>
  );
}
