import { useEffect, useState } from 'react';
import { Check, Link as LinkIcon, RefreshCw, ShieldCheck, X } from 'lucide-react';
import { useSearchParams } from 'react-router-dom';

import { useAuth } from '../../auth';
import { useI18n } from '../../../i18n';
import { EmptyState } from '../../../ui/feedback/EmptyState';
import { ErrorState } from '../../../ui/feedback/ErrorState';
import { LoadingState } from '../../../ui/feedback/LoadingState';
import { formatDateTime } from '../../planning/planning-utils';
import {
  acceptInvitation,
  acceptShareLink,
  declineInvitation,
  getInvitations,
  getSharedResources,
  resolveShareLink,
  revokeInvitation,
} from '../advanced-api';
import { mapAdvancedError } from '../advanced-errors';
import { useAdvancedCopy } from '../advanced-copy';
import type {
  ShareInvitationActionResponse,
  ShareInvitationDto,
  ShareLinkResolveResponse,
  SharedResourcesResponse,
} from '../types';

const emptyResources: SharedResourcesResponse = {
  folders: [],
  goals: [],
  tasks: [],
  createTaskGoalIds: [],
};

export function SharingRoute() {
  const { authorizedFetch } = useAuth();
  const { locale } = useI18n();
  const copy = useAdvancedCopy();
  const [searchParams] = useSearchParams();
  const token = searchParams.get('token') ?? searchParams.get('shareToken') ?? '';
  const [invitations, setInvitations] = useState<ShareInvitationDto[]>([]);
  const [resources, setResources] = useState<SharedResourcesResponse>(emptyResources);
  const [shareLink, setShareLink] = useState<ShareLinkResolveResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [actingId, setActingId] = useState<string | null>(null);

  const totalResources = resources.folders.length + resources.goals.length + resources.tasks.length;
  const targetLabel = (targetType: ShareInvitationDto['targetType']) => {
    if (targetType === 'folder') {
      return copy.sharing.folderLabel;
    }

    return targetType === 'goal' ? copy.common.goal : copy.common.task;
  };

  async function loadSharing() {
    setLoading(true);
    setError(null);

    try {
      const [nextInvitations, nextResources, nextLink] = await Promise.all([
        getInvitations(authorizedFetch),
        getSharedResources(authorizedFetch),
        token ? resolveShareLink(authorizedFetch, token) : Promise.resolve(null),
      ]);
      setInvitations(nextInvitations.items);
      setResources({
        folders: nextResources.folders ?? [],
        goals: nextResources.goals ?? [],
        tasks: nextResources.tasks ?? [],
        createTaskGoalIds: nextResources.createTaskGoalIds ?? [],
      });
      setShareLink(nextLink);
    } catch (loadError) {
      setError(mapAdvancedError(loadError, copy).formError);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadSharing();
  }, [token]);

  async function runInvitationAction(
    invitation: ShareInvitationDto,
    action: (id: string) => Promise<ShareInvitationActionResponse>,
  ) {
    setActingId(invitation.id);
    setError(null);
    setNotice(null);

    try {
      const response = await action(invitation.id);
      setInvitations((current) => current.map((item) => item.id === invitation.id ? { ...item, status: response.status } : item));
      setNotice(copy.sharing.updatedNotice);
      await loadSharing();
    } catch (actionError) {
      setError(mapAdvancedError(actionError, copy).formError);
    } finally {
      setActingId(null);
    }
  }

  async function handleAcceptLink() {
    if (!token) {
      setError(copy.sharing.tokenMissing);
      return;
    }

    setActingId(token);
    setError(null);
    setNotice(null);

    try {
      await acceptShareLink(authorizedFetch, token);
      setNotice(copy.sharing.linkAccepted);
      await loadSharing();
    } catch (linkError) {
      setError(mapAdvancedError(linkError, copy).formError);
    } finally {
      setActingId(null);
    }
  }

  if (loading) {
    return (
      <section className="planner planner--center">
        <LoadingState title={copy.common.loadingTitle} description={copy.common.loadingDescription} />
      </section>
    );
  }

  return (
    <section className="planner">
      <div className="planner-canvas">
        <header className="planner-header">
          <div>
            <h1>{copy.sharing.title}</h1>
            <div className="planner-header__meta">
              <span>{copy.sharing.subtitle}</span>
              <span>{totalResources} {copy.sharing.resourcesCount}</span>
            </div>
          </div>
          <button className="icon-button" type="button" aria-label={copy.common.refresh} title={copy.common.refresh} onClick={() => void loadSharing()}>
            <RefreshCw size={18} aria-hidden="true" />
          </button>
        </header>

        <div className="detail-panel__body">
          {notice ? <div className="state-box state-box--loading">{notice}</div> : null}
          {error ? (
            <div className="stack stack--tight">
              <ErrorState title={copy.common.errorTitle} description={error} />
              <button className="button button--primary" type="button" onClick={() => void loadSharing()}>
                {copy.common.retry}
              </button>
            </div>
          ) : null}

          {shareLink ? (
            <section className="detail-disclosure">
              <div className="breadcrumb">
                <LinkIcon size={16} aria-hidden="true" />
                <strong>{copy.sharing.linkTitle}</strong>
              </div>
              <div className="detail-panel__badges">
                <span className="meta-chip">{copy.common.type}: {targetLabel(shareLink.targetType)}</span>
                <span className="meta-chip">{copy.common.status}: {shareLink.status}</span>
                <span className="meta-chip">{copy.common.dueTime}: {formatDateTime(shareLink.expiresAt, locale)}</span>
              </div>
              <p className="muted">{copy.sharing.linkHint}</p>
              <button className="button button--primary" type="button" disabled={actingId === token} onClick={() => void handleAcceptLink()}>
                <ShieldCheck size={16} aria-hidden="true" />
                {copy.sharing.linkAccept}
              </button>
            </section>
          ) : null}

          <section className="detail-section">
            <div className="detail-label">{copy.sharing.invitationListTitle}</div>
            {invitations.length === 0 ? (
              <EmptyState title={copy.sharing.invitationsEmptyTitle} description={copy.sharing.invitationsEmptyDescription} />
            ) : (
              <div className="stack stack--tight" role="list">
                {invitations.map((invitation) => (
                  <article className="detail-disclosure" key={invitation.id} role="listitem">
                    <div className="breadcrumb">
                      <span className={`marker-dot marker-dot--${invitation.targetType === 'task' ? 'blue' : 'green'}`} aria-hidden="true" />
                      <strong>{targetLabel(invitation.targetType)}: {invitation.targetEmail}</strong>
                    </div>
                    <div className="detail-panel__badges">
                      <span className="meta-chip">{copy.common.status}: {copy.enums.invitationStatus[invitation.status]}</span>
                      <span className="meta-chip">{formatDateTime(invitation.createdAt, locale)}</span>
                      <span className="meta-chip">{copy.common.dueTime}: {formatDateTime(invitation.expiresAt, locale)}</span>
                    </div>
                    {invitation.status === 'pending' ? (
                      <div className="cluster">
                        <button className="button button--ghost" type="button" disabled={actingId === invitation.id} onClick={() => void runInvitationAction(invitation, (id) => acceptInvitation(authorizedFetch, id))}>
                          <Check size={15} aria-hidden="true" />
                          {copy.sharing.accept}
                        </button>
                        <button className="button button--ghost" type="button" disabled={actingId === invitation.id} onClick={() => void runInvitationAction(invitation, (id) => declineInvitation(authorizedFetch, id))}>
                          <X size={15} aria-hidden="true" />
                          {copy.sharing.decline}
                        </button>
                        <button className="button button--ghost" type="button" disabled={actingId === invitation.id} onClick={() => void runInvitationAction(invitation, (id) => revokeInvitation(authorizedFetch, id))}>
                          {copy.sharing.revoke}
                        </button>
                      </div>
                    ) : (
                      <p className="muted">{copy.sharing.pendingOnly}</p>
                    )}
                  </article>
                ))}
              </div>
            )}
          </section>

          <section className="detail-section">
            <div className="detail-label">{copy.sharing.resourcesTitle}</div>
            {totalResources === 0 ? (
              <EmptyState title={copy.sharing.resourcesEmptyTitle} description={copy.sharing.resourcesEmptyDescription} />
            ) : (
              <div className="stack stack--tight">
                {resources.folders.length > 0 ? (
                  <ResourceGroup title={copy.sharing.sharedFolders} items={resources.folders.map((folder) => ({
                    id: folder.id,
                    title: folder.name,
                    description: folder.description,
                    meta: `${copy.sharing.folderLabel} · ${formatDateTime(folder.updatedAt, locale)}`,
                  }))} />
                ) : null}

                {resources.goals.length > 0 ? (
                  <ResourceGroup title={copy.sharing.sharedGoals} items={resources.goals.map((goal) => ({
                    id: goal.id,
                    title: goal.name,
                    description: goal.description,
                    meta: resources.createTaskGoalIds.includes(goal.id)
                      ? copy.sharing.canCreateTasks
                      : `${copy.sharing.goalLabel} · ${formatDateTime(goal.updatedAt, locale)}`,
                  }))} />
                ) : null}

                {resources.tasks.length > 0 ? (
                  <ResourceGroup title={copy.sharing.sharedTasks} items={resources.tasks.map((task) => ({
                    id: task.id,
                    title: task.title,
                    description: task.description,
                    meta: `${copy.sharing.taskLabel} · ${formatDateTime(task.updatedAt, locale)}`,
                  }))} />
                ) : null}
              </div>
            )}
          </section>
        </div>
      </div>
    </section>
  );
}

interface ResourceItem {
  id: string;
  title: string;
  description: string;
  meta: string;
}

function ResourceGroup({ title, items }: { title: string; items: ResourceItem[] }) {
  const copy = useAdvancedCopy();

  return (
    <section className="detail-disclosure">
      <div className="detail-label">{title}</div>
      <div className="stack stack--tight">
        {items.map((item) => (
          <article className="detail-note" key={item.id}>
            <ShieldCheck size={16} aria-hidden="true" />
            <div>
              <strong>{item.title}</strong>
              <p>{item.description || copy.common.noDescription}</p>
              <span className="muted">{item.meta}</span>
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}
