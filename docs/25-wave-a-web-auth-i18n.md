# Wave A Web Auth And i18n

## Status

- Completed

## Scope

- `web/src/i18n/**`
- `web/src/features/auth/**`
- narrow-touch route and provider wiring under `web/src/app/**`
- `web/src/main.tsx`

## Notes

- Russian remains the primary locale.
- English resources are added in the same change set.
- The implementation is integrated into the existing web shell from Wave A frontend shell work.
- The shell now boots through real `I18nProvider` and `AuthProvider` wiring.

Operating clarification for later waves:

- `web/src/i18n/**` remains the primary localization source of truth for shared application copy and route-level shell copy
- feature-local copy modules are allowed for bounded feature text when that keeps write scopes safer
- any feature-local copy must still:
  - add RU and EN in the same change set
  - stay documented as part of the same RU-primary / EN-sync discipline
  - avoid creating a third localization rule set outside the established app runtime

## Implemented

- `web/src/i18n/**`
  - RU-first locale resources
  - mirrored EN resources
  - locale persistence and `document.lang` synchronization
- `web/src/features/auth/**`
  - auth API client
  - local session persistence
  - login, register, and logout routes
  - bootstrap and restore flow through `AuthProvider`
  - auth notice and protected-route guard states
- `web/src/app/**`
  - auth and i18n providers mounted at the app root
  - real auth routes wired into the router
  - protected boundary wired to auth status instead of preview toggles

## Verification

- `npm run build` passes in `web/`
