import { useState } from 'react';
import { Link, Navigate, useNavigate, useSearchParams } from 'react-router-dom';

import { useI18n } from '../../../i18n';
import { AuthCard } from '../components/AuthCard';
import { AuthNotice } from '../components/AuthNotice';
import { mapAuthErrorMessage, useAuth } from '../AuthProvider';

interface RegisterFormState {
  email: string;
  password: string;
  displayName: string;
  timezone: string;
  language: 'ru' | 'en';
}

function validateForm(state: RegisterFormState, t: ReturnType<typeof useI18n>['t']) {
  const nextErrors: Record<string, string> = {};

  if (!state.displayName.trim()) {
    nextErrors.displayName = t('auth.validation.displayNameRequired');
  }

  if (!state.email.trim()) {
    nextErrors.email = t('auth.validation.emailRequired');
  } else if (!/^\S+@\S+\.\S+$/.test(state.email)) {
    nextErrors.email = t('auth.validation.emailInvalid');
  }

  if (!state.password) {
    nextErrors.password = t('auth.validation.passwordRequired');
  } else if (state.password.length < 8) {
    nextErrors.password = t('auth.validation.passwordMin');
  }

  if (!state.timezone.trim()) {
    nextErrors.timezone = t('auth.validation.timezoneRequired');
  }

  return nextErrors;
}

function resolveNextPath(raw: string | null) {
  return raw?.startsWith('/') && !raw.startsWith('//') ? raw : '/app';
}

function authRouteWithNext(path: string, nextPath: string) {
  return nextPath === '/app' ? path : `${path}?next=${encodeURIComponent(nextPath)}`;
}

export function RegisterRoute() {
  const { t, locale, setLocale } = useI18n();
  const { status, register } = useAuth();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [formState, setFormState] = useState<RegisterFormState>({
    email: '',
    password: '',
    displayName: '',
    timezone: 'Europe/Moscow',
    language: locale
  });
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [formError, setFormError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const nextPath = resolveNextPath(searchParams.get('next'));

  if (status === 'authenticated') {
    return <Navigate to={nextPath} replace />;
  }

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
      const nextSession = await register(formState);
      setLocale(nextSession.user.language);
      navigate(nextPath, { replace: true });
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
      {formError ? <AuthNotice tone="error" message={formError} /> : null}

      <AuthCard
        title={t('auth.register.title')}
        subtitle={t('auth.register.subtitle')}
        alternatePrompt={t('auth.register.alternatePrompt')}
        alternateAction={t('auth.register.alternateAction')}
        alternateTo={authRouteWithNext('/auth/login', nextPath)}
      >
        <form className="stack" onSubmit={handleSubmit}>
          <label className="field">
            <span>{t('auth.form.displayName')}</span>
            <input
              className="field__control"
              autoComplete="name"
              value={formState.displayName}
              onChange={(event) => setFormState((current) => ({ ...current, displayName: event.target.value }))}
            />
            {fieldErrors.displayName ? <span className="field__error">{fieldErrors.displayName}</span> : null}
          </label>

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
              autoComplete="new-password"
              value={formState.password}
              onChange={(event) => setFormState((current) => ({ ...current, password: event.target.value }))}
            />
            {fieldErrors.password ? <span className="field__error">{fieldErrors.password}</span> : null}
          </label>

          <label className="field">
            <span>{t('auth.form.timezone')}</span>
            <input
              className="field__control"
              autoComplete="off"
              value={formState.timezone}
              onChange={(event) => setFormState((current) => ({ ...current, timezone: event.target.value }))}
            />
            <span className="field__hint">{t('auth.form.timezoneHint')}</span>
            {fieldErrors.timezone ? <span className="field__error">{fieldErrors.timezone}</span> : null}
          </label>

          <label className="field">
            <span>{t('auth.form.language')}</span>
            <select
              className="field__control"
              value={formState.language}
              onChange={(event) => {
                const nextLanguage = event.target.value as 'ru' | 'en';
                setFormState((current) => ({ ...current, language: nextLanguage }));
                setLocale(nextLanguage);
              }}
            >
              <option value="ru">{t('locale.ru')}</option>
              <option value="en">{t('locale.en')}</option>
            </select>
            <span className="field__hint">{t('auth.form.languageHint')}</span>
          </label>

          <div className="cluster">
            <button className="button button--primary" type="submit" disabled={submitting}>
              {submitting ? t('auth.register.loading') : t('auth.register.submit')}
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
