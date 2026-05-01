# Menubar

The menubar feature owns the overall `MenuBarExtra` popup composition.

It does not own every behavior behind each row. Instead, it defines where feature entry points appear, how sections are ordered, and how menu-level states such as busy/status/quit are presented.

## Purpose

The menubar popup is CodexPill's primary product surface. It combines account status, remote status, saved account actions, and app-level controls in one native menu.

## Section Order

The menu is ordered as:

1. `Active Account` or `Active Accounts`
2. `Accounts`, when saved catalog entries are visible
3. `More Accounts…`, when saved catalog entries overflow the visible limit
4. App Controls
5. Status message, when needed
6. `Quit`

## Active Account Section

Owned behavior: [Accounts](accounts/00-accounts.md).

UX responsibility here:

- Use `Active Account` for one active account card and `Active Accounts` for multiple active account cards.
- Present the active local saved account and connected verified remote active accounts in one unified section.
- Collapse the local and remote surfaces into one card when the same saved account is active on This Mac and a connected verified remote host.
- Show enough plan, location, and session/weekly usage information to answer "what am I using right now and where?"
- If no saved account matches any live active account, show a clear empty state instead of pretending an account is active.

## Accounts Section

Owned behavior: [Accounts](accounts/00-accounts.md).

UX responsibility here:

- Show saved catalog rows below current/remote cards.
- Keep rows compact: account display name plus session/weekly summary.
- Use a submenu per row for target switching and account management.
- Use `More Accounts…` when the visible-account limit hides additional saved accounts.

## App Controls Section

The lower section is called App Controls in product docs. It is not called Preferences because it contains both settings and feature entry points.

Entries:

- `Add Account…`: entry point owned by [Accounts](accounts/00-accounts.md).
- `Hosts`: entry point owned by [Remote Hosts](remote-hosts.md).
- `Notifications`: entry point owned by [Notifications](notifications.md).
- `Refresh Interval`: setting that controls scheduled refresh cadence.
- `Preferences`: status icon, label, pacing marker, and accent settings owned by [Status Bar](status-bar.md).
- `About`: app-level informational alert.
- `Quit`: app-level quit command, separated from status and controls.

## Busy And Status States

When CodexPill is busy, menu actions that would conflict with the active workflow should be disabled or routed through their existing confirmation flow.

If `statusMessage` is visible, it appears below App Controls and above `Quit`.

## Validation Notes

Menu UI validation should assert section ordering, direct-row versus submenu placement, action wiring, disabled states during busy work, and the presence or absence of optional sections.
