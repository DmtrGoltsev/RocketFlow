export type RouteAudience = 'public' | 'protected';
export type RouteArea =
  | 'shell'
  | 'auth'
  | 'planning'
  | 'calendar'
  | 'sharing'
  | 'settings';
export type FutureOwner = 'F1' | 'F2' | 'Planning' | 'Advanced';

export interface RouteInventoryItem {
  id: string;
  path: string;
  audience: RouteAudience;
  area: RouteArea;
  nav: boolean;
  label: {
    ru: string;
    en: string;
  };
  summary: {
    ru: string;
    en: string;
  };
  owner: FutureOwner;
  readyState: 'foundation';
}

export const routeInventory: RouteInventoryItem[] = [
  {
    id: 'home',
    path: '/',
    audience: 'public',
    area: 'shell',
    nav: false,
    label: { ru: 'Старт', en: 'Start' },
    summary: {
      ru: 'Публичный вход в ретро-оболочку и карту экранов.',
      en: 'Public entry to the retro shell and screen map.'
    },
    owner: 'F1',
    readyState: 'foundation'
  },
  {
    id: 'login',
    path: '/auth/login',
    audience: 'public',
    area: 'auth',
    nav: false,
    label: { ru: 'Вход', en: 'Login' },
    summary: {
      ru: 'Граница для будущего экрана входа и восстановления сессии.',
      en: 'Boundary for the future login and session restore screen.'
    },
    owner: 'F2',
    readyState: 'foundation'
  },
  {
    id: 'register',
    path: '/auth/register',
    audience: 'public',
    area: 'auth',
    nav: false,
    label: { ru: 'Регистрация', en: 'Register' },
    summary: {
      ru: 'Граница для будущего экрана регистрации.',
      en: 'Boundary for the future registration screen.'
    },
    owner: 'F2',
    readyState: 'foundation'
  },
  {
    id: 'overview',
    path: '/app',
    audience: 'protected',
    area: 'shell',
    nav: true,
    label: { ru: 'Сводка', en: 'Overview' },
    summary: {
      ru: 'Внутренняя стартовая площадка и сводка состояния модулей.',
      en: 'Protected landing area and module status summary.'
    },
    owner: 'F1',
    readyState: 'foundation'
  },
  {
    id: 'folders',
    path: '/app/folders',
    audience: 'protected',
    area: 'planning',
    nav: true,
    label: { ru: 'Папки', en: 'Folders' },
    summary: {
      ru: 'Навигационная зона для списка папок и будущих CRUD-потоков.',
      en: 'Navigation area for folder listing and later CRUD flows.'
    },
    owner: 'Planning',
    readyState: 'foundation'
  },
  {
    id: 'goals',
    path: '/app/goals',
    audience: 'protected',
    area: 'planning',
    nav: true,
    label: { ru: 'Цели', en: 'Goals' },
    summary: {
      ru: 'Граница списка и деталей целей внутри одной рабочей области.',
      en: 'Boundary for goal list and detail surfaces in the workspace.'
    },
    owner: 'Planning',
    readyState: 'foundation'
  },
  {
    id: 'tasks',
    path: '/app/tasks',
    audience: 'protected',
    area: 'planning',
    nav: true,
    label: { ru: 'Задачи', en: 'Tasks' },
    summary: {
      ru: 'Плейсхолдер для списка, редактора и конфликтных состояний задач.',
      en: 'Placeholder for task list, editor, and conflict states.'
    },
    owner: 'Planning',
    readyState: 'foundation'
  },
  {
    id: 'calendar',
    path: '/app/calendar',
    audience: 'protected',
    area: 'calendar',
    nav: true,
    label: { ru: 'Календарь', en: 'Calendar' },
    summary: {
      ru: 'Граница для простой day/week/month проекции и переносов.',
      en: 'Boundary for simple day/week/month projection and moves.'
    },
    owner: 'Advanced',
    readyState: 'foundation'
  },
  {
    id: 'sharing',
    path: '/app/sharing',
    audience: 'protected',
    area: 'sharing',
    nav: true,
    label: { ru: 'Совместный доступ', en: 'Sharing' },
    summary: {
      ru: 'Зона для инвайтов, shared resources и будущих диалогов доступа.',
      en: 'Zone for invitations, shared resources, and share dialogs.'
    },
    owner: 'Advanced',
    readyState: 'foundation'
  },
  {
    id: 'settings',
    path: '/app/settings',
    audience: 'protected',
    area: 'settings',
    nav: true,
    label: { ru: 'Настройки', en: 'Settings' },
    summary: {
      ru: 'Граница для языка, уведомлений и правил priority decay.',
      en: 'Boundary for language, notifications, and priority decay rules.'
    },
    owner: 'Advanced',
    readyState: 'foundation'
  }
];

export function getRouteById(routeId: string) {
  return routeInventory.find((route) => route.id === routeId);
}
