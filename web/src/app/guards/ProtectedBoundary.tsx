import { type PropsWithChildren } from 'react';
import { useLocation } from 'react-router-dom';

import { AuthRequiredState, useAuth } from '../../features/auth';
import { useI18n } from '../../i18n';
import { LoadingState } from '../../ui/feedback/LoadingState';

export function ProtectedBoundary({ children }: PropsWithChildren) {
  const { status, notice } = useAuth();
  const { t } = useI18n();
  const location = useLocation();

  if (status === 'bootstrapping') {
    return (
      <div className="public-shell public-shell--centered">
        <LoadingState
          title={t('auth.guard.loadingTitle')}
          description={t('auth.guard.loadingDescription')}
        />
      </div>
    );
  }

  if (status !== 'authenticated') {
    const next = `${location.pathname}${location.search}${location.hash}`;
    const encodedNext = encodeURIComponent(next);
    return (
      <div className="public-shell public-shell--centered">
        <AuthRequiredState
          sessionEnded={notice === 'logged_out' || notice === 'expired'}
          loginTo={`/auth/login?reason=required&next=${encodedNext}`}
          registerTo={`/auth/register?next=${encodedNext}`}
        />
      </div>
    );
  }

  return <>{children}</>;
}
