# Cursor Usage

## User Story

As a CodexPill user who also codes in Cursor, I want to see how much of my Cursor plan I have used this billing cycle and when it resets, so I can decide which tool to reach for without opening Cursor's dashboard.

## Product Contract

Cursor Usage is an optional, display-only menu bar feature. When enabled, CodexPill shows the signed-in Cursor account's included-plan usage, any on-demand spend, and the billing-cycle reset date.

Usage reading never signs in to Cursor, refreshes Cursor's session, or changes anything in Cursor. If Cursor's own session is missing or expired, CodexPill says so and points the user back to Cursor. Switching Cursor accounts is a separate, explicit action described in [Account Switching](#account-switching).

The feature is off by default. Enabling it is the user's consent for CodexPill to read Cursor's local sign-in token and send it to cursor.com.

The data contract shipped in the Cursor data-layer PR. The menu section below shipped with the Cursor menu PR.

## Menu

A `Cursor` section sits below `Claude Code`. It never affects account availability, ranking, switching, or notifications.

- **Not connected.** The section shows `Connect Cursor…`. Choosing it opens a consent alert first. Nothing is read until the user confirms.
- **Consent alert.** One short alert:

  > **Connect Cursor?**
  > CodexPill will read Cursor's sign-in on this Mac to show your plan usage from cursor.com. You can disconnect in Preferences.

  The alert stays short. The read and send rules live in the Source Contract below and in [PRIVACY.md](../PRIVACY.md).
- **Connected.** The choice is saved in user defaults (`cursorUsageEnabled`, off by default). `Preferences` gains `Disconnect Cursor…`, which turns the feature off at once with no alert, because it changes nothing outside CodexPill.
- **Current.** A caption with the plan and the read time (`Pro plan · As of 10:42`), one `Billing cycle` meter with `Resets Oct 30`, and, when on-demand usage is enabled, a text line: `On-demand: $12.34 of $50.00`, or `On-demand: $12.34` with no cap. Spend is never drawn as a bar. The meter follows the `% used` or `% left` setting, the meter layout, pacing markers, and the weekly color.
- **Cursor not installed.** `Cursor isn't installed`, with no second line. Last good values are cleared.
- **Signed out.** `Not signed in to Cursor` / `Sign in to Cursor to see usage.` Last good values are cleared.
- **Sign-in expired or rejected.** `Sign in to Cursor again`, with no second line, and the last good values dimmed below it with their `As of` time.
- **Read failed** (network, unexpected response, unreadable database). `Can't reach cursor.com` / `Retrying in a few minutes.`, with the last good values dimmed below it and their `As of` time.
- **Stale.** A snapshot older than 15 minutes is dimmed. Its label still reads `As of …` until the next read.

Reads happen when the menu opens or on the scheduled refresh, at most every 5 minutes. Connecting or disconnecting reads at once.

The menu keeps the last good values itself, through the shared provider runtime, so Claude Code gets the same behavior. That differs from the data layer above in one place: when cursor.com rejects the session, the menu still shows the last values under `Sign in to Cursor again`, because the account has not changed. Signing out of Cursor clears them.

For isolated runs (`CODEXPILL_ISOLATED_APP_SUPPORT_DIR`), CodexPill reads the token from `<root>/Cursor/state.vscdb` instead of Cursor's real database.

## Source Contract

Cursor.app stores its session in a VS Code style SQLite database. CodexPill may read one value from it, only through `Platform/Cursor`:

- Database: `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`.
- Table `ItemTable`, key `cursorAuth/accessToken`. The value is a JWT. It is SQLite TEXT on current builds and may be a UTF-8 or UTF-16LE BLOB on others.

Read rules:

- Open the database strictly read-only with a single keyed lookup. Never scan it. On a typical Mac it is several gigabytes.
- When Cursor's `-wal` and `-shm` sidecars are absent, open in SQLite immutable mode so CodexPill never creates files in Cursor's directory.
- Use the token only while its `exp` claim is more than 60 seconds away. Never refresh it. Cursor refreshes it when Cursor runs.
- Never log, persist, display, or cache the token. The HTTP session uses no cookie store and no URL cache, and refuses redirects so the token never follows to another host.

Usage comes from `GET https://cursor.com/api/usage-summary`, authenticated with Cursor's web session cookie built from the token. Observed shape on 2026-10-09:

- `membershipType` is the plan name, for example `pro`.
- `individualUsage.plan.totalPercentUsed` is the included-usage headline in percent units, matching Cursor's dashboard. It can differ from `plan.used / plan.limit` because bonus credit counts against the dollar figures.
- `individualUsage.onDemand` carries on-demand spend in cents when `enabled` is true. A null `limit` means no cap is set.
- `billingCycleStart` and `billingCycleEnd` are ISO 8601 timestamps. The end is the reset.

CodexPill does not call `/api/auth/me`. Display-only usage needs no email or user ID.

## States

| State | Meaning | Menu copy |
| --- | --- | --- |
| Available | Fresh usage was read. | `Billing cycle` meter at 82%, `Resets Oct 30`, `On-demand: $12.34 of $50.00` |
| Cursor not installed | Cursor's database does not exist on this Mac. | `Cursor isn't installed` |
| Signed out | Cursor has no usable session token. | `Not signed in to Cursor`, `Sign in to Cursor to see usage.` |
| Token expired | Cursor's saved session expired and Cursor has not refreshed it yet. | `Sign in to Cursor again`, last good values dimmed |
| Unauthorized | cursor.com rejected the session. | Same as token expired |
| Unavailable | Network failure, an unexpected response, or an unreadable local database. | `Can't reach cursor.com`, `Retrying in a few minutes.`, last good values dimmed |

On-demand copy appears only when on-demand usage is enabled. With no cap, it shows the spend alone, for example `On-demand: $12.34`.

## Refresh And Failure Behavior

- Refresh no more often than every 5 minutes, and on menu open only when the last read is older than that.
- A transient failure keeps the last good snapshot visible and marked stale.
- Signed out, unauthorized, and not installed clear the last good snapshot, because the data may no longer belong to the current Cursor user.
- Token expired keeps the last good snapshot internally, because it is still the same account, but the menu shows the expired state until Cursor refreshes its session.
- Failures never raise alerts or notifications.

## Mapping To Shared Usage Types

Cursor maps onto the shared `UsageSnapshot` like this:

- `provider`: Cursor.
- `planName`: `membershipType`.
- One window of kind `billingCycle`, with `usedPercent` from `totalPercentUsed`, `resetsAt` from `billingCycleEnd`, and `durationMinutes` from the cycle length.
- `fetchedAt`: the read time.

- `spend`: on-demand spend as a `UsageSpend` with `usedUSD` and an optional `limitUSD`, present only when on-demand usage is enabled.

Spend is not a percent window. It is a dollar amount with an optional dollar cap and no percent when uncapped, so it has its own field.

## Account Switching

### User Story

As someone with a personal and a work Cursor account, I want to save both and switch Cursor between them from the menu bar, so I don't have to sign out and back in through the browser each time.

### Product Contract

- **Save.** CodexPill saves Cursor's current sign-in under a name, with the plan Cursor cached (`stripeMembershipType`). Saving the same Cursor user again refreshes the saved copy and renames it instead of adding a second entry. Cursor need not quit to save.
- **Switch.** Choosing a saved account asks first, then quits Cursor, writes the saved sign-in, and reopens Cursor. The intended alert, from the menu prototype:

  > **Use Work in Cursor?**
  > Cursor quits and reopens signed in as Work.

- **Rename and remove** change only CodexPill's list. Removing the account Cursor is signed in as leaves Cursor signed in.
- The account Cursor is signed in as is the saved account whose user ID (the access token's `sub` claim) matches.

The data layer (`Platform/Cursor`) shipped first. The menu, including the alert above and its failure copy, ships with the chosen menu design.

### Switch Contract

A Cursor sign-in is these 8 rows of `ItemTable` in `state.vscdb`, observed on 2026-10-10:

`cursorAuth/accessToken`, `cursorAuth/refreshToken`, `cursorAuth/cachedEmail`, `cursorAuth/cachedScopedProfile`, `cursorAuth/cachedSignUpType`, `cursorAuth/stripeMembershipAuthId`, `cursorAuth/stripeMembershipType`, `cursorAuth/stripeSubscriptionStatus`.

Rules:

- Saved values live only in the `CodexPill Cursor accounts` Keychain item, one item for all saved accounts. Each value keeps its SQLite storage class (TEXT or BLOB) so it is written back exactly as Cursor wrote it.
- Every statement names its key. CodexPill never scans the database, and writes no table other than `ItemTable` and no row outside the 8 keys.
- Switching runs in this order, and stops at the first failure:
  1. Ask Cursor to quit and wait up to 15 seconds for it to exit. Never force-quit: Cursor may be asking about unsaved work. If it is still running, nothing is written and Cursor is left as it is.
  2. Open the database read-write and run `PRAGMA wal_checkpoint(TRUNCATE)`. If another connection still holds it (a Cursor helper that has not exited), SQLite reports busy after a 5 second wait and nothing is written.
  3. Read the current rows again and save them over the matching saved account, because Cursor may have rotated its tokens since they were captured. A signed-in account that was never saved is saved under its email, so a switch never strands a sign-in. If this Keychain write fails, nothing is written to Cursor.
  4. In one `BEGIN IMMEDIATE` transaction, replace each of the target's rows and delete any of the 8 keys the target lacks, so nothing of the outgoing account stays behind.
  5. Checkpoint again, close, and open Cursor.
- If anything fails after Cursor quit, Cursor is reopened on the sign-in it had, and the error is returned.
- Choosing the account Cursor is already signed in as writes nothing and only reopens Cursor.

For isolated runs, switching uses `<root>/Cursor/state.vscdb`, the same fixture database as usage. Tests use temporary fixture databases in that layout and an in-memory account store, and never open the real database or Keychain item.

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

### Risks

- **Cursor running.** CodexPill only writes after Cursor has exited and SQLite confirms no other connection holds the database. A Cursor that will not quit, or a helper that lingers, makes the switch fail with nothing written.
- **Corrupted or unexpected database.** Any SQLite error, including a missing `ItemTable`, aborts before or inside the transaction, so the database is either unchanged or fully switched. CodexPill does not run `integrity_check`: on a 10 GB database it is too slow for a menu action.
- **Format drift.** If Cursor moves its sign-in out of these rows, a switch would write stale rows Cursor ignores. The rows written are the 8 known keys only, so the damage is limited to Cursor's sign-in, which the user can redo in Cursor.
- **Token lifetime.** A saved inactive account's refresh token can expire or be revoked. Switching to it then lands in Cursor's own sign-in prompt.

## Privacy

The user-facing summary lives in [PRIVACY.md](../PRIVACY.md).

## Out Of Scope

- Team and enterprise pooled budgets and legacy request-count plans.
- Browser cookie import, WebViews, and manual cookie entry.
- Signing in to Cursor. A new Cursor account is added by signing in inside Cursor, then saving it in CodexPill.
- Switching the Cursor CLI (`cursor-agent`) sign-in.
