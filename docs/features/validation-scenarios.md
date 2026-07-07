# Feature Validation Scenarios

This inventory indexes the scenarios CodexPill should validate for each feature
area. The owning feature document is the source of truth for behavior,
acceptance criteria, proof contract, validation targets, deferrals, and open
questions. This file tracks readiness and promotion order across those feature
contracts.

This is not the scenario pack. `.kite/product.json` and
`.kite/scenarios/<scenario-id>.json` are the source of truth only for runnable
Kite scenarios. Target scenarios stay here until their owning feature contract,
fixture, command, artifacts, privacy rules, and degraded-proof rules are
concrete enough to promote.

## Readiness

| Status | Meaning |
| --- | --- |
| `runnable` | Declared in `.kite/scenarios/<scenario-id>.json` and backed by a product-local command. |
| `target` | Needed for the feature, but not yet manifest-ready. |
| `manual-gate` | Maintainer or live-system validation; not a default Kite run. |
| `deferred` | Useful later, but explicitly outside the current validation lane. |

## Promotion Rules

- Every runnable scenario must reference feature acceptance criteria.
- Every runnable scenario must declare Validation Intent, expected artifacts,
  privacy rules, non-claims, and non-regression policy.
- Prefer unit, contract, workflow-event, and deterministic UI proof before live
  native proof.
- Live scenarios require explicit opt-in, cleanup rules, privacy rules, and
  non-claims.
- Release and compiler migration gates can use the same proof-contract shape,
  but they are maintainer validation gates rather than product UI scenarios.
- Manual gates stay out of `.kite/scenarios/<scenario-id>.json` until the owning feature doc
  names the opt-in requirement, cleanup requirement, allowed evidence, blocker
  taxonomy, degraded proof, and non-claims.

## Validation Boundaries

The menu structure exporter should emit observed structure from the built menu
snapshot. Scenario-specific assertions should remain declarative and thin until
Kite owns them directly. The scenario command adapter boundary is closed for
structure-contract scenarios: `verify-ui` names the requested proof type,
requires `ui-structure-contract` plus summary evidence, and treats screenshots
and UI trees as optional debug evidence. The runtime workflow-event boundary is
closed for primary `workflow-event-log` scenarios: `MenuBarRuntimeValidation`
and `MenuBarValidationObserver` emit runtime events only for pack-backed
scenarios whose canonical proof layer is `workflow-event-log`; unit,
contract-fixture, diagnostics, and deterministic UI scenarios may write
receipts or snapshots but do not imply observer-produced workflow logs. This
fixture/bootstrap boundary is closed for the current runnable deterministic
scenarios: product-owned `MenuBarValidationScenarioFixtures` builds synthetic
hosted-menu states for scenario commands and tests, `ValidationFixtureBootstrap`
loads external settings fixtures at app bootstrap, and SwiftUI
presentation/alert views render from injected state instead of reading
`CODEXPILL_VALIDATION_SCENARIO` or matching scenario ids directly.

No remaining validation boundary follow-up is documented in this index.

## Proof Contract Expansion

Each row below is a scenario candidate summary, not the full runnable proof
contract. Before promotion to `.kite/scenarios/<scenario-id>.json`, the owning feature doc
must include or link to the refinement proof-contract shape:

| Required Field | Promotion Requirement |
| --- | --- |
| Command / Method | Name the exact product command or test method, such as `make verify-ui SCENARIO=<id>` or a focused test suite. |
| Artifact | Name the artifact type and path, such as screenshot, UI tree, event log, contract fixture, diagnostics export, or result bundle. |
| Pass Condition | State what must be true in the artifact, not merely that the command exits successfully. |
| Privacy / Redaction | Declare synthetic fixture data, redaction status, and restricted evidence classes. |
| Degraded Proof | State what remains unproven when live, visual, system, or external proof is skipped. |

## Feature Contract Ownership

| Scenario Area | Owning Feature Contract |
| --- | --- |
| Menubar composition, busy state, diagnostics export | [Menubar](menubar.md) |
| Account catalog, overflow, unmatched active account, remote value fallback | [Accounts](accounts/00-accounts.md) |
| Add Account | [Add Account](accounts/01-add-account.md) |
| Switch Account | [Switch Account](accounts/02-switch-account.md) |
| Remove Account | [Remove Account](accounts/03-remove-account.md) |
| Rename Account | [Rename Account](accounts/04-rename-account.md) |
| Refresh Accounts | [Refresh Accounts](accounts/05-refresh-accounts.md) |
| Remote Hosts | [Remote Hosts](remote-hosts.md) |
| Notifications | [Notifications](notifications.md) |
| Status Bar | [Status Bar](status-bar.md) |
| Token Usage menu card and privacy boundary | [Token Usage](token-usage.md) |
| Token Usage loading state | [Token Usage Loading Progress](token-usage-loading-progress.md) |
| Token Usage parser/cache behavior | [Token Usage Incremental Cache](token-usage-cache.md) |
| Launch at Login | [Launch At Login](app-controls/01-launch-at-login.md) |
| Signed release package and beta download gates | [Signed GitHub Release Zip](release/01-signed-github-zip.md), [First Signed Beta Release Checklist](release/03-first-beta-release-checklist.md) |
| Swift 6 compiler gate | [Swift 6 Language Mode Migration](release/04-swift-6-language-mode.md) |

## Menubar

| Scenario | Acceptance Criteria | Validation Intent | Proof Layer | Non-Regression | Status |
| --- | --- | --- | --- | --- | --- |
| `hosted-menu-default` | Default saved-account menu shape does not claim live state. | `ui_visual`, `static_ui`, `privacy` | `ui-structure-contract`; structure contract and summary; screenshot/UI tree are debug-only | `smoke`, blocking | `runnable` |
| `menu-busy-status` | Busy workflows expose status and disable conflicting immediate actions; confirmation routing remains future workflow-event proof. | `workflow_state`, `ui_visual`, `privacy` | `ui-structure-contract`; structure contract and summary; workflow dispatch/event ordering remains a non-claim | `changed-feature`, blocking for menu action changes | `runnable` |
| `diagnostics-export-confirmation` | Diagnostics export requires confirmation and writes only a redacted support artifact. | `privacy`, `diagnostics`, `user_confirmation` | `diagnostics-export` plus workflow receipt; generated report plus negative leakage assertions | `changed-feature`, blocking for diagnostics changes | `runnable` |

## Accounts

| Scenario | Acceptance Criteria | Validation Intent | Proof Layer | Non-Regression | Status |
| --- | --- | --- | --- | --- | --- |
| `menu-empty-catalog` | Empty state guides toward Add Account and does not imply switching is possible. | `state_truth`, `static_ui`, `privacy` | `ui-structure-contract`; structure contract and summary; screenshot/UI tree are debug-only | `changed-feature`, blocking for account-catalog UI | `runnable` |
| `menu-account-overflow` | More than the visible saved-account limit renders discoverable overflow without changing account submenu behavior. | `state_truth`, `ui_visual`, `static_ui` | `ui-structure-contract`; structure contract and summary; screenshot/UI tree are debug-only | `changed-feature`, blocking for account-catalog UI | `runnable` |
| `menu-unmatched-active-account` | Unmatched local auth must not present a saved account as active. | `state_truth`, `ui_visual`, `privacy` | `ui-structure-contract`; structure contract and summary; screenshot/UI tree are debug-only | `smoke`, blocking | `runnable` |
| `add-account-name-validation` | Empty or duplicate display names are blocked before sign-in starts. | `workflow_state`, `privacy` | `unit`; focused test output and scenario summary | `changed-feature`, blocking for Add Account | `runnable` |
| `add-account-isolated-success` | Add Account saves an isolated account without switching This Mac and hydrates usable status when available. | `auth_isolation`, `workflow_state`, `privacy` | `workflow-event-log`; focused fake-client test output, workflow receipt, and scenario summary | `changed-feature`, blocking for Add Account | `runnable` |
| `add-account-failure-cleanup` | Cancel, expiry, prompt failure, live-auth mutation, save failure, and stale temp homes clean up sensitive temporary state. | `auth_isolation`, `failure_path`, `privacy` | `workflow-event-log`; focused fake-client failure tests, cleanup receipt, and negative filesystem/state assertions | `changed-feature`, blocking for Add Account | `runnable` |
| `switch-account-local-confirmed` | Local switch asks for confirmation, activates the snapshot, relaunches Codex, and refreshes account data. | `auth_mutation`, `workflow_state`, `privacy` | `workflow-event-log`; focused fake auth/process runtime proof, workflow receipt, and silent refresh proof | `changed-feature`, blocking for local switch | `runnable` |
| `switch-account-remote-install-verify` | Remote switch installs missing or stale snapshots, switches the target, refreshes app-server, and verifies the expected account. | `remote_mutation`, `workflow_state`, `privacy` | `workflow-event-log`; fake-host workflow tests, SSH contract fixture, controller relink proof, and workflow receipt | `changed-feature`, blocking for remote switch | `runnable` |
| `remove-account-active-targets-sign-out` | Removing an active account signs out local and remote active targets before deleting the saved snapshot. | `auth_mutation`, `workflow_state`, `privacy` | `workflow-event-log`; fake auth/process/remote clients, runtime proof, and workflow receipt | `changed-feature`, blocking for remove | `runnable` |
| `remove-account-signout-failure-keeps-control` | Required sign-out failure keeps the saved snapshot and catalog row. | `failure_path`, `state_truth`, `privacy` | `workflow-event-log`; focused local and remote fake failure clients plus workflow receipt | `changed-feature`, blocking for remove | `runnable` |
| `rename-account-label-only` | Rename changes only the display label, rejects empty or duplicate names, and keeps the persisted catalog in display-name order after a successful rename. | `pure_model`, `state_truth`, `privacy` | `unit`; focused test output and scenario summary | `changed-feature`, blocking for rename | `runnable` |
| `refresh-inactive-isolated-status` | Inactive saved accounts refresh through isolated app-server reads without mutating live auth and preserve meaningful previous limits on failed or suspicious reads. | `parser`, `auth_isolation`, `privacy` | `contract-fixture` plus integration fake app-server/status clients, isolated home cleanup, and workflow receipt | `changed-feature`, blocking for refresh | `runnable` |
| `refresh-active-relinks-same-account` | Active local refresh relinks the saved snapshot when live identity is the same but auth fingerprint changed. | `auth_mutation`, `state_truth`, `privacy` | `unit`; fake auth/status clients, identity matcher fixtures, and workflow receipt | `changed-feature`, blocking for refresh | `runnable` |

## Remote Hosts

| Scenario | Acceptance Criteria | Validation Intent | Proof Layer | Non-Regression | Status |
| --- | --- | --- | --- | --- | --- |
| `remote-host-add-panel-validation` | Add Host validates destination feedback and unlocks Add Host only for a reachable Codex-ready SSH target. | `ui_interaction`, `remote_contract`, `privacy` | `contract-fixture` plus unit form-state proof; fake SSH/Codex readiness contract and receipt | `changed-feature`, blocking for host setup | `runnable` |
| `remote-host-install-switch-current-account` | Host setup can install and switch the current account, or leave no confusing pending host when cancelled. | `remote_mutation`, `workflow_state`, `privacy` | `workflow-event-log` plus contract-fixture; fake remote operation ordering and cancellation receipt | `changed-feature`, blocking for host setup | `runnable` |
| `remote-host-verification-failure` | Failed or ambiguous remote verification is surfaced and never shown as verified active state. | `state_truth`, `failure_path`, `privacy` | `unit` plus deterministic menu projection; verifier/runtime/menu receipt | `changed-feature`, blocking for remote state | `runnable` |
| `remote-host-rate-limit-fallback` | Remote cards prefer verified remote values and use saved-account fallback only when remote data is missing or suspicious. | `state_truth`, `parser`, `privacy` | `contract-fixture` plus unit/menu projection proof; rate-limit resolution receipt | `changed-feature`, blocking for remote active cards | `runnable` |

## Notifications

| Scenario | Acceptance Criteria | Validation Intent | Proof Layer | Non-Regression | Status |
| --- | --- | --- | --- | --- | --- |
| `notifications-permission-denied-menu-state` | Denied macOS permission disables notification modes and routes to System Settings without deleting preferences. | `state_truth`, `ui_visual` | `unit` plus deterministic menu projection; fake settings-launch receipt | `changed-feature`, blocking for notification menu | `runnable` |
| `notifications-account-available-policy` | Account Available fires only for inactive fallback accounts becoming useful again. | `pure_model`, `workflow_state` | `unit`; policy, workflow delivery, and dedupe receipt | `changed-feature`, blocking for notification policy | `runnable` |
| `notifications-current-runs-out-action` | Current Runs Out copy explains the target and direct actions route through stale-checked local or remote switch flows. | `workflow_state`, `privacy` | `workflow-event-log`; fake policy, payload rendering, notification action events, response routing, and runtime receipt | `changed-feature`, blocking for notification actions | `runnable` |
| `notifications-dedupe-after-delivery` | A delivered account notification is suppressed until CodexPill observes that account become active. | `workflow_state`, `state_truth` | `unit`; state, workflow delivery, settings persistence, and runtime activation receipt | `changed-feature`, blocking for notification dedupe | `runnable` |

## Status Bar

| Scenario | Acceptance Criteria | Validation Intent | Proof Layer | Non-Regression | Status |
| --- | --- | --- | --- | --- | --- |
| `status-bar-icon-text-visible` | Icon and optional text produce a visible closed-state status item runtime snapshot. | `ui_visual`, `runtime_state`, `privacy` | `unit` plus `deterministic-ui`; runtime-state artifact, UI tree, and summary | `changed-feature`, blocking for status item rendering | `runnable` |
| `status-bar-hover-label` | Text-on-hover expands while the pointer is inside bounds and collapses when it leaves. | `ui_interaction`, `temporal` | `workflow-event-log`; fake runtime hover events, ordered proof sequence, validation receipt, future `macos_vm_temporal` if native timing is claimed | `changed-feature`, blocking for hover behavior | `runnable` |
| `status-bar-shortcut-reveal` | Reveal shortcut temporarily shows the label without changing saved display mode, and repeat press collapses it. | `ui_interaction`, `temporal` | `workflow-event-log`; fake shortcut callback, ordered reveal/collapse proof sequence, runtime events, validation receipt, native smoke optional | `changed-feature`, blocking for shortcut behavior | `runnable` |
| `status-bar-usage-bars-preferences` | Preferences control label mode, icon style, usage bar pacing markers, and accent colors without changing account state. | `ui_visual`, `state_truth`, `privacy` | `unit` plus deterministic menu projection, semantic menu snapshot, and coordinator state-truth receipt | `changed-feature`, blocking for visual preferences | `runnable` |

## Token Usage

| Scenario | Acceptance Criteria | Validation Intent | Proof Layer | Non-Regression | Status |
| --- | --- | --- | --- | --- | --- |
| `token-usage-off-hidden` | Token Usage off hides the card in the hosted active-account area; scanner lifecycle remains lower-level/runtime proof. | `state_truth`, `ui_visual`, `privacy` | `deterministic-ui`; screenshot, UI tree, summary; runtime scan prevention is a non-claim | `changed-feature`, blocking for Token Usage UI | `runnable` |
| `token-usage-ready-card` | Enabled Token Usage shows a local Last 30 Days aggregate card without implying account, workspace, organization, or remote-host attribution. | `ui_visual`, `state_truth`, `privacy` | `deterministic-ui`; screenshot, UI tree, summary | `changed-feature`, blocking for Token Usage card | `runnable` |
| `token-usage-parser-aggregation` | Scanner parses token-count rows, handles malformed rows, repeated cumulative totals, and large files safely. | `parser`, `privacy`, `performance` | `contract-fixture`; focused test output and scenario summary | `changed-feature`, blocking for scanner changes | `runnable` |
| `token-usage-cache-first` | Cache is reused before scanning and refreshes only changed or new eligible files for the selected period. | `state_truth`, `performance`, `privacy` | `contract-fixture`; focused test output and scenario summary | `changed-feature`, blocking for cache/runtime | `runnable` |
| `token-usage-loading-progress` | First-load progress is animated or live-updating without fake percentages or raw file/session details. | `ui_visual`, `temporal`, `privacy` | `deterministic-ui`; screenshot, UI tree, summary; existing unit coverage owns frame animation mechanics | `changed-feature`, blocking for loading UI | `runnable` |
| `token-usage-privacy-no-raw-session` | Token Usage diagnostics emit aggregate state/totals only, never prompts, session rows, paths, account IDs, emails, hostnames, auth material, or token-like values. | `privacy`, `diagnostics` | `diagnostics-export` plus `privacy-leak-proof`; diagnostics export, privacy leak report, focused test output, and scenario summary | `changed-feature`, blocking for token usage diagnostics | `runnable` |

## App Controls

| Scenario | Acceptance Criteria | Validation Intent | Proof Layer | Non-Regression | Status |
| --- | --- | --- | --- | --- | --- |
| `launch-at-login-menu-states` | Preferences shows checked, unchecked, blocked, and unavailable Launch at Login states truthfully. | `state_truth`, `ui_visual`, `privacy` | `unit` plus `deterministic-ui`; screenshot, UI tree, summary, and state matrix | `changed-feature`, blocking for app controls | `runnable` |
| `launch-at-login-enable-confirmation` | Enabling asks for confirmation before registering the macOS login item; cancelling preserves state; disabling unregisters directly. | `ui_interaction`, `system_mutation`, `privacy` | `workflow-event-log`; fake login-item controller, confirmation presenter, and failure receipt | `changed-feature`, blocking for app controls | `runnable` |
| `launch-at-login-blocked-opens-settings` | Blocked or unavailable state opens System Settings instead of pretending to toggle. | `ui_interaction`, `failure_path`, `privacy` | `workflow-event-log`; fake system opener, menu projection, and no-toggle receipt | `changed-feature`, blocking for app controls | `runnable` |
| `launch-at-login-real-os-smoke` | A local macOS build appears in System Settings and survives toggle on/off. | `system_mutation`, `manual_release_confidence` | `manual-qa` or explicit opt-in live OS proof; owning doc records opt-in, cleanup, blocker taxonomy, degraded proof, and non-claims | release confidence only | `manual-gate` |

## Release And Maintainer Gates

These docs use the same acceptance-to-proof discipline, but they are not normal
Kite product scenarios because they validate packaging, release, or compiler
quality rather than a product user path.

| Gate | Acceptance Criteria | Validation Intent | Proof Layer | Non-Regression | Status |
| --- | --- | --- | --- | --- | --- |
| `signed-release-package` | Clean `main` produces a signed, notarized, stapled zip that Gatekeeper accepts. | `release_artifact`, `privacy` | `manual-qa`; release docs record opt-in, cleanup, blocker taxonomy, degraded proof, and signing/notarization checks | release only, blocking | `manual-gate` |
| `beta-release-fresh-download` | Fresh GitHub Release download unzips and launches without Gatekeeper bypass, and Homebrew installs the same artifact. | `release_artifact`, `live_smoke` | `manual-qa`; release docs record fresh download/install evidence, cleanup, blocker taxonomy, degraded proof, and non-claims | release only, blocking | `manual-gate` |
| `swift-6-language-mode` | App and tests compile in Swift 6 mode with no broad unsafe concurrency escape hatches. | `engineering_quality`, `compiler_contract` | `contract-fixture`; build/test output, blocker taxonomy, degraded proof, and focused code review | release/refactor gate | `manual-gate` |

## Next Promotion Candidates

Current lane:

Feature-owned proof contracts are the prerequisite before promoting more
target scenarios. A target scenario may move into `.kite/scenarios/<scenario-id>.json` only
after the owning feature doc has concrete acceptance criteria, proof rows,
artifact expectations, privacy rules, and degraded-proof rules.

Recommended promotion order after the current runnable deterministic scenarios:

1. Local account mutation, remote host mutation, notification action routing,
   temporal status-bar interaction, and live/system-mutation gates only after
   fake-client workflow receipts or explicit live opt-in exist.

Release and compiler gates remain maintainer validation gates, not normal Kite
product scenarios, until Kite has a separate gate registry for non-product
release evidence.
