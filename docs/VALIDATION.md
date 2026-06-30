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

The current clean-main manifest contains fifteen deterministic scenarios:

```bash
make verify-ui SCENARIO=hosted-menu-default
make verify-ui SCENARIO=menu-busy-status
make verify-ui SCENARIO=menu-unmatched-active-account
make verify-ui SCENARIO=menu-empty-catalog
make verify-ui SCENARIO=menu-account-overflow
make verify-add-account-name-scenario
make verify-rename-scenario
make verify-ui SCENARIO=launch-at-login-menu-states
make verify-ui SCENARIO=status-bar-icon-text-visible
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
- `rename-account-label-only`: changed-feature non-regression for Rename
  Account. It proves through focused unit tests that rename changes only the
  CodexPill display label, preserves saved auth snapshot identity, plan, and
  rate-limit state, and rejects empty or duplicate names; it does not prove
  native rename dialog interaction, live auth mutation, remote host mutation, or
  live macOS menu-bar behavior.
- `launch-at-login-menu-states`: changed-feature non-regression for App Controls
  presentation. It proves that enabled, disabled, requires-approval, and
  unavailable Launch at Login states map to truthful row copy, checked state,
  and action selectors through a structured state matrix; it does not register
  or unregister the real macOS login item, open System Settings, prove a signed
  app appears in Login Items, prove the enable confirmation workflow, or prove
  live macOS menu-bar behavior.
- `status-bar-icon-text-visible`: changed-feature non-regression for Status Bar
  closed-state presentation. It proves that a synthetic active account produces
  an icon-and-text status item runtime snapshot with displayed title
  `S 42% W 68%`; it does not prove live menubar screen capture, native
  hittability, hover expansion, shortcut reveal, temporal behavior, or
  multiple-display layout behavior.
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
- `make verify-add-account-name-scenario` for focused Add Account name
  validation unit proof;
- `make verify-rename-scenario` for focused Rename Account unit proof;
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
