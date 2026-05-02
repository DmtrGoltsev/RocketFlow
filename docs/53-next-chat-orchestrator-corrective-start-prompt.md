# Next Chat Corrective Orchestrator Start Prompt

## Purpose

Use this file as the transition prompt for the next clean RocketFlow chat.

This supersedes `docs/52-next-chat-multiagent-start-prompt.md` for the next run because the previous chat violated the intended orchestration model: Codex acted as a direct executor and tester instead of delegating work to subagents and aggregating their independent results.

## Critical Correction

The next chat must operate as an orchestrator only.

Do not treat the orchestrator as a direct implementation or direct QA worker. The orchestrator's job is to:

- read and preserve the project context;
- split work into bounded tasks;
- assign tasks to subagents;
- receive agent reports and artifacts;
- update the plan and readiness matrix;
- escalate blockers or contradictions to the user;
- avoid declaring final confidence without independent agent evidence.

The orchestrator must not:

- make code fixes directly;
- run the main E2E itself as the primary tester;
- use its own local smoke checks as a replacement for agent reports;
- silently collapse all roles into one worker;
- mark the app as fully validated without backend, web, Android, and DevOps/CI agents reporting independently.

The previous direct checks can be used only as smoke evidence and environment orientation, not as canonical multi-agent E2E sign-off.

## Ready-To-Paste Prompt

```md
Continue the RocketFlow project in `<repo-root>`.

Mandatory first step:
- Read `<repo-root>\docs\53-next-chat-orchestrator-corrective-start-prompt.md`.
- Read and obey the orchestrator instruction files:
  - `<local-prompts-dir>\OrchestratorRules.md`
  - `<local-prompts-dir>\SubagentFirstFinishNew.md`

Role rule:
- You are the orchestrator, not the executor.
- Do not implement fixes yourself.
- Do not perform the main E2E yourself.
- Your work is to assign agent tasks, collect independent reports, integrate their findings, and maintain the plan/status matrix.
- If you need evidence, ask the correct agent to produce it.
- If a blocker needs a human decision, surface it to the user.

Context to load:
- `README.md`
- `docs/19-cross-lead-orchestration-plan.md`
- `docs/33-current-state-summary.md`
- `docs/43-new-chat-transition-instruction.md`
- `docs/51-agent-notification-runtime-playbook.md`
- `docs/metla.md`
- `tmp/local-e2e/metla-20260429/metla-final-report-20260429.md`

Current METLA status from the previous chat:
- `RF-SEC-001`: patched by binding share invitations to `target_user_id`; unknown invitee is rejected; only the bound invitee can list/accept.
- `RF-SEC-002`: patched by making collaborator mutation paths owner-only for goals, tasks, recurrence, reminders, move/reschedule, delete, and further invitations; web owner-only actions are hidden on shared goals/tasks.
- `RF-SEC-004`: patched by disabling replayable web auth session persistence in `localStorage`; refresh of protected route requires login again.
- `RF-SEC-005`: patched by `android:allowBackup="false"` and confirmed in compiled APK.
- `RF-SEC-006`: patched by pinning workflow actions/runner, Docker base images, and Gradle wrapper checksum.

Important caveat:
- The previous chat's checks were done directly by Codex, which violated the intended orchestrator workflow.
- Treat those checks as preliminary smoke evidence only.
- Re-run validation through subagents before calling the application fully validated.

Known local runtime left from previous chat:
- Backend API: `http://localhost:18082/api`
- Postgres: `localhost:15434`
- Web: `http://127.0.0.1:5175`
- Backend Docker image: `rocketflow-backend:metla-20260429`
- Docker smoke report: `tmp/docker-smoke/report-20260429-165257-6072c96c.json`
- METLA report: `tmp/local-e2e/metla-20260429/metla-final-report-20260429.md`

Known external blocker:
- Real FCM delivery is not certified locally because the runtime lacks FCM credentials/config. Do not claim real push delivery as PASS until a proper staging/credentials-backed test is assigned and reported.

Required agent assignments:

1. Backend/API Security Agent
   - Read `docs/metla.md`.
   - Verify backend implementation for `RF-SEC-001` and `RF-SEC-002`.
   - Run backend tests and an API security E2E matrix against the current local runtime or a freshly rebuilt runtime.
   - Confirm invite target binding, stranger isolation, collaborator read access, and collaborator mutation denial.
   - Report exact commands, results, failures, and artifacts.

2. Web/Playwright Agent
   - Verify web behavior against the repaired backend.
   - Confirm no replayable auth session survives full page reload.
   - Confirm owner can use protected planning surfaces.
   - Confirm collaborator can see shared goal/task but does not see owner-only actions: Share, Edit, Delete, Archive.
   - Report browser URLs, screenshots/snapshots, failures, and artifacts.

3. Android Agent
   - Build/install Android debug against the repaired backend.
   - Confirm compiled APK has `allowBackup=false`.
   - Smoke login, browse, task detail, and deep link open.
   - Confirm no claim is made about real FCM delivery unless credentials are configured and tested.
   - Report device/emulator, commands, screenshots/XML dumps, and artifacts.

4. DevOps/Build Trust Agent
   - Verify workflow actions are pinned and `ubuntu-latest` is not used where replaced.
   - Verify Docker base images are digest-pinned.
   - Verify Gradle wrapper checksum is present.
   - Verify local Docker runtime can be rebuilt and started from the current tree.
   - Report exact file references and command outputs.

Orchestrator behavior:
- Spawn/assign the agents first.
- While agents work, only maintain plan/status and resolve coordination questions.
- Do not redo an agent's task yourself.
- When agents return, merge their findings into one readiness matrix.
- If any agent reports failure, create fix tasks for implementation agents; do not patch it directly unless the user explicitly changes the role.
- Final response must distinguish:
  - agent-verified PASS,
  - smoke-only evidence,
  - blocked/not tested,
  - remaining risks.

First response in the new chat:
- Briefly acknowledge that the previous run violated orchestration discipline.
- State that this run will be subagent-first.
- Present the four agent assignments above.
- Then begin by dispatching the agents.
```

## Notes For The Next Orchestrator

The user specifically corrected the process:

- "в рамках основной доки для оркестратора - ты вообще не должен был тестировать или делать что угодно. только давать задачи"

Treat that as the governing expectation for the next chat. The strongest possible recovery is not to defend the previous direct work, but to preserve it as low-grade evidence and redo validation through the intended multi-agent process.
