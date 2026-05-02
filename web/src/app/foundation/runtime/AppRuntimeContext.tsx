import { createContext, useContext, useMemo, type PropsWithChildren } from 'react';

import { useAuth } from '../../../features/auth';
import { useI18n, type TranslationKey } from '../../../i18n';

type SupportedLocale = 'ru' | 'en';
type SessionMode = 'guest' | 'member';
type ShellCopyKey =
  | 'brand'
  | 'tagline'
  | 'publicLabel'
  | 'protectedLabel'
  | 'previewGuest'
  | 'previewMember'
  | 'localeRu'
  | 'localeEn'
  | 'overview'
  | 'folders'
  | 'goals'
  | 'tasks'
  | 'calendar'
  | 'sharing'
  | 'settings'
  | 'authLogin'
  | 'authRegister'
  | 'signIn'
  | 'signOut'
  | 'statusRuntime'
  | 'navigation'
  | 'navigationAria'
  | 'waveBoundaries'
  | 'waveF1'
  | 'waveF2'
  | 'waveLater';

const shellCopyMap: Record<ShellCopyKey, TranslationKey> = {
  brand: 'app.brand',
  tagline: 'app.tagline',
  publicLabel: 'app.publicArea',
  protectedLabel: 'app.protectedArea',
  previewGuest: 'app.guest',
  previewMember: 'app.member',
  localeRu: 'locale.ru',
  localeEn: 'locale.en',
  overview: 'routes.overview.label',
  folders: 'routes.folders.label',
  goals: 'routes.goals.label',
  tasks: 'routes.tasks.label',
  calendar: 'routes.calendar.label',
  sharing: 'routes.sharing.label',
  settings: 'routes.settings.label',
  authLogin: 'routes.login.label',
  authRegister: 'routes.register.label',
  signIn: 'app.signIn',
  signOut: 'app.signOut',
  statusRuntime: 'app.statusRuntime',
  navigation: 'app.navigation',
  navigationAria: 'app.navigationAria',
  waveBoundaries: 'app.waveBoundaries',
  waveF1: 'app.waveF1',
  waveF2: 'app.waveF2',
  waveLater: 'app.waveLater'
};

interface AppRuntimeValue {
  locale: SupportedLocale;
  sessionMode: SessionMode;
  setLocale: (nextLocale: SupportedLocale) => void;
  copy: (key: ShellCopyKey) => string;
}

const AppRuntimeContext = createContext<AppRuntimeValue | null>(null);

export function AppRuntimeProvider({ children }: PropsWithChildren) {
  const { locale, setLocale, t } = useI18n();
  const { status } = useAuth();
  const sessionMode: SessionMode = status === 'authenticated' ? 'member' : 'guest';

  const value = useMemo<AppRuntimeValue>(
    () => ({
      locale,
      sessionMode,
      setLocale,
      copy: (key) => t(shellCopyMap[key])
    }),
    [locale, sessionMode, setLocale, t],
  );

  return <AppRuntimeContext.Provider value={value}>{children}</AppRuntimeContext.Provider>;
}

export function useAppRuntime() {
  const value = useContext(AppRuntimeContext);

  if (!value) {
    throw new Error('useAppRuntime must be used inside AppRuntimeProvider.');
  }

  return value;
}

export type { SessionMode, SupportedLocale };
