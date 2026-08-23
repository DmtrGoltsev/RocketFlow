# RocketFlow native iOS: Mac and physical-device handoff

Status: **Mac workflow defined; physical-device evidence not yet recorded**

This document is the human-readable companion to
[`ios-native-mac-codex-install-prompt.md`](ios-native-mac-codex-install-prompt.md).
It explains what the Mac operator will do, what the user must choose, and which
results may or may not be claimed.

## Identity and evidence

- Living branch: `codex/native-ios-companion`.
- Immutable app-code/build evidence: `35e98d965cf49a356e5a7a7ebdbc59afaa1f9fb3`.
- Baseline manual iOS Verify: run `32655691351`, job `97233929959`, `540` unit
  and `2` UI tests PASS.
- Immutable tooling commit A:
  `a66b501f2a5ec8d8d25dc518a9fcd097e5ee1149`. Its identity scope is exactly:
  `.github/workflows/ios-verify.yml`, `.gitignore`,
  `ios/Config/Device.xcconfig.example`,
  `ios/scripts/mac-handoff-common.sh`, `ios/scripts/mac-preflight.sh`,
  `ios/scripts/mac-verify.sh`, `ios/scripts/mac-build-device.sh`,
  `ios/scripts/mac-install-device.sh`, and
  `ios/scripts/tests/mac-handoff-tests.sh`.
- Tooling manual [iOS Verify run 32669924719](https://github.com/DmtrGoltsev/RocketFlow/actions/runs/32669924719),
  job `97269056380`, completed successfully with head SHA exactly equal to A.
  Mac contracts were `174/174` PASS with `0` skipped; XcodeGen generation,
  committed-project parity, packages/lock and no-sign simulator build passed;
  unit tests were `540` passed / `0` failed, UI tests `2` passed / `0` failed,
  total `542` passed / `0` failed. Artifacts were `RocketFlow-xcresult`, ID
  `9501177125`, `1,317,064` bytes, and
  `RocketFlow-xcodeproj-xcodegen-2.46.0`, ID `9501179599`, `25,070` bytes.
- Docs commit B follows A and records the immutable tooling evidence above. B is
  intentionally not the run's head SHA and is not self-pinned.

The app SHA proves the earlier app build/test. It is not the current branch HEAD
and does not prove the later Mac scripts. On Mac, the operator checks out the
latest candidate/docs state, proves A is its ancestor, and verifies that the
exact tooling identity paths listed above have no byte-for-byte diff from A.
Run A proves tooling and simulator gates at A; the path comparison proves later
docs did not silently change that tooling. The prompt never requires HEAD == A.

## CI policy boundary

Commit `0bbf4acb0ba9620b931fa843dc9d2997379304fb` configures candidate-branch
feature pushes as manual verification and declares automatic PR/push checks for
`master`. It remains candidate-only: `origin/master` at
`7d1ac74cf8f2bf7935c2578f3675db4ca54764bb` contains neither that commit nor
`ios-verify`. Default-branch behavior changes only after merge. Production
deploy/package/rollback workflows were not changed, and branch protection is not
configured; the settings in `docs/58-github-cicd-policy.md` are recommendations.

## What this handoff does not claim

There is no recorded RocketFlow physical-iPhone success yet. This document does
not claim:

- signed device build, install or launch;
- Apple Team/provisioning acceptance;
- production APNs/FCM registration or delivery;
- App Store/TestFlight/public release readiness;
- production HTTPS readiness;
- backend V22 deployment;
- a new production database inspection.

Production backend/web remains source
`50a63270ae094fe08ee57b945be0930cb1115dfe`, release `sha-50a63270ae09`, Flyway
V21 (`21/21`). Candidate V22 adds iOS device-registration support in source but
is not deployed. The deploy compatibility floor remains preflight `>=20`, with
manifest target and post-start gate `>=21`; that floor is not a claim that
production is still V20.

## Modes

| Mode | Default | Purpose | Required external setup | Release meaning |
|---|---:|---|---|---|
| `no-push` | yes | Signed personal development install, app flows and local reminders | Apple Team, unique bundle id, connected trusted iPhone | Does not prove push or App Store readiness |
| `push` | no | Optional push-capable device build and local provider wiring checks | Everything above plus external or ignored/untracked Firebase plist, matching Firebase bundle, APNs/Firebase and push provisioning | Still cannot prove production push until V22 is deployed |

Missing Firebase/APNs/V22 must never block the default `no-push` installation.
Optional push is a separate explicit opt-in and a separate report section.

## Scripted interface

The final handoff uses these repository scripts:

| Path | Responsibility |
|---|---|
| `ios/scripts/mac-preflight.sh` | Full Xcode, iPhoneOS SDK >=16, CLI, exact XcodeGen `2.46.0`, repository and API/ATS contract preflight |
| `ios/scripts/mac-verify.sh` | XcodeGen/project parity, packages, no-sign simulator build and tests |
| `ios/scripts/mac-build-device.sh` | Signed device `.app`; default `no-push`, optional explicit `push` |
| `ios/scripts/mac-install-device.sh` | Mode-aware signed-app revalidation, redacted device selection, `devicectl` install and launch |

The operator must run each script with `--help` first and use only its documented
arguments. The commands below match the current script interface. A mismatch
between script usage, this document, `Device.xcconfig.example` and the copyable
prompt is a stop condition.

Commit A is acceptable only when `ios-verify` also passes shell syntax and the
expanded `ios/scripts/tests/mac-handoff-tests.sh` suite. That suite must fail
closed on unsupported/secret config, redaction, paths with spaces, exact
XcodeGen, no-push/push separation, Firebase bundle validation, the exact
production endpoint and strict ATS allowlist, iPhoneOS SDK >=16, install mode and
arguments, post-build bundle/codesign/entitlements, Team/application-id, and
embedded provisioning/device match. Workflow step `Validate Mac handoff scripts`
must run `bash -n ios/scripts/*.sh ios/scripts/tests/*.sh` followed by
`bash ios/scripts/tests/mac-handoff-tests.sh`. Missing coverage is a tooling
blocker; this document is not evidence that an absent check passed.

The expected no-push sequence, after local config and device selection, is:

```bash
bash ios/scripts/mac-preflight.sh --mode no-push --device "$DEVICE_UDID"
bash ios/scripts/mac-build-device.sh --mode no-push --device "$DEVICE_UDID"
```

The raw device identifier is used only in the local shell and is redacted from
evidence. `--allow-device-registration` is opt-in only when Xcode requires it and
the user approves the system action. Install and launch the newest device build
with:

```bash
bash ios/scripts/mac-install-device.sh --mode no-push --device "$DEVICE_UDID" --launch
```

Use `--app "$BUILT_APP"` when selecting a specific built app. The installed
`devicectl` help remains authoritative for the underlying Apple CLI.

## Mac prerequisites

- Supported Mac capable of running a full Xcode with an iOS 16+ SDK.
- Git and GitHub CLI; GitHub authentication uses browser/device authorization,
  never a pasted token.
- Exact official XcodeGen `2.46.0`. Another version is not accepted for parity.
- An Apple account available in Xcode and an eligible Personal or paid
  Development Team.
- A physical iPhone running supported iOS, connected and unlocked.

The user may need to approve Xcode installation/license/first-launch setup,
Apple ID/2FA, Trust This Computer, Developer Mode, reboot, development identity
trust and device registration. Passwords and 2FA codes stay in system UI.

## Safe local configuration

After simulator verification passes, the Mac operator copies:

```bash
if [[ -e ios/Config/Device.xcconfig || -L ios/Config/Device.xcconfig ]]; then
  echo "Device.xcconfig already exists; review it without overwriting." >&2
  exit 1
fi
cp ios/Config/Device.xcconfig.example ios/Config/Device.xcconfig
git check-ignore -v ios/Config/Device.xcconfig
if git ls-files --error-unmatch -- ios/Config/Device.xcconfig >/dev/null 2>&1; then
  echo "Device.xcconfig must remain untracked." >&2
  exit 1
fi
```

If `Device.xcconfig` already exists, do not run `cp` and do not overwrite it.
Stop and reuse it only after consciously verifying that it is the expected local
configuration and remains ignored and untracked. `Device.xcconfig` must be
ignored and untracked before Team/bundle data is entered. The user chooses only:

1. Apple Team; the Apple Account is added in Xcode UI, while its selected Team
   ID is written only to ignored Device.xcconfig for the scripted build;
2. a unique owner-controlled bundle identifier;
3. one connected iPhone by user-facing device choice.

The tracked example defines only `DEVELOPMENT_TEAM`,
`PRODUCT_BUNDLE_IDENTIFIER`, `CODE_SIGN_STYLE`, `CODE_SIGNING_ALLOWED` and
`CODE_SIGNING_REQUIRED`. Do not add credentials or unrelated overrides.
The bundle identifier is also written only to Device.xcconfig, never to the
tracked Xcode project. `ios/Config/Local.xcconfig` is not created or used by this
handoff; endpoint or ATS changes require a separate security review.

If an implemented `--config` option is used with a custom path, the file must be
outside the repository or both ignored and untracked. Firebase configuration has
the same rule. Paths are kept in local shell variables and are not published.

No Team ID, UDID, serial, certificate, profile, private key, password or 2FA code
belongs in chat, Git, public logs or evidence. The tracked example, project.yml,
entitlements and app source are not edited for personal signing.

## Required order

1. Run the project-mandated planner/orchestration flow and complete a read-only
   repository audit.
2. Clone/fetch `codex/native-ios-companion` and detach at the latest fetched
   candidate/docs HEAD. Verify immutable tooling commit A/run A, prove A is an
   ancestor, and prove the tooling paths have no diff after A. Do not check out
   A in place of the newer docs.
3. Read AGENTS, this handoff, the copyable prompt, iOS README, delivery evidence,
   project.yml, workflow and all four scripts.
4. Create sanitized evidence outside Git.
5. Run exact XcodeGen/project/package/simulator verification with
   `mac-verify.sh` and confirm no tracked diff.
6. Add the Apple Account in Xcode UI, then create ignored Device.xcconfig and
   write the chosen Team ID/bundle only there; obtain the device choice locally.
7. Run `mac-preflight.sh` for the selected mode/device; it intentionally
   validates the completed local config.
8. Build/install/launch in default `no-push` mode.
9. Perform the smoke checklist.
10. Enter optional `push` mode only after explicit consent and prerequisites.
11. Redact evidence, clean local build artifacts safely and report git status.

Audit and tool inventory may be parallel. Device signing begins only after the
simulator gate is green. A compile, parity or script-contract failure is reported
as a blocker; the installation task does not silently patch source.

## Device build and installation

The default build must produce a signed development `.app`, not Archive/IPA.
Before installation the operator verifies, without exposing signing identifiers:

- effective bundle identifier matches Device.xcconfig;
- API base URL is `http://45.10.110.42/rocket-api`;
- ATS is a strict allowlist: `NSExceptionDomains` contains only
  `45.10.110.42`, without subdomains; broad-load keys and additional exception
  domains are forbidden;
- no-push mode does not require GoogleService plist, APNs or backend V22;
- the device `.app` exists, codesign verification/inspection succeeds, its
  bundle matches Device.xcconfig, and signed entitlements match the selected
  mode.
- the built platform/SDK is iPhoneOS, signed Team/application-identifier matches
  Device.xcconfig, and the privately decoded embedded provisioning profile
  matches Team/application-id and the selected device.

The scripts must enforce the endpoint and ATS checks themselves and fail closed.
There is no Local.xcconfig override in this procedure. Any endpoint/ATS change,
or a tooling revision that only asks for a manual check, is a stop condition and
requires security review.

Installation and launch use `xcrun devicectl` through
`mac-install-device.sh --mode no-push --device "$DEVICE_UDID" --launch` by
default, while optional push uses `--mode push`. The installer revalidates the
already signed `.app` against the selected capability mode. A signing failure is
resolved by correcting the Apple Account and/or Device.xcconfig, then rerunning
the scripted build. If `devicectl` cannot install an already signed `.app`, use
Xcode Window > Devices and Simulators to install that same artifact and launch it
from the iPhone. This is an installation fallback, not another build path. The
task never creates Archive/IPA and never deploys backend or inspects the
production database.

Provisioning, application-id, Team, device and local path details remain in
private temporary logs and are deleted after validation. Public output and the
final report contain only redacted PASS/FAIL. Passing these pre-install checks
does not claim that a physical install or launch has succeeded.

## Optional push

Push mode requires all of the following:

- local `GoogleService-Info.plist` outside the repository, or an in-repository
  copy proven ignored and untracked;
- plist/Firebase app bundle matching the effective device bundle;
- Apple push capability and provisioning for the selected Team/bundle;
- APNs credential configured in Firebase outside the repository;
- redacted logs and a clean tracked worktree.

After explicit consent, run the mode-specific preflight and build, then install
the resulting app:

```bash
bash ios/scripts/mac-preflight.sh --mode push --device "$DEVICE_UDID" --firebase-plist "$FIREBASE_PLIST"
bash ios/scripts/mac-build-device.sh --mode push --device "$DEVICE_UDID" --firebase-plist "$FIREBASE_PLIST"
bash ios/scripts/mac-install-device.sh --mode push --device "$DEVICE_UDID" --launch
```

The Firebase path remains local and is not included in logs or the final report.

Firebase Messaging supplies the FCM registration token; RocketFlow does not send
a raw APNs token to its API. Because production V22 is not deployed, successful
local signing/configuration cannot establish end-to-end production push. Record
push as `SKIPPED` or `BLOCKED` without downgrading a successful no-push install.

## Smoke checklist

With credentials entered only on the iPhone, record `PASS`, `FAIL` or `SKIPPED`:

- Login and authenticated shell;
- read-only `/rocket-api/health` status, recorded without response payload; this
  does not prove login;
- Planner, Calendar and Focus tabs;
- Planner hierarchy/scroll and details;
- minimal temporary create and edit flow with user consent;
- local reminder save/pending state and delivery/tap if timing permits;
- Calendar marker/agenda to task detail;
- Focus add/open/remove if safe;
- terminate/relaunch and restoration;
- `rocketflow://focus` and a safe `rocketflow://task/{taskId}` when supported;
- cleanup of temporary entities when safe.

Local notification delivery is OS best effort. Do not fabricate PASS when the
test is unavailable. Evidence must omit account email, credentials, task text,
task UUIDs and private screenshots.

## Stop and escalation

Stop before signing/install when any of these is true:

- tooling run URL/ID/job/head SHA mismatch, A not being an ancestor, or any
  tooling-path diff after A;
- dirty tracked worktree;
- missing full Xcode/iPhoneOS SDK >=16/exact XcodeGen;
- missing script/example or contract mismatch;
- expanded contract tests do not enforce API/ATS, SDK, config/redaction and
  install mode, signed bundle/codesign/entitlements, Team/application-id and
  embedded provisioning behavior;
- XcodeGen project or package-lock drift;
- simulator build/test failure;
- Device.xcconfig is not ignored;
- Local.xcconfig exists or endpoint/ATS differs from the exact contract;
- unexpected API, ATS, bundle or signing behavior;
- request to expose a secret or device/signing identifier;
- attempt to Archive/export/deploy/inspect DB;
- failure that requires a tracked source change.

For a user-only action, ask one short question with one concrete action. For a
technical blocker, report sanitized diagnostics and the smallest proposed
follow-up scope; do not broaden the installation task.

## Evidence and final verdict

Evidence belongs outside the repository, for example
`~/Desktop/rocketflow-ios-evidence-YYYYMMDD-HHMMSS`. The final report includes:

- exact branch and observed docs HEAD; separate immutable tooling A/run A with
  ancestor/no-tooling-diff result; separate app evidence SHA/run;
- Mac/Xcode/Swift/XcodeGen versions;
- parity/package/simulator test results;
- no-push or explicit push mode;
- bundle-match/API/ATS/signing result without the personal bundle value;
- device build/install/launch status using only a redacted device label/result;
- smoke results by item;
- push result separately;
- confirmation that evidence remains outside the repository, cleanup and
  `git status --short`;
- explicit confirmation of no tracked edits, commit/push, Archive/IPA, deploy or
  production DB inspection.

The report must not contain an absolute `.app`, config, Firebase or evidence
path; UDID, Team ID, serial, certificate/profile details; or secret values.

Only that Mac report can advance the status from "workflow defined" to a proven
physical-device result.
