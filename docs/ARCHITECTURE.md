# Architecture

rusage is a local-first macOS menubar app for Codex, Claude Code and Cursor usage limits on this Mac. It was called CodexPill before.

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

- In Platform, next to its adapter, when the adapter is the only thing that implements it: `CodexAccountStatusClient`, `CodexAppProcessClient`, `CodexResetCreditClient`, `IsolatedCodexLoginClient`, `SecurityCommandRunning`.
- In the Features file that uses it, when a feature needs a narrower view of a Platform or Features type. The type adopts it through an extension in that same Features file, so its owner stays unaware of it: `MenuBarAccounts`.

App injects the adapter either way.

## Ownership Rules

### App

`Sources/App/` owns bootstrap, lifecycle wiring, and dependency assembly.

It does not own menu composition, account workflows, file I/O policy, Codex process control, or Codex protocol details.

### Features

`Sources/Features/` owns product behavior and presentation-neutral workflow policy.

`Features/Accounts` owns the one Codex account on this Mac: following `auth.json`, refreshing its limits, using a reset credit, and signing in to another account.

Key boundaries:

- `AccountsController`
- `AccountOperationState`
- `AccountActionFlow`
- `CodexSignInWorkflow`
- `ResetCreditResult`

`Features/TokenUsage` owns local token-usage history lifecycle and cache policy.

Key boundaries:

- `TokenUsageMenuRuntime`
- `TokenUsageMenuProviding`
- local token-usage aggregate cache

It coordinates cache-first loading, scan-task identity, duplicate-scan prevention, progress throttling, and cancellation when Token Usage is disabled. It depends on `Platform/Codex` scanner adapters for local Codex session records, but must not know AppKit menu construction or raw JSONL/session-path details.

`Features/Usage` owns every tool other than Codex: Claude Code and Cursor.

Key boundaries:

- `ProviderConnection`, the port one tool conforms to. See "How a tool plugs in" below.
- `UsageProviderSource`, the read half of that port. It returns a `UsageProviderReading`: not connected, unavailable with a `UsageUnavailableReason`, awaiting usage, or a `UsageSnapshot`. The reasons are not installed, signed out, sign-in expired (401 or past expiry), sign-in required (rusage's own sign-in is gone or rejected), Keychain access needed, sign-in unreadable, sign-in busy (the tool is writing it right now), access denied (403), rate limited (429), unreachable, service error (other status), and unexpected response.
- `ProviderCopy`, the one table of every word the menu shows for a tool: its name, who answers its usage requests, the confirmation before connecting or signing in, the message for each unavailable reason, and the notices a Claude sign-in can end with.
- `ClaudeCodeUsage` and `CursorUsage`, the two connections. Each wraps its Platform adapter, maps its values onto `UsageSnapshot`, and owns the opt-in setting. `ClaudeCodeUsage` also runs one browser sign-in at a time (`ClaudeBrowserSignInSession`) and picks the sign-in each read uses from `claudeUsesOwnSignIn`.
- `ProviderUsageRuntime`, which reads each connection at most once per its `refreshInterval` (5 minutes by default), however often the menu opens, and publishes one `ProviderUsageState` per tool: its status. A snapshot carries the email of the account the tool is signed in to, which the side menu shows. A snapshot older than `staleAfter` is published as `.stale`. When a tool is unavailable for a reason that keeps the same account, the runtime keeps the last good snapshot next to the reason. It also runs the actions the menu sends.

Tool states only feed menu sections. They never reach `AccountsController`, which reads `CodexAccount.usage`. The runtime refuses a connection for `.codex`.

### How a tool plugs in

A tool other than Codex is one type that conforms to `ProviderConnection` and is listed in `AppComposition`'s `providerConnections`:

```swift
protocol ProviderConnection: UsageProviderSource {
    var isConnected: Bool { get }
    func connect() async
    func disconnect() async
    var ownSignIn: ProviderOwnSignIn { get }
    func signIn() async throws(ProviderNotice)
    func signOut() async throws(ProviderNotice)
}
```

`ownSignIn`, `signIn()` and `signOut()` have default implementations for a tool without rusage's own sign-in, which is every tool but Claude. `ProviderUsageState` carries `ownSignIn`, so the menu decides from data whether to offer `Sign in with Claude…` or `Sign Out of Claude`.

Its words go in `ProviderCopy` under its `UsageProvider` case. Nothing else changes: no selector, coordinator property, or menu-builder branch names a tool.

- Every tool menu item, Codex included, carries a `ProviderMenuAction` (tool plus `ProviderAction`) and calls `MenuBarCoordinator.performProviderAction(_:)`.
- The coordinator asks the `ProviderCopy` confirmation, if any, then runs the action in a tracked task through `ProviderUsageRuntime.perform(_:on:)`.
- The runtime reads the tool again after every action. After a sign-in or sign-out it drops the tool's last snapshot first, because the account may have changed. A `ProviderNotice` from the action comes back to the coordinator, which shows it as an info alert.
- rusage never renews a tool's own sign-in or starts the tool. The runtime logs when a reading becomes expired, signed out, or in need of a new sign-in, with the category only.
- The port has no account methods: Claude Code and Cursor show only the account they are signed in to, and rusage never writes their sign-ins.
- Codex is not a connection: its usage lives on the one `CodexAccount` and signing in to another account is an interactive sign-in panel. The coordinator routes `.codex` actions to `AccountsController`, which refreshes the account after a sign-in and never runs a reset credit and a sign-in at the same time.

`Features/AppControls` owns app-level controls the Settings window offers: Launch at Login through `LoginItemController` and the System Settings launcher.

`Features/Diagnostics` owns the diagnostic report: `DiagnosticEventRecorder` keeps recent menu actions and refresh results, `DiagnosticReportBuilder` turns them and the menu state into a redacted report, and `DiagnosticReportPresenter` saves it where the user chooses.

`Features/MenuBar` owns menubar runtime, menu-state projection, menu rendering, the Settings window, native alert/panel presentation, and status-item behavior.

Key boundaries:

- `MenuBarCoordinator`
- `MenuBarAccounts`
- `MenuBarMenuBuilder`
- `SettingsWindow`, `SettingsPane` and `SettingsWindowState` (below)
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

- reading and, after a confirmed sign-in, replacing `auth.json` (`CodexAuthFile`);
- isolated Codex login process execution;
- Codex app-server JSON-RPC I/O;
- Codex CLI process inspection;
- Codex app process control;
- the default Codex sessions folder read for token usage, `CodexSessionTokenUsageScanner.defaultSessionsDirectory()`.

Reusable Codex app-server access is split into these platform boundaries:

- `CodexAppServerClient` is the production facade used by rusage account reads. It turns a local `CodexAppServerConfiguration` into a session command for the shared session runner.
- `CodexAppServerConfiguration` owns executable path, environment, and timeout policy.
- `CodexAppServerSession` owns JSON-RPC request construction and response sequencing.
- `CodexAppServerSessionRunner` owns the reusable app-server session execution loop used by local reads: process launch, stdin/stdout/stderr pipe wiring, request writing, output draining, timeout completion, partial-status completion, and finish-once coordination. It also runs the one-request `account/rateLimitResetCredit/consume` session that spends a Codex reset credit.
- `CodexAppServerAccountParser` and `CodexAppServerRateLimitParser` map raw app-server payload DTOs into generic app-server DTOs.
- `RUsageAccountStatusMapper` maps generic app-server DTOs into rusage account and rate-limit models.

Local app-server reads enter this session runner through `CodexAppServerClient`, which keeps local executable, environment, client-info, and timeout in `CodexAppServerConfiguration`.

The account's read (`readCurrentAccountStatus`) is complete once it has the account and at least one limit window of any length. A Pro plan reports only a weekly window and a free plan only a monthly one. Only a read with no window runs the app-server again, once after 1 second with `refreshToken: true`. A failed read is tried again after 1 second, and once more after 3 seconds when Codex says the rate-limit read failed. Windows and account fields from the attempts merge, the newest winning.

`Platform/Claude` owns everything rusage knows about Claude Code and Claude's OAuth. It never writes Claude Code's files or Keychain item. It owns:

- reading its sign-in from `.credentials.json` and the `Claude Code-credentials` Keychain item, which it reads through `/usr/bin/security` as Claude Code does, so Claude Code's renewals don't bring back a Keychain prompt, and never writes (`ClaudeCredentialsSource`, `SystemClaudeKeychain`, `ClaudeCodeSecurityKeychain`), and the plan tier and email from the account record in its global config;
- the `api.anthropic.com/api/oauth/usage` and `/api/oauth/profile` requests, their redirect rule, the rate-limit wait, and parsing the responses (`ClaudeUsageAPI`, `ClaudeUsageClient`). `ClaudeUsageClient` reads with Claude Code's sign-in or rusage's own, as `ClaudeSignInSource` says, and never falls back from one to the other;
- rusage's own opt-in sign-in: the PKCE browser flow with its loopback receiver (`ClaudeOAuth`, `ClaudeBrowserSignIn`, `LoopbackClaudeOAuthReceiver`), the token endpoint (`ClaudeTokenEndpoint`), the stored sign-in (`ClaudeSignIn`, `ClaudeSignInStoring` with `SystemClaudeSignInKeychain` for the `rusage Claude sign-in` item and `FileClaudeSignInStore` for isolated runs and tests), the cross-process lock (`ClaudeRefreshLock`), and its renewal (`ClaudeOwnSignIn`).

**Renewal boundary.** Only `ClaudeOwnSignIn` sends a refresh token, and only rusage's own. It renews inside one in-process task and under the `flock` on `claude-sign-in.lock`. Under the lock it reads the item again and uses it when another process already renewed it. It saves the item with `refreshPending` set before it sends the refresh token, and clears it in the same write that saves the new pair. An item still marked when the lock is taken never saved its result: it is deleted and the user signs in again, so a spent token is never sent twice. A pair the store refuses stays in memory and wins over the store. `invalid_grant` deletes only rusage's item.

The access token leaves this module only as an `Authorization` header to api.anthropic.com. Nothing in it reads, sends, or renews Claude Code's refresh token; a test scans the Claude sources so that only the own-sign-in files mention a refresh token and none of them names Claude Code's sign-in. Nothing in it starts `claude`: only the user's own `claude` renews Claude Code's sign-in.

`Platform/Cursor` owns everything rusage knows about Cursor. It never writes Cursor's database or quits Cursor. It owns:

- `CursorStateDatabase`, keyed read-only access to `state.vscdb`. It never scans. A read opens the database with `immutable=1` only when no `-wal`, `-shm`, or `-journal` file sits next to it, so it never reads a writer's uncommitted pages;
- `CursorStateDatabaseTokenSource`, the read-only lookup of the token and the cached email used for usage, and `CursorAccessToken`, which prints redacted;
- the `cursor.com/api/usage-summary` request, its redirect rule, its `Retry-After` wait, and parsing its response (`URLSessionCursorUsageWebClient`, `CursorUsageClient`, `CursorUsageSummaryParser`).

The token leaves this module only as the usage request's cookie.

`Platform/Networking` owns HTTP rules shared by tools, such as `RetryAfter`, which reads a `Retry-After` header given as seconds or an HTTP date.

`Platform/Persistence` owns:

- rusage paths, including where `auth.json` lives (`AppPaths.codexAuthFile`);
- isolated `CODEX_HOME` session paths for sign-in;
- `CodexPillMigration`, the one-time copy of CodexPill's folder, preferences and Keychain items at launch;
- the token-usage cache file, `TokenUsageCacheFileStore` at `AppPaths.tokenUsageCacheFile(isolatedRootDirectory:)`.

Platform adapters are the only place where the app should know about live auth files, `codex app-server`, process inspection, or relaunch mechanics.

### Core

`Sources/Core/` is models plus typed preferences:

- `CodexAccount`, the one Codex account, held in memory with its identity and last reading
- `CodexRateLimits`, Codex plan-type rules and `UsageSnapshot.codex(planName:primary:secondary:fetchedAt:)`, the only place that turns Codex's positional primary and secondary windows into named windows, shortest first
- `Usage`, the provider-neutral usage model: `UsageSnapshot` holds a provider, the plan name the provider reported, the signed-in email for Claude and Cursor, and `UsageWindow` values keyed by `UsageWindowKind` (session, weekly, monthly, billing cycle, or other with its length). `UsageWindowKind(durationMinutes:)` is the one rule that names a window by its length, with its tolerances. `UsageWindow.displayedUsedPercent(at:)` is the one rule for showing 0% once a window has reset. `CodexAccount.usage` and `CodexAccountStatus.usage` store it directly.
- `StatusBarIndicatorStyle` and `StatusBarDisplayMode`, the persisted status-item choices
- settings groups, their `Preferences` codec and the `SettingsModel` that owns them

Core models should remain free of process control, storage policy, AppKit, SwiftUI, and Codex protocol mechanics.

Settings are values with one owner, as rbar keeps them:

- Each group is one `SettingsGroup`: a `Codable`, `Equatable`, `Sendable` struct with `defaults`, stored as one JSON value under a versioned key. `GeneralSettings` holds the refresh interval, tool order, email masking and theme. `MenuBarSettings` holds the icon, label, usage bar and reveal-shortcut choices. `TokenUsageSettings` holds whether the Token Usage card shows and how it draws. `CodexSettings`, `ClaudeSettings` and `CursorSettings` hold whether each tool is connected, and Claude's sign-in source and model limits.
- `Preferences` is the only code that reads or writes settings in `UserDefaults`. A field that is missing or no longer decodes takes its default and keeps the rest of its group. A group whose key is missing is read from the flat keys earlier versions stored (`LegacySettingsKeys.swift`), so nothing is migrated.
- `SettingsModel` is the single writer. It is `@Observable` on the main actor, saves each group as it changes, and `MenuBarCoordinator` observes `general`, `menuBar` and `codex` whole, so a new field needs no new observation. Token Usage is left out because its card redraws itself and a rebuild would make an open menu jump.
- Claude's and Cursor's groups are `SettingsCell`s, because their usage sources read and change them off the main actor. A cell takes a lock for every read and change and saves before releasing it. App startup gives each source the model's own cell, so there is one copy of each group.

| State | Single writer |
| --- | --- |
| Refresh interval, tool order, email masking, theme | `SettingsModel.general` |
| Menu bar icon, label, usage bars, reveal shortcut | `SettingsModel.menuBar` |
| Token Usage card on or off, chart style, breakdown, peak scope | `SettingsModel.tokenUsage` |
| Whether Codex is read | `SettingsModel.codex` |
| Whether Claude and Cursor are connected, Claude's sign-in source and model limits | `SettingsModel.claude` and `.cursor` |
| Launch at Login | `SMAppService`, read each time and never stored |

### Settings Window

The menu is for glancing and quick actions; configuration lives in one window, modeled on rbar's. `SettingsWindow` owns our own `NSWindow`, not SwiftUI's `Settings` scene, which an accessory app can't reliably bring forward. Its `NSTabViewController` uses toolbar tabs, one per `SettingsPane`, each a grouped SwiftUI `Form` in an `NSHostingController` sized by `preferredContentSize`. The title follows the pane, minimize and zoom are off, and the last pane is restored.

- `Settings…` (⌘,) runs `MenuBarCoordinator.openSettings()`. ⌘, fires while the menu still tracks, and an activation then is lost when it closes, so the coordinator opens the window from `menuDidClose`.
- While the window shows, the app is `.regular` with a Dock icon and comes forward with `activate(ignoringOtherApps:)`. It goes back to `.accessory` when the window closes. A minimal main menu answers ⌘, ⌘W ⌘Q and text editing while the window is key.
- Closing the window drops its content, so nothing observes the settings while it is closed.
- Controls that only store a value bind straight to `SettingsModel`, and the coordinator's settings observation rebuilds the menu. Anything with side effects goes through `SettingsActions`, which the coordinator implements: showing or hiding a tool runs the same `.connect` and `.disconnect` actions the menu used, so their consent alerts still show, the Accounts pane sends every account action (`Use Another Account…`, sign-in, `Allow Keychain Access…`) through `perform(_:on:)`, the menu's own entry point, and Launch at Login, the reveal shortcut, Token Usage and Claude's model limits keep their coordinator paths.
- `SettingsWindowState` is the `@Observable` copy of what the window shows that isn't a stored setting: the tools with a card and their `ToolSection`s, the login item state, whether the menu bar can show text, and Claude's model limits. The coordinator updates it from `MenuBarMenuState` each time it rebuilds the menu and when the window comes forward. Panes do no file I/O and start no processes.

## Boundary Notes

`AppComposition` is the App composition root. It chooses the production adapters, builds the `AccountsController`, and constructs `MenuBarCoordinator` with every collaborator passed in. `MenuBarCoordinator.init` has no production defaults, so a new collaborator is wired in one place. Tests build the coordinator through `Tests/Support/MenuBarCoordinatorTestFactory.swift`.

`AppRuntimeEnvironment` is read only in `Sources/App`. App turns the process environment into plain values and passes them in: the isolated root for `AppPaths` (`auth.json` through `CODEX_HOME`) and the token-usage cache, the isolated defaults suite, and whether system alerts and panels suppress interactive prompts. Features and Platform code never read `AppRuntimeEnvironment`.

`AppComposition` builds the account feature: one `CodexAuthFile` for `AppPaths.codexAuthFile`, shared by `AccountsController` and `CodexSignInWorkflow`, with `CodexAppServerClient` as the `CodexAccountStatusClient` and `SystemCodexAppProcessClient` for relaunch. App hands the controller to `MenuBarCoordinator` as `MenuBarAccounts`.

`CodexAuthFile` (Platform) is the one Codex sign-in on this Mac: `~/.codex/auth.json`, or `$CODEX_HOME/auth.json` in isolated runs. It reads the file, builds a `CodexAccount` from it without a reading, fingerprints it, and writes it (0600) only for a confirmed sign-in.

`AccountsController` owns the one `CodexAccount`, in memory. It follows `auth.json`: rotated tokens keep the account and its last reading, a different sign-in replaces both, and a missing file means signed out. It refreshes limits with `readCurrentAccountStatus`, spends reset credits with an idempotency key kept until Codex answers, and runs sign-in. A reset and a sign-in never overlap.

`CodexSignInWorkflow` runs the isolated device-code sign-in in a temporary `CODEX_HOME` and holds the result in memory. It refuses the account already in use and a sign-in during which `auth.json` changed. Only `use(_:)` writes `auth.json` and relaunches Codex.

`AccountActionFlow` owns account action sequencing decisions that do not require AppKit access. It converts sign-in outcomes into presentation-neutral next steps: confirm the replacement, or one failure step (prompt unavailable, expired code with retry, capture failed, verification failed, Codex app not found, `auth.json` changed meanwhile, account already in use). MenuBar renders those steps into alerts and retry panels without deriving recovery policy from platform login errors.

`TokenUsageMenuRuntime` is the token-usage feature boundary used by MenuBar. It owns background scan lifecycle, cache-first load state, duplicate-scan prevention, progress throttling, and disable-time cancellation. `MenuBarCoordinator` should only mutate Token Usage preferences, ask the runtime for current load state, and decide whether AppKit menu rebuilds are safe while a menu is being tracked.

`MenuBarCoordinator` owns the `ProviderUsageRuntime` and exposes its states as `MenuBarMenuState.providerUsage`. It holds no tool-specific property or selector: tool actions arrive through `performProviderAction(_:)`. Token usage and provider usage share one path: startup and opening the menu ask both to refresh if due, the scheduled refresh also refreshes providers, and both report changes through `rebuildMenuWhenSafe()`, which waits until the menu is closed.

`MenuBarAccounts` is the port MenuBar declares for account state and intents. It lists only the members the menu reads or calls, and `AccountsController` conforms to it directly. MenuBar never sees the account use cases or Platform adapters behind the controller.

`MenuBarCoordinator` is the menu/application controller. It owns menu rebuilding, selector dispatch, alert/panel presentation, user-response plumbing, wake/timer refresh triggers, and coordination between account and status-item boundaries. Selector handlers and observation callbacks are synchronous, so the coordinator starts their async work through `TrackedTasks`. Tests call `waitForPendingWork()` instead of sleeping.


`StatusItemRuntime` owns the `NSStatusItem`, hover tracking, pointer-inside detection, title/icon transitions, tooltip rendering, and low-level status-item snapshot state.

Reveal-shortcut capture, menu key-equivalent rendering, display formatting, and Carbon hot-key registration are menubar/status-item runtime and presentation concerns. Core owns only the persisted shortcut value: key code, modifier option set, default value, and validity semantics. Core shortcut types must not import AppKit or Carbon.

## Truth Sources

The current truth sources are split by concern:

- the Codex account: `~/.codex/auth.json`;
- local account metadata and rate limits: local `codex app-server`;
- running CLI session observation: local process table inspection;
- Claude Code usage: `api.anthropic.com/api/oauth/usage`, authenticated with Claude Code's local sign-in token, or with rusage's own sign-in once the user chose it;
- rusage's own Claude sign-in: claude.com in the browser to approve it, and `platform.claude.com/v1/oauth/token` to sign in, renew and revoke;
- Cursor usage: `cursor.com/api/usage-summary`, authenticated with Cursor's local sign-in token.

Rules:

- `~/Library/Application Support/rusage` is rusage-owned state and holds no Codex sign-in rusage reads. `accounts.json` and `snapshots/` left there by earlier versions are never read or deleted; `CodexPillMigration` may still copy them over from CodexPill.
- `~/Library/Application Support/Codex` is only an observation surface when needed.
- Rate limits should come from app-server surfaces, not manual counters.
- Tests must use temp paths and injected process clients.

## Naming Conventions

Name boundaries by the role they play in the app, not by an implementation detail or a verb phrase.

Preferred suffixes:

- `Client` for an external service, process, or CLI.
- `Store` for durable persistence.
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

If a change touches file paths, `auth.json`, Codex process control, app-server I/O, or process inspection, it belongs in `Platform`.

If a type is shared domain data or app-wide configuration, it belongs in `Core`.

If a change is only for startup, shutdown, isolated launch, or dependency wiring, it belongs in `App`.
