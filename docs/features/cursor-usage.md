# Cursor Usage

## User Story

As a Refill user who also codes in Cursor, I want to see how much of my Cursor plan I have used this billing cycle and when it resets, so I can decide which tool to reach for without opening Cursor's dashboard.

## Product Contract

Cursor Usage is an optional menu bar feature. When connected, Refill shows the signed-in Cursor account's included-plan usage, any on-demand spend, and the billing-cycle reset date.

Reading usage never changes anything in Cursor. Refill never signs in to Cursor with its own code and never renews a Cursor token. If Cursor's sign-in is missing or expired, Refill says so and points the user back to Cursor. Adding an account runs Cursor's own sign-in in a separate window, described in [Adding A Cursor Account](#adding-a-cursor-account). Switching Cursor between saved sign-ins is a separate, explicit action, described in [Cursor Account Switching](#cursor-account-switching).

The feature is off by default. Connecting it is the user's consent for Refill to read Cursor's local sign-in token and send it to cursor.com.

Cursor usage is display-only. It never feeds account availability, ranking, or notifications, which stay Codex-only.

## Menu

The `Cursor` card follows the shared card and side menu in [Menubar](menubar.md). The side menu switches between saved Cursor sign-ins. `Disconnect Cursor` is in Settings.

- **Not connected.** There is no card. `Settings › Add Account › Cursor…` (and the first-run `Add Account ›`) connects. Choosing it opens a consent alert first. Nothing is read until the user confirms.
- **Consent alert.** One short alert:

  > **Connect Cursor?**
  > Uses Cursor's sign-in to read your usage.

  Confirming saves the choice and reads at once.
- **Connected.** The choice is saved in user defaults (`cursorUsageEnabled`, off by default). `Disconnect Cursor` in Settings turns the feature off at once with no alert, because it changes nothing outside Refill.
- **Current.** The plan tag (`Pro`), one `Billing cycle` meter with `Resets 30 Oct`, and, when on-demand usage is enabled, a text line: `On-demand: $12.34 of $50.00`, or `On-demand: $12.34` with no cap. Spend is never drawn as a bar. The meter follows the percent mode, layout, pacing markers, and the weekly color.
- **No percent.** A plan with no included-usage percent, such as an unlimited plan, shows the header with no meter. It never shows 0%.
- **Failures.** Each failure shows a title and at most one short line. Except for not installed and signed out, the last good values stay dimmed below it with their `As of` time.

  | Cause | Title | Second line |
  |---|---|---|
  | No `state.vscdb` on this Mac | `Cursor isn't installed` | none |
  | No usable access token | `Not signed in to Cursor` | `Sign in to Cursor to see usage.` |
  | Token within a minute of expiry, or `401` | `Cursor sign-in expired` | `Open Cursor to renew it.` |
  | `state.vscdb` unreadable | `Can't read the Cursor sign-in` | `Sign in to Cursor again.` |
  | `state.vscdb` locked, or a hot journal | `Cursor is busy` | `Retrying in a few minutes.` |
  | `403` | `Cursor won't share usage` | `Sign in to Cursor again.` |
  | `429`, or waiting out `Retry-After` | `Cursor asked to wait` | `Retrying in a few minutes.` |
  | No answer (offline, DNS, TLS, timeout) | `Can't reach Cursor` | `Retrying in a few minutes.` |
  | Any other status | `Cursor is having trouble` | `Retrying in a few minutes.` |
  | A `200` that is not the usage shape | `Unexpected reply from Cursor` | `Retrying in a few minutes.` |
- **Stale.** A snapshot older than 15 minutes is dimmed. Its label still reads `As of …` until the next read.

Reads happen when the menu opens or on the scheduled refresh, at most every 5 minutes. Connecting and disconnecting read at once.

## Source Contract

All knowledge of Cursor's database and of cursor.com lives in `Sources/Platform/Cursor`. Feature and UI code see parsed values only.

**Sign-in.** Cursor keeps its session in a VS Code style SQLite database, `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`. Usage reads one row: table `ItemTable`, key `cursorAuth/accessToken`. The value is a JWT, SQLite TEXT on current builds and a UTF-8 or UTF-16LE BLOB on others. Refill takes the user ID from its `sub` claim and the expiry from `exp`.

**Database reads.**

- Read-only, with one keyed lookup per row. Never a scan: on a typical Mac the database is several gigabytes.
- With no `-wal`, `-shm`, or `-journal` next to the database, it is idle, and Refill opens it with SQLite's `immutable=1`, so it never creates a file in Cursor's folder.
- With any of them present, Cursor has it open or crashed mid-write. Refill then opens it normally read-only, so SQLite reads only committed data, or refuses a hot journal. Either way a locked database or a hot journal shows "Cursor is busy" and keeps the last numbers until a later read. `immutable=1` would read the uncommitted pages.

**Request.** `GET https://cursor.com/api/usage-summary` with Cursor's web session cookie built from the token. The HTTP session has no cookie store and no URL cache, and refuses every redirect, so the token never reaches another host. Refill does not call `/api/auth/me`.

**Response.** Observed on 2026-10-09:

- `membershipType` is the plan name, for example `pro`.
- `individualUsage.plan.totalPercentUsed` is the included-usage headline in percent, matching Cursor's dashboard. It can differ from `plan.used / plan.limit`, because bonus credit counts against the dollar figures. Refill uses the percent, and falls back to `used / limit` only when the percent is missing. An unlimited or disabled plan has no percent.
- `individualUsage.onDemand` carries on-demand spend in cents when `enabled` is true. A null `limit` means no cap.
- `billingCycleStart` and `billingCycleEnd` are ISO 8601. The end is the reset.

**Mapping.** One `UsageWindow` of kind `billingCycle`, with `usedPercent` from the percent, `resetsAt` from `billingCycleEnd`, and `durationMinutes` from the cycle length. No percent means no window. On-demand spend goes to `UsageSnapshot.spend` as dollars with an optional cap, because it is money, not a percent of a limit.

## Read Policy

- Token within 60 seconds of expiry: no request. Cursor renews it the next time it runs.
- `401`: sign-in expired. `403`: access denied.
- `429`: no database read and no request until `Retry-After` passes, given as seconds or an HTTP date, or 5 minutes when the header is missing or unreadable. The menu shows rate limited meanwhile.
- Network failure: unreachable. Another status: service error. An unreadable body: unexpected response.
- The shared provider runtime keeps the last good values for every failure except not installed and signed out, which may mean a different Cursor user. The Cursor client keeps no copy of its own.
- Refill holds the token only for the length of one read. It never stores, logs, displays, or refreshes it. `CursorAccessToken` prints as `CursorAccessToken(redacted)` and reflects no children.

## Isolated Runs

With `CODEXPILL_ISOLATED_APP_SUPPORT_DIR` set, Refill never touches the real Cursor:

- Usage reads `<root>/Cursor/state.vscdb`. A missing file reads as not installed. The request still goes to cursor.com with whatever token that file holds.
- Saved accounts live in `<root>/cursor-accounts.json`, never the Keychain. A switch rewrites only `<root>/Cursor/state.vscdb` and never quits or opens Cursor.
- `Add Cursor Account…` runs the stand-in executable `<root>/bin/cursor` with the same `--user-data-dir` and `--extensions-dir` arguments, instead of opening Cursor.app. Without it, the add item reads `Install Cursor first`. Profiles go under `<root>/cursor-sign-in`, so keep `<root>` short: the profile path plus 15 bytes must fit Cursor's 103-byte socket limit.

## Cursor Account Switching

Refill can save Cursor sign-ins and switch Cursor between them from the Cursor side menu ([Menubar](menubar.md)). It works whether or not Cursor usage is connected.

### User Story

As someone with a personal and a work Cursor account, I want to save both and switch Cursor between them from the menu bar, so I don't have to sign out and back in through the browser each time.

### Product Contract

- **Add.** `Add Cursor Account…` signs in through Cursor in a separate window, described in [Adding A Cursor Account](#adding-a-cursor-account).
- **Saved automatically.** Once Cursor is connected, the account Cursor is signed in to is saved as soon as a read finds its user missing from the list: on connect, on each refresh, and after Cursor signs in to another account on its own. Accounts match by Cursor's user ID. A user who is saved already keeps the saved copy; a switch refreshes it. Cursor need not quit. There is no save item.
- **Switch.** The menu asks first, then Refill quits Cursor, writes the saved sign-in, and reopens Cursor:

  > **Switch Cursor account?**
  > Cursor will quit and reopen.

- **Rename and remove** change only Refill's list. Removing the account Cursor is signed in as leaves Cursor signed in.
- **Matching.** The account Cursor is signed in as is the saved account whose user ID, from the access token's `sub` claim, matches.
- **Errors.** Each `CursorAccountsError` has a short alert from `MenuBarAlertFactory.makeCursorAccountErrorRequest`:

  | Error | Title | Second line |
  |---|---|---|
  | `cursorNotInstalled` | `Cursor isn't installed` | `Install Cursor, then try again.` |
  | `signedOut` | `Cursor isn't signed in` | `Sign in to Cursor first.` |
  | `accountNotFound` | `Account not found` | `It may have been removed.` |
  | `savedAccountsUnreadable` | `Can't read saved accounts` | `Try again in a moment.` |
  | `stateUnreadable` | `Can't read Cursor's sign-in` | `Open Cursor, then try again.` |
  | `cursorDidNotQuit` | `Cursor didn't quit` | `Save your work, then try again.` |
  | `cursorBusy` | `Cursor is still closing` | `Wait a moment, then try again.` |
  | `writeFailed` | `Couldn't switch` | `Nothing was changed.` |
  | `reopenFailed` | `Cursor didn't reopen` | `Open Cursor yourself.` |
  | `switchingUnavailable` | `Switching unavailable` | `This build can't switch accounts.` |

### Switch Contract

A Cursor sign-in is these 8 rows of `ItemTable` in `state.vscdb`, observed on 2026-10-10:

`cursorAuth/accessToken`, `cursorAuth/refreshToken`, `cursorAuth/cachedEmail`, `cursorAuth/cachedScopedProfile`, `cursorAuth/cachedSignUpType`, `cursorAuth/stripeMembershipAuthId`, `cursorAuth/stripeMembershipType`, `cursorAuth/stripeSubscriptionStatus`.

Rules:

- Saved values live only in the `CodexPill Cursor accounts` Keychain item, one item for all saved accounts. Each value keeps its SQLite storage class (TEXT or BLOB), so it is written back exactly as Cursor wrote it.
- Every statement names its key. Refill never scans the database, and writes no table other than `ItemTable` and no row outside the 8 keys.
- Switching runs in this order, and stops at the first failure:
  1. Ask Cursor to quit and wait up to 15 seconds for it to exit. Never force-quit: Cursor may be asking about unsaved work. If it is still running, nothing is written and Cursor is left as it is (`cursorDidNotQuit`).
  2. Open the database read-write and run `PRAGMA wal_checkpoint(TRUNCATE)`. If another connection still holds it, such as a Cursor helper that has not exited, SQLite reports busy after a 5 second wait and nothing is written (`cursorBusy`).
  3. Read the current rows again and save them over the matching saved account, because Cursor may have renewed its tokens since they were captured. A signed-in account that was never saved is saved under its email, so a switch never strands a sign-in. If this Keychain write fails, nothing is written to Cursor.
  4. In one `BEGIN IMMEDIATE` transaction, replace each of the target's rows and delete any of the 8 keys the target lacks, so nothing of the outgoing account stays behind.
  5. Checkpoint again, close, and open Cursor.
- If anything fails after Cursor quit, Cursor is reopened on the sign-in it had, and the error is returned.
- Choosing the account Cursor is already signed in as writes nothing and only reopens Cursor.

Tests use temporary fixture databases and an in-memory account store, and never open the real database or Keychain item.

### Adding A Cursor Account

`Add Cursor Account…` runs Cursor's own sign-in in a separate Cursor window, so the account in use is not touched. `CursorIsolatedLogin` owns it.

1. Make a new folder, `<AppSupport>/cursor-sign-in/<8 hex>`, readable only by the user. Cursor names its IPC socket `<user-data-dir>/<version>-main.sock` and quits silently when that path passes macOS's 103-byte limit, so a longer path is refused before Cursor opens (`Couldn't prepare the sign-in`).
2. Open Cursor.app as a new instance, like `open -n`, with `--user-data-dir=<folder>` and `--extensions-dir=<folder>/extensions`. `NSWorkspace.openApplication` returns the new instance's PID. The user's own Cursor keeps running. The card reads `Sign in in the new Cursor window` with `Cancel Sign-In`.
3. Every second, read the folder's `state.vscdb` by key. It is in WAL mode while Cursor runs, so a busy or half-written read is tried again. Once `cursorAuth/accessToken` appears, wait up to 5 seconds for `cachedEmail`, which Cursor writes a moment later.
4. Quit that instance by PID, never by bundle ID, and only if the process with that PID is Cursor. Force-quit it after 10 seconds. Read the rows again after it quits, since Cursor flushes its last writes then.
5. Save the sign-in (the same Cursor user replaces its saved copy), connect Cursor usage, and read the new account's limits at once.
6. Delete the folder, on every path: success, failure, a 5-minute timeout, the window closed before signing in, or `Cancel Sign-In`. Folders left by a crash are deleted at the next launch.

| Outcome | Title | Second line |
| --- | --- | --- |
| Cursor not installed | `Install Cursor first` | none |
| Cursor didn't open | `Couldn't open Cursor` | `Try again in a moment.` |
| Window closed before signing in | `Cursor sign-in didn't finish` | `Nothing was saved.` |
| No sign-in after 5 minutes | `Cursor sign-in timed out` | `Nothing was saved.` |
| Folder could not be made | `Couldn't prepare the sign-in` | `Nothing was saved.` |
| Cancelled | none | none |

A switch of Cursor while the sign-in runs is refused (`Finish signing in first` / `Or cancel the sign-in.`), because a switch quits every Cursor, including the sign-in window.

**Side effects on `~/.cursor`.** The temporary window is a full Cursor. A fresh `--user-data-dir` does not isolate `~/.cursor`, so while the window runs it starts the user's MCP servers from `~/.cursor/mcp.json` and writes `~/.cursor/ai-tracking`. Observed with Cursor 3.21 on 2026-10-11. This is the accepted cost of signing in through Cursor itself.

### Inactive Accounts

Every 15 minutes, one at a time, each saved account Cursor is not signed in to is read with its own saved access token, through the same request as the card. Its limits are saved on the account in the `CodexPill Cursor accounts` item, only if the saved sign-in is still the one read with. A switch may have saved tokens Cursor renewed meanwhile, and a stale read must not undo that.

Refill never renews a saved token. Cursor renews by posting to its own `oauth/token` endpoint while it runs with that profile, and the refresh token changes on every renewal. Once a saved token is within a minute of expiry, nothing is sent, and the side menu keeps the account's last line with its time. A `429` on an inactive read does not hold back the card's read.

### Other Places Cursor Keeps Identity

Observed on a maintainer's Mac on 2026-10-10 with Cursor 3.21.16, by key name only:

| Where | What | Switch writes it? |
| --- | --- | --- |
| `ItemTable` `glass.lastSignedInAuthId`, `adminSettings.cachedAuthId` | The signed-in auth ID, equal to `stripeMembershipAuthId`. | No. Cursor sets these itself after sign-in. |
| `ItemTable` `src.vs.platform.reactivestorage…persistentStorage.applicationUser` | A large JSON blob of cached server state, including `membershipType`, `subscriptionStatus`, `dashboardUserId`, team admin settings, allow and block lists, and privacy mode. | No. It mixes account and editor state, so it cannot be swapped as a unit. |
| `ItemTable` keys containing the auth ID, such as cloud-agent and recent-activity caches | Per-user caches, already namespaced by user. | No. They do not collide between accounts. |
| `ItemTable` `cursorai/donotchange/privacyMode` and related keys | Privacy mode, which a team can enforce. | No. |
| `~/.cursor/cli-config.json` (`authInfo`) and Keychain items `cursor-access-token`, `cursor-refresh-token` | The Cursor CLI's own sign-in. | No. Out of scope. |
| `Cookies` under `~/Library/Application Support/Cursor` | Chromium cookies for Cursor's embedded web views. | No. |

Not verified yet, because it needs a real switch against a real Cursor install:

- that Cursor accepts swapped rows on launch without signing out, and refreshes the cached auth ID keys and the `applicationUser` blob for the new account;
- whether a stale team privacy mode or team settings from the outgoing account show briefly before Cursor refreshes them;
- how long a saved refresh token stays valid while its account is inactive;
- whether Cursor Settings Sync, if turned on, carries anything account-specific between the two accounts;
- the sign-in in a separate window against a real Cursor, the rows it writes, and the token lifetime. The maintainer check `cursor-accounts-check.sh` (kept outside the repo) covers it and has not run yet.

### Switching Risks

- **Cursor running.** Refill only writes after Cursor has exited and SQLite confirms no other connection holds the database. A Cursor that will not quit, or a helper that lingers, makes the switch fail with nothing written.
- **Corrupted or unexpected database.** Any SQLite error, including a missing `ItemTable`, aborts before or inside the transaction, so the database is either unchanged or fully switched. Refill does not run `integrity_check`: on a 10 GB database it is too slow for a menu action.
- **Format drift.** If Cursor moves its sign-in out of these rows, a switch would write stale rows Cursor ignores. The rows written are the 8 known keys only, so the damage is limited to Cursor's sign-in, which the user can redo in Cursor.
- **Token lifetime.** A saved inactive account's refresh token can expire or be revoked. Switching to it then lands in Cursor's own sign-in prompt.

## Privacy

The user-facing summary lives in [PRIVACY.md](../PRIVACY.md).

## Validation

- `CursorAccessTokenTests` and `CursorStateDatabaseTokenSourceTests` parse literal tokens in every storage class, prove no files appear next to an idle database, read a live WAL database, and prove a hot rollback journal is reported as busy and never yields the uncommitted token.
- `CursorUsageSummaryParserTests` and `CursorUsageClientTests` cover the response mapping, the expiry gate, each HTTP status, and the `Retry-After` wait.
- `CursorUsageTests` cover opt-in, each failure reason, the unlimited plan with no meter, on-demand spend, and switching through `CursorUsage`.
- `CursorAccountsTests` cover saving, switching only the 8 rows, quitting before writing, Cursor that won't quit, a database another process holds, a corrupted database, and the Keychain payload printing redacted.
- `CursorAlertTests` check that every switch failure reads differently and stays a title plus one short line.
- `CursorAccountsAddTests` drive the add flow against fake Cursor instances that keep a WAL database: the saved rows, waiting for the email row, only the sign-in PID quit, the profile deleted after quit on every path (cancel, timeout, early quit, launch failure), a cancelled sign-in waiting for a real stand-in process to quit, the socket path limit, leftover sweeping, inactive reads with the account's own token, no renewal of an expired token, and the compare and swap against a switch.
- A coordinator test walks the menu from `Add Account › Cursor…` through declined consent, current usage, a failed read that keeps the last values, and disconnect, reading the built `NSMenu`.
- No test touches the network, the real Cursor database, or the real Keychain.

## Out Of Scope

- Team and enterprise pooled budgets and legacy request-count plans.
- Browser cookie import, WebViews, and manual cookie entry.
- Signing in to Cursor with Refill's own code, or renewing a Cursor token.
- Switching the Cursor CLI (`cursor-agent`) sign-in.
