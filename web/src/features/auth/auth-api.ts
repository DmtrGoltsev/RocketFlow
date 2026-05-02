import type {
  AuthApiError,
  AuthResponse,
  AuthSession,
  AuthTokens,
  AuthUser,
  LoginPayload,
  RegisterPayload
} from './types';

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? '/api';

class ApiError extends Error {
  payload: AuthApiError;
  status: number;

  constructor(status: number, payload: AuthApiError) {
    super(payload.message);
    this.name = 'ApiError';
    this.status = status;
    this.payload = payload;
  }
}

function buildUrl(path: string) {
  return `${API_BASE_URL}${path}`;
}

async function parseError(response: Response): Promise<AuthApiError> {
  try {
    const body = (await response.json()) as { error?: Partial<AuthApiError> };

    if (body.error?.code && body.error.message) {
      return {
        code: body.error.code,
        message: body.error.message,
        details: body.error.details ?? []
      };
    }
  } catch {
    return {
      code: 'internal_error',
      message: 'Request failed.',
      details: []
    };
  }

  return {
    code: 'internal_error',
    message: 'Request failed.',
    details: []
  };
}

async function requestJson<TResponse>(path: string, init: RequestInit): Promise<TResponse> {
  const response = await fetch(buildUrl(path), {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(init.headers ?? {})
    }
  });

  if (!response.ok) {
    throw new ApiError(response.status, await parseError(response));
  }

  if (response.status === 204) {
    return undefined as TResponse;
  }

  return (await response.json()) as TResponse;
}

export async function register(payload: RegisterPayload) {
  return requestJson<AuthResponse>('/auth/register', {
    method: 'POST',
    body: JSON.stringify(payload)
  });
}

export async function login(payload: LoginPayload) {
  return requestJson<AuthResponse>('/auth/login', {
    method: 'POST',
    body: JSON.stringify(payload)
  });
}

export async function refreshTokens(refreshToken: string) {
  return requestJson<{ tokens: AuthTokens }>('/auth/refresh', {
    method: 'POST',
    body: JSON.stringify({ refreshToken })
  });
}

export async function logout(refreshToken: string) {
  return requestJson<void>('/auth/logout', {
    method: 'POST',
    body: JSON.stringify({ refreshToken })
  });
}

export async function fetchCurrentUser(accessToken: string) {
  return requestJson<AuthUser>('/me', {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${accessToken}`
    }
  });
}

export async function restoreSession(session: AuthSession): Promise<AuthSession> {
  try {
    const user = await fetchCurrentUser(session.tokens.accessToken);
    return { user, tokens: session.tokens };
  } catch (error) {
    if (!(error instanceof ApiError) || error.status !== 401) {
      throw error;
    }
  }

  const refreshed = await refreshTokens(session.tokens.refreshToken);
  const user = await fetchCurrentUser(refreshed.tokens.accessToken);

  return {
    user,
    tokens: refreshed.tokens
  };
}

export async function authorizedRequest(
  session: AuthSession,
  input: RequestInfo | URL,
  init?: RequestInit,
) {
  const headers = new Headers(init?.headers);
  headers.set('Authorization', `Bearer ${session.tokens.accessToken}`);

  let response = await fetch(input, {
    ...init,
    headers
  });

  if (response.status !== 401) {
    return {
      response,
      session
    };
  }

  const refreshed = await restoreSession(session);
  headers.set('Authorization', `Bearer ${refreshed.tokens.accessToken}`);
  response = await fetch(input, {
    ...init,
    headers
  });

  return {
    response,
    session: refreshed
  };
}

export { ApiError };
