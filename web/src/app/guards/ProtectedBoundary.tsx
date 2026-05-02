import { type PropsWithChildren } from 'react';

import { AuthRequiredState, useAuth } from '../../features/auth';
import { useI18n } from '../../i18n';
import { LoadingState } from '../../ui/feedback/LoadingState';

export function ProtectedBoundary({ children }: PropsWithChildren) {
  const { status, notice } = useAuth();
  const { t } = useI18n();

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
    return (
      <div className="public-shell public-shell--centered">
        <AuthRequiredState sessionEnded={notice === 'logged_out' || notice === 'expired'} />
      </div>
    );
  }

  return <>{children}</>;
}
