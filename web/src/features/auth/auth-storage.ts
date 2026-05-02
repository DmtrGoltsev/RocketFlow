import type { AuthSession } from './types';

const AUTH_STORAGE_KEY = 'rocketflow.auth.session';
const AUTH_SYNC_CHANNEL = 'rocketflow.auth.sync';
const SUPPORTED_LANGUAGES = new Set(['ru', 'en']);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function isStoredSession(value: unknown): value is AuthSession {
  if (!isRecord(value) || !isRecord(value.user) || !isRecord(value.tokens)) {
    return false;
  }

  const { user, tokens } = value;

  return (
    isNonEmptyString(user.id) &&
    isNonEmptyString(user.email) &&
    isNonEmptyString(user.displayName) &&
    isNonEmptyString(user.timezone) &&
    typeof user.language === 'string' &&
    SUPPORTED_LANGUAGES.has(user.language) &&
    (user.createdAt === undefined || typeof user.createdAt === 'string') &&
    isNonEmptyString(tokens.accessToken) &&
    isNonEmptyString(tokens.refreshToken) &&
    isNonEmptyString(tokens.expiresAt) &&
    !Number.isNaN(Date.parse(tokens.expiresAt))
  );
}

export function readStoredSession(): AuthSession | null {
  try {
    const storedSession = window.localStorage.getItem(AUTH_STORAGE_KEY);

    if (!storedSession) {
      return null;
    }

    const parsedSession = JSON.parse(storedSession) as unknown;

    if (!isStoredSession(parsedSession)) {
      clearStoredSession();
      return null;
    }

    return parsedSession;
  } catch {
    clearStoredSession();
    return null;
  }
}

export function writeStoredSession(session: AuthSession) {
  try {
    window.localStorage.setItem(AUTH_STORAGE_KEY, JSON.stringify(session));
  } catch {
    // Storage can be unavailable in restricted browser modes.
  }
}

export function clearStoredSession() {
  try {
    window.localStorage.removeItem(AUTH_STORAGE_KEY);
  } catch {
    // Storage can be unavailable in restricted browser modes.
  }
}

export { AUTH_STORAGE_KEY, AUTH_SYNC_CHANNEL };
