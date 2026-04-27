# New Chat Transition Instruction

## Purpose

This is the primary handoff instruction for opening a new clean Codex chat and continuing RocketFlow without reconstructing the old thread.

Treat this file as part of the main source-of-truth packet together with:

- `README.md`
- `docs/33-current-state-summary.md`
- `docs/19-cross-lead-orchestration-plan.md`
- `docs/44-android-sdk-assembledebug-verification.md`

## Mandatory First Step

Before planning, delegating, or editing anything in a new chat, first read:

- `C:\Users\hp\Documents\Codex\MyPrompts\Ru_SubagentFirstFinish.md`

This remains mandatory for any new thread that may use subagents.

## Recommended Opening Message

Use the text below in a new clean chat:

```md
Продолжаем проект RocketFlow в папке `C:\Users\hp\Documents\Codex\RocketFlow`.

Самый первый шаг: сначала прочитай и прими как обязательную инструкцию для мультиагентной разработки файл:
- `C:\Users\hp\Documents\Codex\MyPrompts\Ru_SubagentFirstFinish.md`

После этого загрузи и прими как source of truth:
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\43-new-chat-transition-instruction.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\33-current-state-summary.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\README.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\19-cross-lead-orchestration-plan.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\44-android-sdk-assembledebug-verification.md`

При необходимости деталей по волнам и реализованным этапам используй:
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\25-wave-a-web-auth-i18n.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\26-cancelled-status-reconciliation.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\27-wave-b-backend-calendar-priority.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\28-wave-b-backend-notifications.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\29-wave-b-web-planning-flows.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\30-wave-b-qa-scheduling-validation.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\31-wave-b-devops-staging-secrets.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\32-wave-c-web-collaboration-settings.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\34-wave-c-android-companion-foundation.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\35-wave-c-android-auth-session.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\36-shared-resource-contract-reconciliation.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\37-wave-c-qa-validation.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\38-wave-c-devops-verification.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\39-wave-c1-web-scheduling-authoring.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\40-wave-c-android-browse-detail.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\41-wave-c1-web-scheduling-authoring-implementation.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\42-wave-c-android-notification-entry-foundation.md`

Правила проекта:
- русский язык primary, английский держать синхронно
- все значимые этапы документировать в `docs/`
- canonical task statuses: `todo`, `in_progress`, `done`, `cancelled`
- backend остаётся modular monolith
- не надо заново собирать историю чата, документы выше являются source of truth
- можно активно использовать субагентов для параллельности, но с bounded ownership и wave discipline

Текущее состояние:
- planning/docs baseline завершен
- Wave A завершен
- Wave B завершен
- Wave C web `calendar / sharing / settings` завершен
- Wave C.1 web recurrence/reminder authoring завершен
- Android companion имеет scaffold, auth/session baseline, owned/shared browse, read-only task detail, device registration и notification-open/deep-link foundation
- backend `mvn test` зеленый в documented state
- web `npm run build` зеленый в documented state
- Android local `assembleDebug` подтвержден зеленым локально на `2026-04-27`
- в репозитории уже есть build-only GitHub Actions lanes:
  - `backend-verify`
  - `web-verify`
  - `android-verify`

Главные долги и blockers:
- real FCM/runtime token flow еще не реализован end-to-end
- actual push receive/runtime path еще не verified
- backend notification transport пока foundation/stub, не production-like rollout
- web и Android CI lanes пока build-only и не равны runtime/release verification
- staging/release readiness пока больше документарная, чем executable
- scheduler duplicate-send risk все еще требует отдельного safety pass

Следующий правильный порядок действий:
1. держать source-of-truth docs синхронными с реальным состоянием репозитория
2. поддерживать CI credibility:
   - workflow должны быть зафиксированы в репозитории
   - Android lane должен быть устойчив на Linux runner
   - build-only статус lane должен быть обозначен честно
3. держать notification config contract синхронным между docs и code
4. затем закрыть notification critical path:
   - real backend sender
   - Android automatic FCM token acquisition and refresh
   - receive handler
   - tap-open flow
   - staging smoke
5. затем решить scheduler safety
6. затем staging/release assets
7. потом отдельно вернуться к transactional question вокруг web scheduling

После загрузки контекста:
1. кратко подтверди актуальный статус
2. предложи точный next step
3. затем сразу приступай к работе
```

## Project Status Snapshot

Current validated status:

- backend `mvn test` is green in the documented state
- web `npm run build` is green in the documented state
- Android local `assembleDebug` is green in the current environment as of `2026-04-27`
- GitHub Actions `web-verify` and `android-verify` now exist as build-only lanes

Current scope already delivered:

- planning and docs baseline
- Wave A
- Wave B
- Wave C web `calendar / sharing / settings`
- Wave C.1 web recurrence and reminder authoring
- Android scaffold, auth/session, browse/detail, device registration, and notification-open foundation

## Outstanding Debt

Runtime-critical debt:

- real backend FCM sender is still not implemented
- Android automatic token lifecycle is still not wired
- real push receive path is still not verified end-to-end
- staging notification smoke has not happened yet

Delivery debt:

- backend remains the strongest verified surface
- web is build-verified, but still lightly tested
- Android is build-verified, but not runtime-verified
- web and Android CI lanes are build-only, not release certification
- staging/release assets and smoke paths still need executable hardening

Operational debt:

- scheduler logic still assumes a single backend instance
- duplicate-send safety is still not enforced by a claim/lock model

## Multi-Agent Guidance

If the next chat uses subagents:

- keep bounded ownership
- follow `docs/19-cross-lead-orchestration-plan.md`
- do not split shared integration surfaces without one integrator
- a good parallel split for the next phase is:
  - one subagent on backend notification transport
  - one subagent on Android FCM/runtime flow
  - one subagent on docs/QA/devops follow-up
