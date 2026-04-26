import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { Link, useSearchParams } from 'react-router-dom';

import { useAuth } from '../../auth';
import { useI18n } from '../../../i18n';
import { ConflictState } from '../../../ui/feedback/ConflictState';
import { EmptyState } from '../../../ui/feedback/EmptyState';
import { ErrorState } from '../../../ui/feedback/ErrorState';
import { LoadingState } from '../../../ui/feedback/LoadingState';
import { RetroBadge } from '../../../ui/primitives/RetroBadge';
import { RetroButton } from '../../../ui/primitives/RetroButton';
import { RetroDialogFrame } from '../../../ui/primitives/RetroDialogFrame';
import { RetroField } from '../../../ui/primitives/RetroField';
import { RetroPanel } from '../../../ui/primitives/RetroPanel';
import {
  archiveGoal,
  createGoal,
  getGoal,
  listFolders,
  listGoals,
  updateGoal,
} from '../planning-api';
import { usePlanningCopy } from '../planning-copy';
import { isPlanningApiError, mapPlanningError } from '../planning-errors';
import { findById, formatDateTime, normalizeSelection } from '../planning-utils';
import type { FolderDto, GoalDto } from '../types';
import {
  PlanningFieldError,
  PlanningInlineNotice,
  PlanningMetaList,
  PlanningRecordButton,
  PlanningSplitLayout,
} from '../components/PlanningWorkspace';

interface GoalDraft {
  name: string;
  description: string;
}

type FormMode = 'create' | 'edit' | null;

function toDraft(goal: GoalDto | null): GoalDraft {
  return {
    name: goal?.name ?? '',
    description: goal?.description ?? '',
  };
}

export function GoalsRoute() {
  const { authorizedFetch } = useAuth();
  const { locale } = useI18n();
  const copy = usePlanningCopy();
  const [searchParams, setSearchParams] = useSearchParams();
  const [folders, setFolders] = useState<FolderDto[]>([]);
  const [goals, setGoals] = useState<GoalDto[]>([]);
  const [selectedGoal, setSelectedGoal] = useState<GoalDto | null>(null);
  const [loadingFolders, setLoadingFolders] = useState(true);
  const [loadingGoals, setLoadingGoals] = useState(false);
  const [loadingDetail, setLoadingDetail] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [formMode, setFormMode] = useState<FormMode>(null);
  const [draft, setDraft] = useState<GoalDraft>(toDraft(null));
  const [formError, setFormError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [traceId, setTraceId] = useState<string | undefined>();
  const [submitting, setSubmitting] = useState(false);
  const [showConflict, setShowConflict] = useState(false);

  const selectedFolderId = searchParams.get('folder');
  const selectedGoalId = searchParams.get('goal');
  const selectedFolder = useMemo(() => findById(folders, selectedFolderId), [folders, selectedFolderId]);

  function updateSelection(nextFolderId: string | null, nextGoalId: string | null) {
    const nextParams = new URLSearchParams(searchParams);

    if (nextFolderId) {
      nextParams.set('folder', nextFolderId);
    } else {
      nextParams.delete('folder');
    }

    if (nextGoalId) {
      nextParams.set('goal', nextGoalId);
    } else {
      nextParams.delete('goal');
    }

    setSearchParams(nextParams, { replace: true });
  }

  async function loadFolderList() {
    setLoadingFolders(true);
    setLoadError(null);

    try {
      const nextFolders = await listFolders(authorizedFetch);
      const nextSelectedFolderId = normalizeSelection(nextFolders, selectedFolderId);

      setFolders(nextFolders);
      setLoadingFolders(false);
      updateSelection(nextSelectedFolderId, null);
    } catch (error) {
      const mappedError = mapPlanningError(error, copy);
      setLoadError(mappedError.message);
      setLoadingFolders(false);
    }
  }

  async function loadGoalList(folderId: string, preferredGoalId?: string | null) {
    setLoadingGoals(true);
    setLoadError(null);

    try {
      const nextGoals = await listGoals(authorizedFetch, folderId);
      const nextSelectedGoalId = normalizeSelection(nextGoals, preferredGoalId ?? selectedGoalId);

      setGoals(nextGoals);
      setLoadingGoals(false);
      updateSelection(folderId, nextSelectedGoalId);

      return nextGoals;
    } catch (error) {
      const mappedError = mapPlanningError(error, copy);
      setLoadError(mappedError.message);
      setGoals([]);
      setLoadingGoals(false);
      return null;
    }
  }

  async function loadGoalDetail(goalId: string) {
    setLoadingDetail(true);

    try {
      const detail = await getGoal(authorizedFetch, goalId);
      setSelectedGoal(detail);
      return detail;
    } catch (error) {
      const mappedError = mapPlanningError(error, copy);
      setLoadError(mappedError.message);
      setSelectedGoal(null);
      return null;
    } finally {
      setLoadingDetail(false);
    }
  }

  useEffect(() => {
    void loadFolderList();
  }, []);

  useEffect(() => {
    if (!selectedFolderId) {
      setGoals([]);
      setSelectedGoal(null);
      return;
    }

    void loadGoalList(selectedFolderId);
  }, [selectedFolderId]);

  useEffect(() => {
    if (!selectedGoalId) {
      setSelectedGoal(null);
      return;
    }

    void loadGoalDetail(selectedGoalId);
  }, [selectedGoalId]);

  function resetForm(nextMode: FormMode, goal: GoalDto | null) {
    setFormMode(nextMode);
    setDraft(toDraft(goal));
    setFormError(null);
    setFieldErrors({});
    setTraceId(undefined);
    setShowConflict(false);
  }

  function validateDraft() {
    const nextFieldErrors: Record<string, string> = {};

    if (!draft.name.trim()) {
      nextFieldErrors.name = copy.goals.name;
    }

    setFieldErrors(nextFieldErrors);
    return Object.keys(nextFieldErrors).length === 0;
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!selectedFolderId || !validateDraft()) {
      return;
    }

    setSubmitting(true);
    setFormError(null);
    setTraceId(undefined);

    try {
      if (formMode === 'create') {
        const created = await createGoal(authorizedFetch, selectedFolderId, {
          name: draft.name.trim(),
          description: draft.description.trim(),
        });

        await loadGoalList(selectedFolderId, created.id);
        await loadGoalDetail(created.id);
        resetForm(null, null);
      }

      if (formMode === 'edit' && selectedGoal) {
        await updateGoal(authorizedFetch, selectedGoal.id, {
          name: draft.name.trim(),
          description: draft.description.trim(),
          archived: selectedGoal.archived,
          version: selectedGoal.version,
        });

        await loadGoalList(selectedFolderId, selectedGoal.id);
        await loadGoalDetail(selectedGoal.id);
        resetForm(null, null);
      }
    } catch (error) {
      if (isPlanningApiError(error) && error.status === 409 && selectedGoal && selectedFolderId) {
        await loadGoalList(selectedFolderId, selectedGoal.id);
        const freshGoal = await loadGoalDetail(selectedGoal.id);
        resetForm('edit', freshGoal);
        setShowConflict(true);
      } else {
        const mappedError = mapPlanningError(error, copy);
        setFormError(mappedError.message);
        setFieldErrors(mappedError.fieldErrors);
        setTraceId(mappedError.traceId);
      }
    } finally {
      setSubmitting(false);
    }
  }

  async function handleArchive() {
    if (!selectedGoal || !selectedFolderId || !window.confirm(copy.goals.archiveConfirm)) {
      return;
    }

    try {
      await archiveGoal(authorizedFetch, selectedGoal.id);
      await loadGoalList(selectedFolderId);
      setSelectedGoal(null);
      resetForm(null, null);
    } catch (error) {
      const mappedError = mapPlanningError(error, copy);
      setLoadError(mappedError.message);
    }
  }

  const listPanelContent = loadingFolders ? (
    <LoadingState title={copy.common.loadingTitle} description={copy.common.loadingDescription} />
  ) : loadError ? (
    <div className="stack stack--tight">
      <ErrorState title={copy.common.errorTitle} description={loadError} />
      <RetroButton type="button" onClick={() => void loadFolderList()}>
        {copy.common.retry}
      </RetroButton>
    </div>
  ) : folders.length === 0 ? (
    <EmptyState title={copy.goals.noFoldersTitle} description={copy.goals.noFoldersDescription} />
  ) : (
    <div className="stack stack--tight">
      <RetroField label={copy.goals.folderLabel}>
        <select
          className="retro-select"
          value={selectedFolderId ?? ''}
          onChange={(event) => updateSelection(event.target.value || null, null)}
        >
          {folders.map((folder) => (
            <option key={folder.id} value={folder.id}>
              {folder.name}
            </option>
          ))}
        </select>
      </RetroField>
      {loadingGoals ? (
        <LoadingState title={copy.common.loadingTitle} description={copy.common.loadingDescription} />
      ) : goals.length === 0 ? (
        <EmptyState title={copy.goals.listEmptyTitle} description={copy.goals.listEmptyDescription} />
      ) : (
        <div className="planning-record-list">
          {goals.map((goal) => (
            <PlanningRecordButton
              key={goal.id}
              active={goal.id === selectedGoalId}
              title={goal.name}
              subtitle={goal.description || copy.common.noDescription}
              meta={<span>{`${copy.common.version}: ${goal.version}`}</span>}
              onClick={() => updateSelection(selectedFolderId, goal.id)}
            />
          ))}
        </div>
      )}
    </div>
  );

  const detailPanel = formMode ? (
    <RetroDialogFrame
      title={formMode === 'create' ? copy.goals.createTitle : copy.goals.editTitle}
      footer={(
        <div className="cluster">
          <RetroButton type="submit" form="goal-form" variant="primary" disabled={submitting}>
            {submitting ? copy.common.loadingTitle : copy.common.save}
          </RetroButton>
          <RetroButton type="button" onClick={() => resetForm(null, null)} disabled={submitting}>
            {copy.common.cancel}
          </RetroButton>
        </div>
      )}
    >
      {showConflict ? (
        <ConflictState
          title={copy.common.conflictTitle}
          description={copy.common.conflictDescription}
        />
      ) : null}
      {formError ? <PlanningInlineNotice tone="error">{formError}</PlanningInlineNotice> : null}
      {traceId ? (
        <PlanningInlineNotice tone="info">
          {copy.common.serverTrace}: {traceId}
        </PlanningInlineNotice>
      ) : null}
      <form id="goal-form" className="stack stack--tight" onSubmit={handleSubmit}>
        <RetroField label={copy.goals.name}>
          <input
            className="retro-input"
            value={draft.name}
            onChange={(event) => setDraft((current) => ({ ...current, name: event.target.value }))}
          />
          <PlanningFieldError message={fieldErrors.name} />
        </RetroField>
        <RetroField label={copy.goals.description}>
          <textarea
            className="retro-textarea"
            value={draft.description}
            onChange={(event) => setDraft((current) => ({ ...current, description: event.target.value }))}
          />
          <PlanningFieldError message={fieldErrors.description} />
        </RetroField>
      </form>
    </RetroDialogFrame>
  ) : loadingDetail ? (
    <LoadingState title={copy.common.loadingTitle} description={copy.common.loadingDescription} />
  ) : selectedGoal ? (
    <RetroPanel
      title={copy.goals.detailTitle}
      aside={<RetroBadge tone={selectedGoal.shared ? 'warning' : 'info'}>{copy.common.details}</RetroBadge>}
    >
      <div className="stack">
        <div className="surface-header">
          <div className="stack stack--tight">
            <div className="surface-title">{selectedGoal.name}</div>
            <div className="surface-subtitle">
              {selectedGoal.description || copy.common.noDescription}
            </div>
          </div>
          <div className="surface-meta">
            <RetroBadge tone="info">{`${copy.common.version}: ${selectedGoal.version}`}</RetroBadge>
          </div>
        </div>
        <PlanningMetaList
          items={[
            { label: copy.goals.folderLabel, value: selectedFolder?.name ?? '-' },
            { label: copy.goals.shared, value: selectedGoal.shared ? copy.enums.yes : copy.enums.no },
            { label: copy.common.createdAt, value: formatDateTime(selectedGoal.createdAt, locale) },
            { label: copy.common.updatedAt, value: formatDateTime(selectedGoal.updatedAt, locale) },
          ]}
        />
        <div className="cluster">
          <RetroButton type="button" variant="primary" onClick={() => resetForm('edit', selectedGoal)}>
            {copy.common.edit}
          </RetroButton>
          <RetroButton type="button" variant="danger" onClick={handleArchive}>
            {copy.common.archive}
          </RetroButton>
          <RetroButton
            as={Link}
            to={`/app/sharing?folder=${selectedGoal.folderId}&goal=${selectedGoal.id}`}
            variant="ghost"
          >
            Share
          </RetroButton>
          <RetroButton
            as={Link}
            to={`/app/tasks?folder=${selectedGoal.folderId}&goal=${selectedGoal.id}`}
            variant="ghost"
          >
            {copy.common.openTasks}
          </RetroButton>
        </div>
      </div>
    </RetroPanel>
  ) : (
    <EmptyState title={copy.goals.detailTitle} description={copy.goals.selectFolderPrompt} />
  );

  return (
    <div className="stack">
      <div className="surface-header">
        <div className="stack stack--tight">
          <div className="caps">Planning / F3</div>
          <div className="surface-title">{copy.goals.title}</div>
          <div className="surface-subtitle">{copy.goals.subtitle}</div>
        </div>
      </div>

      <PlanningSplitLayout
        sidebar={(
          <RetroPanel
            title={copy.goals.listTitle}
            aside={(
              <RetroButton
                type="button"
                size="small"
                variant="primary"
                disabled={!selectedFolderId}
                onClick={() => resetForm('create', null)}
              >
                {copy.common.create}
              </RetroButton>
            )}
          >
            {listPanelContent}
          </RetroPanel>
        )}
        detail={detailPanel}
      />
    </div>
  );
}
