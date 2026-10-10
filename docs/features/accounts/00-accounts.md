# Accounts

CodexPill accounts are locally saved Codex authentication snapshots with user-facing metadata. Account features must preserve a clear distinction between catalog management and switching the active Codex account.

Feature documents define what the account workflow must do. UX sections define how the user experiences those workflows in menus, alerts, and panels.

## Current User-Facing Features

### 01. Add Account

Add another Codex account to CodexPill's local catalog without changing the currently active local Codex account.

See [Add Account](01-add-account.md).

### 02. Switch Account

Activate a saved account on This Mac through the explicit switch action.

See [Switch Account](02-switch-account.md).

### 03. Remove Account

Remove a saved account snapshot from CodexPill's local catalog.

See [Remove Account](03-remove-account.md).

### 04. Rename Account

Rename the CodexPill display label for a saved account without changing the underlying Codex identity or auth snapshot.

See [Rename Account](04-rename-account.md).

### 05. Refresh Accounts

Refresh account metadata, plan, and rate-limit snapshots for the full account surface: the current local account and saved catalog accounts.

See [Refresh Accounts](05-refresh-accounts.md).

## UX Ownership

The whole menubar layout, including section ordering and the lower App Controls section, is owned by [Menubar](../menubar.md). Accounts owns the account-specific content inside those sections.

## Active Account UX

Active account presentation answers: "Which account am I using right now?"

CodexPill shows the active account in the top `Active Account` section.

### Local Active Account

The local current account appears first when CodexPill can match the live local Codex auth state to a saved account.

The card should show:

- Display name.
- Plan as a compact pill.
- Freshness metadata, such as `Updated 1min ago`.
- Session usage and reset timing when Codex returns a shorter session-like quota window.
- Weekly usage and reset timing when Codex returns a weekly quota window.
- A neutral expected-pace marker inside each usage bar when reset-window duration is available and `Preferences > Usage Bars > Show Pace Markers` is enabled. This marker is visual only; it must not add pacing text to the card.

If CodexPill cannot match the live local Codex auth to a saved account, it should show a clear unmatched or empty state instead of displaying stale saved-account data as current.

## Account Menu And Catalog UX

CodexPill adapts the saved-account menu to the number of saved accounts:

- With one saved account, CodexPill hides the saved-account list and shows `Account > Add Account…, Rename…, Remove…`.
- With multiple saved accounts, CodexPill shows `Other Accounts` rows excluding the active local account. The active local account is managed through `Account > Add Account…, Rename…, Remove…` so account actions stay grouped.

The catalog is not the same as active-account presentation. It shows saved options, while `Active Account` shows the account in use. Management actions for the active local account should not force an otherwise duplicate row to appear in the saved-account list.

### Row Content

Each visible row should show:

- Saved account display name.
- Compact session usage summary.
- Compact weekly usage summary.
- A submenu affordance.

Rows should stay compact. Detailed target actions belong in the account submenu.

### Row Data Source

Catalog rows primarily use saved catalog metadata and latest known rate-limit snapshots.

### Ordering

Rows are ordered by the app's shared account availability ranking.

This means the catalog should help the user find the most useful account first, not simply list accounts alphabetically.

### Overflow

When the visible account limit hides saved accounts, the menubar shows `More Accounts…`. The default visible saved-account count is five.

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
- Switch actions for available targets, such as `Switch on This Mac` and `Switch on workstation`.
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

Rename:

- Uses a native text-input alert.
- Makes clear that the label changes only inside CodexPill.

Remove:

- Uses a destructive confirmation alert.
- If the removed account is active on This Mac, CodexPill signs it out before deleting the saved snapshot.
- If the sign-out fails, CodexPill keeps the saved account so the user does not lose the main control surface for an active login.

### Visual Contract

Submenu rows should remain compact because this is a menu, not a details panel. Extra explanatory copy belongs in confirmation alerts or feature docs, not in the menu.
