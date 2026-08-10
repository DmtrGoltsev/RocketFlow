import {
  Bell,
  BellOff,
  Check,
  ChevronDown,
  ChevronUp,
  Circle,
  Clock3,
  Folder,
  History,
  ListPlus,
  RefreshCw,
  Search,
  Target,
  Trash2,
  X,
} from 'lucide-react';
import { useEffect, useMemo, useRef, useState } from 'react';
import type { MouseEventHandler } from 'react';
import { useNavigate } from 'react-router-dom';

import { useAuth } from '../../auth';
import { useI18n } from '../../../i18n';
import {
  addCurrentFocusItem,
  createWebPushSubscription,
  deleteWebPushSubscription,
  FocusApiError,
  getCurrentFocus,
  getFocusCandidates,
  getFocusHistory,
  getFocusHistoryPeriod,
  getFocusNotificationSettings,
  getWebPushConfig,
  removeCurrentFocusItem,
  reorderCurrentFocusItems,
  resolveFocusRollover,
  saveFocusNotificationSettings,
} from '../focus-api';
import {
  base64UrlToUint8Array,
  browserInstallationId,
  calculateFocusProgress,
  groupFocusCandidates,
  invalidateWebPushSessionOperations,
  isCurrentWebPushSessionOperation,
  isLatestFocusCandidateRequest,
  isLatestFocusHistoryRequest,
  mergeFocusCandidatePages,
  readWebPushSubscriptionId,
  removeLegacyWebPushSubscriptionId,
  taskDetailPath,
  updateCandidateFocusAfterMutation,
  webPushExpirationTimeToIso,
  writeWebPushSubscriptionId,
} from '../focus-utils';
import { LatestRequestController } from '../latest-request';
import {
  cleanupWebPushForUser,
  readPendingWebPushCleanups,
  retryPendingWebPushCleanups,
  unsubscribeCurrentBrowserPush,
} from '../web-push-lifecycle';
import type {
  FocusCandidateDto,
  FocusInterval,
  FocusNotificationSettingsDto,
  FocusPeriodDto,
} from '../types';

const INTERVALS: FocusInterval[] = ['off', '30m', '1h', '2h', '4h'];

export function FocusAddButton({ label, onClick }: { label: string; onClick: MouseEventHandler<HTMLButtonElement> }) {
  return (
    <button className="button button--primary" type="button" title={label} aria-label={label} aria-haspopup="dialog" onClick={onClick}>
      <ListPlus aria-hidden="true" size={17} />
      <span>{label}</span>
    </button>
  );
}

function copyFor(locale: 'ru' | 'en') {
  return locale === 'ru' ? {
    title: 'Фокус', subtitle: 'Главные задачи этой недели', add: 'Добавить задачу', refresh: 'Обновить',
    empty: 'Фокус пока пуст', emptyHint: 'Добавьте задачи, на которых хотите сосредоточиться на этой неделе.',
    completed: 'выполнено', effort: 'веса', remove: 'Убрать из фокуса', up: 'Поднять', down: 'Опустить',
    pickerTitle: 'Добавить в фокус', search: 'Найти папку, цель или задачу', noCandidates: 'Подходящих задач не найдено.',
    close: 'Закрыть', addItem: 'Добавить', already: 'Уже в фокусе', loading: 'Загрузка...', retry: 'Повторить',
    history: 'История', current: 'Текущая неделя', noHistory: 'Завершенных недель пока нет.',
    reminders: 'Напоминания фокуса', reminderHint: 'Регулярно, пока в фокусе есть невыполненные задачи.',
    interval: 'Частота', quiet: 'Тихие часы', from: 'С', to: 'До', save: 'Сохранить',
    pushEnable: 'Включить уведомления браузера', pushDisable: 'Отключить уведомления браузера',
    pushUnsupported: 'Этот браузер не поддерживает фоновые уведомления.', pushDenied: 'Уведомления запрещены в настройках браузера.',
    pushActive: 'Уведомления браузера включены', off: 'Выкл.', rollover: 'Перенести незавершенные задачи?',
    rolloverHint: 'Отметьте задачи, которые должны перейти в текущую неделю.', carry: 'Перенести выбранные', skip: 'Не переносить',
    conflict: 'Фокус изменился на другом устройстве. Данные обновлены.', error: 'Не удалось загрузить фокус.',
  } : {
    title: 'Focus', subtitle: 'Your most important tasks this week', add: 'Add task', refresh: 'Refresh',
    empty: 'Focus is empty', emptyHint: 'Add the tasks you want to concentrate on this week.',
    completed: 'completed', effort: 'weight', remove: 'Remove from Focus', up: 'Move up', down: 'Move down',
    pickerTitle: 'Add to Focus', search: 'Find a folder, goal, or task', noCandidates: 'No matching tasks.',
    close: 'Close', addItem: 'Add', already: 'Already focused', loading: 'Loading...', retry: 'Retry',
    history: 'History', current: 'Current week', noHistory: 'No completed weeks yet.',
    reminders: 'Focus reminders', reminderHint: 'Regularly, while Focus has unfinished tasks.',
    interval: 'Frequency', quiet: 'Quiet hours', from: 'From', to: 'To', save: 'Save',
    pushEnable: 'Enable browser notifications', pushDisable: 'Disable browser notifications',
    pushUnsupported: 'This browser does not support background notifications.', pushDenied: 'Notifications are blocked in browser settings.',
    pushActive: 'Browser notifications are enabled', off: 'Off', rollover: 'Carry unfinished tasks?',
    rolloverHint: 'Select tasks to carry into the current week.', carry: 'Carry selected', skip: 'Do not carry',
    conflict: 'Focus changed on another device. Data was refreshed.', error: 'Could not load Focus.',
  };
}

function periodLabel(period: FocusPeriodDto, locale: string) {
  const start = new Date(`${period.weekStart}T00:00:00`);
  const end = new Date(`${period.weekEndExclusive}T00:00:00`);
  end.setDate(end.getDate() - 1);
  const formatter = new Intl.DateTimeFormat(locale === 'ru' ? 'ru-RU' : 'en-US', { day: 'numeric', month: 'short' });
  return `${formatter.format(start)} - ${formatter.format(end)}`;
}

export function FocusRoute() {
  const { authorizedFetch, session } = useAuth();
  const { locale } = useI18n();
  const navigate = useNavigate();
  const copy = copyFor(locale);
  const [period, setPeriod] = useState<FocusPeriodDto | null>(null);
  const [history, setHistory] = useState<FocusPeriodDto[]>([]);
  const [historyPeriod, setHistoryPeriod] = useState<FocusPeriodDto | null>(null);
  const [selectedHistoryPeriodId, setSelectedHistoryPeriodId] = useState<string | null>(null);
  const [historyDetailLoading, setHistoryDetailLoading] = useState(false);
  const [settings, setSettings] = useState<FocusNotificationSettingsDto | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [candidates, setCandidates] = useState<FocusCandidateDto[]>([]);
  const [candidateLoading, setCandidateLoading] = useState(false);
  const [candidateError, setCandidateError] = useState<string | null>(null);
  const [candidateNextCursor, setCandidateNextCursor] = useState<string | null>(null);
  const [candidateReloadToken, setCandidateReloadToken] = useState(0);
  const [historyError, setHistoryError] = useState<string | null>(null);
  const [settingsError, setSettingsError] = useState<string | null>(null);
  const [selectedCarry, setSelectedCarry] = useState<Set<string>>(new Set());
  const [pushSubscriptionId, setPushSubscriptionId] = useState<string | null>(null);
  const [pushSupported, setPushSupported] = useState(true);
  const candidateRequestRef = useRef(0);
  const historyRequestRef = useRef(0);
  const historyAbortRef = useRef<AbortController | null>(null);
  const loadRequestRef = useRef<LatestRequestController | null>(null);
  const currentPushUserRef = useRef<string | null>(session?.user.id ?? null);
  const pushAbortRef = useRef<AbortController | null>(null);
  const pickerDialogRef = useRef<HTMLElement | null>(null);
  const pickerOpenerRef = useRef<HTMLElement | null>(null);
  currentPushUserRef.current = session?.user.id ?? null;
  if (!loadRequestRef.current) loadRequestRef.current = new LatestRequestController();

  const visiblePeriod = selectedHistoryPeriodId ? historyPeriod : period;
  const progress = visiblePeriod?.progress ?? calculateFocusProgress(visiblePeriod?.items ?? []);
  const groups = useMemo(() => groupFocusCandidates(candidates), [candidates]);

  async function load(showSpinner = true) {
    const coordinator = loadRequestRef.current!;
    const request = coordinator.begin();
    if (showSpinner) setLoading(true);
    setError(null);
    setHistoryError(null);
    setSettingsError(null);
    try {
      const current = await getCurrentFocus(authorizedFetch, request.signal);
      if (!coordinator.isCurrent(request)) return;
      setPeriod(current);
      const offerItems = current.rolloverOffer?.items ?? [];
      setSelectedCarry(new Set(offerItems.map((item) => item.taskId)));

      const [historyResult, settingsResult] = await Promise.allSettled([
        getFocusHistory(authorizedFetch, request.signal),
        getFocusNotificationSettings(authorizedFetch, request.signal),
      ]);
      if (!coordinator.isCurrent(request)) return;
      if (historyResult.status === 'fulfilled') {
        setHistory((historyResult.value.items ?? []).map((item) => ({ ...item, items: item.items ?? [] })));
      } else {
        setHistoryError(historyResult.reason instanceof Error ? historyResult.reason.message : copy.error);
      }
      if (settingsResult.status === 'fulfilled') {
        setSettings(settingsResult.value);
      } else {
        setSettingsError(settingsResult.reason instanceof Error ? settingsResult.reason.message : copy.error);
      }
    } catch (loadError) {
      if (!coordinator.isCurrent(request)) return;
      setError(loadError instanceof Error ? loadError.message : copy.error);
    } finally {
      if (coordinator.isCurrent(request)) {
        setLoading(false);
        coordinator.finish(request);
      }
    }
  }

  useEffect(() => { void load(); }, []);

  useEffect(() => () => {
    historyAbortRef.current?.abort();
    loadRequestRef.current?.invalidate();
  }, []);

  useEffect(() => {
    if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
      setPushSupported(false);
      return;
    }
    const userId = session?.user.id;
    const operationGeneration = invalidateWebPushSessionOperations();
    pushAbortRef.current?.abort();
    const controller = new AbortController();
    pushAbortRef.current = controller;
    setPushSubscriptionId(null);
    if (!userId) return;
    let active = true;
    void navigator.serviceWorker.ready
      .then(async (registration) => {
        const subscription = await registration.pushManager.getSubscription();
        if (!active || !isCurrentWebPushSessionOperation(operationGeneration, userId, currentPushUserRef.current)) return;

        const storedSubscriptionId = readWebPushSubscriptionId(userId);
        const pendingCleanup = readPendingWebPushCleanups().find((item) => item.userId === userId);
        if (pendingCleanup) {
          const result = await cleanupWebPushForUser({
            ...pendingCleanup,
            reason: 'bootstrap_retry',
            deactivateServer: pendingCleanup.subscriptionId
              ? () => deleteWebPushSubscription(authorizedFetch, pendingCleanup.subscriptionId!, controller.signal)
              : null,
            unsubscribeBrowser: unsubscribeCurrentBrowserPush,
          });
          if (!active || currentPushUserRef.current !== userId) return;
          setPushSubscriptionId(result.completed ? null : pendingCleanup.subscriptionId);
          return;
        }
        if (!subscription || !storedSubscriptionId) {
          await cleanupWebPushForUser({
            userId,
            subscriptionId: storedSubscriptionId,
            reason: 'stale_enable',
            deactivateServer: storedSubscriptionId
              ? () => deleteWebPushSubscription(authorizedFetch, storedSubscriptionId, controller.signal)
              : null,
            unsubscribeBrowser: unsubscribeCurrentBrowserPush,
          });
          if (!active || !isCurrentWebPushSessionOperation(operationGeneration, userId, currentPushUserRef.current)) return;
          setPushSubscriptionId(null);
          return;
        }
        removeLegacyWebPushSubscriptionId();
        setPushSubscriptionId(storedSubscriptionId);
      })
      .catch(() => {
        if (active && isCurrentWebPushSessionOperation(operationGeneration, userId, currentPushUserRef.current)) {
          setPushSubscriptionId(null);
        }
      });
    return () => {
      active = false;
      invalidateWebPushSessionOperations();
      controller.abort();
      if (pushAbortRef.current === controller) pushAbortRef.current = null;
    };
  }, [session?.user.id]);

  useEffect(() => {
    if (!pickerOpen) return;
    const requestId = ++candidateRequestRef.current;
    const controller = new AbortController();
    const timeout = window.setTimeout(async () => {
      setCandidateLoading(true);
      setCandidateError(null);
      try {
        const response = await getFocusCandidates(authorizedFetch, query, undefined, controller.signal);
        if (!isLatestFocusCandidateRequest(requestId, candidateRequestRef.current)) return;
        setCandidates(response.items ?? []);
        setCandidateNextCursor(response.nextCursor ?? null);
      } catch (candidateError) {
        if (controller.signal.aborted || !isLatestFocusCandidateRequest(requestId, candidateRequestRef.current)) return;
        setCandidateError(candidateError instanceof Error ? candidateError.message : copy.error);
      } finally {
        if (isLatestFocusCandidateRequest(requestId, candidateRequestRef.current)) setCandidateLoading(false);
      }
    }, query ? 250 : 0);
    return () => {
      window.clearTimeout(timeout);
      controller.abort();
    };
  }, [pickerOpen, query, candidateReloadToken]);

  useEffect(() => {
    if (!pickerOpen) return;
    const dialog = pickerDialogRef.current;
    const opener = pickerOpenerRef.current;
    const focusableSelector = 'button:not([disabled]), input:not([disabled]), [href], [tabindex]:not([tabindex="-1"])';
    dialog?.querySelector<HTMLElement>(focusableSelector)?.focus();

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        event.preventDefault();
        setPickerOpen(false);
        return;
      }
      if (event.key !== 'Tab' || !dialog) return;
      const focusable = [...dialog.querySelectorAll<HTMLElement>(focusableSelector)];
      if (focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault(); last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault(); first.focus();
      }
    }

    document.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('keydown', handleKeyDown);
      opener?.focus();
    };
  }, [pickerOpen]);

  async function loadMoreCandidates() {
    if (!candidateNextCursor || candidateLoading) return;
    const requestId = ++candidateRequestRef.current;
    setCandidateLoading(true);
    setCandidateError(null);
    try {
      const response = await getFocusCandidates(authorizedFetch, query, candidateNextCursor);
      if (!isLatestFocusCandidateRequest(requestId, candidateRequestRef.current)) return;
      setCandidates((current) => mergeFocusCandidatePages(current, response.items ?? [], true));
      setCandidateNextCursor(response.nextCursor ?? null);
    } catch (loadMoreError) {
      if (!isLatestFocusCandidateRequest(requestId, candidateRequestRef.current)) return;
      setCandidateError(loadMoreError instanceof Error ? loadMoreError.message : copy.error);
    } finally {
      if (isLatestFocusCandidateRequest(requestId, candidateRequestRef.current)) setCandidateLoading(false);
    }
  }

  async function mutate(action: () => Promise<FocusPeriodDto>) {
    loadRequestRef.current?.invalidate();
    setLoading(false);
    setSaving(true);
    setError(null);
    setNotice(null);
    try {
      setPeriod(await action());
      return true;
    } catch (mutationError) {
      if (mutationError instanceof FocusApiError && mutationError.status === 409) {
        setNotice(copy.conflict);
        await load(false);
      } else {
        setError(mutationError instanceof Error ? mutationError.message : copy.error);
      }
      return false;
    } finally {
      setSaving(false);
    }
  }

  async function addCandidate(candidate: FocusCandidateDto) {
    if (!period) return;
    const succeeded = await mutate(() => addCurrentFocusItem(authorizedFetch, candidate.taskId, period.version));
    setCandidates((items) => updateCandidateFocusAfterMutation(items, candidate.taskId, succeeded));
  }

  async function moveItem(index: number, direction: -1 | 1) {
    if (!period) return;
    const taskIds = period.items.map((item) => item.taskId);
    const target = index + direction;
    if (target < 0 || target >= taskIds.length) return;
    [taskIds[index], taskIds[target]] = [taskIds[target], taskIds[index]];
    await mutate(() => reorderCurrentFocusItems(authorizedFetch, taskIds, period.version));
  }

  async function saveSettings() {
    if (!settings) return;
    loadRequestRef.current?.invalidate();
    setLoading(false);
    setSaving(true);
    setError(null);
    try {
      const result = await saveFocusNotificationSettings(authorizedFetch, settings);
      setSettings(result.settings);
      setNotice(result.conflict ? copy.conflict : copy.save);
    } catch (settingsError) {
      setError(settingsError instanceof Error ? settingsError.message : copy.error);
    } finally { setSaving(false); }
  }

  async function togglePush() {
    if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
      setPushSupported(false);
      return;
    }
    const userId = session?.user.id;
    if (!userId) return;

    pushAbortRef.current?.abort();
    const controller = new AbortController();
    pushAbortRef.current = controller;
    let operationGeneration: number | null = null;
    const isSameUser = () => !controller.signal.aborted && currentPushUserRef.current === userId;
    const isCurrentOperation = () => (
      isSameUser()
      && operationGeneration !== null
      && isCurrentWebPushSessionOperation(operationGeneration, userId, currentPushUserRef.current)
    );
    setError(null);

    let browserSubscription: PushSubscription | null = null;
    let createdSubscriptionId: string | null = null;
    try {
      const pending = await retryPendingWebPushCleanups(
        'enable_retry',
        (item) => item.userId === userId && item.subscriptionId
          ? () => deleteWebPushSubscription(authorizedFetch, item.subscriptionId!, controller.signal)
          : null,
        unsubscribeCurrentBrowserPush,
      );
      if (!isSameUser()) return;
      if (pending.length > 0) {
        setError(copy.error);
        return;
      }

      if (pushSubscriptionId) {
        const result = await cleanupWebPushForUser({
          userId,
          subscriptionId: pushSubscriptionId,
          reason: 'explicit_disable',
          deactivateServer: () => deleteWebPushSubscription(
            authorizedFetch,
            pushSubscriptionId,
            controller.signal,
          ),
          unsubscribeBrowser: unsubscribeCurrentBrowserPush,
        });
        if (!isSameUser()) return;
        if (result.completed) setPushSubscriptionId(null);
        else setError(copy.error);
        return;
      }

      operationGeneration = invalidateWebPushSessionOperations();
      const config = await getWebPushConfig(authorizedFetch, controller.signal);
      if (!isCurrentOperation()) return;
      if (!config.enabled || !config.publicKey) {
        setError(copy.pushUnsupported);
        return;
      }

      const permission = await Notification.requestPermission();
      if (!isCurrentOperation()) return;
      if (permission !== 'granted') {
        setError(copy.pushDenied);
        return;
      }

      const registration = await navigator.serviceWorker.ready;
      if (!isCurrentOperation()) return;
      const existingSubscription = await registration.pushManager.getSubscription();
      if (existingSubscription) {
        const staleResult = await cleanupWebPushForUser({
          userId,
          subscriptionId: null,
          reason: 'stale_enable',
          deactivateServer: null,
          unsubscribeBrowser: async () => {
            if (!(await existingSubscription.unsubscribe())) {
              throw new Error('Existing browser push subscription could not be replaced.');
            }
          },
        });
        if (!isSameUser() || !staleResult.completed) {
          if (isSameUser()) setError(copy.error);
          return;
        }
        operationGeneration = invalidateWebPushSessionOperations();
      }
      if (!isCurrentOperation()) return;

      browserSubscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: base64UrlToUint8Array(config.publicKey),
      });
      if (!isCurrentOperation()) {
        await cleanupWebPushForUser({
          userId,
          subscriptionId: null,
          reason: 'stale_enable',
          deactivateServer: null,
          unsubscribeBrowser: async () => {
            if (browserSubscription && !(await browserSubscription.unsubscribe())) {
              throw new Error('Stale browser push unsubscribe was rejected.');
            }
          },
        });
        return;
      }

      const json = browserSubscription.toJSON();
      const created = await createWebPushSubscription(authorizedFetch, {
        endpoint: browserSubscription.endpoint,
        expirationTime: webPushExpirationTimeToIso(browserSubscription.expirationTime),
        keys: json.keys,
        installationId: browserInstallationId(),
      }, controller.signal);
      createdSubscriptionId = created.id;
      if (!isCurrentOperation()) {
        await cleanupWebPushForUser({
          userId,
          subscriptionId: created.id,
          reason: 'stale_enable',
          deactivateServer: () => deleteWebPushSubscription(authorizedFetch, created.id),
          unsubscribeBrowser: async () => {
            if (browserSubscription && !(await browserSubscription.unsubscribe())) {
              throw new Error('Stale browser push unsubscribe was rejected.');
            }
          },
        });
        return;
      }

      writeWebPushSubscriptionId(userId, created.id);
      removeLegacyWebPushSubscriptionId();
      setPushSubscriptionId(created.id);
    } catch (pushError) {
      if (browserSubscription) {
        await cleanupWebPushForUser({
          userId,
          subscriptionId: createdSubscriptionId,
          reason: 'stale_enable',
          deactivateServer: createdSubscriptionId
            ? () => deleteWebPushSubscription(authorizedFetch, createdSubscriptionId!)
            : null,
          unsubscribeBrowser: async () => {
            if (browserSubscription && !(await browserSubscription.unsubscribe())) {
              throw new Error('Failed browser push subscription cleanup.');
            }
          },
        });
      }
      if (isSameUser()) {
        setPushSubscriptionId(null);
        if (!(pushError instanceof DOMException && pushError.name === 'AbortError')) setError(copy.error);
      }
    } finally {
      if (pushAbortRef.current === controller) pushAbortRef.current = null;
    }
  }

  async function openHistoryPeriod(periodId: string) {
    const requestId = ++historyRequestRef.current;
    historyAbortRef.current?.abort();
    const controller = new AbortController();
    historyAbortRef.current = controller;
    setSelectedHistoryPeriodId(periodId);
    setHistoryPeriod(null);
    setHistoryDetailLoading(true);
    setHistoryError(null);
    try {
      const response = await getFocusHistoryPeriod(authorizedFetch, periodId, controller.signal);
      if (!isLatestFocusHistoryRequest(requestId, historyRequestRef.current) || controller.signal.aborted) return;
      setHistoryPeriod(response);
    } catch (historyLoadError) {
      if (!isLatestFocusHistoryRequest(requestId, historyRequestRef.current) || controller.signal.aborted) return;
      setHistoryError(historyLoadError instanceof Error ? historyLoadError.message : copy.error);
    } finally {
      if (isLatestFocusHistoryRequest(requestId, historyRequestRef.current)) {
        setHistoryDetailLoading(false);
        if (historyAbortRef.current === controller) historyAbortRef.current = null;
      }
    }
  }

  function returnToCurrentPeriod() {
    historyRequestRef.current += 1;
    historyAbortRef.current?.abort();
    historyAbortRef.current = null;
    setSelectedHistoryPeriodId(null);
    setHistoryPeriod(null);
    setHistoryDetailLoading(false);
    setHistoryError(null);
  }

  if (loading) return <section className="focus-page focus-page--center">{copy.loading}</section>;

  return (
    <section className="focus-page">
      <header className="focus-header">
        <div><h1>{copy.title}</h1><p>{copy.subtitle}</p></div>
        <div className="focus-header__actions">
          <button className="icon-button" type="button" title={copy.refresh} aria-label={copy.refresh} onClick={() => void load()}><RefreshCw size={18} /></button>
          <FocusAddButton label={copy.add} onClick={(event) => { pickerOpenerRef.current = event.currentTarget; setPickerOpen(true); }} />
        </div>
      </header>

      {notice ? <div className="focus-notice">{notice}</div> : null}
      {error ? <div className="focus-error" role="alert">{error}<button type="button" onClick={() => void load()}>{copy.retry}</button></div> : null}

      <div className="focus-tabs" role="tablist">
        <button type="button" role="tab" aria-selected={!selectedHistoryPeriodId} onClick={returnToCurrentPeriod}>{copy.current}</button>
        <button type="button" role="tab" aria-selected={Boolean(selectedHistoryPeriodId)} disabled={!history.length} onClick={async () => {
          const item = history[0]; if (item) await openHistoryPeriod(item.id);
        }}><History size={15} />{copy.history}</button>
      </div>

      {historyDetailLoading ? <section className="focus-page--center">{copy.loading}</section> : visiblePeriod ? (
        <>
          <section className="focus-summary" aria-label={`${progress.percent}% ${copy.completed}`}>
            <div className="focus-summary__heading"><strong>{periodLabel(visiblePeriod, locale)}</strong><span>{progress.percent}% {copy.completed}</span></div>
            <div className="focus-progress"><span style={{ width: `${progress.percent}%` }} /></div>
            <small>{progress.completedWeight} / {progress.totalWeight} {copy.effort}</small>
          </section>

          {!selectedHistoryPeriodId && period?.rolloverOffer ? (
            <section className="focus-rollover">
              <h2>{copy.rollover}</h2><p>{copy.rolloverHint}</p>
              {period.rolloverOffer.items.map((item) => (
                <label key={item.taskId}><input type="checkbox" checked={selectedCarry.has(item.taskId)} onChange={(event) => setSelectedCarry((current) => {
                  const next = new Set(current); event.target.checked ? next.add(item.taskId) : next.delete(item.taskId); return next;
                })} /><span>{item.title}</span></label>
              ))}
              <div className="cluster">
                <button className="button button--primary" type="button" disabled={saving} onClick={() => void mutate(() => resolveFocusRollover(authorizedFetch, period.rolloverOffer!.sourcePeriodId, [...selectedCarry], period.version))}>{copy.carry}</button>
                <button className="button button--ghost" type="button" disabled={saving} onClick={() => void mutate(() => resolveFocusRollover(authorizedFetch, period.rolloverOffer!.sourcePeriodId, [], period.version))}>{copy.skip}</button>
              </div>
            </section>
          ) : null}

          <div className="focus-task-list">
            {visiblePeriod.items.length === 0 ? <div className="focus-empty"><Target size={28} /><h2>{copy.empty}</h2><p>{copy.emptyHint}</p></div> : null}
            {visiblePeriod.items.map((item, index) => (
              <article className={`focus-task${item.status === 'done' ? ' is-done' : ''}`} key={item.id || item.taskId}>
                <button className="focus-task__open" type="button" onClick={() => navigate(taskDetailPath(item.taskId))}>
                  {item.status === 'done' ? <Check size={18} /> : <Circle size={18} />}
                  <span><strong>{item.title}</strong><small>{item.path || [item.folderTitle, item.goalTitle].filter(Boolean).join(' / ')}</small></span>
                  <b>{item.effectiveWeight || item.effort || 1}</b>
                </button>
                {!selectedHistoryPeriodId ? <div className="focus-task__actions">
                  <button type="button" title={copy.up} aria-label={copy.up} disabled={saving || index === 0} onClick={() => void moveItem(index, -1)}><ChevronUp size={16} /></button>
                  <button type="button" title={copy.down} aria-label={copy.down} disabled={saving || index === visiblePeriod.items.length - 1} onClick={() => void moveItem(index, 1)}><ChevronDown size={16} /></button>
                  <button type="button" title={copy.remove} aria-label={copy.remove} disabled={saving} onClick={() => period && void mutate(() => removeCurrentFocusItem(authorizedFetch, item.taskId, period.version))}><Trash2 size={16} /></button>
                </div> : null}
              </article>
            ))}
          </div>
        </>
      ) : null}

      {!selectedHistoryPeriodId && settings ? (
        <section className="focus-settings">
          <div><h2>{copy.reminders}</h2><p>{copy.reminderHint}</p></div>
          <fieldset><legend>{copy.interval}</legend><div className="focus-segments">{INTERVALS.map((interval) => <label key={interval}><input type="radio" name="focus-interval" checked={settings.interval === interval} onChange={() => setSettings({ ...settings, interval })} /><span>{interval === 'off' ? copy.off : interval}</span></label>)}</div></fieldset>
          <div className="focus-quiet"><strong>{copy.quiet}</strong><label>{copy.from}<input type="time" value={settings.quietHoursStart ?? ''} onChange={(event) => setSettings({ ...settings, quietHoursStart: event.target.value || null })} /></label><label>{copy.to}<input type="time" value={settings.quietHoursEnd ?? ''} onChange={(event) => setSettings({ ...settings, quietHoursEnd: event.target.value || null })} /></label></div>
          <div className="cluster">
            <button className="button button--primary" type="button" disabled={saving} onClick={() => void saveSettings()}><Clock3 size={16} />{copy.save}</button>
            <button className="button button--ghost" type="button" disabled={saving || !pushSupported} onClick={() => void togglePush()}>{pushSubscriptionId ? <BellOff size={16} /> : <Bell size={16} />}{pushSubscriptionId ? copy.pushDisable : copy.pushEnable}</button>
          </div>
          {!pushSupported ? <small>{copy.pushUnsupported}</small> : pushSubscriptionId ? <small>{copy.pushActive}</small> : null}
        </section>
      ) : null}

      {settingsError ? <div className="focus-error" role="alert">{settingsError}<button type="button" onClick={() => void load(false)}>{copy.retry}</button></div> : null}

      {historyError ? <div className="focus-error" role="alert">{historyError}<button type="button" onClick={() => void load(false)}>{copy.retry}</button></div> : null}
      {history.length > 0 ? <section className="focus-history"><h2>{copy.history}</h2>{history.map((item) => <button type="button" key={item.id} onClick={() => void openHistoryPeriod(item.id)}><span>{periodLabel(item, locale)}</span><b>{(item.progress ?? calculateFocusProgress(item.items)).percent}%</b></button>)}</section> : null}

      {pickerOpen ? <div className="focus-dialog-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setPickerOpen(false); }}><section ref={pickerDialogRef} className="focus-dialog" role="dialog" aria-modal="true" aria-labelledby="focus-picker-title" aria-describedby="focus-picker-description">
        <header><h2 id="focus-picker-title">{copy.pickerTitle}</h2><button className="icon-button" type="button" title={copy.close} aria-label={copy.close} onClick={() => setPickerOpen(false)}><X size={18} /></button></header>
        <p id="focus-picker-description" className="sr-only">{copy.search}</p>
        <label className="focus-search"><Search size={17} /><input value={query} placeholder={copy.search} onChange={(event) => setQuery(event.target.value)} /></label>
        <div className="focus-picker-list">{candidateError ? <div className="focus-error" role="alert">{candidateError}<button type="button" onClick={() => setCandidateReloadToken((value) => value + 1)}>{copy.retry}</button></div> : null}{candidates.length === 0 && candidateLoading ? <p>{copy.loading}</p> : candidates.length === 0 ? <p>{copy.noCandidates}</p> : groups.map((folder) => <section key={folder.id}><h3><Folder size={15} />{folder.title}</h3>{folder.goals.map((goal) => <div key={goal.id}><h4><Target size={14} />{goal.title}</h4>{goal.items.map((item) => <div className="focus-candidate" key={item.taskId}><button type="button" onClick={() => navigate(taskDetailPath(item.taskId))}><span>{item.title}</span><small>{item.status}</small></button><button className="icon-button" type="button" disabled={saving || item.inFocus || period?.items.some((current) => current.taskId === item.taskId)} title={item.inFocus ? copy.already : copy.addItem} aria-label={item.inFocus ? copy.already : copy.addItem} onClick={() => void addCandidate(item)}>{item.inFocus ? <Check size={16} /> : <ListPlus size={16} />}</button></div>)}</div>)}</section>)}{candidateNextCursor ? <button className="button button--ghost" type="button" disabled={candidateLoading} onClick={() => void loadMoreCandidates()}>{candidateLoading ? copy.loading : (locale === 'ru' ? 'Показать еще' : 'Load more')}</button> : null}</div>
      </section></div> : null}
    </section>
  );
}
