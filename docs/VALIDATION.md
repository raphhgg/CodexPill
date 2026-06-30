# Validation

CodexPill protects user trust by validating account switching, account storage,
remote-host operations, notification behavior, and privacy boundaries through
unit and integration tests.

## Validation Contract

- Tests and validation fixtures must not touch real user data or real product
  processes unless a live mutation scenario is explicitly opted into.
- Tests must use temporary paths, isolated app-support directories, injected
  clients, and fakes for process or SSH side effects.
- Auth snapshots, raw auth payloads, tokens, API keys, and device codes must not
  be logged, committed, or emitted in diagnostics.
- Product behavior that changes account state must have deterministic coverage
  near the owning feature boundary.
- UI copy and menu composition changes should be covered by menu projection or
  presentation tests where possible.

## Kite Scenario Manifest

CodexPill exposes reusable product scenarios for Kite in `.kite/scenarios.json`.
The manifest is product-owned: CodexPill owns scenario IDs, commands, fixture
state, and product semantics; Kite owns manifest validation, artifact
validation, receipts, and reports.

The manifest uses Kite's v2 feature-scenario contract:

- each scenario names its owning feature;
- each scenario maps to one or more acceptance criteria;
- each scenario records Validation Intent before execution;
- each scenario declares non-regression policy separately from product truth.

Feature-owned proof contracts live near the feature in `docs/features/`.
[Feature Validation Scenarios](features/validation-scenarios.md) is the
cross-feature scenario index and promotion tracker. A scenario should move from
that inventory into `.kite/scenarios.json` only when its owning feature doc has
concrete acceptance criteria, proof rows, fixtures, command, artifacts, privacy
rules, non-claims, and degraded-proof rules.

The current clean-main manifest contains thirty-six deterministic scenarios:

```bash
make verify-ui SCENARIO=hosted-menu-default
make verify-ui SCENARIO=menu-busy-status
make verify-diagnostics-export-confirmation-scenario
make verify-notifications-permission-denied-menu-state-scenario
make verify-notifications-account-available-policy-scenario
make verify-notifications-current-runs-out-action-scenario
make verify-notifications-dedupe-after-delivery-scenario
make verify-ui SCENARIO=menu-unmatched-active-account
make verify-ui SCENARIO=menu-empty-catalog
make verify-ui SCENARIO=menu-account-overflow
make verify-add-account-name-scenario
make verify-add-account-isolated-success-scenario
make verify-add-account-failure-cleanup-scenario
make verify-switch-account-local-confirmed-scenario
make verify-switch-account-remote-install-verify-scenario
make verify-remote-host-add-panel-validation-scenario
make verify-remote-host-install-switch-current-account-scenario
make verify-remote-host-verification-failure-scenario
make verify-remote-host-rate-limit-fallback-scenario
make verify-remove-account-active-targets-sign-out-scenario
make verify-remove-account-signout-failure-keeps-control-scenario
make verify-rename-scenario
make verify-refresh-inactive-isolated-status-scenario
make verify-refresh-active-relinks-same-account-scenario
make verify-ui SCENARIO=launch-at-login-menu-states
make verify-launch-at-login-enable-confirmation-scenario
make verify-ui SCENARIO=status-bar-icon-text-visible
make verify-status-bar-hover-label-scenario
make verify-status-bar-shortcut-reveal-scenario
make verify-status-bar-usage-bars-preferences-scenario
make verify-ui SCENARIO=token-usage-off-hidden
make verify-ui SCENARIO=token-usage-ready-card
make verify-token-usage-parser-scenario
make verify-token-usage-cache-scenario
make verify-token-usage-privacy-scenario
make verify-ui SCENARIO=token-usage-loading-progress
```

Those commands write deterministic artifacts under their matching
`build/verification/<scenario>/` directories. UI scenarios usually write a
hosted validation screenshot, `ui-tree.json`, and `scenario-summary.json`.
Unit scenarios write focused test output and a scenario summary. Some scenarios
also write feature-specific structured artifacts such as state matrices or
runtime state snapshots. This is deterministic product evidence, not SwiftUI
preview proof and not live macOS menu-bar proof. Preview and live scenarios
should be added only when their product-local commands and fixtures exist on
the branch being validated.

There is intentionally no `verify-ui-live` command. A live or preview scenario
must first be declared in `.kite/scenarios.json` with explicit opt-in,
privacy, cleanup, and non-claim rules before CodexPill exposes a runnable proof
command for it.

Current deterministic scenarios:

- `hosted-menu-default`: smoke non-regression for the default hosted menu
  projection. It should run before handoff when menubar UI, scenario fixtures,
  or the validation manifest changes.
- `menu-busy-status`: changed-feature non-regression for Menubar busy-state
  presentation. It proves that the hosted menu shows the busy status before
  `Quit` and marks `Add Account…` disabled; it does not prove workflow action
  dispatch, confirmation routing, event-log ordering, live Codex workflow state,
  or live macOS menu-bar behavior.
- `diagnostics-export-confirmation`: changed-feature non-regression for
  Diagnostics export confirmation and privacy. It proves through focused menu,
  alert, and diagnostics builder tests that `Diagnostics…` is present in the
  menu, export shows a redacted-support disclosure before building a report,
  cancellation writes no report, confirmation builds a per-export aliased
  support artifact, and report construction rejects or aliases sensitive
  evidence; it does not prove live `NSSavePanel` rendering, real file writing,
  real local logs/history inspection, or live macOS menu-bar behavior.
- `notifications-permission-denied-menu-state`: changed-feature non-regression
  for Notifications permission recovery. It proves through focused menu and
  runtime tests that denied macOS notification permission shows
  `Enable in macOS Settings…`, renders notification modes effectively off and
  disabled, opens System Settings through a fake launcher, preserves saved
  CodexPill notification preferences, and does not request authorization again;
  it does not prove live System Settings, live notification permission dialogs,
  native click automation, or live macOS menu-bar behavior.
- `notifications-account-available-policy`: changed-feature non-regression for
  Account Available notifications. It proves through focused policy and
  workflow tests that Account Available fires only for inactive fallback
  accounts becoming useful again, skips first-saved, only-saved,
  already-active, barely usable, and non-fallback accounts, renders the simple
  available-again payload with no direct actions, and suppresses repeated
  delivery until activation resets state; it does not prove live macOS
  notification delivery, native notification UI, or Current Runs Out action
  routing.
- `notifications-current-runs-out-action`: changed-feature non-regression for
  Current Runs Out notification actions. It proves through focused policy,
  payload rendering, workflow response, and runtime validation tests that local
  and remote active-account exhaustion can trigger Current Runs Out, rendered
  copy names the exhausted target and fallback account, local and remote direct
  actions are exposed, stale responses re-check current state before switching,
  safer current targets are substituted with explanatory copy, stale remote
  requests are dropped, and switch failures surface through the app; it does not
  prove live macOS notification delivery, native Notification Center rendering,
  real user clicks, real account data, real remote hosts, or real switching.
- `notifications-dedupe-after-delivery`: changed-feature non-regression for
  delivered account notification dedupe. It proves through focused state,
  workflow delivery, settings persistence, and runtime activation tests that a
  delivered notification records reason/window state, disarms repeated delivery
  across later windows, and re-arms only after CodexPill observes that account
  become active locally or on a verified remote host; it does not prove live
  macOS notification delivery, native Notification Center rendering, real user
  clicks, real account data, real remote hosts, or real switching.
- `menu-unmatched-active-account`: smoke non-regression for Active Account
  truth. It proves that saved accounts remain catalog rows and are not presented
  as active when the active local auth state is unmatched.
- `menu-empty-catalog`: changed-feature non-regression for Account Catalog
  empty-state truth. It proves that an empty catalog guides toward Add Account
  and does not expose saved-account rows or switch actions.
- `menu-account-overflow`: changed-feature non-regression for Account Catalog
  overflow truth. It proves that hidden saved accounts remain discoverable under
  `More Accounts…` and keep the same submenu action shape as visible rows.
- `add-account-name-validation`: changed-feature non-regression for Add Account
  name validation. It proves through focused unit tests that empty,
  whitespace-only, and case-insensitive duplicate names are rejected before
  isolated sign-in starts, and that display-name errors return to the Add
  Account name-recovery flow; it does not prove native Add Account panel
  rendering, disabled `Continue` state, browser/device-code sign-in, live auth
  mutation, or live macOS menu-bar behavior.
- `add-account-isolated-success`: changed-feature non-regression for Add Account
  isolated success. It proves through focused fake-client workflow/controller
  tests that captured isolated auth is saved as an inactive account, the active
  This Mac account is preserved, usable metadata and rate limits are hydrated
  through the saved-account status client, the isolated login session is
  cleaned after success, and the success action can route to local switch
  without a second confirmation; it does not prove native device-code UI,
  browser sign-in, live Codex auth/app-server/process relaunch, terminal
  failure cleanup, or live macOS menu-bar behavior.
- `add-account-failure-cleanup`: changed-feature non-regression for Add
  Account terminal failure handling. It proves through focused fake-client
  workflow tests, path cleanup tests, and startup diagnostic redaction tests
  that cancel, auth capture timeout, login verification failure, live-auth
  mutation, duplicate captured identity, and save failures clean isolated state,
  save no unintended account, keep This Mac unchanged, remove only stale old
  CodexPill isolated `CODEX_HOME` directories, and redact device codes and auth
  URL query strings from startup failure diagnostics; it does not prove native
  device-code UI, browser sign-in, live Codex auth, live process termination,
  real app quit handling, app crash simulation, or live macOS menu-bar
  behavior.
- `switch-account-local-confirmed`: changed-feature non-regression for local
  Switch Account. It proves through focused fake auth/process runtime proof,
  workflow tests, observer tests, Add Account action routing, alert copy tests,
  and silent refresh tests that `Switch on This Mac` asks for confirmation
  before local auth mutation, cancellation leaves This Mac unchanged,
  confirmation activates the selected saved snapshot, persists account state,
  relaunches Codex through a fake process client, records switch workflow
  events, can be reused by `Use on This Mac` without a second confirmation, and
  has covered post-switch refresh behavior; it does not prove native
  confirmation panel rendering, click automation, live Codex relaunch, live
  app-server refresh, remote host switching, or live macOS menu-bar behavior.
- `switch-account-remote-install-verify`: changed-feature non-regression for
  remote Switch Account. It proves through fake-host workflow tests, SSH
  contract fixtures, controller relink proof, and verifier tests that missing
  or stale remote snapshots are installed before switching, already-installed
  snapshots switch directly, remote Codex app-server refresh occurs before
  verification, stale status is retried, only the expected account is accepted
  as verified, mismatch or ambiguity is surfaced as not verified, and fresher
  active local auth is relinked before remote mutation when needed; it does not
  exercise a live SSH host, live remote Codex app-server, real remote auth
  mutation, native menu presentation, native click routing, remote verification
  failure menu projection, or live macOS menu-bar behavior.
- `remote-host-add-panel-validation`: changed-feature non-regression for Remote
  Hosts Add Host validation. It proves through focused form-state, alert-copy,
  and SSH contract tests that Add Host stays disabled until validation succeeds
  for the same trimmed destination, unknown host, non-interactive SSH,
  unreachable SSH, and not-Codex-ready failures surface actionable disabled
  states, and SSH validation uses non-interactive BatchMode plus Codex
  CLI/app-server readiness and writable directory checks; it does not prove
  native Add Host panel screenshot rendering, first responder focus, click
  automation, live SSH, live Codex app-server behavior, real remote filesystem
  mutation, install-and-switch follow-up, or live macOS menu-bar behavior.
- `remote-host-install-switch-current-account`: changed-feature non-regression
  for Remote Hosts setup follow-up. It proves through focused runtime,
  workflow, and alert-copy tests that cancelling the install-current-account
  follow-up leaves no pending host state, confirming setup installs missing
  snapshots before switching the current active account, refreshes the remote
  app-server, verifies status, and persists desired, verified, and installed
  host/account state; it does not prove native panel rendering, focus, click
  automation, live SSH, live Codex app-server behavior, real remote auth
  mutation, real remote filesystem mutation, remote verification failure
  presentation, or live macOS menu-bar behavior.
- `remote-host-verification-failure`: changed-feature non-regression for Remote
  Hosts verification truth. It proves through focused verifier, runtime,
  workflow, and menu projection tests that different or ambiguous remote
  identities are marked not verified, failed/read-error verification clears
  verified active remote account state, detected accounts remain recoverable
  through host management, and failed or unverified hosts do not render primary
  active remote cards; it does not prove live SSH, live Codex app-server
  behavior, real remote auth mutation, real remote filesystem mutation, native
  click automation, live menu-bar interaction, remote rate-limit fallback, or
  live macOS menu-bar behavior.
- `remote-host-rate-limit-fallback`: changed-feature non-regression for Remote
  Hosts rate-limit display truth. It proves through focused rate-limit
  resolution, account catalog projection, menu state, and runtime validation
  tests that meaningful verified remote limits win, missing/zeroed/partial/
  expired/suspicious remote windows fall back to meaningful saved-account
  windows, and fallback matching is scoped by canonical saved identity; it does
  not prove live SSH, live Codex app-server behavior, real remote auth
  mutation, real remote filesystem mutation, native click automation, final
  native menu pixels for fallback labels, or live macOS menu-bar behavior.
- `remove-account-active-targets-sign-out`: changed-feature non-regression for
  Remove Account active-target success. It proves through runtime, delete
  use-case, and alert-copy tests that removing an account active on This Mac and
  on a connected remote host asks for destructive confirmation, signs out local
  auth, requests Codex relaunch through a fake process client, signs out active
  remote host state, deletes the saved snapshot and catalog row only after
  required sign-outs succeed, and no longer presents the removed account as
  active locally or remotely; it does not prove native confirmation panel
  rendering, click automation, live Codex relaunch, live SSH sign-out, real
  remote auth mutation, sign-out failure handling, or live macOS menu-bar
  behavior.
- `remove-account-signout-failure-keeps-control`: changed-feature
  non-regression for Remove Account required sign-out failure. It proves through
  focused local use-case and runtime workflow tests that failed local sign-out
  prevents snapshot deletion and catalog persistence, failed remote sign-out
  keeps the saved-account catalog row and active remote state intact, and the
  real sanitized failure is shown to the user; it does not prove native
  confirmation panel rendering, click automation, live Codex relaunch, live SSH
  sign-out, real remote auth mutation, remote inactive snapshot deletion, or
  live macOS menu-bar behavior.
- `rename-account-label-only`: changed-feature non-regression for Rename
  Account. It proves through focused unit tests that rename changes only the
  CodexPill display label, preserves saved auth snapshot identity, plan, and
  rate-limit state, and rejects empty or duplicate names; it does not prove
  native rename dialog interaction, live auth mutation, remote host mutation, or
  live macOS menu-bar behavior.
- `refresh-inactive-isolated-status`: changed-feature non-regression for
  Refresh Accounts inactive saved-account status reads. It proves through
  focused use-case, app-server contract, and isolated path tests that inactive
  saved accounts refresh through isolated saved-account status reads without
  mutating live auth, complete isolated reads update metadata and rate limits,
  failed, missing, or suspicious isolated reads preserve previous meaningful
  limits, app-server success requires the rate-limit response, and temporary
  isolated `CODEX_HOME` state uses root `auth.json` and cleans itself up; it
  does not prove live Codex app-server execution with real accounts, real auth
  snapshots, remote inactive-account refresh, menu projection, or live macOS
  menu-bar behavior.
- `refresh-active-relinks-same-account`: changed-feature non-regression for
  Refresh Accounts active local snapshot relinking. It proves through focused
  active-refresh and matcher unit tests that same-account refresh with a changed
  auth fingerprint saves current live auth into the matched saved account,
  preserves the saved account shape, and refuses ambiguous or different
  identities before overwriting saved snapshots; it does not prove live Codex app-server
  execution, real auth snapshots, remote install/switch preflight relink, menu
  projection, or live macOS menu-bar behavior.
- `launch-at-login-menu-states`: changed-feature non-regression for App Controls
  presentation. It proves that enabled, disabled, requires-approval, and
  unavailable Launch at Login states map to truthful row copy, checked state,
  and action selectors through a structured state matrix; it does not register
  or unregister the real macOS login item, open System Settings, prove a signed
  app appears in Login Items, prove the enable confirmation workflow, or prove
  live macOS menu-bar behavior.
- `launch-at-login-enable-confirmation`: changed-feature non-regression for App
  Controls workflow behavior. It proves through fake login-item controller and
  confirmation presenter tests that enabling asks for confirmation before fake
  registration, cancelling leaves the fake login item disabled, disabling
  unregisters directly without confirmation, and registration failure reports a
  truthful error without claiming enabled state; it does not register or
  unregister the real macOS login item, prove signed-app Login Items visibility,
  or exercise live menu-bar/System Settings UI.
- `status-bar-icon-text-visible`: changed-feature non-regression for Status Bar
  closed-state presentation. It proves that a synthetic active account produces
  an icon-and-text status item runtime snapshot with displayed title
  `S 42% W 68%`; it does not prove live menubar screen capture, native
  hittability, hover expansion, shortcut reveal, temporal behavior, or
  multiple-display layout behavior.
- `status-bar-hover-label`: changed-feature non-regression for Status Bar
  hover behavior. It proves through fake runtime hover events and validation
  snapshots that text-on-hover mode starts hover polling, fake hover enter shows
  the synthetic status title `S 42% W 68%`, fake hover leave hides it, lifecycle
  events are emitted and recorded through validation, and saved display mode is
  not mutated; it does not prove native mouse movement, real pointer bounds,
  live menubar screen capture, native hittability, or multiple-display layout
  behavior.
- `status-bar-shortcut-reveal`: changed-feature non-regression for Status Bar
  reveal shortcut behavior. It proves through fake global shortcut callbacks,
  status item runtime tests, and validation snapshots that first reveal shows
  the synthetic status title `S 42% W 68%` from icon-only mode, repeat press
  collapses it, shortcut lifecycle events are emitted and recorded through
  validation, and saved display mode is not mutated; it does not prove live
  Carbon/global hotkey registration, native keyboard input, system shortcut
  conflicts, live menubar capture, or native hittability.
- `status-bar-usage-bars-preferences`: changed-feature non-regression for
  Status Bar presentation preferences. It proves through settings, menu
  builder, deterministic UI validation, and coordinator action tests that Menu
  Bar Label, Icon Style, Show Pace Markers, Accent Color, and Use Default
  controls update presentation settings/projections only while preserving the
  account catalog, active account, and isolated auth-file bytes; it does not
  prove live color-panel choice, native menu-bar clicks, live menubar capture,
  or native hittability.
- `token-usage-off-hidden`: changed-feature non-regression for Token Usage card
  disabled-state presentation. It proves that the hosted active-account area
  omits the Token Usage card and scanner-derived copy when Token Usage is off;
  it does not prove live scanner lifecycle or duplicate-scan prevention.
- `token-usage-ready-card`: changed-feature non-regression for Token Usage card
  presentation. It proves that synthetic local aggregate data renders in the
  active account area without account, workspace, organization, remote-host,
  raw-session, or prompt attribution.
- `token-usage-parser-aggregation`: changed-feature non-regression for Token
  Usage parser aggregation. It proves through focused synthetic JSONL scanner
  tests that token-count rows aggregate into daily buckets, repeated cumulative
  totals do not inflate usage, malformed or oversized rows are skipped safely,
  and progress/cache contribution metadata avoids raw session paths; it does
  not prove Token Usage UI presentation, diagnostics export privacy, real local
  Codex history, saved-account attribution, live scanner lifecycle, or live
  macOS menu-bar behavior.
- `token-usage-cache-first`: changed-feature non-regression for Token Usage
  cache/runtime behavior. It proves through focused synthetic cache, provider,
  and runtime tests that cached aggregate data is reused before scanner work,
  repeated runtime refreshes do not duplicate load jobs, loaded chart data stays
  visible during refresh progress, and forced refresh reparses only new or
  changed eligible selected-period files; it does not prove Token Usage UI
  rendering, diagnostics export privacy, real local history, saved-account
  attribution, or live macOS menu-bar behavior.
- `token-usage-privacy-no-raw-session`: changed-feature non-regression for
  Token Usage diagnostics privacy. It proves through focused diagnostics export
  tests that support artifacts expose only enabled state, period, chart style,
  load state, bucket count, and aggregate token totals, while prompt content,
  raw session rows, local paths, account identifiers, emails, hostnames, auth
  material, and token-like values are rejected; it does not prove live save
  panel confirmation, real local history, Token Usage UI rendering, or live
  macOS menu-bar behavior.
- `token-usage-loading-progress`: changed-feature non-regression for Token
  Usage first-load feedback. It proves that synthetic file-count progress
  renders in the active account area without fake percentages, account,
  workspace, organization, remote-host, local path, or raw-session attribution.

## Product Validation Adapter

CodexPill's Product Validation Adapter is the product-local layer that makes
those manifest scenarios runnable. It is not generic Kite Harness code.

The adapter currently includes:

- `.kite/scenarios.json` for feature, acceptance criteria, Validation Intent,
  artifact, privacy, and non-regression declarations;
- `make verify-ui SCENARIO=<scenario>` for deterministic hosted-menu proof;
- `make verify-diagnostics-export-confirmation-scenario` for focused
  Diagnostics export confirmation and redacted-support artifact proof;
- `make verify-notifications-permission-denied-menu-state-scenario` for focused
  Notifications denied-permission menu and recovery proof;
- `make verify-notifications-account-available-policy-scenario` for focused
  Account Available notification policy and delivery proof;
- `make verify-notifications-current-runs-out-action-scenario` for focused
  Current Runs Out notification action and stale-response proof;
- `make verify-notifications-dedupe-after-delivery-scenario` for focused
  delivered notification dedupe and activation re-arm proof;
- `make verify-status-bar-hover-label-scenario` for focused Status Bar hover
  runtime event and validation snapshot proof;
- `make verify-status-bar-shortcut-reveal-scenario` for focused Status Bar
  shortcut callback and reveal/collapse proof;
- `make verify-status-bar-usage-bars-preferences-scenario` for focused Status
  Bar preference mapping, deterministic projection, and account-state
  preservation proof;
- `make verify-add-account-name-scenario` for focused Add Account name
  validation unit proof;
- `make verify-add-account-isolated-success-scenario` for focused Add Account
  fake-client workflow-event proof;
- `make verify-add-account-failure-cleanup-scenario` for focused Add Account
  failure cleanup workflow-event proof;
- `make verify-switch-account-local-confirmed-scenario` for focused local
  Switch Account workflow-event proof;
- `make verify-switch-account-remote-install-verify-scenario` for focused
  remote Switch Account workflow-event proof;
- `make verify-remote-host-add-panel-validation-scenario` for focused Remote
  Hosts Add Host contract-fixture proof;
- `make verify-remote-host-install-switch-current-account-scenario` for focused
  Remote Hosts setup follow-up workflow-event proof;
- `make verify-remote-host-verification-failure-scenario` for focused Remote
  Hosts verification failure unit/menu proof;
- `make verify-remote-host-rate-limit-fallback-scenario` for focused Remote
  Hosts rate-limit fallback contract-fixture proof;
- `make verify-remove-account-active-targets-sign-out-scenario` for focused
  Remove Account active-target workflow-event proof;
- `make verify-remove-account-signout-failure-keeps-control-scenario` for
  focused Remove Account required sign-out failure workflow-event proof;
- `make verify-rename-scenario` for focused Rename Account unit proof;
- `make verify-refresh-inactive-isolated-status-scenario` for focused Refresh
  Accounts inactive isolated status proof;
- `make verify-refresh-active-relinks-same-account-scenario` for focused
  Refresh Accounts active relink proof;
- `make verify-launch-at-login-enable-confirmation-scenario` for focused App
  Controls Launch at Login confirmation and unregister workflow proof;
- `make verify-token-usage-parser-scenario` for focused Token Usage scanner
  contract-fixture proof;
- `make verify-token-usage-cache-scenario` for focused Token Usage cache and
  runtime contract-fixture proof;
- `make verify-token-usage-privacy-scenario` for focused Token Usage
  diagnostics-export privacy proof;
- `MenuBarValidationSupport` for semantic menu snapshots and hosted UI
  artifacts;
- `InMemoryRemoteHostClient` for isolated remote-host behavior in deterministic
  tests and validation runs;
- `NoopCodexAppProcessClient` for validation runs that must not relaunch the
  real Codex app;
- `ValidationFixtureBootstrap` for loading product-owned validation fixture
  state into isolated settings;
- `MenuBarValidationObserver` and `MenuBarValidationConfiguration` as dormant
  runtime-event instrumentation for a future explicit live/preview scenario.

The observer/configuration path is disabled unless validation output
environment variables are set. It does not become a reusable Kite scenario until
`.kite/scenarios.json` declares the scenario and its live opt-in, privacy,
cleanup, and non-claim rules.

## Main Local Gate

Run the default test suite before shipping changes:

```bash
make test
```

## Product Invariants

### Account Catalog

- Saved account snapshots are stored in CodexPill-owned app-support state.
- Duplicate saved-account names are rejected before sign-in starts.
- Empty saved-account names are blocked before sign-in starts, with the user kept
  in the Add Account naming flow.
- Terminal Add Account failures clear pending state so the user is not trapped in
  repeated completion alerts.
- Removing an account that is active on a local or remote target signs that
  target out before deleting the saved snapshot.

### Account Switching

- Local switching writes the selected saved snapshot to the active Codex auth
  surface and requests a Codex app refresh or relaunch through an injected
  process client.
- Remote switching uses the configured SSH host adapter and verifies the
  expected account before presenting the host as active.
- Stale notification actions must re-check current availability before switching
  a local or remote target.

### Account Refresh

- Refresh reads account metadata and rate limits from the Codex app-server
  surface when available.
- Refresh failures preserve last-known account state and surface recoverable
  error information without blocking normal menu use.
- Saved account identity matching must avoid merging distinct accounts that only
  share ambiguous metadata.

### Remote Hosts

- Add Host validates SSH destination input before enabling continuation.
- Remote hosts must not be shown as connected when verification fails.
- Remote auth snapshots may only be copied to user-configured hosts selected by
  the user.

### Notifications

- Notification workflows respect the app's notification preferences and macOS
  authorization state.
- Account Available notifications are only for inactive fallback accounts
  becoming useful again; first-saved or already-active accounts must not trigger
  them.
- If app notification workflows are disabled, the menu exposes a simple Enable
  Notifications action.
- If macOS authorization is denied, Enable Notifications opens System Settings
  rather than pretending to grant permission itself.

### App Controls

- Launch at Login reflects the native macOS login-item state; CodexPill must not
  show it as enabled after a failed registration attempt.
- Enabling Launch at Login must require an explicit confirmation before
  CodexPill asks macOS to register the app as a login item.
- When macOS requires approval for the login item, the menu opens System Settings
  instead of pretending CodexPill can approve the permission itself.
- When the login item state is unavailable, the menu keeps the item unchecked
  and opens System Settings instead of leaving the user at a dead end.

### Privacy

- Logs and validation artifacts must redact private paths, raw auth material,
  token-like values, and account identifiers unless the value is already a
  synthetic fixture.
- Diagnostic exports must require explicit user confirmation before a support
  artifact is built or written; cancelling the disclosure must leave no exported
  report behind.
- Demo and screenshot data must use synthetic accounts, hosts, and emails.

### Token Usage

- Cached Token Usage buckets may be reused only when they cover the requested
  current period; the bucket labeled as today must match today's local usage
  window rather than the last day from a stale persisted cache.
