import { Globe2, LogOut } from 'lucide-react';

import { useAuth } from '../../features/auth';
import { useAppRuntime } from '../../app/foundation/runtime/AppRuntimeContext';

interface LanguageSwitchProps {
  compact?: boolean;
}

export function LanguageSwitch({ compact = false }: LanguageSwitchProps) {
  const { locale, setLocale } = useAppRuntime();
  const { status, syncSessionLanguage } = useAuth();
  const label = locale === 'ru' ? 'Язык' : 'Language';

  function handleLocaleChange(nextLocale: 'ru' | 'en') {
    if (status === 'authenticated') {
      syncSessionLanguage(nextLocale);
      return;
    }

    setLocale(nextLocale);
  }

  return (
    <div className={`language-switch${compact ? ' language-switch--compact' : ''}`} aria-label={label}>
      <Globe2 aria-hidden="true" size={16} strokeWidth={1.75} />
      <button
        type="button"
        className="language-switch__segment"
        aria-pressed={locale === 'ru'}
        onClick={() => handleLocaleChange('ru')}
      >
        RU
      </button>
      <button
        type="button"
        className="language-switch__segment"
        aria-pressed={locale === 'en'}
        onClick={() => handleLocaleChange('en')}
      >
        EN
      </button>
    </div>
  );
}

export function LogoutButton() {
  const { copy } = useAppRuntime();
  const { logout } = useAuth();

  return (
    <button
      type="button"
      className="icon-button"
      aria-label={copy('signOut')}
      title={copy('signOut')}
      onClick={() => void logout()}
    >
      <LogOut aria-hidden="true" size={20} strokeWidth={1.75} />
    </button>
  );
}

export function StatusBar() {
  const { copy } = useAppRuntime();

  return (
    <div className="status-line">
      <span className="sync-dot" aria-hidden="true" />
      <span>{copy('statusRuntime')}</span>
    </div>
  );
}
