import { useEffect, useState } from 'react';
import { Link, Navigate, useLocation, useNavigate, useSearchParams } from 'react-router-dom';

import { useI18n } from '../../../i18n';
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

function resolveNextPath(raw: string | null) {
  return raw?.startsWith('/') && !raw.startsWith('//') ? raw : '/app';
}

function authRouteWithNext(path: string, nextPath: string) {
  return nextPath === '/app' ? path : `${path}?next=${encodeURIComponent(nextPath)}`;
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
  const [submitting, setSubmitting] = useState(false);
  const nextPath = resolveNextPath(searchParams.get('next'));

  useEffect(() => {
    return () => {
      clearNotice();
    };
  }, [clearNotice]);

  if (status === 'authenticated') {
    return <Navigate to={nextPath} replace />;
  }

  const noticeMessage = resolveNoticeMessage(searchParams.get('reason'), notice, t);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const nextErrors = validateForm(formState, t);
    setFieldErrors(nextErrors);
    setFormError(null);

    if (Object.keys(nextErrors).length > 0) {
      return;
    }

    setSubmitting(true);

    try {
      const nextSession = await login(formState);
      navigate(nextPath, {
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
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="stack">
      {noticeMessage ? <AuthNotice message={noticeMessage} /> : null}
      {formError ? <AuthNotice tone="error" message={formError} /> : null}

      <AuthCard
        title={t('auth.login.title')}
        subtitle={t('auth.login.subtitle')}
        alternatePrompt={t('auth.login.alternatePrompt')}
        alternateAction={t('auth.login.alternateAction')}
        alternateTo={authRouteWithNext('/auth/register', nextPath)}
      >
        <form className="stack" onSubmit={handleSubmit}>
          <label className="field">
            <span>{t('auth.form.email')}</span>
            <input
              className="field__control"
              autoComplete="email"
              value={formState.email}
              onChange={(event) => setFormState((current) => ({ ...current, email: event.target.value }))}
            />
            {fieldErrors.email ? <span className="field__error">{fieldErrors.email}</span> : null}
          </label>

          <label className="field">
            <span>{t('auth.form.password')}</span>
            <input
              className="field__control"
              type="password"
              autoComplete="current-password"
              value={formState.password}
              onChange={(event) => setFormState((current) => ({ ...current, password: event.target.value }))}
            />
            {fieldErrors.password ? <span className="field__error">{fieldErrors.password}</span> : null}
          </label>

          <div className="cluster">
            <button className="button button--primary" type="submit" disabled={submitting}>
              {submitting ? t('auth.login.loading') : t('auth.login.submit')}
            </button>
            <Link className="button button--ghost" to="/">
              {t('routes.home.label')}
            </Link>
          </div>
        </form>
      </AuthCard>
    </div>
  );
}
