# Changelog

## Unreleased

### Changed

- Renamed CodexPill to Refill. The bundle ID stays the same, so saved accounts
  and settings carry over.
- New capsule app icon, built in Icon Composer.

### Added

- App Icon colour setting under `Settings › Appearance`, with six colours. It
  changes the icon in About and in alerts. Finder keeps Cobalt.

## v0.1.0-beta.2 - 2026-05-31

Second public beta of CodexPill.

### Added

- Optional Token Usage card in the menubar, including chart style and loading
  animation preferences.
- Local Codex session token history aggregation for recent usage windows.
- Token Usage incremental cache to avoid repeatedly rescanning unchanged
  session files.
- GitHub Actions CI for pull requests and `main`.

### Changed

- Migrated the app and tests to Swift 6 language mode.
- Reduced status item background polling.
- Improved README install copy and release documentation.

### Fixed

- Token Usage refreshes now reuse cached all-time peak and unchanged file
  contributions instead of repeatedly scanning the full transcript history.
- Token Usage keeps the previous chart visible while a refresh is in progress.
- Token Usage menu progress updates no longer rebuild the menu while it is open
  or closed until the next safe refresh point.
- Remote host and menu validation tests were stabilized.
- Legacy remote host settings are cleared safely.
- Weekly limit windows tolerate near-weekly reset timings.
- Native menu quit alignment was corrected.

## v0.1.0-beta.1 - 2026-05-13

First public beta of CodexPill.

### Added

- Signed and notarized GitHub Release zip for direct download.
- Menu bar limits for the active Codex account.
- Saved local account switching.
- Isolated Add Account flow that does not switch the current local session immediately.
- Remote host support for using selected saved accounts over SSH.
- Preferences for menu bar label, icon style, usage bars and launch at login.
- Diagnostics export for easier bug reports.

### Notes

- Requires macOS 14 or later.
- Codex must already be installed and signed in.
- Homebrew, Sparkle auto-updates and Mac App Store distribution are not available yet.
- CodexPill is local-first and does not provide cloud sync.
