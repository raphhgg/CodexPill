# Menubar

The menubar feature owns the overall `MenuBarExtra` popup composition.

It does not own every behavior behind each row. Instead, it defines where feature entry points appear, how sections are ordered, and how menu-level states such as busy/status/quit are presented.

## Purpose

The menubar popup is CodexPill's primary product surface. It combines account status, saved account actions, and app-level controls in one native menu.

## Section Order

The menu is ordered as:

1. `Active Account`
2. `Accounts`, when saved catalog entries are visible
3. `More Accounts…`, when saved catalog entries overflow the visible limit
4. `Claude Code`, read-only usage from [Claude Usage](claude-usage.md)
5. `Cursor`, read-only usage from [Cursor Usage](cursor-usage.md)
6. App Controls
7. Status message, when needed
8. `Quit`

## Active Account Section

Owned behavior: [Accounts](accounts/00-accounts.md).

UX responsibility here:

- Use `Active Account` for the one active account card.
- Show enough plan and session/weekly usage information to answer "what am I using right now?"
- Session and weekly meters follow the `Usage Bars` preferences owned by [Status Bar](status-bar.md): percent used or left, session and weekly colors, and layout. `Classic Layout` stacks title, bar, then percent and reset text for each window. `Compact Layout` puts both windows in one grid with the columns label, bar, percent, and reset, so both bars have the same width and the percent and reset text line up between rows. The account name, plan, and location header keeps the same spacing in both layouts.
- If no saved account matches any live active account, show a clear empty state instead of pretending an account is active.

## Accounts Section

Owned behavior: [Accounts](accounts/00-accounts.md).

UX responsibility here:

- Show saved catalog rows below the active account card.
- Keep rows compact: account display name plus session/weekly summary. The summary percentages follow the `Show % Used` / `Show % Left` preference.
- Use a submenu per row for switching and account management.
- Use `More Accounts…` when the visible-account limit hides additional saved accounts.

## App Controls Section

The lower section is called App Controls in product docs. It is not called Preferences because it contains both settings and feature entry points.

Entries:

- `Add Account…`: entry point owned by [Accounts](accounts/00-accounts.md).
- `Refresh Interval`: setting that controls scheduled refresh cadence.
- `Preferences`: visual settings owned by [Status Bar](status-bar.md), plus app-level controls such as [Launch at Login](app-controls/01-launch-at-login.md) and, while connected, `Disconnect Claude Code…` from [Claude Usage](claude-usage.md) and `Disconnect Cursor…` from [Cursor Usage](cursor-usage.md).
- `Diagnostics…`: user-initiated support artifact export. CodexPill first explains what the export contains, then writes a redacted JSON file only if the user confirms. The report is built from allowlisted diagnostic fields, per-export account aliases, summarized freshness/result states, and recent CodexPill-owned workflow events. It must not include raw logs, auth JSON, saved snapshots, raw UserDefaults, emails, hostnames, local paths, tokens, stable account IDs, prompt/session content, or raw stderr.
- `About`: app-level informational alert.
- `Quit`: app-level quit command, separated from status and controls.

## Busy And Status States

When CodexPill is busy, menu actions that would conflict with the active workflow should be disabled or routed through their existing confirmation flow.

If `statusMessage` is visible, it appears below App Controls and above `Quit`.

## Validation Notes

Menu tests build the `NSMenu` with `MenuBarMenuBuilder` and assert section ordering, direct-row versus submenu placement, action wiring, disabled states during busy work, and the presence or absence of optional sections. Coordinator flow tests live in `MenuBarCoordinatorTests`.
