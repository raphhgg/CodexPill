# Architecture

CodexPill is a local-first macOS menubar app for Codex account switching and per-account rate-limit tracking.

This document owns codebase structure and dependency boundaries. Product behavior and UX contracts live in [features](features/README.md).

## Source Shape

The source tree is organized by responsibility:

- `Sources/App/`
- `Sources/Features/Accounts/`
- `Sources/Features/MenuBar/`
- `Sources/Features/TokenUsage/`
- `Sources/Core/Configuration/`
- `Sources/Core/Models/`
- `Sources/Platform/Codex/`
- `Sources/Platform/Persistence/`

The intended dependency direction is:

```text
App -> Features -> Platform
App -> Core
Features -> Core
Platform -> Core
Platform -> Features (port protocols only)
```

`Core` must not depend on `Features`, `Platform`, or `App`.

Platform implements ports declared by Features. A feature declares the protocol it needs next to the code that uses it, and a Platform adapter fulfils it. App injects the adapter. Accounts ports, such as `AccountCatalogStore`, `AccountCatalogLoader`, `CodexAuthActivator`, and `LiveCodexAccountIdentitySource`, are adopted by `AccountRepository` and `CodexAuthSnapshotService` through extensions in the Features file that declares the port, so Platform stays unaware of them. A `Platform -> Features` reference is only ever a protocol conformance, never feature logic or state.

## Ownership Rules

### App

`Sources/App/` owns bootstrap, lifecycle wiring, and dependency assembly.

It does not own menu composition, account workflows, file I/O policy, Codex process control, or Codex protocol details.

### Features

`Sources/Features/` owns product behavior and presentation-neutral workflow policy.

`Features/Accounts` owns saved-account state, active-account resolution, account availability, account workflows, and the account feature composition boundary.

Key boundaries:

- `AccountsFeatureFactory`
- `AccountsController`
- `AccountCatalogState`
- `AccountOperationState`
- `AccountAvailability`
- `InactiveAccountAvailabilityRanking`
- `AccountActionFlow`
- `AddAccountWorkflow`
- `SwitchAccountWorkflow`
- account load/delete/rename/refresh/hydration use cases
- account identity matching and relinking utilities

`Features/TokenUsage` owns local token-usage history lifecycle and cache policy.

Key boundaries:

- `TokenUsageMenuRuntime`
- `TokenUsageMenuProviding`
- local token-usage aggregate cache

It coordinates cache-first loading, scan-task identity, duplicate-scan prevention, progress throttling, and cancellation when Token Usage is disabled. It depends on `Platform/Codex` scanner adapters for local Codex session records, but must not know AppKit menu construction or raw JSONL/session-path details.

`Features/MenuBar` owns menubar runtime, menu-state projection, menu rendering, native alert/panel presentation, and status-item behavior.

Key boundaries:

- `MenuBarCoordinator`
- `MenuBarAccounts`
- `MenuBarAccountCatalogProjection`
- `MenuBarMenuBuilder`
- `MenuBarAlertFactory`
- `AlertPresenter`
- `SystemAlertPresenter`
- `PanelPresenter`
- `SystemPanelPresenter`
- `PanelWindowFactory`
- `CodexSignInPanel`
- `StatusItemRuntime`
- `GlobalShortcutRuntime`
- `KeyboardShortcutPresentation`

### Platform

`Sources/Platform/` owns adapters to Codex and the local machine.

`Platform/Codex` owns:

- auth snapshot reading/writing;
- isolated Codex login process execution;
- Codex app-server JSON-RPC I/O;
- Codex CLI process inspection;
- Codex app process control;
- the default Codex sessions folder read for token usage, `CodexSessionTokenUsageScanner.defaultSessionsDirectory()`.

Reusable Codex app-server access is split into these platform boundaries:

- `CodexAppServerClient` is the production facade used by CodexPill account reads. It turns a local `CodexAppServerConfiguration` into a session command for the shared session runner.
- `CodexAppServerConfiguration` owns executable path, environment, and timeout policy.
- `CodexAppServerSession` owns JSON-RPC request construction and response sequencing.
- `CodexAppServerSessionRunner` owns the reusable app-server session execution loop used by local reads: process launch, stdin/stdout/stderr pipe wiring, request writing, output draining, timeout completion, partial-status completion, and finish-once coordination.
- `CodexAppServerAccountParser` and `CodexAppServerRateLimitParser` map raw app-server payload DTOs into generic app-server DTOs.
- `CodexPillAccountStatusMapper` maps generic app-server DTOs into CodexPill account and rate-limit models.

Local app-server reads enter this session runner through `CodexAppServerClient`, which keeps local executable, environment, client-info, timeout, and saved-account strict rate-limit requirements in `CodexAppServerConfiguration`.

`Platform/Persistence` owns:

- CodexPill catalog paths;
- account catalog persistence;
- auth snapshot storage;
- isolated `CODEX_HOME` session paths;
- the token-usage cache file, `TokenUsageCacheFileStore` at `AppPaths.tokenUsageCacheFile(isolatedRootDirectory:)`.

Platform adapters are the only place where the app should know about live auth files, `codex app-server`, process inspection, or relaunch mechanics.

### Core

`Sources/Core/` owns shared data models and app-wide configuration:

- `CodexAccount`
- `CodexRateLimits`
- `StatusBarIndicatorStyle` and `StatusBarDisplayMode`, the persisted status-item choices
- typed `UserDefaults`-backed settings stores

Core models should remain free of process control, storage policy, AppKit, SwiftUI, and Codex protocol mechanics.

Settings persistence is split by feature boundary:

- `MenuDisplaySettingsStore` owns menu refresh cadence and visible inactive-account count options.
- `StatusItemSettingsStore` owns status-item indicator style, monochrome mode, display mode, pacing marker visibility, progress accent color helpers, and persisted reveal-shortcut values.
- `TokenUsagePreferencesStore` owns token-usage visibility, chart style, loading animation, peak scope, and the fixed 30-day period.

App startup builds each store from one `UserDefaults` instance and injects the ones each runtime boundary needs. There is no shared settings facade.

## Boundary Notes

`AppComposition` is the App composition root. It chooses production or validation adapters, builds the `AccountsController`, and constructs `MenuBarCoordinator` with every collaborator passed in. `MenuBarCoordinator.init` has no production defaults, so a new collaborator is wired in one place. Tests build the coordinator through `Tests/Support/MenuBarCoordinatorTestFactory.swift`.

`AppRuntimeEnvironment` is read only in `Sources/App`. App turns the process environment into plain values and passes them in: the isolated app-support root for `AccountRepository` and the token-usage cache, whether system alerts and panels suppress interactive prompts, the validation auto-refresh interval, and which process client to use. Features and Platform code never read `AppRuntimeEnvironment`.

`AccountsFeatureFactory` is the production composition boundary for the account feature. App startup chooses platform adapters such as `AccountRepository`, `CodexAuthSnapshotService`, `CodexAppProcessClient`, and `CodexAccountStatusClient`, then asks the factory for an `AccountsController`. App hands that controller to `MenuBarCoordinator` as `MenuBarAccounts`; the factory builds no MenuBar types.

`AccountsController` is the account-session and catalog boundary. It coordinates feature-level state transitions, saved-account catalog updates, active-account resolution, mutation result application, metadata persistence, and the silent refresh after a local switch.

`AccountActionFlow` owns account action sequencing decisions that do not require AppKit access. It converts workflow outcomes into presentation-neutral next steps. Add Account sign-in failures cross this boundary as account-domain `AddAccountSignInFailureOutcome` values, such as prompt unavailable, expired code, capture failed, and verification failed; MenuBar renders those outcomes into alerts and retry panels without deriving recovery policy from platform login errors.

`AccountAvailability` reads one saved account's session and weekly usage and reset times for ranking. It must not know menu rendering or AppKit exists.

`InactiveAccountAvailabilityRanking` owns ordering and best-account comparison only.

`TokenUsageMenuRuntime` is the token-usage feature boundary used by MenuBar. It owns background scan lifecycle, cache-first load state, duplicate-scan prevention, progress throttling, and disable-time cancellation. `MenuBarCoordinator` should only mutate Token Usage preferences, ask the runtime for current load state, and decide whether AppKit menu rebuilds are safe while a menu is being tracked.

`MenuBarAccounts` is the port MenuBar declares for account state and intents. It lists only the members the menu reads or calls, and `AccountsController` conforms to it directly. MenuBar never sees the account use cases or Platform adapters behind the controller.

`MenuBarAccountCatalogProjection` owns menu-facing account projection: the active account first, then saved accounts ordered by `InactiveAccountAvailabilityRanking`.

`MenuBarCoordinator` is the menu/application controller. It owns menu rebuilding, selector dispatch, alert/panel presentation, user-response plumbing, wake/timer refresh triggers, and coordination between account and status-item boundaries. Selector handlers and observation callbacks are synchronous, so the coordinator starts their async work through `TrackedTasks`. Tests call `waitForPendingWork()` instead of sleeping.


`StatusItemRuntime` owns the `NSStatusItem`, hover tracking, pointer-inside detection, title/icon transitions, tooltip rendering, and low-level status-item snapshot state.

Reveal-shortcut capture, menu key-equivalent rendering, display formatting, and Carbon hot-key registration are menubar/status-item runtime and presentation concerns. Core owns only the persisted shortcut value: key code, modifier option set, default value, and validity semantics. Core shortcut types must not import AppKit or Carbon.

## Truth Sources

The current truth sources are split by concern:

- active local Codex auth: `~/.codex/auth.json`;
- CodexPill catalog and saved snapshots: `~/Library/Application Support/CodexPill`;
- local account metadata and rate limits: local `codex app-server`;
- running CLI session observation: local process table inspection.

Rules:

- `~/Library/Application Support/CodexPill` is CodexPill-owned state, not the source of truth for the live Codex account.
- `~/Library/Application Support/Codex` is only an observation surface when needed.
- Rate limits should come from app-server surfaces, not manual counters.
- Tests and validation harnesses must use temp paths and injected process clients unless a live mutation scenario explicitly opts in.

## Naming Conventions

Name boundaries by the role they play in the app, not by an implementation detail or a verb phrase.

Preferred suffixes:

- `Client` for an external service, process, or CLI.
- `Store` for durable catalog or snapshot persistence.
- `Source` for read-only values without ownership of persistence.
- `Reconciler` for deterministic matching or merge policy.
- `Presenter`, `Launcher`, `Locator`, and `Runner` for UI presentation, settings launch, path lookup, and command execution.

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
- `Tests/MenuBar/`
- `Tests/TokenUsage/`
- `Tests/Platform/Codex/`
- `Tests/Platform/Persistence/`
- `Tests/Core/Models/`
- `Tests/Core/Configuration/`
- `Tests/App/`

Do not add deeper `unit/integration/e2e` folders unless suite volume or tooling requires them.

## Placement Rule

If a change affects account workflows, token-usage lifecycle, menu behavior, or settings state, it belongs in `Features`, with token-usage lifecycle tests owned by `Tests/TokenUsage/`.

If a change touches file paths, snapshot storage, Codex process control, app-server I/O, or process inspection, it belongs in `Platform`.

If a type is shared domain data or app-wide configuration, it belongs in `Core`.

If a change is only for startup, shutdown, validation bootstrap, or dependency wiring, it belongs in `App`.
