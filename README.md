<p align="center">
  <img src="docs/images/app-icon.png" width="128" alt="Refill app icon">
</p>

<h1 align="center">Refill</h1>

<p align="center">
  <i>A native macOS menubar app that shows when your AI coding limits refill, and switches accounts in a click.</i>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Version-v0.1.0--beta.2-2563EB" alt="Version v0.1.0-beta.2">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Built%20with-%20Codex-8B5CF6?logo=openai&logoColor=white" alt="Built with Codex">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT license">
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/refill-menu-dark.png">
    <img src="docs/assets/refill-menu.png" width="360" alt="Refill menu with Claude, Codex and Cursor cards, then Settings and Quit">
  </picture>
</p>

Refill was called CodexPill before this release. See
[Upgrading From CodexPill](#upgrading-from-codexpill).

## What It Does

- See Codex, Claude Code and Cursor usage limits and when they reset.
- Switch between saved accounts for each tool.
- Add accounts without disrupting your current session.
- Track local Codex token usage history from the menu bar.
- Stay local-first: no cloud sync, no hidden browser automation, no account data upload.

Claude Code and Cursor are optional. Refill reads them only after you connect
them from `Settings › Add Account`.

## What's New

- Claude Code and Cursor: see their limits and switch between saved accounts,
  next to Codex.
- One card per tool, with account actions in side menus and all settings under
  `Settings`.
- Codex reset credits: see how many you have and use one from the Codex menu.
- A new name, a new capsule icon, and six icon colours under
  `Settings › Appearance › App Icon`.
- Remote Hosts and Notifications are gone.

See the [Changelog](CHANGELOG.md) for earlier releases.

## Install

Install with Homebrew:

```bash
brew install --cask raphhgg/tap/codexpill
```

The cask still uses the old name. It will be renamed in a later release.

Or download the latest zip from
[GitHub Releases](https://github.com/raphhgg/Refill/releases).

## Build From Source

Prerequisites:

- macOS with Xcode command line tools installed.
- Tuist installed locally.
- Codex, Claude Code or Cursor installed and signed in on this Mac.

Build and run:

```bash
tuist generate --no-open
make build
./scripts/run_menubar.sh
```

For release maintainers, the signed public beta artifact is produced with:

```bash
make package-release
```

That command requires local Developer ID signing and notarization setup before
it creates a public release artifact. See [Development](docs/DEVELOPMENT.md)
for maintainer packaging details.

## Prerequisite

Install and sign in to at least one tool on your Mac: Codex (the app, the CLI or
both), Claude Code or Cursor. Refill always shows a Codex card. Claude Code and
Cursor appear once you connect them from `Settings › Add Account`.

Token Usage is optional and local to this Mac. It reads local Codex session
history, stores derived aggregate buckets, and does not upload prompt content,
session rows or auth data.

## Screenshots

| Add Account | Codex Side Menu |
| --- | --- |
| <img src="docs/assets/refill-add-account.png" width="420" alt="Refill Add Account dialog with the capsule icon"> | <img src="docs/assets/refill-account-actions.png" width="420" alt="Refill Codex side menu with account, reset and section actions"> |

| Settings |
| --- |
| <img src="docs/assets/refill-settings.png" width="420" alt="Refill Settings submenu"> |

## Local-First

Refill works with Codex, Claude Code and Cursor state on your Mac. It does not
run a cloud service.

Saved Codex accounts stay on your Mac under
`~/Library/Application Support/Refill`. Saved Claude Code and Cursor sign-ins
stay in your login Keychain. They contain authentication material, so treat them
like credentials.

Refill does not use browser cookies, hidden browser windows, Full Disk
Access, Screen Recording or Accessibility permissions for normal use.

## Upgrading From CodexPill

Refill is a new app to macOS, with its own bundle ID. It doesn't read
CodexPill's settings or saved accounts, so add your accounts again and turn
Launch at Login back on if you used it. Quit and delete `CodexPill.app` first.
[Uninstall And Reset](docs/UNINSTALL_RESET.md#leftovers-from-codexpill) shows
how to remove CodexPill's leftover data.

## Product Docs

- [Product overview](docs/PRODUCT.md)
- [Feature contracts](docs/features/README.md)
- [Privacy and data handling](docs/PRIVACY.md)
- [Beta testing guide](docs/BETA_TESTING.md)

## Project Policies

- [Changelog](CHANGELOG.md)
- [MIT license](LICENSE)
- [Security policy](SECURITY.md)
