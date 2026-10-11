<p align="center">
  <img src="docs/images/app-icon.png" width="128" alt="CodexPill app icon">
</p>

<h1 align="center">CodexPill</h1>

<p align="center">
  <i>A native macOS menubar companion for Codex accounts, limits and token usage.</i>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Version-v0.1.0--beta.2-2563EB" alt="Version v0.1.0-beta.2">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Built%20with-%20Codex-8B5CF6?logo=openai&logoColor=white" alt="Built with Codex">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT license">
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/codexpill-menu-dark.png">
    <img src="docs/assets/codexpill-menu.png" width="360" alt="CodexPill menu with Claude, Codex and Cursor cards, then Settings and Quit">
  </picture>
</p>

## What It Does

- See your Codex limits at a glance.
- Track local Codex token usage history from the menu bar.
- Switch between saved Codex accounts.
- Add accounts without disrupting your current session.
- Stay local-first: no cloud sync, no hidden browser automation, no account data upload.

## New In Beta 2

- Optional Token Usage card for this Mac, with daily bars, heat strip and
  sparkline chart styles.
- Local session history scanning with an incremental cache, so refreshes reuse
  unchanged session files instead of rescanning everything.
- Swift 6 language mode for the app and tests.
- CI coverage for pull requests and `main`.

## Install

Install with Homebrew:

```bash
brew install --cask raphhgg/tap/codexpill
```

Or download the latest zip from
[GitHub Releases](https://github.com/raphhgg/CodexPill/releases).

## Build From Source

Prerequisites:

- macOS with Xcode command line tools installed.
- Tuist installed locally.
- Codex installed and signed in on this Mac.

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

Codex must already be installed and signed in on your Mac, either through the
Codex app, the Codex CLI or both.

Token Usage is optional and local to this Mac. It reads local Codex session
history, stores derived aggregate buckets, and does not upload prompt content,
session rows or auth data.

## Screenshots

| Add Account | Codex Side Menu |
| --- | --- |
| <img src="docs/assets/codexpill-add-account.png" width="420" alt="CodexPill Add Account dialog"> | <img src="docs/assets/codexpill-account-actions.png" width="420" alt="CodexPill Codex side menu with account, reset and section actions"> |

| Settings |
| --- |
| <img src="docs/assets/codexpill-settings.png" width="420" alt="CodexPill Settings submenu"> |

## Local-First

CodexPill works with Codex state on your Mac. It does not run a cloud service.

Saved accounts stay on your Mac under
`~/Library/Application Support/CodexPill`. They contain authentication material,
so treat them like credentials.

CodexPill does not use browser cookies, hidden browser windows, Full Disk
Access, Screen Recording or Accessibility permissions for normal use.

## Product Docs

- [Product overview](docs/PRODUCT.md)
- [Feature contracts](docs/features/README.md)
- [Privacy and data handling](docs/PRIVACY.md)
- [Beta testing guide](docs/BETA_TESTING.md)

## Project Policies

- [Changelog](CHANGELOG.md)
- [MIT license](LICENSE)
- [Security policy](SECURITY.md)
