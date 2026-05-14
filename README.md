<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="CodexPill app icon">
</p>

<h1 align="center">CodexPill</h1>

<p align="center">
  <i>A native macOS menubar companion for Codex accounts, limits and remote hosts.</i>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Version-v0.1.0--beta.1-2563EB" alt="Version v0.1.0-beta.1">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Built%20with-%20Codex-8B5CF6?logo=openai&logoColor=white" alt="Built with Codex">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT license">
</p>

<p align="center">
  <img src="docs/assets/codexpill-menu.png" width="360" alt="CodexPill menu showing active accounts, usage bars, saved accounts, and app controls">
</p>

## What It Does

- Keep Codex session and weekly limits visible from the menu bar.
- Switch between saved local accounts without digging through auth files.
- Add accounts through an isolated sign-in flow that does not switch immediately.
- Use selected saved accounts on SSH hosts you configure.
- Stay local-first: no cloud sync, no hidden browser automation, no account data upload.

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

## First Run

Codex must already be installed. CodexPill reads the active local Codex auth
state from `~/.codex/auth.json`, stores saved account snapshots locally under
`~/Library/Application Support/CodexPill` and switches accounts by updating
local Codex auth state.

Saved snapshots contain authentication material and should be treated like
credentials. CodexPill copies selected snapshots only to remote hosts that you
configure.

CodexPill does not require browser cookies, hidden browser windows, Full Disk
Access, Screen Recording or Accessibility permissions for normal use.

## Screenshots

| Add Account | Add Remote Host |
| --- | --- |
| <img src="docs/assets/codexpill-add-account.png" width="420" alt="CodexPill Add Account dialog"> | <img src="docs/assets/codexpill-add-host.png" width="420" alt="CodexPill Add Remote Host dialog"> |

| Account Actions | Preferences |
| --- | --- |
| <img src="docs/assets/codexpill-account-actions.png" width="420" alt="CodexPill account actions submenu"> | <img src="docs/assets/codexpill-preferences.png" width="420" alt="CodexPill preferences submenu"> |

## Product Docs

- [Product overview](docs/PRODUCT.md)
- [Feature contracts](docs/features/README.md)
- [Privacy and data handling](docs/PRIVACY.md)
- [Beta testing guide](docs/BETA_TESTING.md)

## Project Policies

- [Changelog](CHANGELOG.md)
- [MIT license](LICENSE)
- [Security policy](SECURITY.md)
