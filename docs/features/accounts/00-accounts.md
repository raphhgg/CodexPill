# Accounts

rusage shows one Codex account: the one `~/.codex/auth.json` signs in to (`$CODEX_HOME/auth.json` in isolated runs). It works like Claude and Cursor, which also show the one account signed in on this Mac. rusage keeps no catalog of Codex accounts and no copies of sign-ins.

Feature documents define what the account workflow must do. UX sections define how the user experiences those workflows in menus, alerts, and panels.

## Current User-Facing Features

### 01. Sign In To Another Codex Account

Sign in to a Codex account in the browser and, after confirmation, make it the Codex account on this Mac.

See [Sign In To Another Codex Account](01-add-account.md).

### 05. Refresh Accounts

Follow the Codex sign-in on this Mac and refresh its plan, limits, and credits.

See [Refresh Accounts](05-refresh-accounts.md).

## The Codex Account

- rusage builds the account from `auth.json` in memory. Its limits come from the local Codex app-server.
- When Codex rotates its tokens, the account and its last reading stay.
- A different sign-in made outside rusage replaces the account and drops the old reading.
- With `auth.json` missing, Codex is signed out and the menu shows no Codex card.
- The account is identified by its email, masked with Hide Emails. Without an email it reads as its workspace, then its plan, then `Codex account`.

## UX Ownership

The whole menu layout, including the Codex card and its side menu, is owned by [Menubar](../menubar.md). Accounts owns the account-specific behavior behind them.

## Menu UX

The Codex card shows the signed-in account: its plan, its windows, its credits and its reset credits.

The Codex side menu shows the account's email, then, when it has reset credits, `Use a Reset…` and its `Expires <date>` rows.

`Settings › Providers › Codex` shows the account, `Use Another Account…` (tooltip `Replaces the Codex sign-in on this Mac.`) and `Sign Out…`. Sign Out asks first (`Sign Out of Codex?` / `This signs Codex out on this Mac, including the Codex app and CLI.`, `Sign Out` / `Cancel`), then removes `auth.json` and relaunches Codex, so the app and the CLI are signed out too. It is refused while a reset runs. When Codex is signed out, the row says `Signed out` with `Sign In…`. When Codex is signed in but hidden, it says `Not shown in the menu` with `Show`.

With nothing connected, the menu starts at `Settings…`, and launch asks once to sign in to Codex. Account actions are disabled while a sign-in runs. A reset and a sign-in never overlap.

## Earlier Saved Accounts

Earlier versions saved Codex sign-ins in `~/Library/Application Support/rusage/accounts.json` and `~/Library/Application Support/rusage/snapshots/`. This version no longer reads them and never deletes or converts them. See [Uninstall and Reset](../../UNINSTALL_RESET.md).

## Credits

- Source: `credits` in the rate-limit snapshot from `account/rateLimits/read`, the same snapshot rusage uses for the windows. `account/read` has no credits.
- Shape: `{hasCredits, unlimited, balance}`, where `balance` is a decimal string such as `"62498.0761312500"`.
- `unlimited: true` shows `Unlimited credits`. `hasCredits: true` with a readable balance shows the balance in whole credits, such as `62,498 credits`. Anything else shows no line.
- An unreadable `credits` object is skipped and the limits still read.
- Credits are kept in memory with the account's last reading.
- Credits are separate from [reset credits](../codex-reset-credits.md). They never change availability.
