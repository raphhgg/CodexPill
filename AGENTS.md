# AGENTS.md

## Project Shape

- Platform: native macOS menubar app.
- UI: SwiftUI `MenuBarExtra` with AppKit menu, alert, and panel interop.
- Build system: Tuist.
- Product focus: Codex account switching and per-account limit tracking.

## Read First

1. Read this file first.
2. Read `docs/PRODUCT.md` and `docs/features/README.md` for product truth.
3. Read `docs/DEVELOPMENT.md` before build, run, or validation commands.
4. Read `docs/PRIVACY.md` before touching account, auth, logging, or remote-host code.

## Architecture Defaults

- Treat `~/.codex/auth.json` as the primary local switch surface.
- Treat `~/Library/Application Support/Codex` as an observation surface, not the
  source of truth for switching.
- Keep auth switching, Codex app lifecycle control, and Codex rate-limit fetching
  in separate modules.
- Prefer the local Codex app-server for account and rate-limit reads over manual
  counters.

## Hard Rules

- Do not print or expose tokens, API keys, raw auth payloads, or saved auth
  snapshots in logs, tests, docs, UI, issues, or commit messages.
- Do not commit `.env`, secrets, generated auth snapshots, personal app-support
  data, or build artifacts.
- Do not couple SwiftUI views directly to file I/O or process control.
- Do not assume Codex internal file formats beyond the currently observed
  `auth.json` contract without isolating that logic in one service.
