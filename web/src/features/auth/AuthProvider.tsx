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
  const authSyncChannelRef = useRef<BroadcastChannel | null>(null);

  function applySession(nextSession: AuthSession | null) {
    sessionRef.current = nextSession;
    setSession(nextSession);
  }

  function invalidateLocalSession(nextNotice: Extract<AuthNotice, 'expired' | 'logged_out'>) {
    sessionMutationRef.current += 1;
    applySession(null);
    setStatus('anonymous');
    setNotice(nextNotice);
  }

  function publishSessionInvalidation(reason: Extract<AuthNotice, 'expired' | 'logged_out'>) {
    authSyncChannelRef.current?.postMessage({
      type: 'session-invalidated',
      reason
    });
  }

  useEffect(() => {
    let active = true;

    async function bootstrap() {
      const bootstrapMutation = sessionMutationRef.current;
      const storedSession = readStoredSession();

      if (!storedSession) {
        if (active) {
          if (!sessionRef.current) {
            setStatus('anonymous');
          }
          bootstrapCompleteRef.current = true;
        }
        return;
      }

      try {
        const restoredSession = await restoreSessionRequest(storedSession);

        if (!active || bootstrapMutation !== sessionMutationRef.current) {
          return;
        }

        const nextSession = persistAndReturn(preserveSessionLanguage(restoredSession, storedSession), setLocale);
        applySession(nextSession);
        setStatus('authenticated');
      } catch {
        if (!active || bootstrapMutation !== sessionMutationRef.current) {
          return;
        }

        clearStoredSession();
        publishSessionInvalidation('expired');
        applySession(null);
        setNotice('expired');
        setStatus('anonymous');
      } finally {
        bootstrapCompleteRef.current = true;
      }
    }

    bootstrap().catch(() => {
      if (!active) {
        return;
      }

      clearStoredSession();
      publishSessionInvalidation('expired');
      applySession(null);
      setNotice('restore_failed');
      setStatus('anonymous');
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

    function handleExternalInvalidation(reason: Extract<AuthNotice, 'expired' | 'logged_out'>) {
      clearStoredSession();
      invalidateLocalSession(reason);
    }

    function handleStorageChange(event: StorageEvent) {
      if (event.storageArea !== window.localStorage || event.key !== AUTH_STORAGE_KEY) {
        return;
      }

      if (event.newValue === null) {
        handleExternalInvalidation('logged_out');
        return;
      }

      if (!readStoredSession()) {
        handleExternalInvalidation('expired');
      }
    }

    function handleBroadcastMessage(event: MessageEvent) {
      const message = event.data as { type?: unknown; reason?: unknown };

      if (
        message.type === 'session-invalidated' &&
        (message.reason === 'expired' || message.reason === 'logged_out')
      ) {
        handleExternalInvalidation(message.reason);
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
    const nextSession = persistAndReturn(await action(payload), setLocale);
    sessionMutationRef.current += 1;
    applySession(nextSession);
    setNotice(null);
    setStatus('authenticated');

    return nextSession;
  }

  async function login(payload: LoginPayload) {
    return handleSessionAuth(loginRequest, payload);
  }

  async function register(payload: RegisterPayload) {
    return handleSessionAuth(registerRequest, payload);
  }

  async function logout() {
    const currentSession = session;

    clearStoredSession();
    publishSessionInvalidation('logged_out');
    invalidateLocalSession('logged_out');

    if (!currentSession) {
      return;
    }

    try {
      await logoutRequest(currentSession.tokens.refreshToken);
    } catch {
      // Logout should still complete locally even if the network request fails.
    }
  }

  async function authorizedFetch(input: RequestInfo | URL, init?: RequestInit) {
    if (!session) {
      setNotice('login_required');
      throw new Error('No authenticated session available.');
    }

    const result = await authorizedRequest(session, input, init);

    if (result.session !== session) {
      persistAndReturn(result.session, setLocale);
      sessionMutationRef.current += 1;
      applySession(result.session);
    }

    if (result.response.status === 401) {
      clearStoredSession();
      publishSessionInvalidation('expired');
      invalidateLocalSession('expired');
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
