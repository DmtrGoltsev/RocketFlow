import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { Link, useSearchParams } from 'react-router-dom';

import { useI18n } from '../../../i18n';
import { EmptyState } from '../../../ui/feedback/EmptyState';
import { ErrorState } from '../../../ui/feedback/ErrorState';
import { LoadingState } from '../../../ui/feedback/LoadingState';
import { RetroBadge } from '../../../ui/primitives/RetroBadge';
import { RetroButton } from '../../../ui/primitives/RetroButton';
import { RetroField } from '../../../ui/primitives/RetroField';
import { RetroPanel } from '../../../ui/primitives/RetroPanel';
import { useAuth } from '../../auth';
import { PlanningInlineNotice } from '../../planning/components/PlanningWorkspace';
import { formatDateTime } from '../../planning/planning-utils';
import { listFolders, listGoals, listTasks } from '../../planning/planning-api';
import type { FolderDto, GoalDto, TaskDto } from '../../planning/types';
import {
  acceptInvitation,
  AdvancedApiError,
  createGoalInvitation,
  createTaskInvitation,
  declineInvitation,
  getInvitations,
  getSharedResources,
  revokeInvitation,
} from '../advanced-api';
import { useAdvancedCopy } from '../advanced-copy';
import type { ShareInvitationDto, ShareTargetType } from '../types';

function mapError(error: unknown, copy: ReturnType<typeof useAdvancedCopy>) {
  if (error instanceof AdvancedApiError) {
    return {
      message: (copy.api as Record<string, string>)[error.payload.code] ?? copy.api.fallback,
      traceId: error.payload.traceId,
    };
  }

  return {
    message: copy.api.fallback,
    traceId: undefined,
  };
}

export function SharingRoute() {
  const { authorizedFetch } = useAuth();
  const { locale } = useI18n();
  const copy = useAdvancedCopy();
  const [searchParams] = useSearchParams();
  const [folders, setFolders] = useState<FolderDto[]>([]);
  const [goals, setGoals] = useState<GoalDto[]>([]);
  const [tasks, setTasks] = useState<TaskDto[]>([]);
  const [selectedFolderId, setSelectedFolderId] = useState('');
  const [selectedGoalId, setSelectedGoalId] = useState(searchParams.get('goal') ?? '');
  const [targetType, setTargetType] = useState<ShareTargetType>(searchParams.get('task') ? 'task' : 'goal');
  const [targetId, setTargetId] = useState(searchParams.get('task') ?? searchParams.get('goal') ?? '');
  const [email, setEmail] = useState('');
  const [invitations, setInvitations] = useState<ShareInvitationDto[]>([]);
  const [sharedGoals, setSharedGoals] = useState<GoalDto[]>([]);
  const [sharedTasks, setSharedTasks] = useState<TaskDto[]>([]);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [traceId, setTraceId] = useState<string | undefined>();
  const [notice, setNotice] = useState<string | null>(null);

  const targetOptions = useMemo(
    () => (targetType === 'goal' ? goals : tasks).map((item) => ({
      id: item.id,
      label: 'name' in item ? item.name : item.title,
    })),
    [goals, tasks, targetType],
  );

  async function loadPlanningContext() {
    const nextFolders = await listFolders(authorizedFetch);
    setFolders(nextFolders);

    const nextFolderId = searchParams.get('folder') ?? nextFolders[0]?.id ?? '';
    setSelectedFolderId(nextFolderId);

    if (!nextFolderId) {
      setGoals([]);
      setTasks([]);
      return;
    }

    const nextGoals = await listGoals(authorizedFetch, nextFolderId);
    setGoals(nextGoals);

    const nextGoalId = searchParams.get('goal') ?? nextGoals[0]?.id ?? '';
    setSelectedGoalId(nextGoalId);

    if (!nextGoalId) {
      setTasks([]);
      return;
    }

    const nextTasks = await listTasks(authorizedFetch, nextGoalId);
    setTasks(nextTasks);
  }

  async function loadData() {
    setLoading(true);
    setError(null);
    setTraceId(undefined);

    try {
      await loadPlanningContext();
      const [invitationResponse, resourceResponse] = await Promise.all([
        getInvitations(authorizedFetch),
        getSharedResources(authorizedFetch),
      ]);

      setInvitations(invitationResponse.items);
      setSharedGoals(resourceResponse.goals);
      setSharedTasks(resourceResponse.tasks);
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

  useEffect(() => {
    async function reloadGoals() {
      if (!selectedFolderId) {
        setGoals([]);
        setTasks([]);
        return;
      }

      try {
        const nextGoals = await listGoals(authorizedFetch, selectedFolderId);
        setGoals(nextGoals);
        const nextGoalId =
          selectedGoalId && nextGoals.some((goal) => goal.id === selectedGoalId)
            ? selectedGoalId
            : nextGoals[0]?.id ?? '';

        setSelectedGoalId(nextGoalId);

        if (targetType === 'goal') {
          setTargetId((current) =>
            current && nextGoals.some((goal) => goal.id === current) ? current : nextGoalId,
          );
        }
      } catch (error) {
        const mapped = mapError(error, copy);
        setError(mapped.message);
        setTraceId(mapped.traceId);
      }
    }

    void reloadGoals();
  }, [selectedFolderId]);

  useEffect(() => {
    async function reloadTasks() {
      if (!selectedGoalId) {
        setTasks([]);
        return;
      }

      try {
        const nextTasks = await listTasks(authorizedFetch, selectedGoalId);
        setTasks(nextTasks);

        if (targetType === 'task') {
          setTargetId((current) =>
            current && nextTasks.some((task) => task.id === current) ? current : nextTasks[0]?.id ?? '',
          );
        }
      } catch (error) {
        const mapped = mapError(error, copy);
        setError(mapped.message);
        setTraceId(mapped.traceId);
      }
    }

    void reloadTasks();
  }, [selectedGoalId, targetType]);

  async function handleInviteSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!email.trim() || !targetId) {
      setError(copy.api.validation_error);
      return;
    }

    setSubmitting(true);
    setError(null);
    setTraceId(undefined);

    try {
      if (targetType === 'goal') {
        await createGoalInvitation(authorizedFetch, targetId, { email: email.trim() });
      } else {
        await createTaskInvitation(authorizedFetch, targetId, { email: email.trim() });
      }

      setEmail('');
      setNotice(copy.sharing.createdNotice);
      await loadData();
    } catch (error) {
      const mapped = mapError(error, copy);
      setError(mapped.message);
      setTraceId(mapped.traceId);
    } finally {
      setSubmitting(false);
    }
  }

  async function updateInvitation(invitationId: string, action: 'accept' | 'decline' | 'revoke') {
    setSubmitting(true);
    setError(null);
    setTraceId(undefined);

    try {
      if (action === 'accept') {
        await acceptInvitation(authorizedFetch, invitationId);
      } else if (action === 'decline') {
        await declineInvitation(authorizedFetch, invitationId);
      } else {
        await revokeInvitation(authorizedFetch, invitationId);
      }

      setNotice(copy.sharing.updatedNotice);
      await loadData();
    } catch (error) {
      const mapped = mapError(error, copy);
      setError(mapped.message);
      setTraceId(mapped.traceId);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="stack">
      <div className="surface-header">
        <div className="stack stack--tight">
          <div className="caps">{copy.common.title}</div>
          <div className="surface-title">{copy.sharing.title}</div>
          <div className="surface-subtitle">{copy.sharing.subtitle}</div>
        </div>
      </div>

      {notice ? <PlanningInlineNotice tone="info">{notice}</PlanningInlineNotice> : null}
      {error ? <PlanningInlineNotice tone="error">{error}</PlanningInlineNotice> : null}
      {traceId ? <PlanningInlineNotice tone="info">{copy.common.traceId}: {traceId}</PlanningInlineNotice> : null}

      <div className="shell-grid shell-grid--2">
        <RetroPanel title={copy.sharing.inviteTitle} aside={<RetroBadge tone="warning">MVP</RetroBadge>}>
          {loading ? (
            <LoadingState title={copy.common.loadingTitle} description={copy.common.loadingDescription} />
          ) : error ? (
            <ErrorState title={copy.common.errorTitle} description={error} />
          ) : (
            <form className="stack stack--tight" onSubmit={handleInviteSubmit}>
              <RetroField label={copy.sharing.folderLabel}>
                <select
                  className="retro-select"
                  value={selectedFolderId}
                  onChange={(event) => setSelectedFolderId(event.target.value)}
                >
                  {folders.map((folder) => (
                    <option key={folder.id} value={folder.id}>
                      {folder.name}
                    </option>
                  ))}
                </select>
              </RetroField>

              <RetroField label={copy.sharing.inviteTarget} hint={copy.sharing.targetHint}>
                <select
                  className="retro-select"
                  value={targetType}
                  onChange={(event) => setTargetType(event.target.value as ShareTargetType)}
                >
                  <option value="goal">{copy.sharing.inviteGoal}</option>
                  <option value="task">{copy.sharing.inviteTask}</option>
                </select>
              </RetroField>

              {targetType === 'task' ? (
                <RetroField label={copy.sharing.goalLabel}>
                  <select
                    className="retro-select"
                    value={selectedGoalId}
                    onChange={(event) => setSelectedGoalId(event.target.value)}
                  >
                    {goals.map((goal) => (
                      <option key={goal.id} value={goal.id}>
                        {goal.name}
                      </option>
                    ))}
                  </select>
                </RetroField>
              ) : null}

              <RetroField label={targetType === 'goal' ? copy.sharing.goalLabel : copy.sharing.taskLabel}>
                <select
                  className="retro-select"
                  value={targetId}
                  onChange={(event) => setTargetId(event.target.value)}
                >
                  {targetOptions.map((option) => (
                    <option key={option.id} value={option.id}>
                      {option.label}
                    </option>
                  ))}
                </select>
              </RetroField>

              <RetroField label={copy.sharing.inviteEmail}>
                <input
                  className="retro-input"
                  type="email"
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                />
              </RetroField>

              <div className="cluster">
                <RetroButton type="submit" variant="primary" disabled={submitting || !targetId}>
                  {copy.sharing.createInvite}
                </RetroButton>
              </div>
            </form>
          )}
        </RetroPanel>

        <RetroPanel
          title={copy.sharing.invitationListTitle}
          aside={(
            <RetroButton type="button" size="small" onClick={() => void loadData()}>
              {copy.common.refresh}
            </RetroButton>
          )}
        >
          {loading ? (
            <LoadingState title={copy.common.loadingTitle} description={copy.common.loadingDescription} />
          ) : invitations.length === 0 ? (
            <EmptyState
              title={copy.sharing.invitationsEmptyTitle}
              description={copy.sharing.invitationsEmptyDescription}
            />
          ) : (
            <div className="stack stack--tight">
              {invitations.map((invitation) => (
                <div key={invitation.id} className="inventory-card">
                  <div className="surface-header">
                    <div className="stack stack--tight">
                      <div className="inventory-card__label">
                        {invitation.targetType === 'goal' ? copy.sharing.inviteGoal : copy.sharing.inviteTask}
                      </div>
                      <div className="inventory-card__path">{invitation.targetEmail}</div>
                    </div>
                    <RetroBadge tone={invitation.status === 'pending' ? 'warning' : 'info'}>
                      {copy.enums.invitationStatus[invitation.status]}
                    </RetroBadge>
                  </div>
                  <p className="inventory-card__summary">
                    {formatDateTime(invitation.createdAt, locale)} • {formatDateTime(invitation.expiresAt, locale)}
                  </p>
                  {invitation.status === 'pending' ? (
                    <div className="cluster">
                      <RetroButton type="button" size="small" variant="primary" disabled={submitting} onClick={() => void updateInvitation(invitation.id, 'accept')}>
                        {copy.sharing.accept}
                      </RetroButton>
                      <RetroButton type="button" size="small" disabled={submitting} onClick={() => void updateInvitation(invitation.id, 'decline')}>
                        {copy.sharing.decline}
                      </RetroButton>
                      <RetroButton type="button" size="small" variant="danger" disabled={submitting} onClick={() => void updateInvitation(invitation.id, 'revoke')}>
                        {copy.sharing.revoke}
                      </RetroButton>
                    </div>
                  ) : null}
                </div>
              ))}
            </div>
          )}
        </RetroPanel>
      </div>

      <RetroPanel title={copy.sharing.resourcesTitle}>
        {loading ? (
          <LoadingState title={copy.common.loadingTitle} description={copy.common.loadingDescription} />
        ) : sharedGoals.length === 0 && sharedTasks.length === 0 ? (
          <EmptyState
            title={copy.sharing.resourcesEmptyTitle}
            description={copy.sharing.resourcesEmptyDescription}
          />
        ) : (
          <div className="shell-grid shell-grid--2">
            <div className="stack stack--tight">
              <div className="caps">{copy.sharing.sharedGoals}</div>
              {sharedGoals.map((goal) => (
                <div key={goal.id} className="inventory-card">
                  <div className="inventory-card__label">{goal.name}</div>
                  <p className="inventory-card__summary">{goal.description || copy.common.noDescription}</p>
                  <div className="cluster">
                    <RetroBadge tone="warning">{copy.common.share}</RetroBadge>
                    <RetroButton as={Link} to={`/app/goals?goal=${goal.id}`} size="small" variant="ghost">
                      {copy.common.openGoal}
                    </RetroButton>
                  </div>
                </div>
              ))}
            </div>

            <div className="stack stack--tight">
              <div className="caps">{copy.sharing.sharedTasks}</div>
              {sharedTasks.map((task) => (
                <div key={task.id} className="inventory-card">
                  <div className="inventory-card__label">{task.title}</div>
                  <p className="inventory-card__summary">{task.description || copy.common.noDescription}</p>
                  <div className="cluster">
                    <RetroBadge tone={task.type === 'green' ? 'success' : 'danger'}>
                      {copy.enums.type[task.type]}
                    </RetroBadge>
                    <RetroBadge tone="info">{copy.enums.status[task.status]}</RetroBadge>
                    <RetroButton as={Link} to={`/app/tasks?task=${task.id}`} size="small" variant="ghost">
                      {copy.common.openTask}
                    </RetroButton>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </RetroPanel>
    </div>
  );
}

