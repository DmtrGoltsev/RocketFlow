import { useEffect, useState } from 'react';
import { Link, Navigate, useLocation, useNavigate, useSearchParams } from 'react-router-dom';

import { useI18n } from '../../../i18n';
import { RetroButton } from '../../../ui/primitives/RetroButton';
import { RetroField } from '../../../ui/primitives/RetroField';
import { AuthCard } from '../components/AuthCard';
import { AuthNotice } from '../components/AuthNotice';
import { mapAuthErrorMessage, useAuth } from '../AuthProvider';

interface LoginFormState {
  email: string;
  password: string;
}

function validateForm(state: LoginFormState, t: ReturnType<typeof useI18n>['t']) {
  const nextErrors: Record<string, string> = {};

  if (!state.email.trim()) {
    nextErrors.email = t('auth.validation.emailRequired');
  } else if (!/^\S+@\S+\.\S+$/.test(state.email)) {
    nextErrors.email = t('auth.validation.emailInvalid');
  }

  if (!state.password) {
    nextErrors.password = t('auth.validation.passwordRequired');
  }

  return nextErrors;
}

function resolveNoticeMessage(
  reason: string | null,
  notice: ReturnType<typeof useAuth>['notice'],
  t: ReturnType<typeof useI18n>['t'],
) {
  if (reason === 'expired' || notice === 'expired') {
    return t('auth.session.expired');
  }

  if (reason === 'logout' || notice === 'logged_out') {
    return t('auth.session.loggedOut');
  }

  if (reason === 'required' || notice === 'login_required') {
    return t('auth.session.loginRequired');
  }

  if (notice === 'restore_failed') {
    return t('auth.session.restoreFailed');
  }

  return null;
}

export function LoginRoute() {
  const { t } = useI18n();
  const { status, login, notice, clearNotice } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [searchParams] = useSearchParams();
  const [formState, setFormState] = useState<LoginFormState>({
    email: '',
    password: ''
  });
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [formError, setFormError] = useState<string | null>(null);
  const [traceId, setTraceId] = useState<string | undefined>(undefined);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    return () => {
      clearNotice();
    };
  }, [clearNotice]);

  if (status === 'authenticated') {
    const nextPath = searchParams.get('next') ?? '/app';
    return <Navigate to={nextPath} replace />;
  }

  const noticeMessage = resolveNoticeMessage(searchParams.get('reason'), notice, t);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const nextErrors = validateForm(formState, t);
    setFieldErrors(nextErrors);
    setFormError(null);
    setTraceId(undefined);

    if (Object.keys(nextErrors).length > 0) {
      return;
    }

    setSubmitting(true);

    try {
      const nextSession = await login(formState);
      navigate(searchParams.get('next') ?? '/app', {
        replace: true,
        state: {
          from: location.pathname,
          userId: nextSession.user.id
        }
      });
    } catch (error) {
      const mapped = mapAuthErrorMessage(error, t);
      setFieldErrors(mapped.fieldErrors);
      setFormError(mapped.formError);
      setTraceId(mapped.traceId);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="stack">
      {noticeMessage ? <AuthNotice message={noticeMessage} /> : null}
      {formError ? <AuthNotice tone="error" message={formError} traceId={traceId} /> : null}

      <AuthCard
        title={t('auth.login.title')}
        subtitle={t('auth.login.subtitle')}
        alternatePrompt={t('auth.login.alternatePrompt')}
        alternateAction={t('auth.login.alternateAction')}
        alternateTo="/auth/register"
      >
        <form className="stack" onSubmit={handleSubmit}>
          <RetroField label={t('auth.form.email')}>
            <input
              className="retro-input"
              autoComplete="email"
              value={formState.email}
              onChange={(event) => setFormState((current) => ({ ...current, email: event.target.value }))}
            />
          </RetroField>
          {fieldErrors.email ? <div className="muted">{fieldErrors.email}</div> : null}

          <RetroField label={t('auth.form.password')}>
            <input
              className="retro-input"
              type="password"
              autoComplete="current-password"
              value={formState.password}
              onChange={(event) => setFormState((current) => ({ ...current, password: event.target.value }))}
            />
          </RetroField>
          {fieldErrors.password ? <div className="muted">{fieldErrors.password}</div> : null}

          <div className="cluster">
            <RetroButton type="submit" variant="primary" disabled={submitting}>
              {submitting ? t('auth.login.loading') : t('auth.login.submit')}
            </RetroButton>
            <RetroButton as={Link} to="/" variant="ghost">
              {t('routes.home.label')}
            </RetroButton>
          </div>
        </form>
      </AuthCard>
    </div>
  );
}

