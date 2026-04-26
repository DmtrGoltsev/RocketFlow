import { PlanningApiError } from './planning-api';

interface CopyLike {
  api: Record<string, string>;
  common: {
    serverTrace: string;
  };
}

export function isPlanningApiError(error: unknown): error is PlanningApiError {
  return error instanceof PlanningApiError;
}

export function mapPlanningError(error: unknown, copy: CopyLike) {
  if (isPlanningApiError(error)) {
    const message = copy.api[error.payload.code] ?? copy.api.fallback;

    return {
      message,
      fieldErrors: error.payload.details.reduce<Record<string, string>>((accumulator, detail) => {
        if (detail.field) {
          accumulator[detail.field] = detail.message;
        }

        return accumulator;
      }, {}),
      traceId: error.payload.traceId,
    };
  }

  return {
    message: copy.api.fallback,
    fieldErrors: {},
    traceId: undefined,
  };
}

