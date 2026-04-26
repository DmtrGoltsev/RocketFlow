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
import { clearStoredSession, readStoredSession, writeStoredSession } from './auth-storage';
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

export function AuthProvider({ children }: PropsWithChildren) {
  const { setLocale } = useI18n();
  const [status, setStatus] = useState<AuthStatus>('bootstrapping');
  const [session, setSession] = useState<AuthSession | null>(null);
  const [notice, setNotice] = useState<AuthNotice>(null);
  const bootstrapCompleteRef = useRef(false);

  useEffect(() => {
    let active = true;

    async function bootstrap() {
      const storedSession = readStoredSession();

      if (!storedSession) {
        if (active) {
          setStatus('anonymous');
        }
        return;
      }

      try {
        const restoredSession = await restoreSessionRequest(storedSession);

        if (!active) {
          return;
        }

        const nextSession = persistAndReturn(restoredSession, setLocale);
        setSession(nextSession);
        setStatus('authenticated');
      } catch {
        if (!active) {
          return;
        }

        clearStoredSession();
        setSession(null);
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
      setSession(null);
      setNotice('restore_failed');
      setStatus('anonymous');
      bootstrapCompleteRef.current = true;
    });

    return () => {
      active = false;
    };
  }, [setLocale]);

  async function handleSessionAuth<TPayload>(
    action: (payload: TPayload) => Promise<AuthSession>,
    payload: TPayload,
  ) {
    const nextSession = persistAndReturn(await action(payload), setLocale);
    setSession(nextSession);
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
    setSession(null);
    setStatus('anonymous');
    setNotice('logged_out');

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
      setSession(result.session);
    }

    if (result.response.status === 401) {
      clearStoredSession();
      setSession(null);
      setStatus('anonymous');
      setNotice('expired');
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
    setSession(nextSession);
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
      }, {}),
      traceId: error.payload.traceId
    };
  }

  return {
    formError: translate('auth.form.submitErrorFallback'),
    fieldErrors: {},
    traceId: undefined
  };
}

export type { AuthApiError, AuthNotice, AuthStatus };
