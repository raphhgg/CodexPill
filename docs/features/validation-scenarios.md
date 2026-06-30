# Feature Validation Scenarios

This inventory indexes the scenarios CodexPill should validate for each feature
area. The owning feature document is the source of truth for behavior,
acceptance criteria, proof contract, validation targets, deferrals, and open
questions. This file tracks readiness and promotion order across those feature
contracts.

This is not a scenario pack. `.kite/scenarios.json` remains the source of truth
only for runnable Kite scenarios. Target scenarios stay here until their
owning feature contract, fixture, command, artifacts, privacy rules, and
degraded-proof rules are concrete enough to promote.

## Readiness

| Status | Meaning |
| --- | --- |
| `runnable` | Declared in `.kite/scenarios.json` and backed by a product-local command. |
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

## Proof Contract Expansion

Each row below is a scenario candidate summary, not the full runnable proof
contract. Before promotion to `.kite/scenarios.json`, the owning feature doc
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
| `hosted-menu-default` | Default saved-account menu shape does not claim live state. | `ui_visual`, `static_ui`, `privacy` | `deterministic-ui`; screenshot, UI tree, summary | `smoke`, blocking | `runnable` |
| `menu-busy-status` | Busy workflows expose status and disable conflicting immediate actions; confirmation routing remains future workflow-event proof. | `workflow_state`, `ui_visual`, `privacy` | `deterministic-ui`; screenshot, UI tree, summary; workflow dispatch/event ordering is a non-claim | `changed-feature`, blocking for menu action changes | `runnable` |
| `diagnostics-export-confirmation` | Diagnostics export requires confirmation and writes only a redacted support artifact. | `privacy`, `diagnostics`, `user_confirmation` | `diagnostics-export`; generated report plus negative leakage assertions | `changed-feature`, blocking for diagnostics changes | `target` |

## Accounts

| Scenario | Acceptance Criteria | Validation Intent | Proof Layer | Non-Regression | Status |
| --- | --- | --- | --- | --- | --- |
| `menu-empty-catalog` | Empty state guides toward Add Account and does not imply switching is possible. | `state_truth`, `ui_visual`, `static_ui` | `deterministic-ui`; screenshot, UI tree, summary | `changed-feature`, blocking for account-catalog UI | `runnable` |
| `menu-account-overflow` | More than the visible saved-account limit renders discoverable overflow without changing account submenu behavior. | `state_truth`, `ui_visual`, `static_ui` | `deterministic-ui`; screenshot, UI tree, summary | `changed-feature`, blocking for account-catalog UI | `runnable` |
| `menu-unmatched-active-account` | Unmatched local auth must not present a saved account as active. | `state_truth`, `ui_visual`, `privacy` | `deterministic-ui`; screenshot, UI tree, summary | `smoke`, blocking | `runnable` |
| `add-account-name-validation` | Empty or duplicate display names are blocked before sign-in starts. | `workflow_state`, `privacy` | `unit` plus alert/panel presentation assertions | `changed-feature`, blocking for Add Account | `target` |
| `add-account-isolated-success` | Add Account saves an isolated account without switching This Mac and hydrates usable status when available. | `auth_isolation`, `workflow_state`, `privacy` | `integration` plus `workflow-event-log`; fake login/app-server clients | `changed-feature`, blocking for Add Account | `target` |
| `add-account-failure-cleanup` | Cancel, expiry, prompt failure, live-auth mutation, save failure, and stale temp homes clean up sensitive temporary state. | `auth_isolation`, `failure_path`, `privacy` | `integration` plus negative filesystem/state assertions | `changed-feature`, blocking for Add Account | `target` |
| `switch-account-local-confirmed` | Local switch asks for confirmation, activates the snapshot, relaunches Codex, and refreshes account data. | `auth_mutation`, `workflow_state`, `privacy` | `workflow-event-log` with fake process/auth clients | `changed-feature`, blocking for local switch | `target` |
| `switch-account-remote-install-verify` | Remote switch installs missing or stale snapshots, switches the target, refreshes app-server, and verifies the expected account. | `remote_mutation`, `workflow_state`, `privacy` | `workflow-event-log` with `InMemoryRemoteHostClient` or fake SSH contract | `changed-feature`, blocking for remote switch | `target` |
| `remove-account-active-targets-sign-out` | Removing an active account signs out local and remote active targets before deleting the saved snapshot. | `auth_mutation`, `workflow_state`, `privacy` | `workflow-event-log`; fake auth/process/remote clients | `changed-feature`, blocking for remove | `target` |
| `remove-account-signout-failure-keeps-control` | Required sign-out failure keeps the saved snapshot and catalog row. | `failure_path`, `state_truth`, `privacy` | `unit` or `workflow-event-log`; fake failure clients | `changed-feature`, blocking for remove | `target` |
| `rename-account-label-only` | Rename changes only the display label and rejects empty or duplicate names. | `pure_model`, `state_truth` | `unit` plus menu projection when row copy changes | `changed-feature`, blocking for rename | `target` |
| `refresh-inactive-isolated-status` | Inactive saved accounts refresh through isolated app-server reads without mutating live auth and preserve meaningful previous limits on failed or suspicious reads. | `parser`, `auth_isolation`, `privacy` | `contract-fixture` plus integration fake app-server/status clients | `changed-feature`, blocking for refresh | `target` |
| `refresh-active-relinks-same-account` | Active local refresh relinks the saved snapshot when live identity is the same but auth fingerprint changed. | `auth_mutation`, `state_truth`, `privacy` | `integration` with fake auth/status clients | `changed-feature`, blocking for refresh | `target` |

## Remote Hosts

| Scenario | Acceptance Criteria | Validation Intent | Proof Layer | Non-Regression | Status |
| --- | --- | --- | --- | --- | --- |
| `remote-host-add-panel-validation` | Add Host validates destination feedback and unlocks Add Host only for a reachable Codex-ready SSH target. | `ui_interaction`, `remote_contract`, `privacy` | `deterministic-ui` for panel states plus fake SSH contract | `changed-feature`, blocking for host setup | `target` |
| `remote-host-install-switch-current-account` | Host setup can install and switch the current account, or leave no confusing pending host when cancelled. | `remote_mutation`, `workflow_state`, `privacy` | `workflow-event-log` with fake remote operations | `changed-feature`, blocking for host setup | `target` |
| `remote-host-verification-failure` | Failed or ambiguous remote verification is surfaced and never shown as verified active state. | `state_truth`, `failure_path`, `privacy` | `unit` plus deterministic menu projection | `changed-feature`, blocking for remote state | `target` |
| `remote-host-rate-limit-fallback` | Remote cards prefer verified remote values and use saved-account fallback only when remote data is missing or suspicious. | `state_truth`, `parser`, `privacy` | `unit` and contract fixtures for rate-limit resolution | `changed-feature`, blocking for remote active cards | `target` |

## Notifications

| Scenario | Acceptance Criteria | Validation Intent | Proof Layer | Non-Regression | Status |
| --- | --- | --- | --- | --- | --- |
| `notifications-permission-denied-menu-state` | Denied macOS permission disables notification modes and routes to System Settings without deleting preferences. | `state_truth`, `ui_visual` | `unit` plus deterministic menu projection | `changed-feature`, blocking for notification menu | `target` |
| `notifications-account-available-policy` | Account Available fires only for inactive fallback accounts becoming useful again. | `pure_model`, `workflow_state` | `unit`; policy and dedupe state fixtures | `changed-feature`, blocking for notification policy | `target` |
| `notifications-current-runs-out-action` | Current Runs Out copy explains the target and direct actions route through stale-checked local or remote switch flows. | `workflow_state`, `privacy` | `workflow-event-log` with fake notification response payloads | `changed-feature`, blocking for notification actions | `target` |
| `notifications-dedupe-after-delivery` | A delivered account notification is suppressed until CodexPill observes that account become active. | `workflow_state`, `state_truth` | `unit`; notification state fixtures | `changed-feature`, blocking for notification dedupe | `target` |

## Status Bar

| Scenario | Acceptance Criteria | Validation Intent | Proof Layer | Non-Regression | Status |
| --- | --- | --- | --- | --- | --- |
| `status-bar-icon-text-visible` | Icon and optional text produce a visible closed-state status item snapshot. | `ui_visual` | `unit` or `deterministic-ui` snapshot of runtime state | `changed-feature`, blocking for status item rendering | `target` |
| `status-bar-hover-label` | Text-on-hover expands while the pointer is inside bounds and collapses when it leaves. | `ui_interaction`, `temporal` | `workflow-event-log`; future `macos_vm_temporal` if native timing is claimed | `changed-feature`, blocking for hover behavior | `target` |
| `status-bar-shortcut-reveal` | Reveal shortcut temporarily shows the label without changing saved display mode, and repeat press collapses it. | `ui_interaction`, `temporal` | `workflow-event-log`; native smoke optional | `changed-feature`, blocking for shortcut behavior | `target` |
| `status-bar-usage-bars-preferences` | Preferences control label mode, icon style, usage bar pacing markers, and accent colors without changing account state. | `ui_visual`, `state_truth` | `unit` plus deterministic menu projection | `changed-feature`, blocking for visual preferences | `target` |

## Token Usage

| Scenario | Acceptance Criteria | Validation Intent | Proof Layer | Non-Regression | Status |
| --- | --- | --- | --- | --- | --- |
| `token-usage-off-hidden` | Token Usage off hides the card in the hosted active-account area; scanner lifecycle remains lower-level/runtime proof. | `state_truth`, `ui_visual`, `privacy` | `deterministic-ui`; screenshot, UI tree, summary; runtime scan prevention is a non-claim | `changed-feature`, blocking for Token Usage UI | `runnable` |
| `token-usage-ready-card` | Enabled Token Usage shows a local Last 30 Days aggregate card without implying account, workspace, organization, or remote-host attribution. | `ui_visual`, `state_truth`, `privacy` | `deterministic-ui`; screenshot, UI tree, summary | `changed-feature`, blocking for Token Usage card | `runnable` |
| `token-usage-parser-aggregation` | Scanner parses token-count rows, handles malformed rows, repeated cumulative totals, and large files safely. | `parser`, `privacy`, `performance` | `contract-fixture`; synthetic JSONL fixtures | `changed-feature`, blocking for scanner changes | `target` |
| `token-usage-cache-first` | Cache is reused before scanning and refreshes only changed or new eligible files for the selected period. | `state_truth`, `performance`, `privacy` | `unit` and integration cache fixtures | `changed-feature`, blocking for cache/runtime | `target` |
| `token-usage-loading-progress` | First-load progress is animated or live-updating without fake percentages or raw file/session details. | `ui_visual`, `temporal`, `privacy` | `deterministic-ui`; screenshot, UI tree, summary; existing unit coverage owns frame animation mechanics | `changed-feature`, blocking for loading UI | `runnable` |
| `token-usage-privacy-no-raw-session` | Token Usage artifacts, diagnostics, and UI emit aggregates only, never prompts, session rows, paths, account IDs, emails, or hostnames. | `privacy` | `diagnostics-export` and negative leakage fixtures | `changed-feature`, blocking for token usage diagnostics | `target` |

## App Controls

| Scenario | Acceptance Criteria | Validation Intent | Proof Layer | Non-Regression | Status |
| --- | --- | --- | --- | --- | --- |
| `launch-at-login-menu-states` | Preferences shows checked, unchecked, blocked, and unavailable Launch at Login states truthfully. | `state_truth`, `ui_visual`, `privacy` | `unit` plus `deterministic-ui`; screenshot, UI tree, summary, and state matrix | `changed-feature`, blocking for app controls | `runnable` |
| `launch-at-login-enable-confirmation` | Enabling asks for confirmation before registering the macOS login item; disabling unregisters directly. | `ui_interaction`, `system_mutation` | `workflow-event-log` with fake login-item controller | `changed-feature`, blocking for app controls | `target` |
| `launch-at-login-blocked-opens-settings` | Blocked or unavailable state opens System Settings instead of pretending to toggle. | `ui_interaction`, `failure_path` | `workflow-event-log` with fake system opener | `changed-feature`, blocking for app controls | `target` |
| `launch-at-login-real-os-smoke` | A local macOS build appears in System Settings and survives toggle on/off. | `system_mutation`, `manual_release_confidence` | `manual-qa` or explicit opt-in live OS proof with cleanup | release confidence only | `manual-gate` |

## Release And Maintainer Gates

These docs use the same acceptance-to-proof discipline, but they are not normal
Kite product scenarios because they validate packaging, release, or compiler
quality rather than a product user path.

| Gate | Acceptance Criteria | Validation Intent | Proof Layer | Non-Regression | Status |
| --- | --- | --- | --- | --- | --- |
| `signed-release-package` | Clean `main` produces a signed, notarized, stapled zip that Gatekeeper accepts. | `release_artifact`, `privacy` | `manual-qa`; packaging command output and signing/notarization checks | release only, blocking | `manual-gate` |
| `beta-release-fresh-download` | Fresh GitHub Release download unzips and launches without Gatekeeper bypass, and Homebrew installs the same artifact. | `release_artifact`, `live_smoke` | `manual-qa`; fresh download/install evidence | release only, blocking | `manual-gate` |
| `swift-6-language-mode` | App and tests compile in Swift 6 mode with no broad unsafe concurrency escape hatches. | `engineering_quality`, `compiler_contract` | `contract-fixture`; build/test output plus focused code review | release/refactor gate | `manual-gate` |

## Next Promotion Candidates

Current lane:

Feature-owned proof contracts are the prerequisite before promoting more
target scenarios. A target scenario may move into `.kite/scenarios.json` only
after the owning feature doc has concrete acceptance criteria, proof rows,
artifact expectations, privacy rules, and degraded-proof rules.

Recommended promotion order after the current runnable deterministic menu
scenarios:

1. `status-bar-icon-text-visible`: cover simple deterministic closed-state
   presentation before temporal interaction proof.
2. `rename-account-label-only` and `add-account-name-validation`: lower-risk
   account model/presentation scenarios before auth mutation workflows.
3. Token Usage parser, cache, and privacy scenarios when scanner, cache,
   diagnostics, or artifact behavior changes.
4. Local account mutation, remote host mutation, notification action routing,
   temporal status-bar interaction, and live/system-mutation gates only after
   fake-client workflow receipts or explicit live opt-in exist.

Release and compiler gates remain maintainer validation gates, not normal Kite
product scenarios, until Kite has a separate gate registry for non-product
release evidence.
