import { createContext, useContext, useEffect, useRef, useState, type PropsWithChildren } from 'react';

import { useI18n } from '../../i18n';
import {
  ApiError,
  authorizedRequest,
  login as loginRequest,
  logout as logoutRequest,
  register as registerRequest,
  restoreSession as restoreSessionRequest
} from './auth-api';
import {
  AUTH_STORAGE_KEY,
  AUTH_SYNC_CHANNEL,
  clearStoredSession,
  readStoredSession,
  writeStoredSession
} from './auth-storage';
import type { AuthApiError, AuthSession, LoginPayload, RegisterPayload } from './types';
import type { TranslationKey } from '../../i18n';
import { deleteWebPushSubscription } from '../focus/focus-api';
import { readLegacyWebPushSubscriptionId, readWebPushSubscriptionId } from '../focus/focus-utils';
import {
  pendingCleanupMatchesSession,
  restoreSessionBeforePendingCleanup,
} from './auth-bootstrap';
import {
  cleanupWebPushForUser,
  retryPendingWebPushCleanups,
  unsubscribeCurrentBrowserPush,
  type PendingWebPushCleanup,
  type WebPushCleanupReason,
} from '../focus/web-push-lifecycle';
import { noRefreshAuthorizedFetch, runExplicitLogoutProtocol } from './explicit-logout';

type AuthStatus = 'bootstrapping' | 'anonymous' | 'authenticated';
type AuthNotice = 'expired' | 'logged_out' | 'login_required' | 'restore_failed' | null;

interface AuthContextValue {
  status: AuthStatus;
  session: AuthSession | null;
  notice: AuthNotice;
  clearNotice: () => void;
  login: (payload: LoginPayload) => Promise<AuthSession>;
  register: (payload: RegisterPayload) => Promise<AuthSession>;
  logout: () => Promise<void>;
  authorizedFetch: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
  syncSessionLanguage: (language: AuthSession['user']['language']) => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

function isApiError(error: unknown): error is ApiError {
  return error instanceof ApiError;
}

function persistAndReturn(session: AuthSession, setLocale: (locale: AuthSession['user']['language']) => void) {
  writeStoredSession(session);
  setLocale(session.user.language);
  return session;
}

function preserveSessionLanguage(restoredSession: AuthSession, storedSession: AuthSession): AuthSession {
  return {
    ...restoredSession,
    user: {
      ...restoredSession.user,
      language: storedSession.user.language
    }
  };
}

export function AuthProvider({ children }: PropsWithChildren) {
  const { setLocale } = useI18n();
  const [status, setStatus] = useState<AuthStatus>('bootstrapping');
  const [session, setSession] = useState<AuthSession | null>(null);
  const [notice, setNotice] = useState<AuthNotice>(null);
  const bootstrapCompleteRef = useRef(false);
  const sessionMutationRef = useRef(0);
  const sessionRef = useRef<AuthSession | null>(null);
  const logoutInProgressRef = useRef(false);
  const authSyncChannelRef = useRef<BroadcastChannel | null>(null);

  function applySession(nextSession: AuthSession | null) {
    sessionRef.current = nextSession;
    setSession(nextSession);
  }

  function publishSessionInvalidation(reason: Extract<AuthNotice, 'expired' | 'logged_out'>) {
    authSyncChannelRef.current?.postMessage({
      type: 'session-invalidated',
      reason
    });
  }

  function serverDeactivationForSession(
    currentSession: AuthSession | null,
    pending: PendingWebPushCleanup,
  ) {
    if (!pendingCleanupMatchesSession(currentSession, pending.userId) || !pending.subscriptionId) {
      return null;
    }
    return () => deleteWebPushSubscription(
      async (input, init) => {
        const requestMutation = sessionMutationRef.current;
        const result = await authorizedRequest(currentSession!, input, init);
        if (
          result.session !== currentSession
          && requestMutation === sessionMutationRef.current
          && sessionRef.current === currentSession
        ) {
          const nextSession = persistAndReturn(
            preserveSessionLanguage(result.session, currentSession!),
            setLocale,
          );
          sessionMutationRef.current += 1;
          applySession(nextSession);
        }
        return result.response;
      },
      pending.subscriptionId!,
    );
  }

  async function retryPendingPushCleanup(
    currentSession: AuthSession | null,
    reason: Extract<WebPushCleanupReason, 'bootstrap_retry' | 'session_retry' | 'enable_retry'>,
  ) {
    return retryPendingWebPushCleanups(
      reason,
      (pending) => serverDeactivationForSession(currentSession, pending),
      unsubscribeCurrentBrowserPush,
    );
  }

  async function terminateSession(
    nextNotice: Extract<AuthNotice, 'expired' | 'logged_out' | 'restore_failed'>,
    cleanupReason: Exclude<WebPushCleanupReason, 'bootstrap_retry' | 'session_retry' | 'enable_retry'>,
    currentSession: AuthSession | null,
    publishReason: Extract<AuthNotice, 'expired' | 'logged_out'> | null,
    allowServerDeactivation = true,
  ) {
    finalizeLocalSession(nextNotice, publishReason);

    if (currentSession) {
      const pending = pushCleanupTarget(currentSession);
      await cleanupWebPushForUser({
        ...pending,
        reason: cleanupReason,
        deactivateServer: allowServerDeactivation
          ? serverDeactivationForSession(currentSession, pending)
          : null,
        unsubscribeBrowser: unsubscribeCurrentBrowserPush,
      });
      return;
    }

    await retryPendingPushCleanup(null, 'bootstrap_retry');
  }

  function finalizeLocalSession(
    nextNotice: Extract<AuthNotice, 'expired' | 'logged_out' | 'restore_failed'>,
    publishReason: Extract<AuthNotice, 'expired' | 'logged_out'> | null,
  ) {
    sessionMutationRef.current += 1;
    applySession(null);
    setStatus('anonymous');
    setNotice(nextNotice);
    clearStoredSession();
    if (publishReason) publishSessionInvalidation(publishReason);
  }

  function pushCleanupTarget(currentSession: AuthSession) {
    return {
      userId: currentSession.user.id,
      subscriptionId: readWebPushSubscriptionId(currentSession.user.id)
        ?? readLegacyWebPushSubscriptionId(),
    };
  }

  useEffect(() => {
    let active = true;

    async function bootstrap() {
      const bootstrapMutation = sessionMutationRef.current;
      const storedSession = readStoredSession();

      const result = await restoreSessionBeforePendingCleanup({
        storedSession,
        restoreSession: async (candidate) => preserveSessionLanguage(
          await restoreSessionRequest(candidate),
          candidate,
        ),
        commitSession: (restoredSession) => {
          const nextSession = persistAndReturn(restoredSession, setLocale);
          applySession(nextSession);
          setStatus('authenticated');
          return nextSession;
        },
        retryPendingCleanup: (currentSession) => retryPendingPushCleanup(
          currentSession,
          'bootstrap_retry',
        ).then(() => undefined),
        cleanupAfterRestoreFailure: (failedSession) => terminateSession(
          'expired',
          'bootstrap_invalidation',
          failedSession,
          'expired',
          false,
        ),
        isCurrent: () => active && bootstrapMutation === sessionMutationRef.current,
      });

      if (result.status === 'anonymous' && !sessionRef.current) setStatus('anonymous');
      if (active) bootstrapCompleteRef.current = true;
    }

    bootstrap().catch(async () => {
      if (!active) {
        return;
      }
      const currentSession = sessionRef.current;
      if (!currentSession) {
        await terminateSession(
          'restore_failed',
          'bootstrap_invalidation',
          readStoredSession(),
          'expired',
          false,
        );
      }
      bootstrapCompleteRef.current = true;
    });

    return () => {
      active = false;
    };
  }, [setLocale]);

  useEffect(() => {
    const authSyncChannel =
      'BroadcastChannel' in window ? new BroadcastChannel(AUTH_SYNC_CHANNEL) : null;
    authSyncChannelRef.current = authSyncChannel;

    function handleExternalInvalidation(
      reason: Extract<AuthNotice, 'expired' | 'logged_out'>,
      cleanupReason: Extract<WebPushCleanupReason, 'storage_event' | 'broadcast_event'>,
    ) {
      void terminateSession(reason, cleanupReason, sessionRef.current, null, false);
    }

    function handleStorageChange(event: StorageEvent) {
      if (event.storageArea !== window.localStorage || event.key !== AUTH_STORAGE_KEY) {
        return;
      }

      if (event.newValue === null) {
        handleExternalInvalidation('logged_out', 'storage_event');
        return;
      }

      if (!readStoredSession()) {
        handleExternalInvalidation('expired', 'storage_event');
      }
    }

    function handleBroadcastMessage(event: MessageEvent) {
      const message = event.data as { type?: unknown; reason?: unknown };

      if (
        message.type === 'session-invalidated' &&
        (message.reason === 'expired' || message.reason === 'logged_out')
      ) {
        handleExternalInvalidation(message.reason, 'broadcast_event');
      }
    }

    window.addEventListener('storage', handleStorageChange);
    authSyncChannel?.addEventListener('message', handleBroadcastMessage);

    return () => {
      window.removeEventListener('storage', handleStorageChange);
      authSyncChannel?.removeEventListener('message', handleBroadcastMessage);
      authSyncChannel?.close();
      authSyncChannelRef.current = null;
    };
  }, []);

  async function handleSessionAuth<TPayload>(
    action: (payload: TPayload) => Promise<AuthSession>,
    payload: TPayload,
  ) {
    const authenticatedSession = await action(payload);
    const nextSession = persistAndReturn(authenticatedSession, setLocale);
    sessionMutationRef.current += 1;
    applySession(nextSession);
    setNotice(null);
    setStatus('authenticated');
    await retryPendingPushCleanup(nextSession, 'session_retry');

    return nextSession;
  }

  async function login(payload: LoginPayload) {
    return handleSessionAuth(loginRequest, payload);
  }

  async function register(payload: RegisterPayload) {
    return handleSessionAuth(registerRequest, payload);
  }

  async function logout() {
    if (logoutInProgressRef.current) return;
    logoutInProgressRef.current = true;
    const currentSession = sessionRef.current;
    try {
      sessionMutationRef.current += 1;
      if (!currentSession) {
        await runExplicitLogoutProtocol({
          deactivatePushServer: async () => undefined,
          revokeAuthSession: async () => undefined,
          cleanupPushBrowser: () => retryPendingPushCleanup(null, 'bootstrap_retry').then(() => undefined),
          finalizeLocalAuth: () => finalizeLocalSession('logged_out', 'logged_out'),
        });
        return;
      }

      const pending = pushCleanupTarget(currentSession);
      await runExplicitLogoutProtocol({
        deactivatePushServer: pending.subscriptionId
          ? () => deleteWebPushSubscription(
            noRefreshAuthorizedFetch(currentSession),
            pending.subscriptionId!,
          )
          : async () => undefined,
        revokeAuthSession: () => logoutRequest(currentSession.tokens.refreshToken),
        cleanupPushBrowser: (serverDeactivated) => cleanupWebPushForUser({
          ...pending,
          reason: 'explicit_logout',
          deactivateServer: serverDeactivated && pending.subscriptionId
            ? async () => undefined
            : null,
          unsubscribeBrowser: unsubscribeCurrentBrowserPush,
        }).then(() => undefined),
        finalizeLocalAuth: () => finalizeLocalSession('logged_out', 'logged_out'),
      });
    } finally {
      logoutInProgressRef.current = false;
    }
  }

  async function authorizedFetch(input: RequestInfo | URL, init?: RequestInit) {
    if (logoutInProgressRef.current) {
      throw new Error('Logout is in progress.');
    }
    const currentSession = sessionRef.current;
    if (!currentSession) {
      setNotice('login_required');
      throw new Error('No authenticated session available.');
    }

    const requestMutation = sessionMutationRef.current;
    let result;
    try {
      result = await authorizedRequest(currentSession, input, init);
    } catch (error) {
      if (
        isApiError(error)
        && error.status === 401
        && requestMutation === sessionMutationRef.current
        && sessionRef.current === currentSession
      ) {
        await terminateSession('expired', 'authorized_401', currentSession, 'expired', false);
      }
      throw error;
    }

    if (requestMutation !== sessionMutationRef.current || sessionRef.current !== currentSession) {
      return result.response;
    }

    if (result.session !== currentSession) {
      persistAndReturn(result.session, setLocale);
      sessionMutationRef.current += 1;
      applySession(result.session);
    }

    if (result.response.status === 401) {
      await terminateSession('expired', 'authorized_401', result.session, 'expired', false);
    }

    return result.response;
  }

  function clearNotice() {
    setNotice(null);
  }

  function syncSessionLanguage(language: AuthSession['user']['language']) {
    if (!session) {
      setLocale(language);
      return;
    }

    const nextSession = {
      ...session,
      user: {
        ...session.user,
        language
      }
    };

    persistAndReturn(nextSession, setLocale);
    applySession(nextSession);
  }

  return (
    <AuthContext.Provider
      value={{
        status,
        session,
        notice,
        clearNotice,
        login,
        register,
        logout,
        authorizedFetch,
        syncSessionLanguage
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const value = useContext(AuthContext);

  if (!value) {
    throw new Error('useAuth must be used inside AuthProvider.');
  }

  return value;
}

export function mapAuthErrorMessage(error: unknown, translate: (key: TranslationKey) => string) {
  if (isApiError(error)) {
    const candidate = `auth.api.${error.payload.code}` as TranslationKey;
    const knownCodes = new Set<TranslationKey>([
      'auth.api.authentication_failed',
      'auth.api.unauthorized',
      'auth.api.validation_error',
      'auth.api.conflict',
      'auth.api.internal_error'
    ]);
    const codeKey = knownCodes.has(candidate) ? candidate : 'auth.api.internal_error';

    return {
      formError: translate(codeKey),
      fieldErrors: error.payload.details.reduce<Record<string, string>>((accumulator, detail) => {
        if (detail.field) {
          accumulator[detail.field] = detail.message;
        }

        return accumulator;
      }, {})
    };
  }

  return {
    formError: translate('auth.form.submitErrorFallback'),
    fieldErrors: {}
  };
}

export type { AuthApiError, AuthNotice, AuthStatus };
