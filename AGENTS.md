# AGENTS.md

## Read First

1. Read this file first.
2. Read `$HOME/Projects/codex-usage-menubar-app/docs/BOOTSTRAP.md` for current product truth.
3. For shared standards, load `$HOME/agent-standards/AGENTS.md`.

## Shared Standards

- This repo is a prototype-first bootstrap.
- Prefer the `bootstrap-orchestrator` path for day-zero changes and the `macos-menubar-tuist-app` skill for scaffold/build loop work.
- Load one shape doc and only the minimum matching capability docs from `$HOME/agent-standards`.

## Project Shape

- Platform: native macOS menubar app
- UI: SwiftUI `MenuBarExtra`
- Build system: Tuist
- Product focus: Codex account switching and per-account limit tracking

## Architecture Defaults

- Treat `~/.codex/auth.json` as the primary switch surface.
- Treat `~/Library/Application Support/Codex` as an observation surface, not the source of truth for switching.
- Keep auth switching, Codex app lifecycle control, and Codex rate-limit fetching in separate modules.
- Prefer the local Codex app-server for account and rate-limit reads over manual counters.

## Hard Rules

- Do not print or expose tokens, API keys, or raw auth payloads in logs or UI.
- Do not couple SwiftUI views directly to file I/O or process control.
- Do not assume Codex internal file formats beyond the currently observed `auth.json` contract without isolating that logic in one service.
