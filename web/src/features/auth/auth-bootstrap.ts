import type { AuthSession } from './types';

export interface AuthBootstrapDependencies {
  storedSession: AuthSession | null;
  restoreSession: (session: AuthSession) => Promise<AuthSession>;
  commitSession: (session: AuthSession) => AuthSession;
  retryPendingCleanup: (session: AuthSession | null) => Promise<void>;
  cleanupAfterRestoreFailure: (session: AuthSession) => Promise<void>;
  isCurrent: () => boolean;
}

export type AuthBootstrapResult =
  | { status: 'anonymous' | 'restore_failed' | 'superseded'; session: null }
  | { status: 'authenticated'; session: AuthSession };

export function pendingCleanupMatchesSession(
  session: AuthSession | null,
  pendingUserId: string,
) {
  return session?.user.id === pendingUserId;
}

export async function restoreSessionBeforePendingCleanup({
  storedSession,
  restoreSession,
  commitSession,
  retryPendingCleanup,
  cleanupAfterRestoreFailure,
  isCurrent,
}: AuthBootstrapDependencies): Promise<AuthBootstrapResult> {
  if (!storedSession) {
    await retryPendingCleanup(null);
    return isCurrent()
      ? { status: 'anonymous', session: null }
      : { status: 'superseded', session: null };
  }

  let restoredSession: AuthSession;
  try {
    restoredSession = await restoreSession(storedSession);
  } catch {
    if (!isCurrent()) return { status: 'superseded', session: null };
    await cleanupAfterRestoreFailure(storedSession);
    return { status: 'restore_failed', session: null };
  }

  if (!isCurrent()) return { status: 'superseded', session: null };

  const committedSession = commitSession(restoredSession);
  await retryPendingCleanup(committedSession);
  return { status: 'authenticated', session: committedSession };
}
