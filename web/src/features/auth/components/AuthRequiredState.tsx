import { Link } from 'react-router-dom';
import { LockKeyhole } from 'lucide-react';

import { useI18n } from '../../../i18n';

interface AuthRequiredStateProps {
  sessionEnded?: boolean;
  loginTo?: string;
  registerTo?: string;
}

export function AuthRequiredState({ sessionEnded = false, loginTo = '/auth/login', registerTo = '/auth/register' }: AuthRequiredStateProps) {
  const { t } = useI18n();

  return (
    <section className="lock-state" role="status">
      <div className="lock-state__icon" aria-hidden="true">
        <LockKeyhole size={24} strokeWidth={1.75} />
      </div>
      <div className="stack stack--tight">
        <h1 className="lock-state__title">
          {sessionEnded ? t('auth.guard.signedOutTitle') : t('auth.guard.lockedTitle')}
        </h1>
        <p className="lock-state__copy">
          {sessionEnded ? t('auth.guard.signedOutDescription') : t('auth.guard.lockedDescription')}
        </p>
      </div>
      <div className="entry-actions">
        <Link className="button button--primary" to={loginTo}>
          {t('app.signIn')}
        </Link>
        <Link className="button button--ghost" to={registerTo}>
          {t('auth.login.alternateAction')}
        </Link>
      </div>
    </section>
  );
}
