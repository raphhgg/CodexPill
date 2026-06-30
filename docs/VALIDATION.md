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

Feature-level target scenarios are tracked in
[Feature Validation Scenarios](features/validation-scenarios.md). A scenario
should move from that inventory into `.kite/scenarios.json` only when it is
runnable and has concrete fixtures, command, artifacts, privacy rules,
non-claims, and degraded-proof rules.

The current clean-main manifest contains three deterministic hosted-menu
scenarios:

```bash
make verify-ui SCENARIO=hosted-menu-default
make verify-ui SCENARIO=menu-unmatched-active-account
make verify-ui SCENARIO=menu-empty-catalog
```

Those commands write hosted validation screenshots, `ui-tree.json`, and
`scenario-summary.json` under their matching `build/verification/<scenario>/`
directories. This is deterministic UI evidence, not SwiftUI preview proof and
not live macOS menu-bar proof. Preview and live scenarios should be added only
when their product-local commands and fixtures exist on the branch being
validated.

There is intentionally no `verify-ui-live` command. A live or preview scenario
must first be declared in `.kite/scenarios.json` with explicit opt-in,
privacy, cleanup, and non-claim rules before CodexPill exposes a runnable proof
command for it.

Current deterministic scenarios:

- `hosted-menu-default`: smoke non-regression for the default hosted menu
  projection. It should run before handoff when menubar UI, scenario fixtures,
  or the validation manifest changes.
- `menu-unmatched-active-account`: smoke non-regression for Active Account
  truth. It proves that saved accounts remain catalog rows and are not presented
  as active when the active local auth state is unmatched.
- `menu-empty-catalog`: changed-feature non-regression for Account Catalog
  empty-state truth. It proves that an empty catalog guides toward Add Account
  and does not expose saved-account rows or switch actions.

## Product Validation Adapter

CodexPill's Product Validation Adapter is the product-local layer that makes
those manifest scenarios runnable. It is not generic Kite Harness code.

The adapter currently includes:

- `.kite/scenarios.json` for feature, acceptance criteria, Validation Intent,
  artifact, privacy, and non-regression declarations;
- `make verify-ui SCENARIO=<scenario>` for deterministic hosted-menu proof;
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
