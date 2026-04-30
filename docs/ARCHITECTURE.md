# Architecture

## Purpose

CodexPill is a local-first macOS menubar app for Codex account switching and per-account rate-limit tracking. The codebase is still in prototype-first mode, so the goal is to keep boundaries clear without freezing the repo into a heavy framework.

## Current Shape

The current source tree is organized by responsibility, not by file type:

- `Sources/App/`
- `Sources/Features/Accounts/`
- `Sources/Features/Hosts/`
- `Sources/Features/MenuBar/`
- `Sources/Core/Configuration/`
- `Sources/Platform/Codex/`
- `Sources/Platform/Persistence/`
- `Sources/Core/Models/`

That split is intentional:

- `App` owns bootstrap and lifecycle wiring.
- `Features` owns user-facing product behavior.
- `Platform` owns Codex, file-system, and process adapters.
- `Core` owns shared domain models and app-wide configuration.

## Boundary Ownership

## Naming Conventions

Name boundaries by the role they play in the app, not by an implementation detail or a verb phrase. Prefer short noun suffixes that make dependency direction obvious:

- `Client` for an external service, process, CLI, or host adapter. Example: `CodexAccountStatusClient`, `RemoteHostClient`, `CodexAppProcessClient`.
- `Store` for durable catalog or snapshot persistence. Example: `AccountCatalogStore`, `CodexAuthSnapshotStore`.
- `Source` for read-only values without ownership of persistence. Example: `LiveCodexAccountIdentitySource`, `AppIconSource`.
- `Reconciler` for deterministic matching or merge policy. Example: `StoredAccountIdentityReconciler`.
- `Presenter`, `Notifier`, `Activator`, `Launcher`, `Locator`, and `Runner` for UI presentation, notification delivery, app activation, Settings launch, path lookup, and command execution.

Avoid protocol names that describe an action in progress, such as `*Reading`, `*Switching`, `*Providing`, `*Presenting`, `*Foregrounding`, `*Opening`, or `*Delivering`. Those names make call sites read like implementation steps instead of stable domain roles.

Test collaborators should also describe their role:

- `Probe` records calls or exposes observed side effects for assertions. Example: `RemoteHostClientProbe`, `MenuBarAlertPresenterProbe`.
- `Fixture` returns fixed canned data. Example: `CurrentIdentityFixture`, `RemoteHostStatusFixture`.
- `Harness` is mutable test infrastructure that drives a scenario. Example: `CurrentIdentityHarness`.
- `Adapter` passes through to production-like behavior while fitting a test seam. Example: `IdentityReconcilerAdapter`.
- `Null` intentionally does nothing. Example: `NullAuthService`.
- `ErrorCase` deterministically throws or returns a failure. Example: `RemoteHostErrorCase`.

Avoid generic or framework-loaded test names such as `Spy`, `Stub`, `Mock`, `Noop`, `Throwing`, `Recording`, or `Passthrough`. Use the narrower role above so tests explain why the collaborator exists.

### App

`Sources/App/` is thin bootstrap only.

Owns:

- `CodexPillApp`
- `CodexPillAppDelegate`
- app startup and shutdown wiring
- dependency assembly

Does not own:

- menu composition
- account workflows
- file I/O
- Codex process control

### Features

`Sources/Features/` contains the product behavior.

`Features/Accounts` owns:

- `AccountsController`
- `AccountCatalogState`
- `AccountOperationState`
- `AccountAvailability`
- `AccountAvailabilityNotifications`
- `InactiveAccountAvailabilityRanking`
- `SilentPostActionRefresh`
- `LoadAccountsUseCase`
- `RefreshActiveAccountUseCase`
- `SwitchAccountWorkflow`
- `AddAccountWorkflow`
- `SavedAccountIdentityResolver`
- `CodexAccountMatcher`

`Features/Hosts` owns:

- `RemoteHostRuntime`
- `RemoteRateLimitResolution`
- `RemoteHostAccountVerifier`
- `RemoteHost`
- remote-host connection and verification state transitions

Internal grouping:

- `Application/` for the feature-level boundary
- `UseCases/` for single-purpose catalog/data operations
- `Workflows/` for multi-step account actions
- `Utils/` for tightly-scoped support types used inside the feature

`Features/MenuBar` owns:

- `MenuBarCoordinator`
- `MenuBarAccountsStore`
- `StatusItemRuntime`
- `MenuBarAccountCatalogProjection`
- `MenuBarMenuBuilder`
- `MenuBarAlertFactory`
- `MenuBarAlertPresenter`
- `StatusBarIconRenderer`
- `StatusBarIndicatorStyle`

Internal grouping:

- `Runtime/` for AppKit status-item and menu lifecycle behavior
- `Presentation/` for menu state, formatting, builders, and hosted SwiftUI menu content
- `Validation/` for validation snapshots and hosted proof helpers

### Platform

`Sources/Platform/` contains adapters to Codex and the local machine.

`Platform/Persistence` owns:

- `AccountRepository`
- `AppPaths`
- local catalog persistence
- snapshot file storage

`Platform/Codex` owns:

- `CodexAuthSnapshotService`
- `CodexAppController`
- `CodexAppServerClient`
- `CodexCLIProcessInspector`

These adapters are the only place where the app should know about live auth files, `codex app-server`, CLI process inspection, or relaunch mechanics.

### Core

`Sources/Core/` owns shared data models and app-wide configuration:

- `CodexAccount`
- `CodexRateLimits`
- `AppSettings`

These types are shared between features and platform adapters. Models should remain free of process or storage policy. App-wide configuration may persist lightweight preferences, but it should not take on UI workflow or process-control behavior.

## State And Workflow Ownership

`AccountsController` is the deeper account-session and catalog boundary. It owns the saved-account catalog, active-account resolution, mutation result application, and silent refresh policy. Stable sub-policies that do not need controller state should be extracted behind the boundary instead of staying inline.

`AccountActionFlow` owns account action sequencing decisions that do not require AppKit access. It maps Add Account completion and failure outcomes into next UI steps, including retry prompts, duplicate-name recovery, duplicate captured identity messaging, live-auth mutation failures, catalog save failures, and the direct local switch step after a confirmed Add Account success.

`AccountAvailability` owns pure local and remote target availability modeling. It derives account/target status, next availability, snapshots, and availability transitions. It must not know notification policy, menu rendering, or delivery mechanics exist.

`AccountAvailabilityNotifications` owns account-centric notification policy and action resolution. It may use availability snapshots and the shared inactive-account ranking to select the best currently usable account, but it must not deliver notifications or own AppKit/UserNotifications integration.

`InactiveAccountAvailabilityRanking` owns ordering only. It compares local accounts and target availabilities for menu ordering and best-account selection, without owning notification decisions or target availability derivation.

`MenuBarAccountsStore` is a thin observable adapter for the menu layer. It forwards menu intents into `AccountsController` and exposes account state to the menubar runtime.

`RemoteHostRuntime` is the deeper remote-host feature boundary. It owns configured-host connection state, host verification refresh, detected-account adoption state, and preservation of last verified remote metadata when a host becomes unavailable or no longer matches the desired saved account.

`RemoteRateLimitResolution` owns remote rate-limit fallback semantics. It decides when remote app-server rate-limit payloads are meaningful and when the local catalog or verified-account fallback should be preferred.

`StatusItemRuntime` is the deep status-item boundary. It owns the `NSStatusItem`, hover tracking, pointer-inside detection, title/icon transitions, and low-level status-item snapshot state for validation.

`MenuBarAccountCatalogProjection` owns account catalog projection for the menu. It relinks remote account snapshots to saved accounts, resolves remote display metadata, builds local/remote availability snapshots, and orders active/non-active catalog rows before rendering.

`MenuBarCoordinator` is the menu/application controller. It owns menu rebuilding, `@objc` menu selector dispatch, alert and panel presentation, user-response plumbing, validation event recording, wake/timer refresh triggers, and final coordination with `MenuBarAccountsStore`, `RemoteHostRuntime`, and `StatusItemRuntime`. Account-flow policy should enter through `AccountActionFlow` rather than inline Add Account decision trees.

`AccountAvailabilityNotificationRuntime` owns notification delivery mechanics. It translates notification decisions into copy, payloads, categories, and `UserNotifications` requests, and it opens macOS notification settings when needed. It must not decide when an account is usable or execute a switch; those stay in account notification policy/action resolution and `MenuBarCoordinator` response routing.

`AccountsController` owns:

- feature-level state transitions
- post-switch and post-save refresh policy

`AccountCatalogState` owns:

- `accounts`
- `activeAccountID`
- applying load/save/delete/refresh/hydration results to the in-memory catalog
- deriving active and inactive account views from the current catalog
- resolving the current active account id from the identity resolver

`AccountOperationState` owns:

- `pendingErrorMessage`
- `statusMessage`
- `isBusy`
- operation lifecycle transitions (`begin`, `succeed`, `fail`)
- consuming one-shot error presentation state

`InactiveAccountAvailabilityRanking` owns:

- inactive-account availability sorting for menu presentation
- the ranking comparison contract used by `AccountsController.compareForMenu`

`AddAccountWorkflow` owns:

- Add Account display-name validation before isolated sign-in starts
- isolated Codex sign-in session capture
- duplicate captured identity rejection
- live-auth mutation guard before catalog save
- temporary auth cleanup on cancel, failure, timeout, and success

`AccountActionFlow` owns:

- Add Account success and failure routing into presentation-neutral flow steps
- expired-code retry and duplicate-name recovery decisions
- live-auth mutation, catalog save failure, and duplicate captured identity user-step mapping
- bypassing normal switch confirmation after the user accepts the Add Account success prompt

`SilentPostActionRefresh` owns:

- silent refresh attempts after save, switch, and completed sign-in flows
- optional delay before those refresh attempts
- swallowing refresh failures so post-action UX is not interrupted

`RemoteHostRuntime` owns:

- restoring persisted remote-host connection state
- deriving menu-ready remote-host state from persisted hosts and saved accounts
- applying remote switch verification outcomes
- preserving verified remote account metadata back into the local catalog before clearing stale host state
- remote-host refresh and reverification state transitions

`RemoteRateLimitResolution` owns:

- choosing the best fallback snapshot for a remote account
- preserving meaningful remote rate-limit windows
- rejecting suspicious empty or expired remote rate-limit windows
- merging remote metadata with local catalog fallback metadata

`MenuBarAccountsStore` owns:

- menu-facing observation and delegation
- no business logic beyond delegation

`StatusItemRuntime` owns:

- `NSStatusItem` / `NSStatusBarButton`
- hover tracking and pointer polling
- title visibility policy application
- icon and tooltip rendering on the status item
- low-level status-item snapshot capture

`StatusItemRuntime` does not own:

- account refresh policy
- menu action dispatch
- alert presentation
- account workflow orchestration

`MenuBarAccountCatalogProjection` owns:

- relinking remote active accounts to saved catalog identities
- applying remote display metadata and rate-limit fallback to catalog rows
- deriving remote target availability for menu and notification snapshots
- ordering active and inactive account catalog entries for presentation

`MenuBarAccountsStore` does not own:

- direct file writes
- auth snapshot mechanics
- Codex relaunch
- app-server protocol details
- account mutation policy
- pending sign-in policy
- availability sorting

The use cases and workflows own the multi-step business operations:

- load local accounts
- reconcile stored identities
- refresh the active account from live Codex data
- save the current account snapshot
- switch accounts
- prepare Add Account flows

## Current Truth Sources

The current source of truth is split by concern:

- switching surface: `~/.codex/auth.json`
- local account catalog and snapshots: `~/Library/Application Support/CodexPill`
- live account metadata and rate limits: local `codex app-server`
- running CLI session observation: local process table inspection

Important rule:

- `~/Library/Application Support/CodexPill` is CodexPill-owned state, not the source of truth for the live Codex account
- `~/Library/Application Support/Codex` is only an observation surface when we need to inspect Codex-adjacent state
- rate limits should come from the local app-server, not from manual counters

## Prototype-First Constraints

This repo is still prototype-first. That means:

- keep the thinnest boundary that removes coupling
- extract a module when a real responsibility becomes stable
- do not split files just to satisfy folder aesthetics
- do not introduce full DDD ceremony unless the domain complexity actually needs it
- prefer feature and platform grouping over flat `Services`, `Stores`, `Views`, and `Models` buckets

The current architecture is already past the shallow type-split stage. New work should extend the current `App / Features / Platform / Core` shape instead of drifting back to generic buckets.

## File Ownership Rules

- Default to one primary type per file.
- Keep only tightly-coupled private support types in the same file as that primary owner.
- Split peer-level boundary types into separate files when they can evolve independently or represent different ownership.
- Do not split files just to satisfy a ritual; split when ownership and navigation become clearer.

Examples for this repo:

- acceptable: a coordinator plus a file-private hover tracker or tiny policy helper used only by that coordinator
- not preferred: a deep account-session controller and a thin store adapter sharing one file

## Test Layout Rules

- Tests should mirror stable source ownership boundaries once those boundaries exist.
- Keep one level of grouping that matches source ownership:
  - `Tests/Accounts/`
  - `Tests/MenuBar/`
  - `Tests/Platform/Codex/`
  - `Tests/Core/Models/`
- Do not add deeper `unit/integration/e2e` folders unless suite volume or tooling actually requires them.
- Test file names should still be behavior- or type-specific inside those folders.

## Practical Rule

If a change affects menu behavior, account workflows, or settings state, it belongs in `Features`.

If a change touches file paths, snapshot storage, Codex process control, or app-server I/O, it belongs in `Platform`.

If a type is shared domain data, it belongs in `Core`.

If a change is only for startup, shutdown, or dependency wiring, it belongs in `App`.
