import { type PropsWithChildren } from 'react';

import { AuthRequiredState, useAuth } from '../../features/auth';
import { useI18n } from '../../i18n';
import { LoadingState } from '../../ui/feedback/LoadingState';
import { useAppRuntime } from '../foundation/runtime/AppRuntimeContext';

export function ProtectedBoundary({ children }: PropsWithChildren) {
  useAppRuntime();
  const { status } = useAuth();
  const { t } = useI18n();

  if (status === 'bootstrapping') {
    return (
      <div className="shell-page shell-page--public">
        <div className="hero-grid">
          <LoadingState
            title={t('auth.guard.loadingTitle')}
            description={t('auth.guard.loadingDescription')}
          />
        </div>
      </div>
    );
  }

  if (status !== 'authenticated') {
    return (
      <div className="shell-page shell-page--public">
        <div className="hero-grid">
          <AuthRequiredState />
        </div>
      </div>
    );
  }

  return <>{children}</>;
}
