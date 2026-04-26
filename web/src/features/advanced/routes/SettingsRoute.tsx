import { useEffect, useState, type FormEvent } from 'react';

import { useI18n } from '../../../i18n';
import { ConflictState } from '../../../ui/feedback/ConflictState';
import { ErrorState } from '../../../ui/feedback/ErrorState';
import { LoadingState } from '../../../ui/feedback/LoadingState';
import { RetroButton } from '../../../ui/primitives/RetroButton';
import { RetroField } from '../../../ui/primitives/RetroField';
import { RetroPanel } from '../../../ui/primitives/RetroPanel';
import { useAuth } from '../../auth';
import { PlanningInlineNotice } from '../../planning/components/PlanningWorkspace';
import { AdvancedApiError, getSettings, updateSettings } from '../advanced-api';
import { useAdvancedCopy } from '../advanced-copy';
import type { Locale, ThresholdPreset, UserSettingsResponse } from '../types';

interface SettingsDraft {
  language: Locale;
  notificationsEnabled: boolean;
  greenEnabled: boolean;
  greenThresholdPreset: ThresholdPreset;
  greenDecayAmount: string;
  redEnabled: boolean;
  redThresholdPreset: ThresholdPreset;
  redDecayAmount: string;
  version: number;
}

function toDraft(settings: UserSettingsResponse): SettingsDraft {
  return {
    language: settings.language,
    notificationsEnabled: settings.notificationsEnabled,
    greenEnabled: settings.greenPriorityDecayPolicy.enabled,
    greenThresholdPreset: settings.greenPriorityDecayPolicy.thresholdPreset,
    greenDecayAmount: String(settings.greenPriorityDecayPolicy.decayAmount),
    redEnabled: settings.redPriorityDecayPolicy.enabled,
    redThresholdPreset: settings.redPriorityDecayPolicy.thresholdPreset,
    redDecayAmount: String(settings.redPriorityDecayPolicy.decayAmount),
    version: settings.version,
  };
}

function mapError(error: unknown, copy: ReturnType<typeof useAdvancedCopy>) {
  if (error instanceof AdvancedApiError) {
    return {
      message: (copy.api as Record<string, string>)[error.payload.code] ?? copy.api.fallback,
      traceId: error.payload.traceId,
      status: error.status,
    };
  }

  return {
    message: copy.api.fallback,
    traceId: undefined,
    status: 0,
  };
}

interface PolicyEditorProps {
  title: string;
  enabled: boolean;
  thresholdPreset: ThresholdPreset;
  decayAmount: string;
  copy: ReturnType<typeof useAdvancedCopy>;
  onEnabledChange: (value: boolean) => void;
  onThresholdChange: (value: ThresholdPreset) => void;
  onDecayAmountChange: (value: string) => void;
}

function PolicyEditor({
  title,
  enabled,
  thresholdPreset,
  decayAmount,
  copy,
  onEnabledChange,
  onThresholdChange,
  onDecayAmountChange,
}: PolicyEditorProps) {
  return (
    <RetroPanel title={title}>
      <div className="stack stack--tight">
        <RetroField label={copy.common.enabled}>
          <select
            className="retro-select"
            value={enabled ? 'true' : 'false'}
            onChange={(event) => onEnabledChange(event.target.value === 'true')}
          >
            <option value="true">{copy.common.enabled}</option>
            <option value="false">{copy.common.disabled}</option>
          </select>
        </RetroField>

        <RetroField label={copy.settings.threshold}>
          <select
            className="retro-select"
            value={thresholdPreset}
            onChange={(event) => onThresholdChange(event.target.value as ThresholdPreset)}
          >
            <option value="day">{copy.enums.thresholdPreset.day}</option>
            <option value="week">{copy.enums.thresholdPreset.week}</option>
            <option value="month">{copy.enums.thresholdPreset.month}</option>
          </select>
        </RetroField>

        <RetroField label={copy.settings.decayAmount}>
          <input
            className="retro-input"
            type="number"
            min={1}
            value={decayAmount}
            onChange={(event) => onDecayAmountChange(event.target.value)}
          />
        </RetroField>
      </div>
    </RetroPanel>
  );
}

export function SettingsRoute() {
  const { authorizedFetch, syncSessionLanguage } = useAuth();
  const { setLocale } = useI18n();
  const copy = useAdvancedCopy();
  const [draft, setDraft] = useState<SettingsDraft | null>(null);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [traceId, setTraceId] = useState<string | undefined>();
  const [notice, setNotice] = useState<string | null>(null);
  const [showConflict, setShowConflict] = useState(false);

  async function loadData() {
    setLoading(true);
    setError(null);
    setTraceId(undefined);

    try {
      const settings = await getSettings(authorizedFetch);
      setDraft(toDraft(settings));
      setLoading(false);
    } catch (error) {
      const mapped = mapError(error, copy);
      setError(mapped.message);
      setTraceId(mapped.traceId);
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadData();
  }, []);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!draft) {
      return;
    }

    setSubmitting(true);
    setError(null);
    setTraceId(undefined);
    setNotice(null);
    setShowConflict(false);

    try {
      const response = await updateSettings(authorizedFetch, {
        language: draft.language,
        notificationsEnabled: draft.notificationsEnabled,
        greenPriorityDecayPolicy: {
          enabled: draft.greenEnabled,
          thresholdPreset: draft.greenThresholdPreset,
          decayAmount: Number(draft.greenDecayAmount),
        },
        redPriorityDecayPolicy: {
          enabled: draft.redEnabled,
          thresholdPreset: draft.redThresholdPreset,
          decayAmount: Number(draft.redDecayAmount),
        },
        version: draft.version,
      });

      setDraft(toDraft(response));
      setLocale(response.language);
      syncSessionLanguage(response.language);
      setNotice(copy.common.saved);
    } catch (error) {
      const mapped = mapError(error, copy);

      if (mapped.status === 409) {
        await loadData();
        setShowConflict(true);
      } else {
        setError(mapped.message);
        setTraceId(mapped.traceId);
      }
    } finally {
      setSubmitting(false);
    }
  }

  if (loading) {
    return <LoadingState title={copy.common.loadingTitle} description={copy.common.loadingDescription} />;
  }

  if (!draft) {
    return <ErrorState title={copy.common.errorTitle} description={error ?? copy.common.errorDescription} />;
  }

  return (
    <div className="stack">
      <div className="surface-header">
        <div className="stack stack--tight">
          <div className="caps">{copy.common.title}</div>
          <div className="surface-title">{copy.settings.title}</div>
          <div className="surface-subtitle">{copy.settings.subtitle}</div>
        </div>
      </div>

      {showConflict ? (
        <ConflictState title={copy.common.conflictTitle} description={copy.common.conflictDescription} />
      ) : null}
      {notice ? <PlanningInlineNotice tone="info">{notice}</PlanningInlineNotice> : null}
      {error ? <PlanningInlineNotice tone="error">{error}</PlanningInlineNotice> : null}
      {traceId ? <PlanningInlineNotice tone="info">{copy.common.traceId}: {traceId}</PlanningInlineNotice> : null}

      <form className="stack" onSubmit={handleSubmit}>
        <RetroPanel title={copy.settings.generalTitle}>
          <div className="planning-form-grid">
            <RetroField label={copy.common.language} hint={copy.settings.syncHint}>
              <select
                className="retro-select"
                value={draft.language}
                onChange={(event) =>
                  setDraft((current) => current ? { ...current, language: event.target.value as Locale } : current)
                }
              >
                <option value="ru">Русский</option>
                <option value="en">English</option>
              </select>
            </RetroField>

            <RetroField label={copy.settings.notificationsLabel}>
              <select
                className="retro-select"
                value={draft.notificationsEnabled ? 'true' : 'false'}
                onChange={(event) =>
                  setDraft((current) =>
                    current ? { ...current, notificationsEnabled: event.target.value === 'true' } : current,
                  )
                }
              >
                <option value="true">{copy.common.enabled}</option>
                <option value="false">{copy.common.disabled}</option>
              </select>
            </RetroField>
          </div>
        </RetroPanel>

        <RetroPanel title={copy.settings.policyTitle}>
          <div className="shell-grid shell-grid--2">
            <PolicyEditor
              title={copy.settings.greenPolicy}
              enabled={draft.greenEnabled}
              thresholdPreset={draft.greenThresholdPreset}
              decayAmount={draft.greenDecayAmount}
              copy={copy}
              onEnabledChange={(value) => setDraft((current) => current ? { ...current, greenEnabled: value } : current)}
              onThresholdChange={(value) => setDraft((current) => current ? { ...current, greenThresholdPreset: value } : current)}
              onDecayAmountChange={(value) => setDraft((current) => current ? { ...current, greenDecayAmount: value } : current)}
            />

            <PolicyEditor
              title={copy.settings.redPolicy}
              enabled={draft.redEnabled}
              thresholdPreset={draft.redThresholdPreset}
              decayAmount={draft.redDecayAmount}
              copy={copy}
              onEnabledChange={(value) => setDraft((current) => current ? { ...current, redEnabled: value } : current)}
              onThresholdChange={(value) => setDraft((current) => current ? { ...current, redThresholdPreset: value } : current)}
              onDecayAmountChange={(value) => setDraft((current) => current ? { ...current, redDecayAmount: value } : current)}
            />
          </div>
        </RetroPanel>

        <div className="cluster">
          <RetroButton type="submit" variant="primary" disabled={submitting}>
            {copy.settings.saveAction}
          </RetroButton>
          <RetroButton type="button" disabled={submitting} onClick={() => void loadData()}>
            {copy.common.refresh}
          </RetroButton>
        </div>
      </form>
    </div>
  );
}
