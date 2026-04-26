# Wave C Android: Auth and Session Baseline

## Scope

This slice implements the first executable Android companion foundation after the repository scaffold:

- login with `POST /api/auth/login`
- persisted session storage
- session restore on app start through `GET /api/me`
- refresh-token recovery through `POST /api/auth/refresh`
- logout cleanup with best-effort `POST /api/auth/logout`
- a minimal signed-in shell that shows the current user and the next companion surfaces

## Implementation Notes

- the Android client uses a small JSON-over-HTTP layer instead of introducing a broader networking stack immediately
- session state is stored in `SharedPreferences`
- the active language in the small Android shell follows either the signed-in user language or the device locale fallback
- the current surface stays intentionally read-only and companion-only

## Guardrails Kept

- no planning CRUD
- no calendar or task move UI
- no invitation management UI yet
- no push wiring yet
- no offline sync architecture

## Done Criteria For This Slice

- user can log in from the Android companion
- app restart restores the session when tokens are still usable
- expired access token can recover through refresh
- logout clears the local session and returns to the login shell
- the stage is documented in `docs/`

