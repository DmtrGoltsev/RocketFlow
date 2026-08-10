import type { AuthSession } from './types';

type RequestImplementation = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

interface ExplicitLogoutProtocolOptions {
  deactivatePushServer: () => Promise<void>;
  revokeAuthSession: () => Promise<void>;
  cleanupPushBrowser: (serverDeactivated: boolean) => Promise<void>;
  finalizeLocalAuth: () => void | Promise<void>;
}

export function noRefreshAuthorizedFetch(
  session: AuthSession,
  request: RequestImplementation = fetch,
) {
  return async (input: RequestInfo | URL, init?: RequestInit) => {
    const headers = new Headers(init?.headers);
    headers.set('Authorization', `Bearer ${session.tokens.accessToken}`);
    return request(input, { ...init, headers });
  };
}

export async function runExplicitLogoutProtocol({
  deactivatePushServer,
  revokeAuthSession,
  cleanupPushBrowser,
  finalizeLocalAuth,
}: ExplicitLogoutProtocolOptions) {
  let serverDeactivated = false;

  try {
    await deactivatePushServer();
    serverDeactivated = true;
  } catch {
    // Auth revocation and browser cleanup must continue when the access token is stale.
  }

  try {
    await revokeAuthSession();
  } catch {
    // Browser cleanup and local invalidation must continue when revocation is unavailable.
  }

  try {
    await cleanupPushBrowser(serverDeactivated);
  } catch {
    // Push cleanup keeps its own pending state; local auth must always be invalidated.
  } finally {
    await finalizeLocalAuth();
  }
}
