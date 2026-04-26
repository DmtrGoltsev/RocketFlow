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
import { archiveFolder, createFolder, listFolders, updateFolder } from '../planning-api';
import { usePlanningCopy } from '../planning-copy';
import { mapPlanningError, isPlanningApiError } from '../planning-errors';
import { findById, formatDateTime, normalizeSelection } from '../planning-utils';
import type { FolderDto } from '../types';
import {
  PlanningFieldError,
  PlanningInlineNotice,
  PlanningMetaList,
  PlanningRecordButton,
  PlanningSplitLayout,
} from '../components/PlanningWorkspace';

interface FolderDraft {
  name: string;
  description: string;
}

type FormMode = 'create' | 'edit' | null;

function toDraft(folder: FolderDto | null): FolderDraft {
  return {
    name: folder?.name ?? '',
    description: folder?.description ?? '',
  };
}

export function FoldersRoute() {
  const { authorizedFetch } = useAuth();
  const { locale } = useI18n();
  const copy = usePlanningCopy();
  const [searchParams, setSearchParams] = useSearchParams();
  const [folders, setFolders] = useState<FolderDto[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [formMode, setFormMode] = useState<FormMode>(null);
  const [draft, setDraft] = useState<FolderDraft>(toDraft(null));
  const [formError, setFormError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [traceId, setTraceId] = useState<string | undefined>();
  const [submitting, setSubmitting] = useState(false);
  const [showConflict, setShowConflict] = useState(false);

  const selectedFolderId = searchParams.get('folder');
  const selectedFolder = useMemo(() => findById(folders, selectedFolderId), [folders, selectedFolderId]);

  function updateFolderSelection(nextFolderId: string | null) {
    const nextParams = new URLSearchParams(searchParams);

    if (nextFolderId) {
      nextParams.set('folder', nextFolderId);
    } else {
      nextParams.delete('folder');
    }

    setSearchParams(nextParams, { replace: true });
  }

  async function loadAllFolders(preferredId?: string | null) {
    setLoading(true);
    setLoadError(null);

    try {
      const nextFolders = await listFolders(authorizedFetch);
      const nextSelectedId = normalizeSelection(nextFolders, preferredId ?? selectedFolderId);

      setFolders(nextFolders);
      setLoading(false);
      updateFolderSelection(nextSelectedId);

      return nextFolders;
    } catch (error) {
      const mappedError = mapPlanningError(error, copy);
      setLoadError(mappedError.message);
      setLoading(false);
      return null;
    }
  }

  useEffect(() => {
    void loadAllFolders();
  }, []);

  useEffect(() => {
    if (folders.length === 0) {
      if (selectedFolderId) {
        updateFolderSelection(null);
      }

      return;
    }

    const normalized = normalizeSelection(folders, selectedFolderId);

    if (normalized !== selectedFolderId) {
      updateFolderSelection(normalized);
    }
  }, [folders, selectedFolderId]);

  function resetForm(nextMode: FormMode, folder: FolderDto | null) {
    setFormMode(nextMode);
    setDraft(toDraft(folder));
    setFormError(null);
    setFieldErrors({});
    setTraceId(undefined);
    setShowConflict(false);
  }

  function validateDraft() {
    const nextFieldErrors: Record<string, string> = {};

    if (!draft.name.trim()) {
      nextFieldErrors.name = copy.folders.name;
    }

    setFieldErrors(nextFieldErrors);
    return Object.keys(nextFieldErrors).length === 0;
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!validateDraft()) {
      return;
    }

    setSubmitting(true);
    setFormError(null);
    setTraceId(undefined);

    try {
      if (formMode === 'create') {
        const created = await createFolder(authorizedFetch, {
          name: draft.name.trim(),
          description: draft.description.trim(),
        });

        await loadAllFolders(created.id);
        resetForm(null, null);
      }

      if (formMode === 'edit' && selectedFolder) {
        await updateFolder(authorizedFetch, selectedFolder.id, {
          name: draft.name.trim(),
          description: draft.description.trim(),
          displayOrder: selectedFolder.displayOrder,
          archived: selectedFolder.archived,
          version: selectedFolder.version,
        });

        await loadAllFolders(selectedFolder.id);
        resetForm(null, null);
      }
    } catch (error) {
      if (isPlanningApiError(error) && error.status === 409 && selectedFolder) {
        const refreshed = await loadAllFolders(selectedFolder.id);
        const freshFolder = refreshed ? findById(refreshed, selectedFolder.id) : null;

        resetForm('edit', freshFolder);
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
    if (!selectedFolder || !window.confirm(copy.folders.archiveConfirm)) {
      return;
    }

    try {
      await archiveFolder(authorizedFetch, selectedFolder.id);
      await loadAllFolders();
      resetForm(null, null);
    } catch (error) {
      const mappedError = mapPlanningError(error, copy);
      setLoadError(mappedError.message);
    }
  }

  const detailPanel = formMode ? (
    <RetroDialogFrame
      title={formMode === 'create' ? copy.folders.createTitle : copy.folders.editTitle}
      footer={(
        <div className="cluster">
          <RetroButton type="submit" form="folder-form" variant="primary" disabled={submitting}>
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
      <form id="folder-form" className="stack stack--tight" onSubmit={handleSubmit}>
        <RetroField label={copy.folders.name}>
          <input
            className="retro-input"
            value={draft.name}
            onChange={(event) => setDraft((current) => ({ ...current, name: event.target.value }))}
          />
          <PlanningFieldError message={fieldErrors.name} />
        </RetroField>
        <RetroField label={copy.folders.description}>
          <textarea
            className="retro-textarea"
            value={draft.description}
            onChange={(event) => setDraft((current) => ({ ...current, description: event.target.value }))}
          />
          <PlanningFieldError message={fieldErrors.description} />
        </RetroField>
      </form>
    </RetroDialogFrame>
  ) : selectedFolder ? (
    <RetroPanel
      title={copy.folders.detailTitle}
      aside={<RetroBadge tone="info">{`#${selectedFolder.displayOrder}`}</RetroBadge>}
    >
      <div className="stack">
        <div className="surface-header">
          <div className="stack stack--tight">
            <div className="surface-title">{selectedFolder.name}</div>
            <div className="surface-subtitle">
              {selectedFolder.description || copy.common.noDescription}
            </div>
          </div>
          <div className="surface-meta">
            <RetroBadge tone="info">{`${copy.common.version}: ${selectedFolder.version}`}</RetroBadge>
          </div>
        </div>
        <PlanningMetaList
          items={[
            { label: copy.folders.displayOrder, value: selectedFolder.displayOrder },
            { label: copy.common.createdAt, value: formatDateTime(selectedFolder.createdAt, locale) },
            { label: copy.common.updatedAt, value: formatDateTime(selectedFolder.updatedAt, locale) },
          ]}
        />
        <div className="cluster">
          <RetroButton type="button" variant="primary" onClick={() => resetForm('edit', selectedFolder)}>
            {copy.common.edit}
          </RetroButton>
          <RetroButton type="button" variant="danger" onClick={handleArchive}>
            {copy.common.archive}
          </RetroButton>
          <RetroButton
            as={Link}
            to={`/app/goals?folder=${selectedFolder.id}`}
            variant="ghost"
          >
            {copy.common.openGoals}
          </RetroButton>
        </div>
      </div>
    </RetroPanel>
  ) : (
    <EmptyState title={copy.folders.detailTitle} description={copy.folders.selectPrompt} />
  );

  return (
    <div className="stack">
      <div className="surface-header">
        <div className="stack stack--tight">
          <div className="caps">Planning / F3</div>
          <div className="surface-title">{copy.folders.title}</div>
          <div className="surface-subtitle">{copy.folders.subtitle}</div>
        </div>
        <div className="surface-meta">
          <RetroBadge tone="info">{`${copy.folders.count}: ${folders.length}`}</RetroBadge>
        </div>
      </div>

      <PlanningSplitLayout
        sidebar={(
          <RetroPanel
            title={copy.folders.listTitle}
            aside={(
              <RetroButton type="button" size="small" variant="primary" onClick={() => resetForm('create', null)}>
                {copy.common.create}
              </RetroButton>
            )}
          >
            {loading ? (
              <LoadingState
                title={copy.common.loadingTitle}
                description={copy.common.loadingDescription}
              />
            ) : loadError ? (
              <div className="stack stack--tight">
                <ErrorState title={copy.common.errorTitle} description={loadError} />
                <RetroButton type="button" onClick={() => void loadAllFolders()}>
                  {copy.common.retry}
                </RetroButton>
              </div>
            ) : folders.length === 0 ? (
              <EmptyState
                title={copy.folders.listEmptyTitle}
                description={copy.folders.listEmptyDescription}
              />
            ) : (
              <div className="planning-record-list">
                {folders.map((folder) => (
                  <PlanningRecordButton
                    key={folder.id}
                    active={folder.id === selectedFolderId}
                    title={folder.name}
                    subtitle={folder.description || copy.common.noDescription}
                    meta={(
                      <span>
                        {copy.folders.displayOrder}: {folder.displayOrder}
                      </span>
                    )}
                    onClick={() => updateFolderSelection(folder.id)}
                  />
                ))}
              </div>
            )}
          </RetroPanel>
        )}
        detail={detailPanel}
      />
    </div>
  );
}
