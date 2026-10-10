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

### 05. Refresh Accounts

Refresh account metadata, plan, and rate-limit snapshots for the full account surface: the current local account and saved catalog accounts.

See [Refresh Accounts](05-refresh-accounts.md).

## UX Ownership

The whole menu layout, including the Codex card and its side menu, is owned by [Menubar](../menubar.md). Accounts owns the account-specific behavior behind them.

## Menu UX

The Codex card shows the account in use: its plan, its windows and its reset credits. When CodexPill cannot match the live `auth.json` to a saved account, the card says `No saved account in use` instead of showing a saved account's numbers as current.

The Codex side menu lists accounts by email, never by name:

- The account in use, disabled, at the top.
- `Use <email>` for a single other account, or `Use Another Codex Account ›` listing the others in the shared availability ranking, best first.
- `Add Codex Account…` and `Remove Codex Account ›`.

Switch:

- Uses the normal local switch path.
- Presents the local switch confirmation unless the caller is an explicit no-second-confirmation path such as Add Account success.

Remove:

- Uses a destructive confirmation alert.
- If the removed account is active on This Mac, CodexPill signs it out before deleting the saved snapshot.
- If the sign-out fails, CodexPill keeps the saved account so the user does not lose the main control surface for an active login.

With no saved account and no other tool connected, the menu offers `Add Account ›` directly. Account actions are disabled while another account operation runs.
