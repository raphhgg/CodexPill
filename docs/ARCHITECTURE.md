# Architecture

## Purpose

CodexPill is a local-first macOS menubar app for Codex account switching and per-account rate-limit tracking. The codebase is still in prototype-first mode, so the goal is to keep boundaries clear without freezing the repo into a heavy framework.

## Current Shape

The current source tree is organized by responsibility, not by file type:

- `Sources/App/`
- `Sources/Features/Accounts/`
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
- `InactiveAccountAvailabilityRanking`
- `PendingSignInLifecycle`
- `SilentPostActionRefresh`
- `LoadAccountsUseCase`
- `RefreshActiveAccountUseCase`
- `SaveCurrentAccountWorkflow`
- `SwitchAccountWorkflow`
- `SignInAnotherWorkflow`
- `SavedAccountIdentityResolver`
- `CodexAccountMatcher`

Internal grouping:

- `Application/` for the feature-level boundary
- `UseCases/` for single-purpose catalog/data operations
- `Workflows/` for multi-step account actions
- `Utils/` for tightly-scoped support types used inside the feature

`Features/MenuBar` owns:

- `MenuBarCoordinator`
- `MenuBarAccountsStore`
- `StatusItemRuntime`
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

`MenuBarAccountsStore` is a thin observable adapter for the menu layer. It forwards menu intents into `AccountsController` and exposes account state to the menubar runtime.

`StatusItemRuntime` is the deep status-item boundary. It owns the `NSStatusItem`, hover tracking, pointer-inside detection, title/icon transitions, and low-level status-item snapshot state for validation.

`MenuBarCoordinator` is the menu/application controller. It owns menu rebuilding, action dispatch, alerts, validation event recording, wake/timer refresh triggers, and coordination with `MenuBarAccountsStore` and `StatusItemRuntime`.

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

`PendingSignInLifecycle` owns:

- pending sign-in state after preparing `Sign In Another Account…`
- completion-in-flight state for post-login save flows
- clearing/retaining the pending sign-in marker
- gating metadata hydration while sign-in completion is unresolved

`SilentPostActionRefresh` owns:

- silent refresh attempts after save, switch, and completed sign-in flows
- optional delay before those refresh attempts
- swallowing refresh failures so post-action UX is not interrupted

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
- prepare sign-in-another flows

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
