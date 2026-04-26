import { Link } from 'react-router-dom';

import { useI18n } from '../../../i18n';
import { RetroButton } from '../../../ui/primitives/RetroButton';
import { RetroPanel } from '../../../ui/primitives/RetroPanel';

export function AuthRequiredState() {
  const { t } = useI18n();

  return (
    <RetroPanel title={t('auth.guard.lockedTitle')}>
      <div className="stack">
        <div className="surface-subtitle">{t('auth.guard.lockedDescription')}</div>
        <div className="cluster">
          <RetroButton as={Link} to="/auth/login" variant="primary">
            {t('app.signIn')}
          </RetroButton>
          <RetroButton as={Link} to="/" variant="ghost">
            {t('routes.home.label')}
          </RetroButton>
        </div>
      </div>
    </RetroPanel>
  );
}

