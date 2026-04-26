# Wave A Web Shell Foundation

## Purpose

This document records the Wave A frontend foundation implemented by subagent `F1`.

Scope owned here:

- `web/` project scaffold
- app shell and route boundaries
- retro design tokens and base primitives
- screen inventory placeholders for later waves

Out of scope in this change:

- real auth and session flows
- real RU-first i18n infrastructure and locale files
- planning, calendar, sharing, and settings business logic

## Implemented

### 1. Web project scaffold

Created a new `web/` SPA foundation with:

- `Vite + React + TypeScript`
- browser entrypoint in `src/main.tsx`
- base build scripts in `package.json`
- TypeScript project references through `tsconfig.json`, `tsconfig.app.json`, and `tsconfig.node.json`
- `vite.config.ts` tuned for local development on `127.0.0.1:5173`

### 2. Stable application boundaries

Implemented route and layout separation for:

- public shell:
  - `/`
  - `/auth/login`
  - `/auth/register`
- protected shell:
  - `/app`
  - `/app/folders`
  - `/app/goals`
  - `/app/tasks`
  - `/app/calendar`
  - `/app/sharing`
  - `/app/settings`

The route inventory lives in `web/src/app/route-map.ts`.

This gives later frontend workers a fixed route map and ownership hints without requiring business screens yet.

### 3. Public/protected shell split

Implemented:

- `PublicLayout`
- `ProtectedLayout`
- `ProtectedBoundary`

Current behavior:

- the shell includes a preview runtime with `guest/member` mode switching
- protected routes are blocked in `guest` mode
- this is intentionally a temporary shell-only bridge until the auth/session implementation lands

This keeps the protected boundary testable without taking over `F2` auth ownership.

### 4. Retro design foundation

Added shared retro styling in `web/src/styles/`:

- dense desktop-first layout rules
- gray/blue system-like palette
- hard borders and bevel-inspired chrome
- retro window, panel, button, badge, field, list, and dialog scaffolding
- baseline responsive behavior for narrower widths

Files:

- `tokens.css`
- `base.css`
- `components.css`

### 5. Base primitives and global UX states

Created reusable UI primitives under `web/src/ui/`:

- `RetroButton`
- `RetroBadge`
- `RetroPanel`
- `RetroField`
- `RetroList`
- `RetroDialogFrame`

Created shared feedback/state placeholders:

- `LoadingState`
- `EmptyState`
- `ErrorState`
- `ConflictState`
- `LockedState`

These are meant to be reused by later auth, planning, calendar, sharing, and settings work.

### 6. Extension points for later waves

Added a shell runtime provider in `web/src/app/foundation/runtime/AppRuntimeContext.tsx`.

It currently provides:

- preview locale switching between `ru` and `en`
- preview session mode switching between `guest` and `member`
- shell copy lookup for foundation-owned labels only

This is intentionally lightweight and should be replaced or wrapped by the future real:

- RU-first i18n provider
- auth/session provider

### 7. Screen inventory placeholders

The home route and route placeholder screens now expose:

- route purpose
- audience boundary (`public` vs `protected`)
- future ownership hints
- adjacency between related route areas

This should help future waves plug features into known surfaces with less routing churn.

## Folder structure introduced

```text
web/
  src/
    app/
      foundation/runtime/
      guards/
      layouts/
      routes/
    ui/
      feedback/
      layout/
      primitives/
    styles/
```

## Notes for follow-up waves

- `F2` should replace the preview runtime with real auth/session and RU-first i18n plumbing instead of rebuilding the shell structure.
- Planning work can attach folders/goals/tasks screens directly to the existing `/app/*` route boundaries.
- Calendar/sharing/settings work should preserve the retro primitives and reuse the shared state components before adding feature-specific variants.
- Localization key files were intentionally not created here because `ru/en` synchronization is a high-coordination surface owned by the i18n/auth wave.
