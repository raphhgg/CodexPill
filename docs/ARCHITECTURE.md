# Architecture

CodexPill is a local-first macOS menubar app for account switching and limits for Codex, Claude and Cursor on this Mac.

This document owns codebase structure and dependency boundaries. Product behavior and UX contracts live in [features](features/README.md).

## Source Shape

The source tree is organized by responsibility:

- `Sources/App/`
- `Sources/Features/Accounts/`
- `Sources/Features/AppControls/`
- `Sources/Features/Diagnostics/`
- `Sources/Features/MenuBar/`
- `Sources/Features/TokenUsage/`
- `Sources/Features/Usage/`
- `Sources/Core/Configuration/`
- `Sources/Core/Models/`
- `Sources/Platform/Claude/`
- `Sources/Platform/Codex/`
- `Sources/Platform/Cursor/`
- `Sources/Platform/Networking/`
- `Sources/Platform/Persistence/`

The dependency direction is:

```text
App -> Features -> Platform -> Core
App -> Core
Features -> Core
```

`Core` depends on nothing else. `Core` and `Platform` never reference a type or function declared in `Features`. `Tests/App/LayerBoundaryTests.swift` fails `make test` when they do.

A port lives in one of two places:

- In Platform, next to its adapter, when the adapter is the only thing that implements it: `CodexAppProcessClient`, `CodexResetCreditClient`, `IsolatedCodexLoginClient`, `CursorAppProcessClient`, `ClaudeCodeProcessRunning`, `ClaudeCodeFolderKeychain`.
- In the Features file that uses it, when a feature needs a narrower view of a Platform type. The Platform type adopts it through an extension in that same Features file, so Platform stays unaware of it: `AccountCatalogStore`, `AccountCatalogLoader`, `CodexAuthActivator`, `LiveCodexAccountIdentitySource`.

App injects the adapter either way.

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

`Features/Usage` owns every tool other than Codex: Claude Code and Cursor.

Key boundaries:

- `ProviderConnection`, the port one tool conforms to. See "How a tool plugs in" below.
- `UsageProviderSource`, the read half of that port. It returns a `UsageProviderReading`: not connected, unavailable with a `UsageUnavailableReason`, awaiting usage, or a `UsageSnapshot`. The reasons are not installed, signed out, sign-in expired (401 or past expiry), Keychain access needed, sign-in unreadable, sign-in busy (the tool is writing it right now), access denied (403), rate limited (429), unreachable, service error (other status), and unexpected response.
- `ProviderCopy`, the one table of every word the menu shows for a tool: its name, who answers its usage requests, the confirmation before connecting or switching, and the message for each unavailable reason. Each tool's switch errors map to a short `ProviderNotice` next to it.
- `ClaudeCodeUsage` and `CursorUsage`, the two connections. Each wraps its Platform adapter, maps its values onto `UsageSnapshot`, and owns the opt-in setting.
- `ProviderUsageRuntime`, which reads each connection at most once per its `refreshInterval` (5 minutes by default), however often the menu opens, and publishes one `ProviderUsageState` per tool: its status, its saved accounts with their last limits, whether the tool's sign-in can run here, and whether a sign-in is waiting. A snapshot older than `staleAfter` is published as `.stale`. When a tool is unavailable for a reason that keeps the same account, the runtime keeps the last good snapshot next to the reason. It also runs the actions the menu sends, and reads inactive saved accounts every `inactiveRefreshInterval` (15 minutes).

Tool states only feed menu sections. They never reach `AccountAvailability` or `InactiveAccountAvailabilityRanking`: those read `CodexAccount.usage`. The runtime refuses a connection for `.codex`.

### How a tool plugs in

A tool other than Codex is one type that conforms to `ProviderConnection` and is listed in `AppComposition`'s `providerConnections`:

```swift
protocol ProviderConnection: UsageProviderSource {
    var isConnected: Bool { get }
    func connect() async
    func disconnect() async
    var signInAvailability: ProviderSignInAvailability { get }
    func savedAccounts() async throws(ProviderNotice) -> [ProviderAccount]
    func switchAccount(to id: UUID) async throws(ProviderNotice)
    func addAccount() async throws(ProviderNotice) -> Bool
    func saveLiveAccountIfNew() async -> Bool
    func removeAccount(_ id: UUID) async throws(ProviderNotice)
    func refreshInactiveAccount(_ id: UUID, now: Date) async
}
```

Each saved account is the tool's own sign-in in the tool's own format, held by CodexPill, and the tool's live sign-in is the account in use. The four account operations follow one style, the one Codex accounts already use:

- `addAccount()` runs the tool's own sign-in away from its live sign-in, in a throwaway home the Platform adapter creates and always deletes, and saves what the tool wrote there. Cancelling the calling task stops the sign-in and returns false. `signInAvailability` says whether that sign-in can run here (`available`, `notInstalled`) or the tool only saves its current sign-in (`unsupported`).
- `saveLiveAccountIfNew()` saves the account the tool is signed in to when it is not saved yet, without a prompt, and returns true when it saved one. `ProviderUsageRuntime` calls it after each read of a connected tool, never while sign-ins change, and account actions wait for it. The default does nothing.
- `switchAccount(to:)` saves the live sign-in back to its account first, because the tool may have renewed it, then writes the target, all or nothing.
- `refreshInactiveAccount(_:now:)` reads one saved account the tool is not signed in to, with that account's own sign-in, and records its limits on `ProviderAccount.usage`. When the saved sign-in needs renewing, the tool renews it in a throwaway home and the adapter writes it back only if the saved copy is unchanged (compare and swap). Cursor renews nothing: an expired saved token keeps its last limits. Limits are recorded under the same compare and swap, so a read never overwrites tokens a switch saved meanwhile. It never reads or changes the live sign-in. The default does nothing.
- `renewLiveSignInIfNeeded(now:)` lets the tool renew its own expired live sign-in while the tool is not running, and returns true when the sign-in changed. Claude runs `claude doctor` with Claude Code's own config, once per expiry with a 30-minute retry. The default does nothing.

Its words go in `ProviderCopy` under its `UsageProvider` case. Nothing else changes: no selector, coordinator property, or menu-builder branch names a tool.

- Every tool menu item, Codex included, carries a `ProviderMenuAction` (tool plus `ProviderAction`) and calls `MenuBarCoordinator.performProviderAction(_:)`.
- The coordinator asks the `ProviderCopy` confirmation, if any, then runs the action in a tracked task through `ProviderUsageRuntime.perform(_:on:)` and shows the `ProviderNotice` it returns.
- The runtime reads the tool again after every action. A switch first drops the tool's last reading and bumps a generation, so a read that started before the change is discarded and the previous account's numbers never show.
- The runtime owns the sign-in task, so `.cancelSignIn` cancels it and the card shows `isSigningIn` until it ends. An account just added is read at once. A switch of that tool is refused while its sign-in runs, since a Cursor switch would quit the sign-in window.
- Inactive reads run one account at a time. Switching, adding, saving or removing first lets the account being read finish and stops the rest, so a renewed sign-in is saved before any sign-in is touched. A new inactive pass does not start while a sign-in, an account action, or a live renewal runs.
- After a read, the coordinator asks the runtime to renew each tool whose reading is sign-in expired. One renewal runs at a time, never during a sign-in, an account action, or the inactive pass. Account actions wait for it. A tool that renewed is read again.
- `ProviderAccount` is the only account type the menu sees. It never carries tokens.
- Codex is not a connection: its usage lives on each saved `CodexAccount` and adding an account is an interactive sign-in panel. The coordinator routes `.codex` actions to `AccountsController`, which refreshes the new active account after a switch and never runs a reset credit and an account change at the same time.

`Features/AppControls` owns app-level controls the menu offers: Launch at Login through `LoginItemController` and the System Settings launcher.

`Features/Diagnostics` owns the diagnostic report: `DiagnosticEventRecorder` keeps recent menu actions and refresh results, `DiagnosticReportBuilder` turns them and the menu state into a redacted report, and `DiagnosticReportPresenter` saves it where the user chooses.

`Features/MenuBar` owns menubar runtime, menu-state projection, menu rendering, native alert/panel presentation, and status-item behavior.

Key boundaries:

- `MenuBarCoordinator`
- `MenuBarAccounts`
- `MenuBarAccountCatalogProjection`
- `MenuBarMenuBuilder`
- `UsageMeterRow`, the SwiftUI row (label, bar, used percent, reset text) drawn for one `UsageWindow` in the account card
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
- `CodexAppServerSessionRunner` owns the reusable app-server session execution loop used by local reads: process launch, stdin/stdout/stderr pipe wiring, request writing, output draining, timeout completion, partial-status completion, and finish-once coordination. It also runs the one-request `account/rateLimitResetCredit/consume` session that spends a Codex reset credit.
- `CodexAppServerAccountParser` and `CodexAppServerRateLimitParser` map raw app-server payload DTOs into generic app-server DTOs.
- `CodexPillAccountStatusMapper` maps generic app-server DTOs into CodexPill account and rate-limit models.

Local app-server reads enter this session runner through `CodexAppServerClient`, which keeps local executable, environment, client-info, timeout, and saved-account strict rate-limit requirements in `CodexAppServerConfiguration`.

`Platform/Claude` owns everything CodexPill knows about Claude Code:

- reading its sign-in from `.credentials.json` and the `Claude Code-credentials` Keychain item, with the Keychain prompt shown only after a user action (`ClaudeCredentialsSource`, `SystemClaudeKeychain`);
- the `api.anthropic.com/api/oauth/usage` request, its redirect rule, its rate-limit wait, and parsing its response (`ClaudeUsageAPI`, `ClaudeUsageClient`);
- saved Claude Code accounts and switching (`ClaudeCodeAccountStore`, `ClaudeCodeSignInStore`, `SystemClaudeCodeAccountItems`). A switch writes CodexPill's own item and list, then Claude Code's credentials, then `oauthAccount` in Claude Code's global config, and puts every earlier step back when a later one fails. Accounts match by Claude Code's account record, never by token;
- whether terminal Claude Code is running, behind the `ClaudeCodeProcessDetecting` port. A switch or renewal waits while it runs. The Claude desktop app's own Claude Code is ignored.

The access token leaves this module only as the usage request's `Authorization` header. Nothing in it reads, sends, or renews Claude Code's refresh token; a test scans the Claude sources to keep it that way. Renewal is always Claude Code's own, through `claude doctor`.

`Platform/Cursor` owns everything CodexPill knows about Cursor:

- `CursorStateDatabase`, keyed reads and the one write path for `state.vscdb`. It never scans. A read opens the database with `immutable=1` only when no `-wal`, `-shm`, or `-journal` file sits next to it, so it never reads a writer's uncommitted pages. A write folds the WAL into the database, refuses while another connection holds it, and replaces only the named rows in one transaction;
- `CursorStateDatabaseTokenSource`, the read-only token lookup used for usage, and `CursorAccessToken`, which prints redacted;
- the `cursor.com/api/usage-summary` request, its redirect rule, its `Retry-After` wait, and parsing its response (`URLSessionCursorUsageWebClient`, `CursorUsageClient`, `CursorUsageSummaryParser`);
- `CursorSignIn`, the eight `cursorAuth/*` rows that are a Cursor sign-in, and `CursorSavedAccount`, a named copy of one;
- `CursorAccountStore` and `SystemCursorAccountKeychain`, the `CodexPill Cursor accounts` Keychain item holding every saved account;
- `CursorAccounts`: capture, add a sign-in made in a throwaway profile, record an inactive account's limits (compare and swap on the saved sign-in), rename, remove, and activate. Activation quits Cursor, saves the outgoing sign-in again, writes the saved one, and reopens Cursor. It throws one `CursorAccountsError` per outcome the menu must tell apart;
- `CursorAppProcessClient` and `SystemCursorAppProcessClient`, quitting and opening Cursor.app. It never force-quits and knows nothing about Cursor's files;
- `CursorIsolatedLogin`, Cursor's own sign-in in a separate Cursor instance with a throwaway `--user-data-dir` under `<AppSupport>/cursor-sign-in/<8 hex>`. It refuses a profile path that would push Cursor's IPC socket past macOS's 103-byte limit, polls the profile's `state.vscdb` for the `cursorAuth/*` rows, quits that instance by PID, and deletes the profile on every path. `CursorInstanceLaunching` starts and quits instances by PID: `SystemCursorInstanceLauncher` opens Cursor.app as a new instance and quits only a Cursor process with that PID, and `ExecutableCursorInstanceLauncher` runs a stand-in for isolated runs.

Tokens leave this module only as the usage request's cookie or in CodexPill's Keychain item.

`Platform/Networking` owns HTTP rules shared by tools, such as `RetryAfter`, which reads a `Retry-After` header given as seconds or an HTTP date.

`Platform/Persistence` owns:

- CodexPill catalog paths;
- account catalog persistence;
- auth snapshot storage;
- isolated `CODEX_HOME` session paths;
- the token-usage cache file, `TokenUsageCacheFileStore` at `AppPaths.tokenUsageCacheFile(isolatedRootDirectory:)`.

Platform adapters are the only place where the app should know about live auth files, `codex app-server`, process inspection, or relaunch mechanics.

### Core

`Sources/Core/` is models plus typed preferences:

- `CodexAccount` and `LiveCodexAccountIdentity`
- `CodexRateLimits`, Codex plan-type rules and `UsageSnapshot.codex(planName:primary:secondary:fetchedAt:)`, the only place that turns Codex's positional primary and secondary windows into named windows, shortest first
- `Usage`, the provider-neutral usage model: `UsageSnapshot` holds a provider, the plan name the provider reported, and `UsageWindow` values keyed by `UsageWindowKind` (session, weekly, monthly, billing cycle, or other with its length). `UsageWindowKind(durationMinutes:)` is the one rule that names a window by its length, with its tolerances. `UsageWindow.displayedUsedPercent(at:)` is the one rule for showing 0% once a window has reset. `CodexAccount.usage` and `CodexAccountStatus.usage` store it directly. `CodexAccount` reads and writes the `rateLimits` primary/secondary shape `accounts.json` has always used through a private storage type, so files from earlier versions still load and earlier versions can still read new files. Loading names each stored window by its length again.
- `StatusBarIndicatorStyle` and `StatusBarDisplayMode`, the persisted status-item choices
- typed `UserDefaults`-backed settings stores

Core models should remain free of process control, storage policy, AppKit, SwiftUI, and Codex protocol mechanics.

Settings persistence is split by feature boundary:

- `MenuDisplaySettingsStore` owns menu refresh cadence and visible inactive-account count options.
- `StatusItemSettingsStore` owns status-item indicator style, monochrome mode, display mode, pacing marker visibility, progress accent color helpers, and persisted reveal-shortcut values.
- `TokenUsagePreferencesStore` owns token-usage visibility and the fixed 30-day period. Its stored chart style, loading animation and peak scope have no menu control anymore and keep their defaults.
- `ClaudeUsageSettingsStore` owns whether Claude Code usage is connected (`claudeUsageEnabled`). It is off by default.
- `CursorUsageSettingsStore` owns whether Cursor usage is connected (`cursorUsageEnabled`). It is off by default.

App startup builds each store from one `UserDefaults` instance and injects the ones each runtime boundary needs. There is no shared settings facade.

## Boundary Notes

`AppComposition` is the App composition root. It chooses the production adapters, builds the `AccountsController`, and constructs `MenuBarCoordinator` with every collaborator passed in. `MenuBarCoordinator.init` has no production defaults, so a new collaborator is wired in one place. Tests build the coordinator through `Tests/Support/MenuBarCoordinatorTestFactory.swift`.

`AppRuntimeEnvironment` is read only in `Sources/App`. App turns the process environment into plain values and passes them in: the isolated app-support root for `AccountRepository` and the token-usage cache, the isolated defaults suite, and whether system alerts and panels suppress interactive prompts. Features and Platform code never read `AppRuntimeEnvironment`.

`AccountsFeatureFactory` is the production composition boundary for the account feature. App startup chooses platform adapters such as `AccountRepository`, `CodexAuthSnapshotService`, `CodexAppProcessClient`, and `CodexAccountStatusClient`, then asks the factory for an `AccountsController`. App hands that controller to `MenuBarCoordinator` as `MenuBarAccounts`; the factory builds no MenuBar types.

`AccountsController` is the account-session and catalog boundary. It coordinates feature-level state transitions, saved-account catalog updates, active-account resolution, mutation result application, metadata persistence, and the silent refresh after a local switch.

`AccountActionFlow` owns account action sequencing decisions that do not require AppKit access. It converts workflow outcomes into presentation-neutral next steps. Add Account sign-in failures cross this boundary as account-domain `AddAccountSignInFailureOutcome` values, such as prompt unavailable, expired code, capture failed, and verification failed; MenuBar renders those outcomes into alerts and retry panels without deriving recovery policy from platform login errors.

`AccountAvailability` reads one saved account's session usage and its fullest longer window (weekly, monthly, or other) with their reset times for ranking. It must not know menu rendering or AppKit exists.

`InactiveAccountAvailabilityRanking` owns ordering and best-account comparison only.

`TokenUsageMenuRuntime` is the token-usage feature boundary used by MenuBar. It owns background scan lifecycle, cache-first load state, duplicate-scan prevention, progress throttling, and disable-time cancellation. `MenuBarCoordinator` should only mutate Token Usage preferences, ask the runtime for current load state, and decide whether AppKit menu rebuilds are safe while a menu is being tracked.

`MenuBarCoordinator` owns the `ProviderUsageRuntime` and exposes its states as `MenuBarMenuState.providerUsage`. It holds no tool-specific property or selector: tool actions arrive through `performProviderAction(_:)`. Token usage and provider usage share one path: startup and opening the menu ask both to refresh if due, the scheduled refresh also refreshes providers, and both report changes through `rebuildMenuWhenSafe()`, which waits until the menu is closed.

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
- running CLI session observation: local process table inspection;
- Claude Code usage: `api.anthropic.com/api/oauth/usage`, authenticated with Claude Code's local sign-in token;
- active Claude Code account: `oauthAccount` in Claude Code's global config, `~/.claude.json`;
- Cursor usage: `cursor.com/api/usage-summary`, authenticated with Cursor's local sign-in token;
- active Cursor account: the `cursorAuth/*` rows in Cursor's `state.vscdb`;
- saved Cursor accounts: CodexPill's `CodexPill Cursor accounts` Keychain item.

Rules:

- `~/Library/Application Support/CodexPill` is CodexPill-owned state, not the source of truth for the live Codex account.
- `~/Library/Application Support/Codex` is only an observation surface when needed.
- Rate limits should come from app-server surfaces, not manual counters.
- Tests must use temp paths and injected process clients.

## Naming Conventions

Name boundaries by the role they play in the app, not by an implementation detail or a verb phrase.

Preferred suffixes:

- `Client` for an external service, process, or CLI.
- `Store` for durable catalog or snapshot persistence.
- `Source` for read-only values without ownership of persistence.
- `Reconciler` for deterministic matching or merge policy.
- `Presenter`, `Launcher`, `Locator`, and `Runner` for UI presentation, settings launch, path lookup, and command execution.

Test collaborators should describe their role:

- `Probe` records calls or exposes observed side effects for assertions.
- `Fixture` returns fixed canned data.
- `Harness` is mutable test infrastructure that drives a scenario.
- `Adapter` passes through to production-like behavior while fitting a test seam.
- `Null` intentionally does nothing.
- `ErrorCase` deterministically throws or returns a failure.

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
- `Tests/Usage/`
- `Tests/Platform/Claude/`
- `Tests/Platform/Codex/`
- `Tests/Platform/Cursor/`
- `Tests/Platform/Networking/`
- `Tests/Platform/Persistence/`
- `Tests/Core/Models/`
- `Tests/Core/Configuration/`
- `Tests/App/`

Do not add deeper `unit/integration/e2e` folders unless suite volume or tooling requires them.

## Placement Rule

If a change affects account workflows, token-usage lifecycle, menu behavior, or settings state, it belongs in `Features`, with token-usage lifecycle tests owned by `Tests/TokenUsage/`.

If a change touches file paths, snapshot storage, Codex process control, app-server I/O, or process inspection, it belongs in `Platform`.

If a type is shared domain data or app-wide configuration, it belongs in `Core`.

If a change is only for startup, shutdown, isolated launch, or dependency wiring, it belongs in `App`.
