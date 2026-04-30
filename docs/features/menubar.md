# Menubar

The menubar feature owns the overall `MenuBarExtra` popup composition.

It does not own every behavior behind each row. Instead, it defines where feature entry points appear, how sections are ordered, and how menu-level states such as busy/status/quit are presented.

## Purpose

The menubar popup is CodexPill's primary product surface. It combines account status, remote status, saved account actions, and app-level controls in one native menu.

## Section Order

The menu is ordered as:

1. `Current Account`
2. `Remote Accounts`, when one or more remote hosts are connected
3. `Accounts`, when saved catalog entries are visible
4. `More Accounts…`, when saved catalog entries overflow the visible limit
5. App Controls
6. Status message, when needed
7. `Quit`

## Current Account Section

Owned behavior: [Accounts](accounts/00-accounts.md).

UX responsibility here:

- Present the active local saved account first.
- Show enough plan and session/weekly usage information to answer "what am I using right now?"
- If no saved account matches the live local Codex account, show a clear empty state instead of pretending an account is active.

## Remote Accounts Section

Owned behavior: [Remote Hosts](remote-hosts.md).

UX responsibility here:

- Show connected remote hosts separately from the local current account.
- Prefer remote target values for the remote card when the remote account is verified.
- Hide disconnected or invalid remote account cards unless the host needs an explicit user-facing recovery state.

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
