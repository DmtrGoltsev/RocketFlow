export type RouteAudience = 'public' | 'protected';
export type RouteArea = 'workspace' | 'auth' | 'planning' | 'calendar' | 'sharing' | 'settings';
export type FutureOwner = 'Product' | 'Planning' | 'Advanced';

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
  readyState: 'ready';
}

export const routeInventory: RouteInventoryItem[] = [
  {
    id: 'home',
    path: '/',
    audience: 'public',
    area: 'workspace',
    nav: false,
    label: { ru: 'На главную', en: 'Home' },
    summary: { ru: 'Вход в RocketFlow.', en: 'RocketFlow entry.' },
    owner: 'Product',
    readyState: 'ready'
  },
  {
    id: 'login',
    path: '/auth/login',
    audience: 'public',
    area: 'auth',
    nav: false,
    label: { ru: 'Вход', en: 'Sign in' },
    summary: { ru: 'Вход в план.', en: 'Sign in to the plan.' },
    owner: 'Product',
    readyState: 'ready'
  },
  {
    id: 'register',
    path: '/auth/register',
    audience: 'public',
    area: 'auth',
    nav: false,
    label: { ru: 'Создать аккаунт', en: 'Create account' },
    summary: { ru: 'Создание аккаунта.', en: 'Create an account.' },
    owner: 'Product',
    readyState: 'ready'
  },
  {
    id: 'overview',
    path: '/app',
    audience: 'protected',
    area: 'planning',
    nav: false,
    label: { ru: 'План', en: 'Plan' },
    summary: { ru: 'Папки, цели и задачи.', en: 'Folders, goals, and tasks.' },
    owner: 'Planning',
    readyState: 'ready'
  },
  {
    id: 'tasks',
    path: '/app/tasks',
    audience: 'protected',
    area: 'planning',
    nav: true,
    label: { ru: 'План', en: 'Plan' },
    summary: { ru: 'Папки, цели и задачи.', en: 'Folders, goals, and tasks.' },
    owner: 'Planning',
    readyState: 'ready'
  },
  {
    id: 'calendar',
    path: '/app/calendar',
    audience: 'protected',
    area: 'calendar',
    nav: true,
    label: { ru: 'Календарь', en: 'Calendar' },
    summary: { ru: 'План задач по времени.', en: 'Time-based task plan.' },
    owner: 'Advanced',
    readyState: 'ready'
  },
  {
    id: 'sharing',
    path: '/app/sharing',
    audience: 'protected',
    area: 'sharing',
    nav: true,
    label: { ru: 'Доступ', en: 'Sharing' },
    summary: { ru: 'Инвайты и общие ресурсы.', en: 'Invitations and shared resources.' },
    owner: 'Advanced',
    readyState: 'ready'
  },
  {
    id: 'settings',
    path: '/app/settings',
    audience: 'protected',
    area: 'settings',
    nav: true,
    label: { ru: 'Настройки', en: 'Settings' },
    summary: { ru: 'Язык, уведомления и правила приоритета.', en: 'Language, notifications, and priority rules.' },
    owner: 'Advanced',
    readyState: 'ready'
  }
];

export function getRouteById(routeId: string) {
  return routeInventory.find((route) => route.id === routeId);
}
