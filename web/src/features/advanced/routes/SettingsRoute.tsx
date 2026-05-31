import { useEffect, useState, type FormEvent } from 'react';
import { Bell, Save, Settings } from 'lucide-react';

import { useAuth } from '../../auth';
import { ErrorState } from '../../../ui/feedback/ErrorState';
import { LoadingState } from '../../../ui/feedback/LoadingState';
import { AdvancedApiError, getSettings, updateSettings } from '../advanced-api';
import { mapAdvancedError } from '../advanced-errors';
import { useAdvancedCopy } from '../advanced-copy';
import type { Locale, UpdateSettingsPayload, UserSettingsResponse } from '../types';

type SettingsDraft = UserSettingsResponse;

function toPayload(draft: SettingsDraft): UpdateSettingsPayload {
  return {
    language: draft.language,
    greenPriorityDecayPolicy: {
      enabled: draft.greenPriorityDecayPolicy.enabled,
      thresholdPreset: draft.greenPriorityDecayPolicy.thresholdPreset,
      decayAmount: draft.greenPriorityDecayPolicy.decayAmount,
    },
    redPriorityDecayPolicy: {
      enabled: draft.redPriorityDecayPolicy.enabled,
      thresholdPreset: draft.redPriorityDecayPolicy.thresholdPreset,
      decayAmount: draft.redPriorityDecayPolicy.decayAmount,
    },
    notificationsEnabled: draft.notificationsEnabled,
    version: draft.version,
  };
}

export function SettingsRoute() {
  const { authorizedFetch, syncSessionLanguage } = useAuth();
  const copy = useAdvancedCopy();
  const [draft, setDraft] = useState<SettingsDraft | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [notice, setNotice] = useState<string | null>(null);

  async function loadSettings(options: { quiet?: boolean } = {}) {
    if (!options.quiet) {
      setLoading(true);
    }
    setError(null);

    try {
      setDraft(await getSettings(authorizedFetch));
    } catch (loadError) {
      setError(mapAdvancedError(loadError, copy).formError);
    } finally {
      if (!options.quiet) {
        setLoading(false);
      }
    }
  }

  useEffect(() => {
    void loadSettings();
  }, []);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!draft) {
      return;
    }

    setSaving(true);
    setError(null);
    setNotice(null);
    setFieldErrors({});

    try {
      const saved = await updateSettings(authorizedFetch, toPayload(draft));
      setDraft(saved);
      syncSessionLanguage(saved.language);
      setNotice(copy.common.saved);
    } catch (saveError) {
      const mapped = mapAdvancedError(saveError, copy);
      setFieldErrors(mapped.fieldErrors);
      setError(mapped.formError);

      if (saveError instanceof AdvancedApiError && saveError.status === 409) {
        setNotice(copy.common.conflictDescription);
        try {
          setDraft(await getSettings(authorizedFetch));
        } catch {
          // Keep the mapped conflict visible if the refresh also fails.
        }
      }
    } finally {
      setSaving(false);
    }
  }

  if (loading) {
    return (
      <section className="planner planner--center">
        <LoadingState title={copy.common.loadingTitle} description={copy.common.loadingDescription} />
      </section>
    );
  }

  if (!draft) {
    return (
      <section className="planner planner--center">
        <ErrorState title={copy.common.errorTitle} description={error ?? copy.common.errorDescription} />
        <button className="button button--primary" type="button" onClick={() => void loadSettings()}>
          {copy.common.retry}
        </button>
      </section>
    );
  }

  return (
    <section className="planner planner--settings">
      <div className="planner-canvas">
        <header className="planner-header">
          <div>
            <h1>{copy.settings.title}</h1>
            <div className="planner-header__meta">
              <span>{copy.settings.subtitle}</span>
              <span>{copy.common.version}: {draft.version}</span>
            </div>
          </div>
          <button className="icon-button" type="button" aria-label={copy.common.refresh} title={copy.common.refresh} onClick={() => void loadSettings({ quiet: true })}>
            <Settings size={19} aria-hidden="true" />
          </button>
        </header>

        <form className="detail-panel__body" onSubmit={handleSubmit}>
          {notice ? <div className="state-box state-box--loading">{notice}</div> : null}
          {error ? <div className="state-box state-box--error">{error}</div> : null}

          <section className="detail-section">
            <div className="detail-label">{copy.settings.generalTitle}</div>
            <label className="field">
              <span>{copy.common.language}</span>
              <select
                className="field__control"
                value={draft.language}
                onChange={(event) => setDraft((current) => current ? { ...current, language: event.target.value as Locale } : current)}
              >
                <option value="ru">{copy.locale.ru}</option>
                <option value="en">{copy.locale.en}</option>
              </select>
              <span className="field__hint">{copy.settings.syncHint}</span>
              {fieldErrors.language ? <span className="field__error">{fieldErrors.language}</span> : null}
            </label>

            <label className="field">
              <span>{copy.settings.notificationsLabel}</span>
              <select
                className="field__control"
                value={draft.notificationsEnabled ? 'enabled' : 'disabled'}
                onChange={(event) => setDraft((current) => current ? { ...current, notificationsEnabled: event.target.value === 'enabled' } : current)}
              >
                <option value="enabled">{copy.common.enabled}</option>
                <option value="disabled">{copy.common.disabled}</option>
              </select>
              <span className="field__hint">{copy.settings.notificationsHint}</span>
            </label>
          </section>

          <button className="button button--primary detail-save" type="submit" disabled={saving}>
            {saving ? <Bell size={16} aria-hidden="true" /> : <Save size={16} aria-hidden="true" />}
            {copy.settings.saveAction}
          </button>
        </form>
      </div>
    </section>
  );
}
