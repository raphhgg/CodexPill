# Cursor Usage

## User Story

As a CodexPill user who also codes in Cursor, I want to see how much of my Cursor plan I have used this billing cycle and when it resets, so I can decide which tool to reach for without opening Cursor's dashboard.

## Product Contract

Cursor Usage is an optional menu bar feature. When connected, CodexPill shows the signed-in Cursor account's included-plan usage, any on-demand spend, and the billing-cycle reset date.

Reading usage never changes anything in Cursor. CodexPill never signs in to Cursor and never renews Cursor's session. If Cursor's sign-in is missing or expired, CodexPill says so and points the user back to Cursor. Switching Cursor between saved sign-ins is a separate, explicit action, described in [Cursor Account Switching](#cursor-account-switching).

The feature is off by default. Connecting it is the user's consent for CodexPill to read Cursor's local sign-in token and send it to cursor.com.

Cursor usage is display-only. It never feeds account availability, ranking, or notifications, which stay Codex-only.

## Menu

A `Cursor` section sits below `Claude Code`. It has no switching actions yet.

- **Not connected.** The section shows `Connect Cursor…`. Choosing it opens a consent alert first. Nothing is read until the user confirms.
- **Consent alert.** One short alert:

  > **Connect Cursor?**
  > Uses Cursor's sign-in to read your usage.

  Confirming saves the choice and reads at once.
- **Connected.** The choice is saved in user defaults (`cursorUsageEnabled`, off by default). `Preferences` gains `Disconnect Cursor…`, which turns the feature off at once with no alert, because it changes nothing outside CodexPill.
- **Current.** A caption with the plan and the read time (`Pro plan · As of 10:42`), one `Billing cycle` meter with `Resets Oct 30`, and, when on-demand usage is enabled, a text line: `On-demand: $12.34 of $50.00`, or `On-demand: $12.34` with no cap. Spend is never drawn as a bar. The meter follows the percent mode, layout, pacing markers, and the weekly color.
- **No percent.** A plan with no included-usage percent, such as an unlimited plan, shows the caption with no meter. It never shows 0%.
- **Failures.** Each failure shows a title and at most one short line. Except for not installed and signed out, the last good values stay dimmed below it with their `As of` time.

  | Cause | Title | Second line |
  |---|---|---|
  | No `state.vscdb` on this Mac | `Cursor isn't installed` | none |
  | No usable access token | `Not signed in to Cursor` | `Sign in to Cursor to see usage.` |
  | Token within a minute of expiry, or `401` | `Cursor sign-in expired` | `Open Cursor to renew it.` |
  | `state.vscdb` unreadable | `Can't read the Cursor sign-in` | `Sign in to Cursor again.` |
  | `403` | `Cursor won't share usage` | `Sign in to Cursor again.` |
  | `429`, or waiting out `Retry-After` | `Cursor asked to wait` | `Retrying in a few minutes.` |
  | No answer (offline, DNS, TLS, timeout) | `Can't reach Cursor` | `Retrying in a few minutes.` |
  | Any other status | `Cursor is having trouble` | `Retrying in a few minutes.` |
  | A `200` that is not the usage shape | `Unexpected reply from Cursor` | `Retrying in a few minutes.` |
- **Stale.** A snapshot older than 15 minutes is dimmed. Its label still reads `As of …` until the next read.

Reads happen when the menu opens or on the scheduled refresh, at most every 5 minutes. Connecting and disconnecting read at once.

## Source Contract

All knowledge of Cursor's database and of cursor.com lives in `Sources/Platform/Cursor`. Feature and UI code see parsed values only.

**Sign-in.** Cursor keeps its session in a VS Code style SQLite database, `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`. Usage reads one row: table `ItemTable`, key `cursorAuth/accessToken`. The value is a JWT, SQLite TEXT on current builds and a UTF-8 or UTF-16LE BLOB on others. CodexPill takes the user ID from its `sub` claim and the expiry from `exp`.

**Database reads.**

- Read-only, with one keyed lookup per row. Never a scan: on a typical Mac the database is several gigabytes.
- With no `-wal`, `-shm`, or `-journal` next to the database, it is idle, and CodexPill opens it with SQLite's `immutable=1`, so it never creates a file in Cursor's folder.
- With any of them present, Cursor has it open or crashed mid-write. CodexPill then opens it normally read-only, so SQLite reads only committed data, or refuses a hot journal and the read is retried later. `immutable=1` would read the uncommitted pages.

**Request.** `GET https://cursor.com/api/usage-summary` with Cursor's web session cookie built from the token. The HTTP session has no cookie store and no URL cache, and refuses every redirect, so the token never reaches another host. CodexPill does not call `/api/auth/me`.

**Response.** Observed on 2026-10-09:

- `membershipType` is the plan name, for example `pro`.
- `individualUsage.plan.totalPercentUsed` is the included-usage headline in percent, matching Cursor's dashboard. It can differ from `plan.used / plan.limit`, because bonus credit counts against the dollar figures. CodexPill uses the percent, and falls back to `used / limit` only when the percent is missing. An unlimited or disabled plan has no percent.
- `individualUsage.onDemand` carries on-demand spend in cents when `enabled` is true. A null `limit` means no cap.
- `billingCycleStart` and `billingCycleEnd` are ISO 8601. The end is the reset.

**Mapping.** One `UsageWindow` of kind `billingCycle`, with `usedPercent` from the percent, `resetsAt` from `billingCycleEnd`, and `durationMinutes` from the cycle length. No percent means no window. On-demand spend goes to `UsageSnapshot.spend` as dollars with an optional cap, because it is money, not a percent of a limit.

## Read Policy

- Token within 60 seconds of expiry: no request. Cursor renews it the next time it runs.
- `401`: sign-in expired. `403`: access denied.
- `429`: no database read and no request until `Retry-After` passes, given as seconds or an HTTP date, or 5 minutes when the header is missing or unreadable. The menu shows rate limited meanwhile.
- Network failure: unreachable. Another status: service error. An unreadable body: unexpected response.
- The shared provider runtime keeps the last good values for every failure except not installed and signed out, which may mean a different Cursor user. The Cursor client keeps no copy of its own.
- CodexPill holds the token only for the length of one read. It never stores, logs, displays, or refreshes it. `CursorAccessToken` prints as `CursorAccessToken(redacted)` and reflects no children.

## Isolated Runs

With `CODEXPILL_ISOLATED_APP_SUPPORT_DIR` set, CodexPill never touches the real Cursor:

- Usage reads `<root>/Cursor/state.vscdb`. A missing file reads as not installed. The request still goes to cursor.com with whatever token that file holds.
- There is no account switching, so an isolated run never quits Cursor, writes a database, or writes the Keychain.

## Cursor Account Switching

CodexPill can save Cursor sign-ins and switch Cursor between them. This is the data layer only. No menu shows it yet; `CursorUsage.accounts` and `CursorUsage.switchAccount(to:)` are the entry points a menu uses. It works whether or not Cursor usage is connected.

### User Story

As someone with a personal and a work Cursor account, I want to save both and switch Cursor between them from the menu bar, so I don't have to sign out and back in through the browser each time.

### Product Contract

- **Save.** CodexPill saves Cursor's current sign-in under a name, with the plan Cursor cached (`stripeMembershipType`). Saving the same Cursor user again refreshes the saved copy and renames it instead of adding a second entry. Cursor need not quit to save.
- **Switch.** The menu asks first, then CodexPill quits Cursor, writes the saved sign-in, and reopens Cursor:

  > **Switch Cursor account?**
  > Cursor will quit and reopen.

- **Rename and remove** change only CodexPill's list. Removing the account Cursor is signed in as leaves Cursor signed in.
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
- Every statement names its key. CodexPill never scans the database, and writes no table other than `ItemTable` and no row outside the 8 keys.
- Switching runs in this order, and stops at the first failure:
  1. Ask Cursor to quit and wait up to 15 seconds for it to exit. Never force-quit: Cursor may be asking about unsaved work. If it is still running, nothing is written and Cursor is left as it is (`cursorDidNotQuit`).
  2. Open the database read-write and run `PRAGMA wal_checkpoint(TRUNCATE)`. If another connection still holds it, such as a Cursor helper that has not exited, SQLite reports busy after a 5 second wait and nothing is written (`cursorBusy`).
  3. Read the current rows again and save them over the matching saved account, because Cursor may have renewed its tokens since they were captured. A signed-in account that was never saved is saved under its email, so a switch never strands a sign-in. If this Keychain write fails, nothing is written to Cursor.
  4. In one `BEGIN IMMEDIATE` transaction, replace each of the target's rows and delete any of the 8 keys the target lacks, so nothing of the outgoing account stays behind.
  5. Checkpoint again, close, and open Cursor.
- If anything fails after Cursor quit, Cursor is reopened on the sign-in it had, and the error is returned.
- Choosing the account Cursor is already signed in as writes nothing and only reopens Cursor.

Tests use temporary fixture databases and an in-memory account store, and never open the real database or Keychain item.

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
- whether Cursor Settings Sync, if turned on, carries anything account-specific between the two accounts.

### Switching Risks

- **Cursor running.** CodexPill only writes after Cursor has exited and SQLite confirms no other connection holds the database. A Cursor that will not quit, or a helper that lingers, makes the switch fail with nothing written.
- **Corrupted or unexpected database.** Any SQLite error, including a missing `ItemTable`, aborts before or inside the transaction, so the database is either unchanged or fully switched. CodexPill does not run `integrity_check`: on a 10 GB database it is too slow for a menu action.
- **Format drift.** If Cursor moves its sign-in out of these rows, a switch would write stale rows Cursor ignores. The rows written are the 8 known keys only, so the damage is limited to Cursor's sign-in, which the user can redo in Cursor.
- **Token lifetime.** A saved inactive account's refresh token can expire or be revoked. Switching to it then lands in Cursor's own sign-in prompt.

## Privacy

The user-facing summary lives in [PRIVACY.md](../PRIVACY.md).

## Validation

- `CursorAccessTokenTests` and `CursorStateDatabaseTokenSourceTests` parse literal tokens in every storage class, prove no files appear next to an idle database, read a live WAL database, and prove a hot rollback journal never yields the uncommitted token.
- `CursorUsageSummaryParserTests` and `CursorUsageClientTests` cover the response mapping, the expiry gate, each HTTP status, and the `Retry-After` wait in seconds and as an HTTP date.
- `CursorUsageTests` cover opt-in, each failure reason, the unlimited plan with no meter, on-demand spend, and switching through `CursorUsage`.
- `CursorAccountsTests` cover saving, switching only the 8 rows, quitting before writing, Cursor that won't quit, a database another process holds, a corrupted database, and the Keychain payload printing redacted.
- `CursorAlertTests` check that every switch failure reads differently and stays a title plus one short line.
- A coordinator test walks the menu from `Connect Cursor…` through declined consent, current usage, a failed read that keeps the last values, and disconnect, reading the built `NSMenu`.
- No test touches the network, the real Cursor database, or the real Keychain.

## Out Of Scope

- Team and enterprise pooled budgets and legacy request-count plans.
- Browser cookie import, WebViews, and manual cookie entry.
- Signing in to Cursor. A new Cursor account is added by signing in inside Cursor, then saving it in CodexPill.
- Switching the Cursor CLI (`cursor-agent`) sign-in.
