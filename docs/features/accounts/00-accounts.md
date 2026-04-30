# Accounts

CodexPill accounts are locally saved Codex authentication snapshots with user-facing metadata. Account features must preserve a clear distinction between catalog management and switching the active Codex account.

Feature documents define what the account workflow must do. UX sections define how the user experiences those workflows in menus, alerts, and panels.

## Current User-Facing Features

### 01. Add Account

Add another Codex account to CodexPill's local catalog without changing the currently active local Codex account.

See [Add Account](01-add-account.md).

### 02. Switch Account

Activate a saved account on This Mac or on a configured remote host through the explicit switch actions.

See [Switch Account](02-switch-account.md).

### 03. Remove Account

Remove a saved account snapshot from CodexPill's local catalog.

See [Remove Account](03-remove-account.md).

### 04. Rename Account

Rename the CodexPill display label for a saved account without changing the underlying Codex identity or auth snapshot.

See [Rename Account](04-rename-account.md).

### 05. Refresh Accounts

Refresh account metadata, plan, and rate-limit snapshots for the full account surface: current local account, saved catalog accounts, and configured remote accounts.

See [Refresh Accounts](05-refresh-accounts.md).

## Related Account Operations

### Remote Account Setup

Remote host setup installs and switches saved account snapshots on configured remote hosts. It is related to account switching, but host management has its own feature surface.

## UX Ownership

The whole menubar layout, including section ordering and the lower App Controls section, is owned by [Menubar](../menubar.md). Accounts owns the account-specific content inside those sections.

## Current Account UX

Current account presentation answers: "Which account am I using right now?"

CodexPill can show one or two current-account surfaces:

- `Current Account`: the active local account on This Mac.
- `Remote Accounts`: active verified accounts on connected remote hosts.

### Local Current Account

The local current account appears first when CodexPill can match the live local Codex auth state to a saved account.

The card should show:

- Display name.
- Plan.
- Email when it fits the current visual design.
- Session usage and reset timing.
- Weekly usage and reset timing.
- Compact pacing comparison on session and weekly rows when both usage and reset window data are available.

If CodexPill cannot match the live local Codex auth to a saved account, it should show a clear unmatched or empty state instead of displaying stale saved-account data as current.

### Remote Account Cards

Remote account cards appear for connected verified remote hosts.

The card should show:

- Saved account display name.
- Remote host name or destination.
- Connection state.
- Plan and email when available.
- Session and weekly usage values from the remote target.
- Compact pacing comparison using the same model and visual language as the local current account when remote usage and reset window data are available.

Remote cards must prefer remote target values over local catalog values when the remote active account is verified. The user should not see the local catalog's stale limits as if they represented the remote host.

### Duplicate Local And Remote Accounts

If the same saved account is active locally and on a connected verified remote host, CodexPill collapses the duplicate primary remote account card into the `Current Account` section and labels the remote location, such as `Also active on debian-vm`. The `Current Account` card continues to show local current-account limits; remote host management and troubleshooting remain under `Hosts`.

The user must be able to answer:

- Is this account active on This Mac?
- Is this account active on a remote host?
- Where do I inspect or manage the remote host if it needs attention?

### Error And Pending States

Remote pending, failed, disconnected, or unverified states should not be presented as verified current-account facts.

When the app cannot verify a remote account, it should either hide the remote account card or show an explicit recovery state owned by the Remote Hosts feature.

## Account Catalog UX

The `Accounts` section lists saved accounts that can be selected for local or remote use.

The catalog is not the same as current-account presentation. It shows saved options, while `Current Account` and `Remote Accounts` show active targets.

### Row Content

Each visible row should show:

- Saved account display name.
- Compact session usage summary.
- Compact weekly usage summary.
- A submenu affordance.

Rows should stay compact. Detailed target actions belong in the account submenu.

Saved catalog rows do not show pacing indicators in the first pacing implementation; pacing belongs only to current local and current remote account cards.

### Pacing Model

Current account cards compare actual used percentage with a simple linear expectation: expected usage equals the elapsed percentage of the reset window.

When the app has usage, future reset time, and reset-window duration, the session and weekly progress bars show a neutral expected marker and a small delta badge near the reset copy. Positive deltas mean the account is over the elapsed-window expectation, negative deltas mean there is room left, and near-zero deltas are on pace. Missing reset or window-duration data falls back to the existing usage and reset row without inventing pacing.

### Row Data Source

Catalog rows primarily use saved catalog metadata and latest known rate-limit snapshots.

If an account is currently active on a remote host and that remote value is fresher or target-specific, the row may prefer that remote target's values, as long as the UI remains clear about where those values came from.

### Ordering

Rows are ordered by the app's shared account availability ranking.

This means the catalog should help the user find the most useful account first, not simply list accounts alphabetically.

### Overflow

When the visible account limit hides saved accounts, the menubar shows `More Accounts…`.

The overflow menu remains part of the same saved account catalog and should use the same row and submenu behavior.

### Empty State

When no saved accounts exist, the menu should guide the user toward `Add Account…`.

The empty state should not imply that CodexPill can switch accounts before at least one account is saved.

## Account Submenu UX

The account submenu is the per-account action surface. It should identify the account, show where it is currently used, and expose actions without forcing the user to open separate detail screens.

### Current Shape

The submenu currently contains:

- A disabled email identity row such as `name@example.com` or `No email`.
- A disabled usage row such as `In use on: This Mac`.
- Switch actions for available targets, such as `Switch on This Mac` and `Switch on debian-vm`.
- Management actions: `Rename…` and `Remove…`.

### Identity

The submenu should show the account email address near the top when available. This helps distinguish accounts with similar display names.

Recommended order:

1. Email address as disabled informational text.
2. Usage row, for example `In use on: This Mac`.
3. Switch actions.
4. Rename and remove actions.

If the email is unknown, show `No email` in the same disabled informational row.

### Actions

Switch on This Mac:

- Uses the normal local switch path.
- Presents the local switch confirmation unless the caller is an explicit no-second-confirmation path such as Add Account success.

Switch on remote host:

- Uses the normal remote switch/install flow for that host.
- Must verify or surface remote errors instead of silently assuming success.

Rename:

- Uses a native text-input alert.
- Makes clear that the label changes only inside CodexPill.

Remove:

- Uses a destructive confirmation alert.
- If the removed account is current locally, the alert explains that the live Codex session remains logged in but no longer matches a saved account.

### Visual Contract

Submenu rows should remain compact because this is a menu, not a details panel. Extra explanatory copy belongs in confirmation alerts or feature docs, not in the menu.
