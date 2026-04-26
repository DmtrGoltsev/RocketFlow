export type Locale = 'ru' | 'en';

const ru = {
  app: {
    brand: 'RocketFlow',
    tagline: 'Ретро-оболочка для MVP-планирования',
    publicArea: 'Публичная зона',
    protectedArea: 'Рабочая зона',
    chromePublic: 'Wave A / Shell + Auth',
    chromeProtected: 'Desktop / Protected Workspace',
    statusRuntime: 'RU-first i18n и auth foundation',
    navigation: 'Навигация',
    navigationAria: 'Основная навигация',
    waveBoundaries: 'Границы волны',
    waveF1: 'F1: shell, tokens, layouts',
    waveF2: 'F2: auth и i18n foundation',
    waveLater: 'Later: planning, calendar, sharing, settings',
    mvp: 'MVP',
    retro: 'Ретро',
    loading: 'Загрузка...',
    guest: 'Гость',
    member: 'Участник',
    signedInAs: 'Сеанс',
    signIn: 'Войти',
    signOut: 'Выйти',
    sessionRestore: 'Восстановление сеанса',
    notAuthorized: 'Не авторизован'
  },
  locale: {
    ru: 'Русский',
    en: 'English'
  },
  routes: {
    home: {
      label: 'Старт',
      summary: 'Публичный вход в ретро-оболочку и карту экранов.'
    },
    login: {
      label: 'Вход',
      summary: 'Экран входа и восстановления пользовательской сессии.'
    },
    register: {
      label: 'Регистрация',
      summary: 'Экран создания учетной записи и начального языка интерфейса.'
    },
    overview: {
      label: 'Сводка',
      summary: 'Защищенная стартовая площадка и обзор состояния модулей.'
    },
    folders: {
      label: 'Папки',
      summary: 'Навигационная зона для списка папок и будущих CRUD-потоков.'
    },
    goals: {
      label: 'Цели',
      summary: 'Граница для списка и деталей целей внутри рабочего пространства.'
    },
    tasks: {
      label: 'Задачи',
      summary: 'Зона для списка задач, редактора и конфликтных состояний.'
    },
    calendar: {
      label: 'Календарь',
      summary: 'Граница для простой day/week/month проекции и переносов.'
    },
    sharing: {
      label: 'Совместный доступ',
      summary: 'Зона для инвайтов, shared resources и будущих диалогов доступа.'
    },
    settings: {
      label: 'Настройки',
      summary: 'Граница для языка, уведомлений и правил priority decay.'
    }
  },
  routeAreas: {
    shell: 'shell',
    auth: 'auth',
    planning: 'planning',
    calendar: 'calendar',
    sharing: 'sharing',
    settings: 'settings'
  },
  home: {
    purpose: 'Назначение',
    heading: 'Каркас SPA с RU-first локализацией и основой auth/session',
    body: 'Эта волна подготавливает публичную и защищенную части приложения для следующих модулей без смены shell-границ.',
    openWorkspace: 'Открыть рабочую зону',
    openLogin: 'Открыть вход',
    openRegister: 'Открыть регистрацию',
    sessionState: 'Состояние сеанса',
    publicSurfaces: 'Публичные поверхности',
    protectedSurfaces: 'Защищенные поверхности',
    foundationNotes: 'Что уже есть',
    foundationItemRoutes: 'Маршруты уже закреплены в shell и готовы для дальнейших экранов.',
    foundationItemLocale: 'Язык интерфейса хранится локально и может быть связан с настройками позже.',
    foundationItemAuth: 'Auth provider поднимает, восстанавливает и очищает пользовательскую сессию.'
  },
  placeholder: {
    title: 'Маршрут и владение',
    pathLabel: 'Путь',
    audiencePublic: 'Public',
    audienceProtected: 'Protected',
    statusFoundation: 'foundation',
    existsTitle: 'Что уже есть',
    adjacentTitle: 'Соседние поверхности',
    stablePath: 'Стабильный путь',
    stablePathBody: 'Маршрут уже подключен в shell и готов к feature-реализации.',
    shellBody: 'Панели, заголовки и статусная строка уже единообразны.',
    integrationSlot: 'Точка интеграции',
    integrationSlotBody: 'Следующие волны могут подключать API и бизнес-логику без смены layout-границ.',
    noAdjacentTitle: 'Нет соседних поверхностей',
    noAdjacentBody: 'Эта зона служит корневой точкой входа для своей группы.'
  },
  auth: {
    login: {
      title: 'Вход',
      subtitle: 'Войдите в RocketFlow и восстановите рабочую сессию.',
      submit: 'Войти',
      loading: 'Выполняем вход...',
      alternatePrompt: 'Нет учетной записи?',
      alternateAction: 'Создать аккаунт'
    },
    register: {
      title: 'Регистрация',
      subtitle: 'Создайте аккаунт с русским интерфейсом по умолчанию.',
      submit: 'Зарегистрироваться',
      loading: 'Создаем аккаунт...',
      alternatePrompt: 'Уже есть учетная запись?',
      alternateAction: 'Открыть вход'
    },
    logout: {
      title: 'Выход из системы',
      subtitle: 'Сессия завершается, подождите немного.'
    },
    guard: {
      loadingTitle: 'Восстанавливаем сеанс',
      loadingDescription: 'Проверяем сохраненные токены и профиль пользователя.',
      redirectingTitle: 'Нужен вход',
      redirectingDescription: 'Перенаправляем на экран входа, чтобы открыть защищенную рабочую зону.',
      lockedTitle: 'Рабочая зона требует авторизации',
      lockedDescription: 'Войдите в систему, чтобы открыть папки, цели, задачи и остальные защищенные маршруты.'
    },
    session: {
      expired: 'Сохраненная сессия истекла. Войдите снова.',
      loggedOut: 'Вы вышли из системы.',
      loginRequired: 'Сначала войдите, чтобы открыть защищенный маршрут.',
      restoreFailed: 'Не удалось восстановить сеанс. Попробуйте войти снова.',
      active: 'Сеанс активен',
      anonymous: 'Сеанс не найден'
    },
    form: {
      email: 'Email',
      password: 'Пароль',
      displayName: 'Имя',
      timezone: 'Часовой пояс',
      language: 'Язык',
      timezoneHint: 'Например: Europe/Moscow',
      languageHint: 'Русский остается основным языком MVP.',
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
      unauthorized: 'Сеанс больше не действителен.',
      validation_error: 'Проверьте заполнение формы.',
      conflict: 'Такой пользователь уже существует.',
      internal_error: 'Сервер временно недоступен.'
    }
  }
};

type MessageTree = typeof ru;

const en: MessageTree = {
  app: {
    brand: 'RocketFlow',
    tagline: 'Retro shell for the planning MVP',
    publicArea: 'Public area',
    protectedArea: 'Workspace',
    chromePublic: 'Wave A / Shell + Auth',
    chromeProtected: 'Desktop / Protected Workspace',
    statusRuntime: 'RU-first i18n and auth foundation',
    navigation: 'Navigation',
    navigationAria: 'Main navigation',
    waveBoundaries: 'Wave boundaries',
    waveF1: 'F1: shell, tokens, layouts',
    waveF2: 'F2: auth and i18n foundation',
    waveLater: 'Later: planning, calendar, sharing, settings',
    mvp: 'MVP',
    retro: 'Retro',
    loading: 'Loading...',
    guest: 'Guest',
    member: 'Member',
    signedInAs: 'Session',
    signIn: 'Sign in',
    signOut: 'Sign out',
    sessionRestore: 'Restoring session',
    notAuthorized: 'Not signed in'
  },
  locale: {
    ru: 'Russian',
    en: 'English'
  },
  routes: {
    home: {
      label: 'Start',
      summary: 'Public entry to the retro shell and screen map.'
    },
    login: {
      label: 'Login',
      summary: 'Login screen and user session restore entrypoint.'
    },
    register: {
      label: 'Register',
      summary: 'Account creation screen with initial interface language.'
    },
    overview: {
      label: 'Overview',
      summary: 'Protected landing area and module status overview.'
    },
    folders: {
      label: 'Folders',
      summary: 'Navigation area for folder listing and later CRUD flows.'
    },
    goals: {
      label: 'Goals',
      summary: 'Boundary for goal list and detail surfaces in the workspace.'
    },
    tasks: {
      label: 'Tasks',
      summary: 'Zone for task list, editor, and conflict states.'
    },
    calendar: {
      label: 'Calendar',
      summary: 'Boundary for simple day/week/month projection and moves.'
    },
    sharing: {
      label: 'Sharing',
      summary: 'Zone for invitations, shared resources, and share dialogs.'
    },
    settings: {
      label: 'Settings',
      summary: 'Boundary for language, notifications, and priority decay rules.'
    }
  },
  routeAreas: {
    shell: 'shell',
    auth: 'auth',
    planning: 'planning',
    calendar: 'calendar',
    sharing: 'sharing',
    settings: 'settings'
  },
  home: {
    purpose: 'Purpose',
    heading: 'SPA shell with RU-first localization and auth/session foundation',
    body: 'This wave prepares the public and protected application areas for later modules without changing shell boundaries.',
    openWorkspace: 'Open workspace',
    openLogin: 'Open login',
    openRegister: 'Open registration',
    sessionState: 'Session state',
    publicSurfaces: 'Public surfaces',
    protectedSurfaces: 'Protected surfaces',
    foundationNotes: 'What exists now',
    foundationItemRoutes: 'Routes are already fixed in the shell and ready for later screens.',
    foundationItemLocale: 'Interface language persists locally and can be linked to settings later.',
    foundationItemAuth: 'The auth provider bootstraps, restores, and clears the user session.'
  },
  placeholder: {
    title: 'Route and ownership',
    pathLabel: 'Path',
    audiencePublic: 'Public',
    audienceProtected: 'Protected',
    statusFoundation: 'foundation',
    existsTitle: 'What exists now',
    adjacentTitle: 'Adjacent surfaces',
    stablePath: 'Stable path',
    stablePathBody: 'The route is already mounted in the shell and ready for feature work.',
    shellBody: 'Panels, headers, and the status bar are already consistent.',
    integrationSlot: 'Integration slot',
    integrationSlotBody: 'Later waves can plug in APIs and business logic without changing layout boundaries.',
    noAdjacentTitle: 'No adjacent surfaces',
    noAdjacentBody: 'This area acts as the root entry point for its group.'
  },
  auth: {
    login: {
      title: 'Login',
      subtitle: 'Sign in to RocketFlow and restore your workspace session.',
      submit: 'Sign in',
      loading: 'Signing in...',
      alternatePrompt: 'No account yet?',
      alternateAction: 'Create account'
    },
    register: {
      title: 'Register',
      subtitle: 'Create an account with Russian as the default interface language.',
      submit: 'Register',
      loading: 'Creating account...',
      alternatePrompt: 'Already have an account?',
      alternateAction: 'Open login'
    },
    logout: {
      title: 'Signing out',
      subtitle: 'Ending your session, please wait a moment.'
    },
    guard: {
      loadingTitle: 'Restoring session',
      loadingDescription: 'Checking saved tokens and the current user profile.',
      redirectingTitle: 'Login required',
      redirectingDescription: 'Redirecting to the login screen so the protected workspace can open.',
      lockedTitle: 'Workspace requires authentication',
      lockedDescription: 'Sign in to open folders, goals, tasks, and the rest of the protected routes.'
    },
    session: {
      expired: 'Your saved session expired. Please sign in again.',
      loggedOut: 'You signed out successfully.',
      loginRequired: 'Please sign in before opening a protected route.',
      restoreFailed: 'The session could not be restored. Please sign in again.',
      active: 'Session active',
      anonymous: 'No session found'
    },
    form: {
      email: 'Email',
      password: 'Password',
      displayName: 'Display name',
      timezone: 'Timezone',
      language: 'Language',
      timezoneHint: 'For example: Europe/Moscow',
      languageHint: 'Russian stays the primary MVP language.',
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
      unauthorized: 'The session is no longer valid.',
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
