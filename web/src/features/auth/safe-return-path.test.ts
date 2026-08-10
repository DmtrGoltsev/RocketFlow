import { describe, expect, it } from 'vitest';

import { authRouteWithReturnPath, resolveSafeReturnPath } from './safe-return-path';

describe('resolveSafeReturnPath', () => {
  it.each([
    ['/app', '/app'],
    ['/app/focus', '/app/focus'],
    ['/app/tasks?taskId=task-1#details', '/app/tasks?taskId=task-1#details'],
    ['/app/tasks?label=100%25', '/app/tasks?label=100%25'],
  ])('accepts same-app absolute path %s', (raw, expected) => {
    expect(resolveSafeReturnPath(raw)).toBe(expected);
  });

  it.each([
    null,
    '',
    'app/focus',
    '//evil.example/path',
    'https://evil.example/app',
    '/rocket/app/focus',
    '/auth/login',
    '/app\\evil.example',
    '/app/%5cevil',
    '/app/%255cevil',
    '/app/%00evil',
    '/app/%250aevil',
    '/app/../auth/login',
  ])('rejects unsafe return target %s', (raw) => {
    expect(resolveSafeReturnPath(raw)).toBe('/app');
  });

  it('preserves basename-relative router paths when linking between auth routes', () => {
    expect(authRouteWithReturnPath('/auth/register', '/app/focus')).toBe(
      '/auth/register?next=%2Fapp%2Ffocus',
    );
    expect(authRouteWithReturnPath('/auth/register', '/app')).toBe('/auth/register');
  });
});
