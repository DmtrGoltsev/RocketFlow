import { createContext, useContext, useEffect, useState, type PropsWithChildren } from 'react';

import { resources, type Locale, type TranslationKey } from './resources';

const LOCALE_STORAGE_KEY = 'rocketflow.locale';

interface I18nContextValue {
  locale: Locale;
  setLocale: (nextLocale: Locale) => void;
  t: (key: TranslationKey) => string;
}

const I18nContext = createContext<I18nContextValue | null>(null);

function resolveMessage(locale: Locale, key: TranslationKey) {
  const value = key.split('.').reduce<unknown>((current, segment) => {
    if (!current || typeof current !== 'object') {
      return undefined;
    }

    return (current as Record<string, unknown>)[segment];
  }, resources[locale]);

  return typeof value === 'string' ? value : key;
}

function readStoredLocale(): Locale {
  const savedLocale = window.localStorage.getItem(LOCALE_STORAGE_KEY);

  return savedLocale === 'en' ? 'en' : 'ru';
}

export function I18nProvider({ children }: PropsWithChildren) {
  const [locale, setLocaleState] = useState<Locale>(() => readStoredLocale());

  useEffect(() => {
    document.documentElement.lang = locale;
    window.localStorage.setItem(LOCALE_STORAGE_KEY, locale);
  }, [locale]);

  function setLocale(nextLocale: Locale) {
    setLocaleState(nextLocale);
  }

  function t(key: TranslationKey) {
    return resolveMessage(locale, key);
  }

  return (
    <I18nContext.Provider value={{ locale, setLocale, t }}>
      {children}
    </I18nContext.Provider>
  );
}

export function useI18n() {
  const value = useContext(I18nContext);

  if (!value) {
    throw new Error('useI18n must be used inside I18nProvider.');
  }

  return value;
}

export { LOCALE_STORAGE_KEY };

