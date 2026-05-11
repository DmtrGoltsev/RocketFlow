import { AdvancedApiError } from './advanced-api';
import type { AdvancedApiErrorPayload } from './types';

interface CopyLike {
  api: Record<string, string>;
}

export function isAdvancedApiError(error: unknown): error is AdvancedApiError {
  return error instanceof AdvancedApiError;
}

export function mapAdvancedError(error: unknown, copy: CopyLike) {
  if (isAdvancedApiError(error)) {
    const payload: AdvancedApiErrorPayload = error.payload;

    return {
      formError: copy.api[payload.code] ?? copy.api.fallback,
      fieldErrors: payload.details.reduce<Record<string, string>>((accumulator, detail) => {
        if (detail.field) {
          accumulator[detail.field] = detail.message;
        }

        return accumulator;
      }, {}),
    };
  }

  return {
    formError: copy.api.fallback,
    fieldErrors: {},
  };
}
