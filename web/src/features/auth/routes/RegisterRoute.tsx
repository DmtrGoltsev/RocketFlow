import { useState } from 'react';
import { Link, Navigate, useNavigate } from 'react-router-dom';

import { useI18n } from '../../../i18n';
import { RetroButton } from '../../../ui/primitives/RetroButton';
import { RetroField } from '../../../ui/primitives/RetroField';
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

export function RegisterRoute() {
  const { t, locale, setLocale } = useI18n();
  const { status, register } = useAuth();
  const navigate = useNavigate();
  const [formState, setFormState] = useState<RegisterFormState>({
    email: '',
    password: '',
    displayName: '',
    timezone: 'Europe/Moscow',
    language: locale
  });
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [formError, setFormError] = useState<string | null>(null);
  const [traceId, setTraceId] = useState<string | undefined>(undefined);
  const [submitting, setSubmitting] = useState(false);

  if (status === 'authenticated') {
    return <Navigate to="/app" replace />;
  }

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
      const nextSession = await register(formState);
      setLocale(nextSession.user.language);
      navigate('/app', { replace: true });
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
      {formError ? <AuthNotice tone="error" message={formError} traceId={traceId} /> : null}

      <AuthCard
        title={t('auth.register.title')}
        subtitle={t('auth.register.subtitle')}
        alternatePrompt={t('auth.register.alternatePrompt')}
        alternateAction={t('auth.register.alternateAction')}
        alternateTo="/auth/login"
      >
        <form className="stack" onSubmit={handleSubmit}>
          <RetroField label={t('auth.form.displayName')}>
            <input
              className="retro-input"
              autoComplete="name"
              value={formState.displayName}
              onChange={(event) => setFormState((current) => ({ ...current, displayName: event.target.value }))}
            />
          </RetroField>
          {fieldErrors.displayName ? <div className="muted">{fieldErrors.displayName}</div> : null}

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
              autoComplete="new-password"
              value={formState.password}
              onChange={(event) => setFormState((current) => ({ ...current, password: event.target.value }))}
            />
          </RetroField>
          {fieldErrors.password ? <div className="muted">{fieldErrors.password}</div> : null}

          <RetroField label={t('auth.form.timezone')} hint={t('auth.form.timezoneHint')}>
            <input
              className="retro-input"
              autoComplete="off"
              value={formState.timezone}
              onChange={(event) => setFormState((current) => ({ ...current, timezone: event.target.value }))}
            />
          </RetroField>
          {fieldErrors.timezone ? <div className="muted">{fieldErrors.timezone}</div> : null}

          <RetroField label={t('auth.form.language')} hint={t('auth.form.languageHint')}>
            <select
              className="retro-input"
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
          </RetroField>

          <div className="cluster">
            <RetroButton type="submit" variant="primary" disabled={submitting}>
              {submitting ? t('auth.register.loading') : t('auth.register.submit')}
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

