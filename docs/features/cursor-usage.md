# Cursor Usage

## User Story

As a CodexPill user who also codes in Cursor, I want to see how much of my Cursor plan I have used this billing cycle and when it resets, so I can decide which tool to reach for without opening Cursor's dashboard.

## Product Contract

Cursor Usage is an optional, display-only menu bar feature. When enabled, CodexPill shows the signed-in Cursor account's included-plan usage, any on-demand spend, and the billing-cycle reset date.

CodexPill does not switch Cursor accounts, sign in to Cursor, refresh Cursor's session, or change anything in Cursor. If Cursor's own session is missing or expired, CodexPill says so and points the user back to Cursor.

The feature is off by default. Enabling it is the user's consent for CodexPill to read Cursor's local sign-in token and send it to cursor.com.

This document covers the data contract shipped in the Cursor data-layer PR. The menu presentation lands in a later PR and will extend the UI section below.

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

| State | Meaning | Proposed copy |
| --- | --- | --- |
| Available | Fresh usage was read. | `Included usage 82%`, `On-demand $12.34 of $50`, `Resets Oct 30` |
| Cursor not installed | Cursor's database does not exist on this Mac. | `Cursor isn't installed on this Mac` |
| Signed out | Cursor has no usable session token. | `Sign in to Cursor to see usage` |
| Token expired | Cursor's saved session expired and Cursor has not refreshed it yet. | `Open Cursor to refresh usage` |
| Unauthorized | cursor.com rejected the session. | `Sign in to Cursor again to see usage` |
| Unavailable | Network failure, an unexpected response, or an unreadable local database. | Keep the last good values with `Updated <relative time>`; with no last good values show `Cursor usage unavailable` |

On-demand copy appears only when on-demand usage is enabled. With no cap, show the spend alone, for example `On-demand $12.34`.

## Refresh And Failure Behavior

- Refresh no more often than every 5 minutes, and on menu open only when the last read is older than that.
- A transient failure keeps the last good snapshot visible and marked stale.
- Signed out, unauthorized, and not installed clear the last good snapshot, because the data may no longer belong to the current Cursor user.
- Token expired keeps the last good snapshot internally, because it is still the same account, but the menu shows the expired state until Cursor refreshes its session.
- Failures never raise alerts or notifications.

## Mapping To Shared Usage Types

The planned Core `UsageSnapshot` holds percent windows. Cursor maps onto it like this:

- `provider`: Cursor.
- `planName`: `membershipType`.
- One window of kind `billingCycle`, with `usedPercent` from `totalPercentUsed`, `resetsAt` from `billingCycleEnd`, and `durationMinutes` from the cycle length.
- `fetchedAt`: the read time.

On-demand spend does not fit a percent window. It is a dollar amount with an optional dollar cap and no percent when uncapped. The shared model needs a separate spend field, or Cursor keeps it as a provider-specific extra.

## Proposed Privacy Paragraph

To add to [PRIVACY.md](../PRIVACY.md) when the menu UI ships:

> **Cursor usage (optional).** When you turn on Cursor Usage, CodexPill reads Cursor's sign-in token from Cursor's local settings database on this Mac (`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`). It opens that database read-only, reads only the token, and never changes Cursor's files. CodexPill sends the token only to cursor.com to fetch your plan usage, on-demand spend, and billing-cycle dates. It does not store, log, or display the token, does not refresh it, and does not read browser cookies. Turning the feature off stops all reads.

## Out Of Scope

- Menu UI and preferences toggle. They land in a later PR.
- Team and enterprise pooled budgets and legacy request-count plans.
- Browser cookie import, WebViews, and manual cookie entry.
- Cursor account switching or sign-in.
