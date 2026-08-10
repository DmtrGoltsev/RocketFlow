const DEFAULT_RETURN_PATH = '/app';
const INTERNAL_ORIGIN = 'https://rocketflow.invalid';
const UNSAFE_CHARACTER = /[\\\u0000-\u001f\u007f]/;
const ENCODED_UNSAFE_CHARACTER = /%(?:25)*(?:0[0-9a-f]|1[0-9a-f]|5c|7f)/i;

export function resolveSafeReturnPath(raw: string | null, fallback = DEFAULT_RETURN_PATH) {
  if (!raw || UNSAFE_CHARACTER.test(raw) || ENCODED_UNSAFE_CHARACTER.test(raw)) {
    return fallback;
  }

  if (!raw.startsWith('/') || raw.startsWith('//')) {
    return fallback;
  }

  try {
    const parsed = new URL(raw, INTERNAL_ORIGIN);
    const isSameOrigin = parsed.origin === INTERNAL_ORIGIN;
    const isProtectedAppPath = parsed.pathname === '/app' || parsed.pathname.startsWith('/app/');

    if (!isSameOrigin || !isProtectedAppPath) {
      return fallback;
    }

    return `${parsed.pathname}${parsed.search}${parsed.hash}`;
  } catch {
    return fallback;
  }
}

export function authRouteWithReturnPath(path: string, nextPath: string) {
  return nextPath === DEFAULT_RETURN_PATH ? path : `${path}?next=${encodeURIComponent(nextPath)}`;
}
