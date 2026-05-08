# CodexPill Feature To Seal Scenario Coverage

Date: 2026-05-03

This map categorizes CodexPill runtime and live-validation business claims from
`docs/features/` against current Seal scenario coverage.

CodexPill owns these feature claims. Seal may reference this document as
adoption pressure or release-readiness context, but Seal should not duplicate
these product semantics as Seal product truth.

## Categories

- **Seal runtime/live scenario exists**: a Seal-backed live scenario currently
  covers the claim.
- **Seal scenario needed**: the claim is runtime/live behavior that would
  benefit from a Seal scenario and is not already Seal-backed.
- **Lower-layer test owns this better**: unit, integration, deterministic UI, or
  static validation is the right proof because the claim is pure policy,
  persistence, projection, parsing, formatting, or orchestration at an injected
  boundary.
- **Manual/OS/environmental validation**: the claim depends on macOS behavior,
  Accessibility, real SSH setup, browser sign-in, external Codex app behavior,
  or another environment outside deterministic agent control.
- **Deferred or not currently validated**: the feature doc names a claim, but it
  is not yet represented by an automated proof target or is intentionally out
  of the current validation surface.

## Existing Seal Runtime/Live Scenarios

Current Seal-backed scenarios are implemented by feature-owned validation
catalogs in `Sources/Features/Accounts/Validation/` and
`Sources/Features/Hosts/Validation/`, with shared proof composition/runtime in
`Sources/Features/Validation/`. The selected Seal-only flows run through
config-backed `seal run --scenario ...`; Seal artifacts under `proof/`,
`reports/`, and `adapter/` are authoritative, while CodexPill compatibility
summaries and legacy live artifacts are diagnostic pointers only.

| Feature claim | Legacy live scenario | Seal scenario | Category |
| --- | --- | --- | --- |
| Add Account name dialog is presented and can be cancelled without mutating accounts. | `live-add-account-name-dialog-cancelled` | `add-account-name-dialog-cancelled` | Seal runtime/live scenario exists |
| Selecting an inactive account from the running menubar changes the active account after confirmation. | `live-account-switch` | `switch-account-changes-active-account` | Seal runtime/live scenario exists |
| Add Host panel accepts an invalid destination and emits validation feedback. | `live-add-host-destination-validation-failed` | `add-host-destination-validation-failed` | Seal runtime/live scenario exists |
| Switching an account through a remote-host submenu updates that host's active account. | `live-remote-host-switch` | `switch-account-on-host-changes-remote-active-account` | Seal runtime/live scenario exists |
| Scheduled refresh requests and completes without changing saved account identity or showing a blocking alert. | `live-scheduled-refresh` | `scheduled-refresh-preserves-account-catalog` | Seal runtime/live scenario exists |
| Persisted remote host refresh failure preserves fallback state, marks the host disconnected, and hides disconnected hosts from active account facts. | `persisted_host_refresh_failure` | `remote-host-refresh-failure-preserves-fallback-state` | Seal runtime/live scenario exists |
| Removing an active saved account confirms destructive removal and signs out active targets before deleting the saved snapshot. | Remove-account live validation in `MenuBarLiveValidationTests` | `remove-active-account-signs-out-before-deletion` | Seal runtime/live scenario exists |
| Active local and connected remote account cards group same-account targets and multiple remote hosts without real SSH credentials. | Multiple-host active-card live validation | `active-account-grouping-runtime-ready` | Seal runtime/live scenario exists |
| Baseline app starts, the menu opens, required App Controls render, inactive account switch wiring is present, and custom rows fit the rendered width. | `live-menu-open` | `baseline-menu-open-runtime-ready` | Seal runtime/live scenario exists |

## Coverage Map

### Menubar

| Claim | Category | Current proof or rationale |
| --- | --- | --- |
| Menu section order is `Active Account(s)`, `Accounts`, `More Accounts...`, App Controls, status, `Quit`. | Lower-layer test owns this better | Deterministic UI validation owns static menu shape and ordering better than Seal because no live event sequence is required. |
| Active local and verified remote accounts render in one unified active section, including collapsed same-account cards. | Seal runtime/live scenario exists | Covered by `active-account-grouping-runtime-ready`, with CodexPill-owned evidence and generic Seal event/snapshot rules. Deterministic projection tests remain lower-layer coverage. |
| Saved account rows render compactly, use submenus, and overflow to `More Accounts...`. | Lower-layer test owns this better | Deterministic UI snapshots prove row placement, overflow, labels, and submenu shape without needing live mutation. |
| App Controls contains `Add Account...`, `Hosts`, `Notifications`, `Refresh Interval`, `Preferences`, `About`, and `Quit`. | Lower-layer test owns this better | Static composition and labels are deterministic menu projection claims. |
| Busy work disables or routes conflicting actions through existing confirmation flow. | Seal scenario needed | Busy-state action gating is runtime menu behavior and should get a focused Seal scenario once the highest-risk account flows are covered. |
| Status messages appear below App Controls and above `Quit`. | Lower-layer test owns this better | Deterministic UI state projection should own this layout/copy claim. |
| Custom menubar rows stay flush with rendered menu width. | Seal runtime/live scenario exists | Covered by `live-menu-open` / `baseline-menu-open-runtime-ready`; Seal artifacts are authoritative for the baseline runtime gate. |
| Baseline app starts and the menu opens. | Seal runtime/live scenario exists | Covered by `live-menu-open` / `baseline-menu-open-runtime-ready`; Seal artifacts are authoritative for launch and menu-open readiness. |

### Status Bar

| Claim | Category | Current proof or rationale |
| --- | --- | --- |
| Closed-state status item shows icon, optional label, compact usage indicators, and tooltip content. | Lower-layer test owns this better | Formatting, status item snapshot state, and deterministic UI are better owners unless the claim depends on live pointer or shortcut delivery. |
| Text-on-hover stays visible while the pointer remains inside resized bounds. | Seal scenario needed | `live-status-item-hover` is a legacy live flow. It depends on real status-item runtime behavior and is a clear Seal candidate. |
| Reveal shortcut temporarily shows the label without opening the menu or changing saved display mode. | Manual/OS/environmental validation | Unit tests own shortcut policy and registration handling, but end-to-end global hot-key delivery and conflict behavior depend on macOS and local environment. |
| Configurable shortcut keeps the previous working shortcut when registration fails. | Lower-layer test owns this better | `GlobalShortcutRuntimeTests` can inject registration failure without depending on global OS state. |
| Usage bar pacing marker is visual only and does not change rows, ranking, switching, notifications, or persistence. | Lower-layer test owns this better | Unit and deterministic UI validation own this because it is projection and persistence policy, not a live interaction sequence. |
| Pacing prototype alternatives remain rejected for V1. | Deferred or not currently validated | `docs/features/pacing-prototype-notes.md` is product decision history, not a runtime claim to automate. |

### Accounts: Current And Catalog Presentation

| Claim | Category | Current proof or rationale |
| --- | --- | --- |
| Active local account shows matched saved account metadata, plan, usage, reset timing, and optional pacing markers. | Lower-layer test owns this better | Menu-state projection and formatting tests own the data-selection rules. |
| Unmatched live auth shows a clear empty/unmatched state instead of stale saved-account data. | Seal scenario needed | This is runtime/live account-observation behavior and should get a Seal scenario after switch and refresh flows are stable. |
| Remote active cards use verified remote target values and hide pending, failed, disconnected, or unverified hosts as active facts. | Seal runtime/live scenario exists | `active-account-grouping-runtime-ready` proves grouped verified targets and excludes unverified or disconnected hosts from active-card evidence. Lower-layer tests continue to own projection details. |
| Duplicate local and remote active accounts collapse into one card with location context. | Seal runtime/live scenario exists | Covered by `active-account-grouping-runtime-ready`. |
| Catalog rows use saved metadata, latest known rate limits, availability ranking, overflow behavior, and compact submenu content. | Lower-layer test owns this better | Deterministic UI and unit ranking/projection tests are better owners for static row shape and ordering. |
| Account submenu shows disabled email or `No email`, usage row, switch actions, rename, and remove. | Lower-layer test owns this better | Deterministic UI snapshots prove submenu content and action wiring metadata. |
| Inactive account live rows expose enabled `switchAccount:` action targets. | Seal runtime/live scenario exists | Folded into `baseline-menu-open-runtime-ready` for the baseline menu-open gate. |

### Accounts: Add Account

| Claim | Category | Current proof or rationale |
| --- | --- | --- |
| Add Account starts from `Add Account...`, presents the name dialog, and cancellation leaves account state unchanged. | Seal runtime/live scenario exists | Covered by `live-add-account-name-dialog-cancelled` / `add-account-name-dialog-cancelled`. |
| Empty or duplicate display names are blocked before browser/device sign-in starts. | Lower-layer test owns this better | `AddAccountWorkflowTests` owns duplicate-name preflight without live Codex mutation. |
| Isolated sign-in displays the device code in-app with `Copy Code`, `Open Browser`, and `Cancel`. | Lower-layer test owns this better | Alert factory and workflow tests own copy/actions and state transitions; a live scenario would require external Codex device-auth behavior. |
| `Copy Code` keeps the sign-in alert open while waiting. | Manual/OS/environmental validation | Clipboard behavior and real alert interaction are partly OS-level; copy/action shape is lower-layer tested. |
| Browser sign-in completion saves the captured isolated account without changing live local auth. | Manual/OS/environmental validation | Real browser/device auth completion is external and intentionally not mutated by normal validation. Integration tests own isolated snapshot behavior with injected seams. |
| Success alert offers `Use on This Mac` without a second switch confirmation and includes CLI restart warning when needed. | Seal scenario needed | Alert copy is lower-layer tested, but coordinator wiring from live Add Account success into the existing switch path is still a runtime gap. |
| Cancel, timeout, duplicate captured identity, live-auth mutation, save failure, quit, and stale temp homes clean sensitive temporary auth state. | Lower-layer test owns this better | Integration tests own cleanup and sensitive temp-path behavior without real auth payload exposure. |
| Raw auth payloads, tokens, and device codes are not logged or exposed beyond the intended device-code UI. | Lower-layer test owns this better | Secrets/logging contracts belong to code review, unit/integration assertions, and safety gates. Seal should not inspect raw secrets. |

### Accounts: Switch Account

| Claim | Category | Current proof or rationale |
| --- | --- | --- |
| `Switch on This Mac` asks for confirmation before activating the selected snapshot. | Seal runtime/live scenario exists | Covered as part of `live-account-switch` / `switch-account-changes-active-account`. |
| Local switch activates the saved snapshot, persists catalog state, relaunches Codex, and refreshes account data. | Seal runtime/live scenario exists | Covered by `switch-account-changes-active-account`; the Seal proof requires active-account snapshot change, `codex_relaunch_requested`, `post_switch_refresh_completed`, and `post_switch_refresh` evidence. Lower-layer switch workflow tests continue to own activation, persistence, matcher failure ordering, and injected process boundaries. |
| Add Account success routes through the existing local switch path without a second confirmation. | Seal scenario needed | This is runtime coordinator wiring across two feature flows and is not currently Seal-backed. |
| Remote switch installs a missing snapshot before switching, switches directly when already installed, refreshes remote app-server state, and verifies the expected account. | Lower-layer test owns this better | Injected integration tests own SSH/client command ordering and failure mapping more safely than a live Seal scenario against a real host. |
| Remote-host submenu dispatch changes the host's active account card. | Seal runtime/live scenario exists | Covered by `live-remote-host-switch` / `switch-account-on-host-changes-remote-active-account`. |
| Remote verification failure is surfaced instead of silently marking success. | Seal scenario needed | Current integration tests cover failure semantics; a focused Seal scenario would prove the runtime/live menu recovery path. |
| Real SSH, host-key, 2FA, password, passphrase, custom port, and user SSH config behavior works from the user's machine. | Manual/OS/environmental validation | These claims depend on the user's SSH environment and OpenSSH configuration. |

### Accounts: Remove Account

| Claim | Category | Current proof or rationale |
| --- | --- | --- |
| Remove requires destructive confirmation before active-account removal proceeds. | Seal runtime/live scenario exists | Covered for the confirmed active-account path by `remove-active-account-signs-out-before-deletion`. The cancel/no-mutation branch remains lower-layer or future focused Seal coverage. |
| Confirmed removal deletes the local saved snapshot and recomputes active saved-account match. | Lower-layer test owns this better | Repository/use-case tests own snapshot deletion and catalog recomputation. |
| Removing an active local account signs out local auth before deleting the snapshot. | Seal runtime/live scenario exists | `remove-active-account-signs-out-before-deletion` proves the selected fixture-owned local plus connected-remote target shape without real auth mutation. Lower-layer tests continue to own relaunch and failure ordering. |
| Removing an active connected remote account signs out the host before deleting the snapshot and no longer presents it as active. | Seal runtime/live scenario exists | `remove-active-account-signs-out-before-deletion` proves fixture-owned local and remote sign-out evidence before deletion without real SSH credentials. |
| Sign-out failure keeps the saved account and surfaces the failure. | Lower-layer test owns this better | Injected use-case tests own failure ordering and retention safely. |
| Removing a saved account does not delete remote snapshots already installed on remote hosts. | Lower-layer test owns this better | This is command/repository orchestration best proven with injected remote clients. |
| Remove actions are disabled while another account operation is busy. | Seal scenario needed | Runtime busy-state gating is visible and shared with other menu actions. |

### Accounts: Rename Account

| Claim | Category | Current proof or rationale |
| --- | --- | --- |
| Rename updates only the display label and leaves auth snapshot, Codex identity, active local auth, remote installed snapshots, plan, and rate limits unchanged. | Lower-layer test owns this better | Catalog persistence and identity immutability are repository/use-case claims. |
| Rename rejects empty and duplicate names, allows same-name no-op, and sorts the catalog by display name. | Lower-layer test owns this better | Pure validation and sorting policy should stay in unit/integration tests. |
| Rename uses a native text-input alert with specific copy. | Manual/OS/environmental validation | Native alert rendering and text-entry UX are residual manual UI concerns; copy shape can be lower-layer tested. |
| Rename actions are disabled while another account operation is busy. | Seal scenario needed | Shared runtime busy-state action gating should be covered by one menu busy-state Seal scenario. |

### Accounts: Refresh Accounts

| Claim | Category | Current proof or rationale |
| --- | --- | --- |
| Scheduled refresh refreshes active local account, emits completion/failure proof, preserves saved account identity, and shows no blocking alert. | Seal runtime/live scenario exists | Covered by `live-scheduled-refresh` / `scheduled-refresh-preserves-account-catalog`. |
| Background wake or timer refresh failures are logged but do not queue a blocking UI error. | Lower-layer test owns this better | `AccountsControllerTests` and integration boundaries can inject failures without real timers or OS wake state. |
| Inactive saved catalog refresh uses isolated `CODEX_HOME` app-server reads without mutating live auth. | Lower-layer test owns this better | The core claim is process/env isolation and app-server parsing; integration tests and manual probe documentation are the right owners. |
| App-server account/rate-limit parsing handles notification frames, JSON-RPC errors, transient retry, stale-limit preservation, and known plan-code mapping. | Lower-layer test owns this better | Parser/client tests own protocol details better than Seal. |
| Real Codex app-server availability and protocol shape on the user's installed Codex build. | Manual/OS/environmental validation | Depends on external Codex installation/version and should remain explicit in manual probes or compatibility issues. |

### Remote Hosts

| Claim | Category | Current proof or rationale |
| --- | --- | --- |
| `Hosts` entry point and per-account host actions appear in the App Controls and account submenu surfaces. | Lower-layer test owns this better | Deterministic UI validation owns static placement and labels. |
| Add Host panel captures optional display name and required SSH destination with documented layout and copy. | Manual/OS/environmental validation | Native panel text-entry UX and first-responder behavior are manual/OS-sensitive; deterministic tests can own copy where practical. |
| Invalid Add Host destination presents validation feedback before workflow continuation. | Seal runtime/live scenario exists | Covered by `live-add-host-destination-validation-failed` / `add-host-destination-validation-failed`. |
| Successful Add Host validates SSH and remote Codex readiness, then asks whether to install and switch the current account. | Seal scenario needed | The invalid path is Seal-backed, but success/follow-up runtime flow is not. Real SSH readiness remains environmental. |
| SSH destination accepts OpenSSH-compatible aliases and destinations but not raw SSH flags, and uses `BatchMode=yes`. | Lower-layer test owns this better | SSH command construction and destination validation should stay in SSH client/unit tests. |
| Non-interactive SSH failures explain setup must happen outside CodexPill. | Manual/OS/environmental validation | Failure causes depend on local SSH config, credentials, host-key trust, 2FA, and network. |
| Remote host refresh fallback preserves last-known account state while marking disconnected. | Seal runtime/live scenario exists | Covered by `persisted_host_refresh_failure` / `remote-host-refresh-failure-preserves-fallback-state`. |
| Reachable verification failures remain connected and surface verification failure. | Seal scenario needed | Runtime recovery state should be Seal-backed after the happy path. |

### Notifications

| Claim | Category | Current proof or rationale |
| --- | --- | --- |
| Notification policy selects one best usable saved account, suppresses weak candidates, ignores future resets, and evaluates local plus verified remote active accounts. | Lower-layer test owns this better | Pure policy/ranking is a unit-test responsibility. |
| Notification dedupe suppresses repeat delivery until the account becomes active locally or on a verified remote host, and persists across launches. | Lower-layer test owns this better | State and persistence tests own this without OS notification delivery. |
| Enabling notification modes requests permission only on first enable; permission recovery uses `Enable Notifications...`. | Manual/OS/environmental validation | macOS authorization prompts and System Settings handoff are OS-level. Integration tests can own injected authorization-state policy. |
| Delivered notification copy explains the active account, target, limit summary, and fallback account. | Lower-layer test owns this better | Rendering from policy output is deterministic. |
| Notification actions offer `Use on This Mac` and `Use on <remote host>`, falling back to one best option when needed. | Seal scenario needed | Action dispatch from a delivered notification into local/remote switch paths is runtime behavior and not currently Seal-backed. |

## Legacy Runtime Validation Not Yet Seal-Backed

These legacy flows are still useful but are not currently Seal-backed:

| Legacy flow | Related claim | Proposed disposition |
| --- | --- | --- |
| `live-status-item-hover` | Text-on-hover remains visible while pointer stays inside resized status-item bounds. | Promote to a status-bar Seal scenario if live hover remains a release-readiness gate. |
| Remove-account live validation in `MenuBarLiveValidationTests` | Active local and remote targets are signed out before saved account deletion. | Migrated to `remove-active-account-signs-out-before-deletion`; keep lower-layer and harness safety coverage. |

## Prioritized Migration Backlog

1. **Status item hover Seal scenario**: migrate `live-status-item-hover` if hover behavior remains a live release gate.
2. **Add Account success-to-switch Seal scenario**: cover `Use on This Mac` routing through the existing switch path without a second confirmation.
3. **Remote verification failure Seal scenario**: prove runtime failure surfacing after a remote switch verification mismatch.
4. **Busy-state gating Seal scenario**: cover disabled or confirmation-routed actions during active account operations.
5. **Notification action dispatch Seal scenario**: cover notification actions routing into local or remote switch paths when macOS notification delivery can be controlled without flakiness.

## Not Recommended For Seal

The following should remain lower-layer or manual unless the product contract
changes:

- Auth snapshot parsing, persistence, and sensitive temporary auth cleanup.
- App-server JSON-RPC parsing, retry, stale-limit preservation, and plan-code
  normalization.
- SSH command mapping, install/switch command ordering, and injected remote
  failure mapping.
- Notification ranking, dedupe, settings persistence, and copy rendering from
  policy output.
- Native alert text entry, clipboard interaction, global hot-key conflicts,
  macOS notification authorization, real browser device-auth completion, real
  SSH credentials, and installed Codex app-server availability.
