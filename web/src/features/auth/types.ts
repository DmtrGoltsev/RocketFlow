import type { Locale } from '../../i18n';

export interface AuthUser {
  id: string;
  email: string;
  displayName: string;
  timezone: string;
  language: Locale;
  createdAt?: string;
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  expiresAt: string;
}

export interface AuthSession {
  user: AuthUser;
  tokens: AuthTokens;
}

export interface AuthResponse {
  user: AuthUser;
  tokens: AuthTokens;
}

export interface AuthApiErrorDetail {
  field?: string;
  message: string;
}

export interface AuthApiError {
  code: string;
  message: string;
  details: AuthApiErrorDetail[];
  traceId?: string;
}

export interface LoginPayload {
  email: string;
  password: string;
}

export interface RegisterPayload extends LoginPayload {
  displayName: string;
  timezone: string;
  language: Locale;
}

export interface UserSettingsSnapshot {
  language: Locale;
  notificationsEnabled: boolean;
}

