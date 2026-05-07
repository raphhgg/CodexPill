# Test Suite Relevance After Seal Runtime Migration

Date: 2026-05-03

This review decides which CodexPill tests still add value after Seal owns
canonical runtime/live validation for migrated scenarios. It is a decision
backlog, not a cleanup patch. No tests are deleted by this slice.

## Inputs

- `docs/features/`
- `docs/VALIDATION.md`
- `docs/feature-to-seal-scenario-coverage.md`
- repository test layout under `Tests/`
- current Seal-backed scenario declarations in `.seal/run.yml` and
  feature-owned validation catalogs under
  `Sources/Features/Accounts/Validation/` and
  `Sources/Features/Hosts/Validation/`, plus shared proof runtime under
  `Sources/Features/Validation/`
- `docs/seal-runtime-validation-migration-plan.md`

## Decision Rule

Seal should replace CodexPill tests only when the test's main value is proving a
runtime/live feature claim that is already Seal-backed with the same invariant
and evidence. Seal should not replace tests that prove pure policy, formatting,
parser behavior, persistence, injected process or SSH orchestration, secrets
redaction, validation harness contracts, deterministic menu projection, or
negative failure ordering.

Lower-layer tests remain valuable when they fail for reasons Seal should not
own: bad data mapping, broken persistence, unsafe auth-file ordering, wrong
command construction, missing redaction, stale rate-limit preservation, ranking
policy drift, or injected error mapping.

## Ownership Categories

| Category | Disposition | Current examples |
| --- | --- | --- |
| Keep | Preserve lower-layer tests when they prove distinct defects before runtime proof would fail. | Model, settings, parser, persistence, injected workflow, deterministic UI, projection, validation-boundary, redaction, and harness-isolation tests. |
| Migrate | Promote runtime/live behavior to Seal when the claim needs a running app, live menu state, runtime action dispatch, or cross-feature coordinator wiring. | Baseline menu open, hover bounds, active-account grouping, destructive remove flow, post-switch refresh evidence, Add Account success routing, remote verification failure, busy-state gating, and notification action dispatch. |
| Remove or narrow | Delete only future duplicate assertions after equivalent Seal scenarios and stable machine-readable Seal results exist. | Legacy live success assertions for migrated scenarios, duplicate proof-sequence checks, and stale snapshot presence checks that can pass without fresh Seal verification. |
| Defer | Keep manual or OS/external-environment validation explicit until automation can control the dependency without risking local state or flakiness. | Real browser device-auth completion, real SSH credentials and host-key behavior, macOS notification authorization/delivery, clipboard interaction, global hot-key conflicts, native alert text entry, and installed Codex app-server protocol drift. |

This slice records ownership only. No test is deleted here.

## Suites Reviewed

| Suite area | Files reviewed | Current relevance |
| --- | --- | --- |
| Core models | `Tests/Core/Models/*Tests.swift` | Keep. These tests prove plan normalization, rate-limit window display, and remote metadata identity rules. Seal should not own pure model decisions. |
| Core configuration | `Tests/Core/Configuration/*Tests.swift` | Keep. Settings persistence, migration, remote host state, notification state, shortcut shape, and accent color storage are lower-layer contracts. |
| Platform persistence | `Tests/Platform/Persistence/AppPathsTests.swift` | Keep. Validation path isolation and isolated `CODEX_HOME` cleanup prevent real user-state mutation. Seal depends on this safety boundary rather than replacing it. |
| Platform Codex | `Tests/Platform/Codex/*Tests.swift` | Keep. App-server parsing, auth snapshot handling, JSON-RPC errors, transient retry, status mapping, and sensitive auth parsing are protocol and safety tests. |
| Platform hosts | `Tests/Platform/Hosts/*Tests.swift` | Keep. SSH command mapping, remote copy/sign-out command behavior, remote app-server refresh, and validation remote-host fixtures are injected boundary tests. |
| Accounts use cases and workflows | `Tests/Accounts/*Tests.swift` | Keep, with targeted backlog checks. These tests own account matching, add/switch/remove/rename workflows, refresh, ranking, operation state, and failure ordering. |
| Host use cases and workflows | `Tests/Hosts/*Tests.swift` | Keep. These tests own remote-host runtime state, remote account verification, remote rate-limit resolution, and switch-on-host orchestration. |
| Menubar presentation and deterministic UI | `Tests/MenuBar/MenuBarMenu*Tests.swift`, `MenuBarAccount*Tests.swift`, `ActiveAccountsProjectionTests.swift`, `StatusBarIconRendererTests.swift`, `KeyboardShortcutPresentationTests.swift`, `MenuBarUIValidationTests.swift` | Keep. Static menu shape, copy, layout, projection, sorting, overflow, and deterministic screenshots are better owned below Seal. |
| Menubar runtime units | `Tests/MenuBar/StatusItem*Tests.swift`, `GlobalShortcutRuntimeTests.swift`, `MenuBarHostActionCoordinatorTests.swift`, `MenuBarNotificationWorkflowTests.swift`, `AccountAvailabilityNotificationRuntimeTests.swift` | Keep. These tests inject OS/runtime seams and cover policy, event emission, registration failure, notification workflow, and coordinator routing. |
| Menubar alert and form tests | `Tests/MenuBar/MenuBarAlertFactoryTests.swift`, `MenuBarHostSetupFormStateTests.swift`, `ShortcutCapturePanelTests.swift` | Keep. Copy/action shape and native-panel state are lower-layer or manual/OS adjacent. |
| Menubar live validation tests | `Tests/MenuBar/MenuBarLiveValidationTests.swift` | Mixed. Keep harness, redaction, injected-runtime, and non-Seal flows. Rewrite or migrate Seal-proof emitter tests after Seal has stable machine-readable verifier result coverage. Promote legacy runtime flows to Seal scenarios before deleting live coverage. The persisted remote-host refresh failure runtime claim is now Seal-backed, so remaining CodexPill live coverage should focus on fixture safety and bridge diagnostics, not independent pass/fail authority. |
| Menubar live smoke script tests | `Tests/MenuBar/MenuBarLiveSmokeScriptTests.swift` | Keep for now. These tests guard the shell validation contract and Seal-derived summary semantics for the legacy smoke-script bridge; revisit only after the Seal verifier artifact contract is fully stable and the bridge no longer provides handoff evidence. |
| App runtime environment | `Tests/App/AppRuntimeEnvironmentTests.swift` | Keep. These tests enforce validation environment isolation and automated-test safety gates. |

## Feature Claims Considered

Seal already owns these runtime/live claims as canonical migrated scenarios:

| Feature claim | Legacy scenario | Seal scenario | Test-suite impact |
| --- | --- | --- | --- |
| Add Account name dialog is presented and can be cancelled without mutating accounts. | `live-add-account-name-dialog-cancelled` | `add-account-name-dialog-cancelled` | Do not delete lower-layer Add Account workflow, alert, duplicate-name, cleanup, or live-auth mutation tests. Candidate to reduce duplicate legacy proof assertions once Seal verifier artifacts are stable. |
| Selecting an inactive account changes the active account after confirmation. | `live-account-switch` | `switch-account-changes-active-account` | Keep `SwitchAccountWorkflowTests` for activation, persistence, relaunch, and matcher failure ordering. Candidate to move live proof responsibility fully to Seal after post-switch refresh/relaunch gaps are separately covered. |
| Add Host invalid destination emits validation feedback. | `live-add-host-destination-validation-failed` | `add-host-destination-validation-failed` | Keep form-state and remote-host command tests. Candidate to reduce duplicate legacy live script assertions. |
| Remote-host submenu switch updates that host's active account. | `live-remote-host-switch` | `switch-account-on-host-changes-remote-active-account` | Keep `SwitchAccountOnHostWorkflowTests`, `RemoteHostAccountVerifierTests`, and SSH/validation-client tests for install, switch, refresh, verification, and failure semantics. |
| Scheduled refresh completes without changing saved account identity or showing a blocking alert. | `live-scheduled-refresh` | `scheduled-refresh-preserves-account-catalog` | Keep controller/use-case tests for silent refresh, error behavior, stale rate-limit preservation, and remote refresh. Candidate to reduce duplicate live proof checks only after failure-path ownership is clear. |
| Persisted remote host refresh failure preserves fallback state and hides disconnected hosts from active account facts. | `persisted_host_refresh_failure` | `remote-host-refresh-failure-preserves-fallback-state` | Keep host refresh, active-card projection, and validation-client tests for lower-layer fallback/disconnection state. Candidate to narrow duplicate live success assertions now that Seal owns the runtime claim. |

Claims that still need Seal scenarios must not drive deletion yet:

- `live-menu-open`: app launch, menu-open runtime snapshot, custom row width, and inactive-account action wiring.
- `live-status-item-hover`: status-item hover and resized bounds behavior.
- active-account grouping across local and remote targets.
- remove active account sign-out before saved snapshot deletion.
- switch-account relaunch and post-switch refresh evidence.
- Add Account success routing into local switch without a second confirmation.
- remote verification failure surfaced in the live menu.
- busy-state action gating.
- notification action dispatch.

## Keep

Keep these categories as first-class CodexPill tests:

- **Pure model and policy tests**: plan normalization, rate-limit display,
  availability ranking, account matching, identity resolution, notification
  ranking and dedupe, shortcut shape, and state machines.
- **Persistence and migration tests**: account catalog writes, settings stores,
  remote host state, notification state, isolated `CODEX_HOME`, temporary auth
  cleanup, and validation app-support overrides.
- **Parser and protocol tests**: app-server JSON-RPC framing, notification
  frames, retry, stale-limit preservation, plan-code mapping, auth snapshot
  parsing, and remote app-server output parsing.
- **Injected orchestration tests**: local switching, add-account isolated login,
  remove-account sign-out ordering, remote install/switch/refresh/verify,
  Codex relaunch calls, and failure mapping.
- **Deterministic UI tests**: menu section order, account overflow, submenu
  shape, status and plan copy, active-card grouping, disconnected-host
  projection, notification menu entries, and hosted screenshots.
- **Harness safety tests**: validation app environment isolation, automated-test
  alert suppression, validation artifact shape, payload redaction, and real
  user path sanitization.

Rationale: these tests fail close to the defect and protect contracts Seal
either cannot observe or should not encode as product truth. Removing them
would turn lower-layer defects into broad runtime failures or leave them
uncovered.

## Rewrite Or Narrow

These tests should remain, but should be narrowed if they duplicate Seal-owned
runtime proof once Seal reporting is stable:

| Candidate | Current value | Rewrite direction |
| --- | --- | --- |
| Seal proof emitter tests in `MenuBarLiveValidationTests` | Verify CodexPill records expected Seal proof events for migrated scenarios. | Keep until `logs/seal-verifier.result.json` is the stable machine-readable pass/fail source. Then narrow to declaration/event-emission unit coverage and rely on Seal verifier for proof acceptance. |
| `MenuBarLiveSmokeScriptTests` summary assertions | Guard that shell live validation reports Seal-derived verdicts rather than stale legacy status. | Keep as script contract tests while compatibility envelopes exist. Later narrow to checking artifact references and non-stale cleanup, not scenario semantics. |
| Live validation observer artifact tests | Ensure runtime snapshots/events are written and sanitized. | Keep redaction and schema tests. Remove only duplicate assertions that Seal verifier already checks for migrated scenario success. |

Rationale: these are not product-behavior duplicates yet; they protect the
migration bridge. They become cleanup candidates after Seal exposes durable
machine-readable results and CodexPill no longer needs compatibility summaries
for handoff evidence.

## Migrate To Seal

Create follow-up Seal migration issues for runtime/live behavior still covered
only by legacy live tests or deterministic approximations:

| Follow-up candidate | Current owner | Reason |
| --- | --- | --- |
| Baseline menu-open Seal scenario | `make verify-ui-live` / `live-menu-open` plus deterministic UI | Runtime launch, menu opening, custom row width, and action wiring are live readiness claims. |
| Status-item hover Seal scenario | `StatusItemRuntimeTests` plus `live-status-item-hover` | Unit tests cover policy/events, but real hover bounds are runtime UI behavior. |
| Remove active account Seal scenario | `DeleteSavedAccountUseCaseTests`, host client tests, `MenuBarLiveValidationTests` | Live destructive flow deserves Seal readiness proof, while failure ordering stays lower-layer. |
| Switch-account post-refresh Seal scenario | `SwitchAccountWorkflowTests` plus current switch Seal scenario | Existing Seal coverage proves visible active-account change, not relaunch/post-switch refresh as distinct invariants. |
| Add Account success-to-switch Seal scenario | `AccountActionFlowTests`, `AddAccountWorkflowTests`, alert tests | Runtime coordinator wiring after success is not currently Seal-backed. |
| Remote verification failure Seal scenario | `SwitchAccountOnHostWorkflowTests`, `MenuBarLiveValidationTests` | Injected tests prove failure semantics; live menu recovery remains a runtime gap. |
| Busy-state gating Seal scenario | menu-state and account operation tests | Shared runtime disabled/confirmation-routed actions should be proven once as visible behavior. |
| Notification action dispatch Seal scenario | notification policy/runtime tests | Delivered notification action routing is runtime behavior, if macOS delivery can be controlled reliably. |

Rationale: these are runtime/live claims from the coverage map. They should be
promoted to Seal before CodexPill treats Seal as complete live-readiness
coverage.

Active account grouping is now covered by `active-account-grouping-runtime-ready`;
keep deterministic projection tests because they still own lower-level grouping
rules and fixture safety.

## Delete Or Devalue

Do not bulk-delete tests from this repo as part of the Seal migration. Current
delete candidates are limited to future, reviewed cleanup after a replacement
Seal scenario exists and after a lower-layer distinct-failure check remains.

Potential future deletion candidates:

- duplicate legacy live success assertions for the already Seal-backed
  legacy smoke-script scenarios and the config-backed remote-host refresh
  failure scenario, but only after Seal verifier result artifacts are stable and the
  validation script no longer needs compatibility summaries;
- redundant proof-sequence assertions that inspect the same migrated invariant
  Seal already verifies, while retaining artifact cleanup, redaction, and
  failure-step tests;
- stale snapshot presence checks that can pass without fresh Seal verification.

Rationale: without those prerequisites, deletion would be premature. Seal owns
canonical runtime proof; it does not replace CodexPill's lower-layer safety net.

## Risky Or Mutating Tests

These tests or validation flows deserve special handling because they touch
auth-like state, process control, remote command boundaries, notification
delivery, or live UI state. They are not necessarily unsafe today; the point is
that future rewrites must preserve their isolation.

| Test or flow | Risk | Required guard |
| --- | --- | --- |
| `SCENARIO=live-account-switch make verify-ui-live` with `CODEXPILL_ALLOW_LIVE_ACCOUNT_SWITCH_VALIDATION=1` | May mutate live auth when explicitly enabled. | Keep opt-in environment gate. Prefer fixture-owned Seal proof for routine validation. |
| `SwitchAccountWorkflowTests` | Activates saved auth and relaunches Codex through injected seams. | Keep injected snapshot/process clients; never point at default `~/.codex/auth.json` in tests. |
| `DeleteSavedAccountUseCaseTests` and remove-account live validation | Signs out local or remote active targets before deletion through seams. | Keep fixture stores and injected host/process clients; require explicit live mutation opt-in for any real-auth scenario. |
| `AddAccountWorkflowTests` | Exercises isolated login cleanup and live-auth mutation abort behavior. | Keep isolated `CODEX_HOME`; never log raw auth/device data; preserve stale temp-home cleanup tests. |
| `HydrateSavedAccountsMetadataUseCaseTests` | Temporarily activates saved snapshots to hydrate inactive metadata through injected seams. | Keep restore-current-auth assertions and no default auth path access. |
| `SSHRemoteHostClientTests` | Builds commands that would affect remote `~/.codex/auth.json` if run against a real host. | Keep command-runner fixtures; do not convert to real SSH validation by default. |
| `ValidationRemoteHostClientTests` and remote-host live validation helpers | Simulate remote install, switch, sign-out, and active-account reads. | Keep validation-only fixtures and app-support isolation. |
| `MenuBarLiveValidationTests` notification tests | Exercise notification center and app activation seams. | Keep fake notification center/application clients unless testing macOS permission manually. |
| `AppPathsTests` and `AppRuntimeEnvironmentTests` | Define where validation and tests write state. | Treat failures here as safety blockers because they protect real user state. |

## Follow-Up Issue Candidates

1. Promote baseline `live-menu-open` to a Seal scenario and then remove duplicate
   legacy live success assertions.
2. Promote `live-status-item-hover` to a Seal scenario if hover remains a
   release-readiness gate.
3. Promote active local/remote account grouping to a Seal scenario.
4. Promote active-account removal sign-out flow to a Seal scenario, with
   lower-layer tests retaining sign-out failure ordering.
5. Extend switch-account Seal coverage for Codex relaunch and post-switch
   refresh evidence.
6. Add Seal coverage for Add Account success routing into local switch.
7. Add Seal coverage for remote switch verification failure surfacing.
8. Add one shared busy-state action-gating Seal scenario.
9. Add notification action dispatch Seal coverage only if macOS delivery can be
    controlled without flakiness.
10. After machine-readable Seal verifier results are stable, narrow
    `MenuBarLiveValidationTests` Seal emitter tests to CodexPill declaration and
    event forwarding coverage.
11. After compatibility summaries are retired, simplify
    `MenuBarLiveSmokeScriptTests` to script/artifact contract checks.

## Verification Notes

- Repository layout cross-check: test suites currently live under
  `Tests/Accounts`, `Tests/App`, `Tests/Core`, `Tests/Hosts`, `Tests/MenuBar`,
  `Tests/Platform`, and `Tests/Support`.
- Seal coverage cross-check: migrated runtime/live scenarios are listed in
  `docs/feature-to-seal-scenario-coverage.md`, and config-backed scenarios are
  declared in `.seal/run.yml`; the remaining runtime/live migration backlog in
  that document is reflected above.
- Scope check: this slice adds documentation only. It does not delete tests,
  implement cleanup, add Seal scenarios, or change live UI permissions.
