import { Link } from 'react-router-dom';

import { useAuth } from '../../features/auth';
import { RetroButton } from '../primitives/RetroButton';
import { useAppRuntime } from '../../app/foundation/runtime/AppRuntimeContext';

export function StatusBar() {
  const { copy, locale, sessionMode, setLocale } = useAppRuntime();
  const { status } = useAuth();

  return (
    <div className="retro-statusbar">
      <div className="cluster">
        <span>{copy('brand')}</span>
        <span className="muted">|</span>
        <span>{locale === 'ru' ? 'Auth + i18n foundation' : 'Auth + i18n foundation'}</span>
      </div>

      <div className="cluster">
        <RetroButton
          variant={locale === 'ru' ? 'primary' : 'ghost'}
          size="small"
          onClick={() => setLocale('ru')}
        >
          {copy('localeRu')}
        </RetroButton>
        <RetroButton
          variant={locale === 'en' ? 'primary' : 'ghost'}
          size="small"
          onClick={() => setLocale('en')}
        >
          {copy('localeEn')}
        </RetroButton>
        {status === 'authenticated' ? (
          <RetroButton as={Link} to="/auth/logout" variant="danger" size="small">
            {copy('signOut')}
          </RetroButton>
        ) : (
          <RetroButton as={Link} to="/auth/login" variant="primary" size="small">
            {copy('signIn')}
          </RetroButton>
        )}
        <span className="muted">
          {sessionMode === 'member' ? copy('previewMember') : copy('previewGuest')}
        </span>
      </div>
    </div>
  );
}
