import { useEffect } from 'react';
import { useNavigate } from 'react-router-dom';

import { useI18n } from '../../../i18n';
import { LoadingState } from '../../../ui/feedback/LoadingState';
import { useAuth } from '../AuthProvider';

export function LogoutRoute() {
  const { t } = useI18n();
  const { logout } = useAuth();
  const navigate = useNavigate();

  useEffect(() => {
    logout()
      .catch(() => undefined)
      .finally(() => {
        navigate('/auth/login?reason=logout', { replace: true });
      });
  }, [logout, navigate]);

  return (
    <LoadingState
      title={t('auth.logout.title')}
      description={t('auth.logout.subtitle')}
    />
  );
}

