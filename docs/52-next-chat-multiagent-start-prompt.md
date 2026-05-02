# Next Chat Orchestrator Start Prompt

## Purpose

This file is the exact prompt to paste into a new clean chat when RocketFlow should continue with orchestrator-first multi-agent discipline and without reconstructing prior context by hand.

Use this together with:

- `docs/43-new-chat-transition-instruction.md`
- `docs/31-wave-b-devops-staging-secrets.md`
- `docs/33-current-state-summary.md`
- `docs/38-wave-c-devops-verification.md`
- `docs/51-agent-notification-runtime-playbook.md`

## Ready-To-Paste Prompt

```md
Continue the RocketFlow project in `<repo-root>`.

First step: read and accept as mandatory the orchestrator instruction files:
- `<local-prompts-dir>\OrchestratorRules.md`
- `<local-prompts-dir>\SubagentFirstFinishNew.md`

Primary operating rule:
- act and make decisions only by `<local-prompts-dir>\OrchestratorRules.md`
- treat this chat as a multi-agent development orchestrator, not as a direct executor

Then load and treat as source of truth:
- `<repo-root>\README.md`
- `<repo-root>\docs\33-current-state-summary.md`
- `<repo-root>\docs\43-new-chat-transition-instruction.md`
- `<repo-root>\docs\24-wave-a-devops-backend-ci.md`
- `<repo-root>\docs\31-wave-b-devops-staging-secrets.md`
- `<repo-root>\docs\44-android-sdk-assembledebug-verification.md`
- `<repo-root>\docs\45-notification-staging-smoke-runbook.md`
- `<repo-root>\docs\47-device-registration-logical-device-upsert-repair.md`
- `<repo-root>\docs\50-notification-runtime-clean-pass.md`
- `<repo-root>\docs\51-agent-notification-runtime-playbook.md`
- `<repo-root>\docs\38-wave-c-devops-verification.md`
- `<repo-root>\docs\19-cross-lead-orchestration-plan.md`

Current confirmed status:
- backend `mvn test` green
- backend local container artifact baseline is proven through `backend/Dockerfile` + temporary `postgres:16` `/actuator/health` smoke
- backend image registry target is fixed to `GHCR` via `ghcr.io/<owner>/rocketflow-backend`
- GitHub Actions `backend-image-publish` now exists as the manual GHCR publish lane
- web `npm run build` green
- Android local `assembleDebug` green
- local Android notification runtime path `reminder -> push -> tap -> task open` is already closed on the owned backend + emulator path, with `tap-open proven` reconfirmed on `2026-04-28`
- logical-device upsert for device registration is already closed through `installationId`
- the historical Firebase access-token refresh blocker is already closed: the root cause was backend classpath dependency skew
- the next active backend delivery gate is the first successful remote GHCR image publish
- after that, the next active notification gate is staging deployment/runtime wiring plus staging notification certification
- there are no active subagents that need to be resumed

Working rules:
- do not trust an unknown backend on `localhost:8080` for notification verification
- if the work touches backend image delivery, treat `GHCR` as the chosen registry target and use `.github/workflows/backend-image-publish.yml` as the canonical publish lane
- treat the first remote GHCR publish as the immediate delivery gate before staging runtime work
- after the first remote publish succeeds, treat staging notification certification as the active notification gate and use `docs/45-notification-staging-smoke-runbook.md` as the primary path for it
- if a local notification re-check is needed for regression isolation, use `docs/51-agent-notification-runtime-playbook.md`
- if you spawn subagents, keep bounded ownership and follow `docs/19-cross-lead-orchestration-plan.md`
- if worker-oriented execution guidance is needed for a subagent, use `<local-prompts-dir>\SubagentFirstFinishNew.md`

Current next-step bias:
- first complete the remote GHCR image publish and validate package/tag visibility plus package permissions
- then move to staging deployment/runtime wiring
- then treat staging notification certification as the active notification gate
- keep the owned-runtime playbook in `docs/51-agent-notification-runtime-playbook.md` as fallback for regressions or environment isolation

First briefly confirm the current status, then propose the exact next step, and after that start work immediately.
```
