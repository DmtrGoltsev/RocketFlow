export type Locale = 'ru' | 'en';

const ru = {
  app: {
    brand: 'RocketFlow',
    tagline: 'Папки, цели и задачи в одном спокойном рабочем пространстве.',
    publicArea: 'Вход',
    protectedArea: 'План',
    chromePublic: 'RocketFlow',
    chromeProtected: 'План',
    statusRuntime: 'Синхронизировано',
    navigation: 'Навигация',
    navigationAria: 'Основная навигация',
    waveBoundaries: 'Разделы',
    waveF1: 'Папки',
    waveF2: 'Цели',
    waveLater: 'Задачи',
    retro: 'Классика',
    loading: 'Загрузка...',
    guest: 'Гость',
    member: 'Участник',
    signedInAs: 'Профиль',
    signIn: 'Войти',
    signOut: 'Выйти',
    sessionRestore: 'Проверяем вход',
    notAuthorized: 'Не авторизован'
  },
  locale: {
    ru: 'Русский',
    en: 'English'
  },
  routes: {
    home: {
      label: 'На главную',
      summary: 'Вход в RocketFlow.'
    },
    login: {
      label: 'Вход',
      summary: 'Вход в план.'
    },
    register: {
      label: 'Создать аккаунт',
      summary: 'Создание аккаунта.'
    },
    overview: {
      label: 'План',
      summary: 'Папки, цели и задачи.'
    },
    folders: {
      label: 'Папки',
      summary: 'Рабочие папки.'
    },
    goals: {
      label: 'Цели',
      summary: 'Цели внутри папок.'
    },
    tasks: {
      label: 'План',
      summary: 'Планирование задач.'
    },
    calendar: {
      label: 'Календарь',
      summary: 'План по времени.'
    },
    sharing: {
      label: 'Совместный доступ',
      summary: 'Общие задачи.'
    },
    settings: {
      label: 'Настройки',
      summary: 'Язык и синхронизация.'
    }
  },
  routeAreas: {
    shell: 'План',
    auth: 'Вход',
    planning: 'План',
    calendar: 'Календарь',
    sharing: 'Доступ',
    settings: 'Настройки'
  },
  home: {
    purpose: 'Планирование',
    heading: 'RocketFlow',
    body: 'Папки, цели и задачи в одном спокойном рабочем пространстве.',
    openWorkspace: 'Открыть план',
    openLogin: 'Войти',
    openRegister: 'Создать аккаунт',
    sessionState: 'Вход',
    publicSurfaces: 'Вход',
    protectedSurfaces: 'План',
    foundationNotes: 'RocketFlow',
    foundationItemRoutes: 'Папки держат цели вместе.',
    foundationItemLocale: 'Язык интерфейса сохраняется.',
    foundationItemAuth: 'Вход сохраняется при возвращении.'
  },
  auth: {
    login: {
      title: 'Вход',
      subtitle: 'Войдите, чтобы открыть план.',
      submit: 'Войти',
      loading: 'Входим...',
      alternatePrompt: 'Нет аккаунта?',
      alternateAction: 'Создать аккаунт'
    },
    register: {
      title: 'Создать аккаунт',
      subtitle: 'Русский включен по умолчанию.',
      submit: 'Создать аккаунт',
      loading: 'Создаем...',
      alternatePrompt: 'Уже есть аккаунт?',
      alternateAction: 'Войти'
    },
    logout: {
      title: 'Сессия завершена',
      subtitle: 'Войдите снова, чтобы продолжить.'
    },
    guard: {
      loadingTitle: 'Проверяем вход',
      loadingDescription: 'Проверяем сохраненный вход.',
      redirectingTitle: 'Нужен вход',
      redirectingDescription: 'Войдите, чтобы открыть план.',
      lockedTitle: 'Нужен вход',
      lockedDescription: 'Войдите, чтобы открыть план.',
      signedOutTitle: 'Сессия завершена',
      signedOutDescription: 'Войдите снова, чтобы продолжить.'
    },
    session: {
      expired: 'Сессия завершена. Войдите снова.',
      loggedOut: 'Сессия завершена.',
      loginRequired: 'Войдите, чтобы открыть план.',
      restoreFailed: 'Не удалось восстановить вход. Войдите снова.',
      active: 'Вход выполнен',
      anonymous: 'Вход не выполнен'
    },
    form: {
      email: 'Email',
      password: 'Пароль',
      displayName: 'Имя',
      timezone: 'Часовой пояс',
      language: 'Язык',
      timezoneHint: 'Например: Europe/Moscow',
      languageHint: 'Русский остается языком по умолчанию.',
      submitErrorFallback: 'Не удалось выполнить запрос. Попробуйте еще раз.'
    },
    validation: {
      emailRequired: 'Укажите email.',
      emailInvalid: 'Введите корректный email.',
      passwordRequired: 'Укажите пароль.',
      passwordMin: 'Пароль должен содержать минимум 8 символов.',
      displayNameRequired: 'Укажите имя.',
      timezoneRequired: 'Укажите часовой пояс.'
    },
    api: {
      authentication_failed: 'Неверный email или пароль.',
      unauthorized: 'Войдите снова, чтобы продолжить.',
      validation_error: 'Проверьте заполнение формы.',
      conflict: 'Пользователь с таким email уже существует.',
      internal_error: 'Сервер временно недоступен.'
    }
  }
};

type MessageTree = typeof ru;

const en: MessageTree = {
  app: {
    brand: 'RocketFlow',
    tagline: 'Folders, goals, and tasks in one quiet workspace.',
    publicArea: 'Sign in',
    protectedArea: 'Plan',
    chromePublic: 'RocketFlow',
    chromeProtected: 'Plan',
    statusRuntime: 'Synced',
    navigation: 'Navigation',
    navigationAria: 'Main navigation',
    waveBoundaries: 'Sections',
    waveF1: 'Folders',
    waveF2: 'Goals',
    waveLater: 'Tasks',
    retro: 'Classic',
    loading: 'Loading...',
    guest: 'Guest',
    member: 'Member',
    signedInAs: 'Account',
    signIn: 'Sign in',
    signOut: 'Sign out',
    sessionRestore: 'Restoring sign-in',
    notAuthorized: 'Not signed in'
  },
  locale: {
    ru: 'Russian',
    en: 'English'
  },
  routes: {
    home: {
      label: 'Home',
      summary: 'RocketFlow entry.'
    },
    login: {
      label: 'Sign in',
      summary: 'Sign in to open your plan.'
    },
    register: {
      label: 'Create account',
      summary: 'Create an account.'
    },
    overview: {
      label: 'Plan',
      summary: 'Folders, goals, and tasks.'
    },
    folders: {
      label: 'Folders',
      summary: 'Workspace folders.'
    },
    goals: {
      label: 'Goals',
      summary: 'Goals inside folders.'
    },
    tasks: {
      label: 'Plan',
      summary: 'Task planning.'
    },
    calendar: {
      label: 'Calendar',
      summary: 'Time-based plan.'
    },
    sharing: {
      label: 'Sharing',
      summary: 'Shared tasks.'
    },
    settings: {
      label: 'Settings',
      summary: 'Language and sync.'
    }
  },
  routeAreas: {
    shell: 'Plan',
    auth: 'Sign in',
    planning: 'Plan',
    calendar: 'Calendar',
    sharing: 'Sharing',
    settings: 'Settings'
  },
  home: {
    purpose: 'Planning',
    heading: 'RocketFlow',
    body: 'Folders, goals, and tasks in one quiet workspace.',
    openWorkspace: 'Open plan',
    openLogin: 'Sign in',
    openRegister: 'Create account',
    sessionState: 'Sign-in',
    publicSurfaces: 'Sign in',
    protectedSurfaces: 'Plan',
    foundationNotes: 'RocketFlow',
    foundationItemRoutes: 'Folders keep goals together.',
    foundationItemLocale: 'Interface language persists.',
    foundationItemAuth: 'Sign-in is remembered when you return.'
  },
  auth: {
    login: {
      title: 'Sign in',
      subtitle: 'Sign in to open your plan.',
      submit: 'Sign in',
      loading: 'Signing in...',
      alternatePrompt: 'No account yet?',
      alternateAction: 'Create account'
    },
    register: {
      title: 'Create account',
      subtitle: 'Russian is the default interface language.',
      submit: 'Create account',
      loading: 'Creating...',
      alternatePrompt: 'Already have an account?',
      alternateAction: 'Sign in'
    },
    logout: {
      title: 'Signed out',
      subtitle: 'Sign in again to continue.'
    },
    guard: {
      loadingTitle: 'Checking sign-in',
      loadingDescription: 'Checking saved sign-in.',
      redirectingTitle: 'Sign in required',
      redirectingDescription: 'Sign in to open your plan.',
      lockedTitle: 'Sign in required',
      lockedDescription: 'Sign in to open your plan.',
      signedOutTitle: 'Signed out',
      signedOutDescription: 'Sign in again to continue.'
    },
    session: {
      expired: 'Signed out. Please sign in again.',
      loggedOut: 'Signed out.',
      loginRequired: 'Sign in to open your plan.',
      restoreFailed: 'Sign-in could not be restored. Please sign in again.',
      active: 'Signed in',
      anonymous: 'Signed out'
    },
    form: {
      email: 'Email',
      password: 'Password',
      displayName: 'Display name',
      timezone: 'Timezone',
      language: 'Language',
      timezoneHint: 'For example: Europe/Moscow',
      languageHint: 'Russian remains the default language.',
      submitErrorFallback: 'Request failed. Please try again.'
    },
    validation: {
      emailRequired: 'Email is required.',
      emailInvalid: 'Enter a valid email.',
      passwordRequired: 'Password is required.',
      passwordMin: 'Password must be at least 8 characters.',
      displayNameRequired: 'Display name is required.',
      timezoneRequired: 'Timezone is required.'
    },
    api: {
      authentication_failed: 'Incorrect email or password.',
      unauthorized: 'Please sign in again to continue.',
      validation_error: 'Please review the form fields.',
      conflict: 'A user with this email already exists.',
      internal_error: 'The server is temporarily unavailable.'
    }
  }
};

type Join<K extends string, P extends string> = `${K}.${P}`;

type MessageKeyOf<T> = {
  [K in keyof T & string]: T[K] extends string ? K : Join<K, MessageKeyOf<T[K]>>;
}[keyof T & string];

export type TranslationKey = MessageKeyOf<MessageTree>;

export const resources: Record<Locale, MessageTree> = {
  ru,
  en
};
