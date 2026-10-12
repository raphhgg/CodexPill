# Cursor Usage

## User Story

As a Refill user who also codes in Cursor, I want to see how much of my Cursor plan I have used this billing cycle and when it resets, so I can decide which tool to reach for without opening Cursor's dashboard.

## Product Contract

Cursor Usage is an optional menu bar feature. When connected, Refill shows the signed-in Cursor account's included-plan usage, any on-demand spend, and the billing-cycle reset date.

Reading usage never changes anything in Cursor. Refill never signs in to Cursor and never renews Cursor's session. If Cursor's sign-in is missing or expired, Refill says so and points the user back to Cursor. Refill shows only the account Cursor is signed in to, by the email Cursor cached. It never saves, adds, or switches Cursor accounts, never quits Cursor, and never writes Cursor's database or a Keychain item.

The feature is off by default. Connecting it is the user's consent for Refill to read Cursor's local sign-in token and send it to cursor.com.

Cursor usage is display-only. It never feeds account availability, ranking, or notifications, which stay Codex-only.

## Menu

The `Cursor` card follows the shared card and side menu in [Menubar](menubar.md). The side menu shows the email Cursor is signed in to, checked and disabled, and has no account actions. `Appearance › Show Tools › Cursor` disconnects it.

- **Not connected.** There is no card. Checking `Appearance › Show Tools › Cursor` connects. Choosing it opens a consent alert first. Nothing is read until the user confirms.
- **Consent alert.** One short alert:

  > **Connect Cursor?**
  > Uses Cursor's sign-in to read your usage.

  Confirming saves the choice and reads at once.
- **Connected.** The choice is saved in user defaults (`cursorUsageEnabled`, off by default). Unchecking `Appearance › Show Tools › Cursor` turns the feature off at once with no alert, because it changes nothing outside Refill. Checking it again connects through the same consent alert.
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

**Sign-in.** Cursor keeps its session in a VS Code style SQLite database, `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`. Usage reads two rows of table `ItemTable`: `cursorAuth/accessToken` and `cursorAuth/cachedEmail`. The token is a JWT, SQLite TEXT on current builds and a UTF-8 or UTF-16LE BLOB on others. Refill takes the user ID from its `sub` claim and the expiry from `exp`. The email is stored JSON-encoded. Refill drops the quotes and shows it in the side menu.

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

When Token Usage is also on, Refill reads daily tokens by model from `POST https://cursor.com/api/dashboard/get-filtered-usage-events` with the same token and rules. See [Token Usage](token-usage.md#other-tools).

## Read Policy

- Token within 60 seconds of expiry: no request. Cursor renews it the next time it runs.
- `401`: sign-in expired. `403`: access denied.
- `429`: no database read and no request until `Retry-After` passes, given as seconds or an HTTP date, or 5 minutes when the header is missing or unreadable. The menu shows rate limited meanwhile.
- Network failure: unreachable. Another status: service error. An unreadable body: unexpected response.
- The shared provider runtime keeps the last good values for every failure except not installed and signed out, which may mean a different Cursor user. The Cursor client keeps no copy of its own.
- Refill holds the token only for the length of one read. It never stores, logs, displays, or refreshes it. `CursorAccessToken` prints as `CursorAccessToken(redacted)` and reflects no children.

## Isolated Runs

With `REFILL_ISOLATED_APP_SUPPORT_DIR` set, Refill never touches the real Cursor:

- Usage reads `<root>/Cursor/state.vscdb`. A missing file reads as not installed. The request still goes to cursor.com with whatever token that file holds.

## Privacy

The user-facing summary lives in [PRIVACY.md](../PRIVACY.md).

## Validation

- `CursorAccessTokenTests` and `CursorStateDatabaseTokenSourceTests` parse literal tokens in every storage class, prove no files appear next to an idle database, read a live WAL database, and prove a hot rollback journal is reported as busy and never yields the uncommitted token.
- `CursorUsageSummaryParserTests` and `CursorUsageClientTests` cover the response mapping, the expiry gate, each HTTP status, and the `Retry-After` wait.
- `CursorUsageTests` cover opt-in, each failure reason, the unlimited plan with no meter, and on-demand spend.
- A coordinator test walks the menu from `Appearance › Show Tools › Cursor` through declined consent, current usage, a failed read that keeps the last values, and disconnect, reading the built `NSMenu`.
- No test touches the network or the real Cursor database.

## Out Of Scope

- Team and enterprise pooled budgets and legacy request-count plans.
- Browser cookie import, WebViews, and manual cookie entry.
- Signing in to Cursor, and saving or switching Cursor accounts. Refill shows the account Cursor is signed in to.
