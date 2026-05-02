# New Chat Transition Instruction

## Purpose

Use this file to open a new clean chat and continue RocketFlow without reconstructing the previous thread by hand.

Treat this file as a source-of-truth entry point together with:

- `README.md`
- `docs/33-current-state-summary.md`
- `docs/19-cross-lead-orchestration-plan.md`
- `docs/24-wave-a-devops-backend-ci.md`
- `docs/31-wave-b-devops-staging-secrets.md`
- `docs/38-wave-c-devops-verification.md`
- `docs/44-android-sdk-assembledebug-verification.md`
- `docs/47-device-registration-logical-device-upsert-repair.md`
- `docs/45-notification-staging-smoke-runbook.md`
- `docs/50-notification-runtime-clean-pass.md`
- `docs/51-agent-notification-runtime-playbook.md`

If a new chat needs a ready-to-paste starter prompt, open:

- `docs/52-next-chat-multiagent-start-prompt.md`

## Mandatory First Step

Before planning, delegating, or editing anything in a new chat, first read:

- `C:\Users\hp\Documents\Codex\MyPrompts\OrchestratorRules.md`
- `C:\Users\hp\Documents\Codex\MyPrompts\SubagentFirstFinishNew.md`

Priority rule for new chats:

- `OrchestratorRules.md` is the primary operating contract
- `SubagentFirstFinishNew.md` is the secondary supporting instruction

Every new RocketFlow chat must act as a multi-agent delivery orchestrator, not as a direct executor.

It must act and make decisions only under `OrchestratorRules.md`.

## Recommended Opening Message

Use the text below in a new clean chat:

```md
Continue the RocketFlow project in `C:\Users\hp\Documents\Codex\RocketFlow`.

First step: read and accept as mandatory the orchestrator instruction files:
- `C:\Users\hp\Documents\Codex\MyPrompts\OrchestratorRules.md`
- `C:\Users\hp\Documents\Codex\MyPrompts\SubagentFirstFinishNew.md`

Primary operating rule:
- act and make decisions only by `C:\Users\hp\Documents\Codex\MyPrompts\OrchestratorRules.md`
- treat this chat as a multi-agent development orchestrator, not as a direct executor

Then load and treat as source of truth:
- `C:\Users\hp\Documents\Codex\RocketFlow\README.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\33-current-state-summary.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\43-new-chat-transition-instruction.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\24-wave-a-devops-backend-ci.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\31-wave-b-devops-staging-secrets.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\45-notification-staging-smoke-runbook.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\50-notification-runtime-clean-pass.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\51-agent-notification-runtime-playbook.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\38-wave-c-devops-verification.md`
- `C:\Users\hp\Documents\Codex\RocketFlow\docs\19-cross-lead-orchestration-plan.md`

Current confirmed status:
- backend `mvn test` green
- backend local container artifact baseline is proven through `backend/Dockerfile` + temporary `postgres:16` `/actuator/health` smoke
- backend image registry target is fixed to `GHCR` via `ghcr.io/<owner>/rocketflow-backend`
- GitHub Actions `backend-image-publish` now exists as the manual GHCR publish lane
- web `npm run build` green
- Android local `assembleDebug` green
- local Android notification runtime path `reminder -> push -> tap -> task open` is closed on the owned backend + emulator path, with `tap-open proven` reconfirmed on `2026-04-28`
- logical-device upsert for device registration already closed through `installationId`
- the historical Firebase access-token refresh blocker is already explained and closed: the root cause was backend classpath dependency skew
- the next active backend delivery gate is the first successful remote GHCR image publish
- after that, the next active notification gate is staging deployment/runtime wiring plus staging notification certification
- there are no active subagents that need to be resumed

Working rules:
- do not trust an unknown backend on `localhost:8080` for notification verification
- if the work touches backend image delivery, treat `GHCR` as the chosen registry target and use `.github/workflows/backend-image-publish.yml` as the canonical publish lane
- treat the first remote GHCR publish as the immediate delivery gate before staging runtime work
- after the first remote publish succeeds, treat staging notification certification as the active notification gate and use `docs/45-notification-staging-smoke-runbook.md` as the primary path for it
- if a local notification re-check is needed for regression isolation, use `docs/51-agent-notification-runtime-playbook.md`
- if you launch subagents, keep bounded ownership and follow `docs/19-cross-lead-orchestration-plan.md`
- if worker-oriented execution guidance is needed for a subagent, use `C:\Users\hp\Documents\Codex\MyPrompts\SubagentFirstFinishNew.md`

First briefly confirm the current status, then propose the exact next step, and after that start work immediately.
```

## Current Snapshot

Current validated status:

- backend `mvn test` is green in the documented state
- backend local container artifact baseline is green in the documented state
- backend image registry target is now GHCR and the manual publish lane already exists in the repo
- web `npm run build` is green in the documented state
- Android local `assembleDebug` is green in the documented state
- local notification runtime gate is closed in `docs/50-notification-runtime-clean-pass.md`
- the shortest autonomous repeat path is documented in `docs/51-agent-notification-runtime-playbook.md`

## Default Next-Step Bias

If a new chat touches notifications:

- first check whether the remote GHCR image publish is already closed; if not, treat it as the immediate delivery gate
- after publish is closed, treat staging notification certification as the active gate
- use `docs/45-notification-staging-smoke-runbook.md` as the primary verification path
- keep the owned-runtime playbook in `docs/51-agent-notification-runtime-playbook.md` as fallback for regressions or environment isolation
- keep backend env explicit
- keep evidence repo-backed
- do not reopen already-closed historical blockers unless the new evidence actually points back there

If a new chat is broader than notifications:

- use `docs/33-current-state-summary.md` for the current overall status
- use `docs/19-cross-lead-orchestration-plan.md` when subagent discipline matters
