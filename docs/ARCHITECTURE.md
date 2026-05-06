# Architecture

CodexPill is a local-first macOS menubar app for Codex account switching and per-account rate-limit tracking.

This document owns codebase structure and dependency boundaries. Product behavior and UX contracts live in [features](features/README.md).

## Source Shape

The source tree is organized by responsibility:

- `Sources/App/`
- `Sources/Features/Accounts/`
- `Sources/Features/Hosts/`
- `Sources/Features/MenuBar/`
- `Sources/Features/Validation/`
- `Sources/Core/Configuration/`
- `Sources/Core/Models/`
- `Sources/Platform/Codex/`
- `Sources/Platform/Hosts/`
- `Sources/Platform/Persistence/`

The intended dependency direction is:

```text
App -> Features -> Platform
App -> Core
Features -> Core
Platform -> Core
```

`Core` must not depend on `Features`, `Platform`, or `App`.

## Ownership Rules

### App

`Sources/App/` owns bootstrap, lifecycle wiring, and dependency assembly.

It does not own menu composition, account workflows, file I/O policy, Codex process control, or Codex protocol details.

### Features

`Sources/Features/` owns product behavior and presentation-neutral workflow policy.

`Features/Accounts` owns saved-account state, active-account resolution, account availability, account notifications policy, account workflows, and the account feature composition boundary.

Key boundaries:

- `AccountsFeatureFactory`
- `AccountsController`
- `AccountCatalogState`
- `AccountOperationState`
- `AccountAvailability`
- `AccountAvailabilityNotifications`
- `InactiveAccountAvailabilityRanking`
- `AccountActionFlow`
- `AddAccountWorkflow`
- `SwitchAccountWorkflow`
- account load/delete/rename/refresh/hydration use cases
- account identity matching and relinking utilities

`Features/Hosts` owns configured remote-host state, host verification, remote switch orchestration, and remote rate-limit fallback policy.

Key boundaries:

- `RemoteHostRuntime`
- `RemoteHostAccountVerifier`
- `RemoteRateLimitResolution`
- `SwitchAccountOnHostWorkflow`

`Features/MenuBar` owns menubar runtime, menu-state projection, menu rendering, native alert/panel presentation, status-item behavior, notification delivery mechanics, and validation snapshots.

Key boundaries:

- `MenuBarCoordinator`
- `MenuBarHostActionCoordinator`
- `MenuBarNotificationWorkflow`
- `MenuBarAccountsStore`
- `MenuBarAccountCatalogProjection`
- `MenuBarMenuBuilder`
- `MenuBarAlertFactory`
- `AlertPresenter`
- `SystemAlertPresenter`
- `PanelPresenter`
- `SystemPanelPresenter`
- `PanelWindowFactory`
- `AddHostPanel`
- `CodexSignInPanel`
- `StatusItemRuntime`
- `GlobalShortcutRuntime`
- `KeyboardShortcutPresentation`
- `AccountAvailabilityNotificationRuntime`

`Features/Validation` owns CodexPill's shared validation composition and Seal runtime adapter. It is not product behavior and it is not Seal itself: it may adapt CodexPill feature validation APIs to `SealRecorder`, but generic proof contracts, manifest semantics, verifier output, and reusable recorder primitives belong in Seal. This layer is UI-surface-neutral, so it may define registry seams, proof sessions, and validation-owned evidence DTOs, but it must not import AppKit, SwiftUI, or MenuBar-specific snapshot types.

Key boundaries:

- `CodexPillSealProofRecorderFactory`
- `CodexPillSealProofRecorderRegistry`
- `CodexPillSealProofRecorder`
- `CodexPillSealProofSession`

Feature-specific Seal scenario contracts live with the feature they prove:

- `AccountValidationRecorder`, `AccountSealScenarioCatalog`, `AccountSealProofRecorder`, and `AccountSealProofRecorderRegistry` live in `Features/Accounts/Validation`.
- `HostValidationRecorder`, `HostSealScenarioCatalog`, `HostSealProofRecorder`, and `HostSealProofRecorderRegistry` live in `Features/Hosts/Validation`.

### Platform

`Sources/Platform/` owns adapters to Codex and the local machine.

`Platform/Codex` owns:

- auth snapshot reading/writing;
- isolated Codex login process execution;
- Codex app-server JSON-RPC I/O;
- Codex CLI process inspection;
- local command execution for SSH-backed operations;
- Codex app process control.

Reusable Codex app-server access is split into these platform boundaries:

- `CodexAppServerClient` is the production facade used by CodexPill account reads.
- `CodexAppServerConfiguration` owns executable path, environment, and timeout policy.
- `CodexAppServerProcessRunner` owns `codex app-server` process launch, stdin/stdout wiring, termination, and timeout completion.
- `CodexAppServerSession` owns JSON-RPC request construction and response sequencing.
- `CodexAppServerAccountParser` and `CodexAppServerRateLimitParser` map raw app-server payload DTOs into generic app-server DTOs.
- `CodexPillAccountStatusMapper` maps generic app-server DTOs into CodexPill account and rate-limit models.

`Platform/Hosts` owns host-client implementations used by validation or host adapters.

`Platform/Persistence` owns:

- CodexPill catalog paths;
- account catalog persistence;
- auth snapshot storage;
- isolated `CODEX_HOME` session paths.

Platform adapters are the only place where the app should know about live auth files, `codex app-server`, shell commands, SSH, process inspection, or relaunch mechanics.

### Core

`Sources/Core/` owns shared data models and app-wide configuration:

- `CodexAccount`
- `CodexRateLimits`
- typed `UserDefaults`-backed settings stores

Core models should remain free of process control, storage policy, AppKit, SwiftUI, and Codex protocol mechanics.

Settings persistence is split by feature boundary:

- `MenuDisplaySettingsStore` owns menu refresh cadence and visible inactive-account count options.
- `StatusItemSettingsStore` owns status-item indicator style, monochrome mode, display mode, pacing marker visibility, progress accent color helpers, and persisted reveal-shortcut values.
- `RemoteHostSettingsStore` owns persisted remote-host state, configured-host compatibility helpers, and legacy remote-host key migration.
- `NotificationPreferencesStore` owns notification workflow toggles and legacy notification-setting migration.
- `NotificationStateStore` owns per-account notification delivery state and deterministic update ordering.

`CodexPillSettingsStore` remains a compatibility facade that assembles these stores from one `UserDefaults` instance and forwards legacy property names. Feature/runtime boundaries should depend on the typed store they need where practical.

## Boundary Notes

`AccountsFeatureFactory` is the production composition boundary for the account feature. App startup chooses platform adapters such as `AccountRepository`, `CodexAuthSnapshotService`, `CodexAppProcessClient`, `CodexAccountStatusClient`, and the remote host operation capabilities implemented by `SSHRemoteHostClient`, then asks the factory for the account feature entry point.

`AccountsController` is the account-session and catalog boundary. It coordinates feature-level state transitions, saved-account catalog updates, active-account resolution, mutation result application, and silent refresh policy.

`AccountActionFlow` owns account action sequencing decisions that do not require AppKit access. It converts workflow outcomes into presentation-neutral next steps. Add Account sign-in failures cross this boundary as account-domain `AddAccountSignInFailureOutcome` values, such as prompt unavailable, expired code, capture failed, and verification failed; MenuBar renders those outcomes into alerts and retry panels without deriving recovery policy from platform login errors.

`AccountAvailability` owns pure local and remote target availability modeling. It must not know menu rendering, notification delivery, or AppKit exists.

`AccountAvailabilityNotifications` owns account-centric notification policy and action resolution. It must not deliver notifications or execute switches.

`InactiveAccountAvailabilityRanking` owns ordering and best-account comparison only.

`RemoteHostRuntime` is the remote-host feature boundary. It owns configured-host connection state, host verification refresh, detected-account adoption state, and preservation of verified remote metadata. It depends on remote account status reading, not the full remote host operation set.

`RemoteRateLimitResolution` owns remote rate-limit fallback semantics.

`MenuBarAccountsStore` is a thin observable adapter for the menu layer. It forwards menu intents into `AccountsController` and should not grow business logic or production dependency assembly.

`MenuBarAccountCatalogProjection` owns menu-facing account projection: relinking remote snapshots to saved accounts, resolving display metadata, building availability snapshots, and ordering catalog entries before rendering.

`MenuBarCoordinator` is the menu/application controller. It owns menu rebuilding, selector dispatch, alert/panel presentation, user-response plumbing, validation event recording, wake/timer refresh triggers, and coordination between account, host, notification, and status-item boundaries.

`MenuBarHostActionCoordinator` is the menubar runtime boundary for host-specific user actions. It owns add-host, remove-host, reverify-host, adopt-detected-account, and switch-account-on-host sequencing while `MenuBarCoordinator` keeps AppKit selector entry points and menu rebuild callbacks.

`CodexPillSealProofRecorderFactory` is the product validation composition boundary. It reads validation environment, asks per-feature `CodexPillSealProofRecorderRegistry` implementations whether they own the requested legacy scenario, and returns the injected `CodexPillSealProofRecorder` facade for the active scenario.

`CodexPillSealProofRecorder` is the small product validation composition container injected into menubar instrumentation. It does not own scenario definitions or feature event APIs; it exposes the active feature-owned recorder selected by the factory.

`CodexPillSealProofSession` is the local Seal runtime adapter. It owns Seal feature registration, run start, event/snapshot recording, finish, and cancellation for CodexPill. If this shape proves reusable across another Apple client, it should be promoted into Seal or a Seal-owned Apple adapter rather than expanded as CodexPill product code. The current keep/simplify/promote decisions for shared validation adapter plumbing are recorded in [validation-adapter-classification-RGR-197.md](validation-adapter-classification-RGR-197.md).

`AccountValidationRecorder` and `HostValidationRecorder` are the feature validation tracking-plan APIs. They list the semantic events a feature exposes for live proof, in feature language. `AccountSealScenarioCatalog` and `HostSealScenarioCatalog` own feature-specific Seal scenario IDs, invariant IDs, rules, and expectations. `AccountSealProofRecorder` and `HostSealProofRecorder` implement the feature APIs by capturing evidence and writing Seal proof events. Validation evidence DTOs must stay independent from AppKit, SwiftUI, and MenuBar snapshot types.

`MenuBarValidationObserver` is observer instrumentation for menubar validation. It owns translation from runtime events to validation event names, invariant IDs, payload sanitization, menu snapshot/action-trace recording, file sink forwarding, and forwarding semantic evidence to the product validation proof boundary. Production coordinators should call semantic observer methods only; they should not know validation artifact formats or Seal lifecycle details. The observer is disabled/no-op in normal production paths when validation configuration is absent.

`MenuBarNotificationWorkflow` is the menubar runtime boundary for account-availability notification orchestration. It owns previous availability snapshot tracking, authorization-state refresh interaction, policy evaluation, payload/action rendering, stale notification response resolution, dedupe state updates, and re-evaluation scheduling callbacks. It delegates local account switching, remote host switching, alert presentation, app activation, and refresh execution back to coordinator-owned runtime collaborators; it uses `AccountAvailabilityNotifications` for account-centric policy and `AccountAvailabilityNotificationRuntime` for macOS delivery mechanics.

`StatusItemRuntime` owns the `NSStatusItem`, hover tracking, pointer-inside detection, title/icon transitions, tooltip rendering, and low-level status-item snapshot state.

Reveal-shortcut capture, menu key-equivalent rendering, display formatting, and Carbon hot-key registration are menubar/status-item runtime and presentation concerns. Core owns only the persisted shortcut value: key code, modifier option set, default value, and validity semantics. Core shortcut types must not import AppKit or Carbon.

`AccountAvailabilityNotificationRuntime` owns notification delivery mechanics and rendering primitives: copy/payload renderers, notification categories, `UserNotifications` requests, and macOS notification settings launch. It does not decide when to notify or how notification clicks map to account-switch actions.

## Truth Sources

The current truth sources are split by concern:

- active local Codex auth: `~/.codex/auth.json`;
- CodexPill catalog and saved snapshots: `~/Library/Application Support/CodexPill`;
- local account metadata and rate limits: local `codex app-server`;
- remote account metadata and rate limits: remote `codex app-server` through the host adapter;
- running CLI session observation: local process table inspection.

Rules:

- `~/Library/Application Support/CodexPill` is CodexPill-owned state, not the source of truth for the live Codex account.
- `~/Library/Application Support/Codex` is only an observation surface when needed.
- Rate limits should come from app-server surfaces, not manual counters.
- Tests and validation harnesses must use temp paths and injected process clients unless a live mutation scenario explicitly opts in.

## Naming Conventions

Name boundaries by the role they play in the app, not by an implementation detail or a verb phrase.

Preferred suffixes:

- `Client` for an external service, process, CLI, or host adapter.
- `Store` for durable catalog or snapshot persistence.
- `Source` for read-only values without ownership of persistence.
- `Reconciler` for deterministic matching or merge policy.
- `Presenter`, `Notifier`, `Activator`, `Launcher`, `Locator`, and `Runner` for UI presentation, notification delivery, app activation, settings launch, path lookup, and command execution.

Avoid protocol names that describe an action in progress, such as `*Reading`, `*Switching`, `*Providing`, `*Presenting`, `*Foregrounding`, `*Opening`, or `*Delivering`.

Test collaborators should describe their role:

- `Probe` records calls or exposes observed side effects for assertions.
- `Fixture` returns fixed canned data.
- `Harness` is mutable test infrastructure that drives a scenario.
- `Adapter` passes through to production-like behavior while fitting a test seam.
- `Null` intentionally does nothing.
- `ErrorCase` deterministically throws or returns a failure.

Avoid generic test names such as `Spy`, `Stub`, `Mock`, `Noop`, `Throwing`, `Recording`, or `Passthrough`.

## File Ownership

- Default to one primary type per file.
- Keep only tightly coupled private support types in the same file as that primary owner.
- Split peer-level boundary types into separate files when they can evolve independently or represent different ownership.
- Do not split files just to satisfy a ritual; split when ownership and navigation become clearer.

## Test Layout

Tests should mirror stable source ownership boundaries once those boundaries exist:

- `Tests/Accounts/`
- `Tests/Hosts/`
- `Tests/MenuBar/`
- `Tests/Platform/Codex/`
- `Tests/Platform/Hosts/`
- `Tests/Platform/Persistence/`
- `Tests/Core/Models/`
- `Tests/Core/Configuration/`
- `Tests/App/`

Do not add deeper `unit/integration/e2e` folders unless suite volume or tooling requires them.

## Placement Rule

If a change affects account workflows, host workflows, menu behavior, notification behavior, or settings state, it belongs in `Features`, with host feature tests owned by `Tests/Hosts/`.

If a change touches file paths, snapshot storage, Codex process control, app-server I/O, shell commands, SSH, or process inspection, it belongs in `Platform`.

If a type is shared domain data or app-wide configuration, it belongs in `Core`.

If a change is only for startup, shutdown, validation bootstrap, or dependency wiring, it belongs in `App`.
