# AGENTS.md

## Project Shape

- Platform: native macOS menubar app.
- UI: AppKit `NSMenu` and status item, with SwiftUI views inside menu items, plus AppKit alerts and panels.
- Build system: Tuist.
- Product: Refill (formerly CodexPill). Usage limits for Codex, Claude Code and Cursor on this Mac, and switching
  between saved Codex accounts.

## Read First

1. Read this file first.
2. Read `docs/PRODUCT.md` and `docs/features/README.md` for product truth.
3. Read `docs/ARCHITECTURE.md` before adding a module, a port, or a tool.
4. Read `docs/DEVELOPMENT.md` before build, run, or validation commands.
5. Read `docs/PRIVACY.md` before touching account, auth, Keychain, or logging code.

## Architecture Defaults

- Dependencies point one way: `App -> Features -> Platform -> Core`. Core and Platform never reference a
  Features name; `LayerBoundaryTests` fails the build's tests when they do.
- Core holds models and typed preferences only.
- Every tool section is driven the same way: Claude Code and Cursor conform to `ProviderConnection`, and
  every tool menu item sends a `ProviderMenuAction` through one coordinator selector. Codex stays on
  `AccountsController` behind the same action value. See "How a tool plugs in" in `docs/ARCHITECTURE.md`.
- Codex: `~/.codex/auth.json` is the switch surface. `~/Library/Application Support/Codex` is only
  observed. Read accounts and limits from the local Codex app-server, never from manual counters.
- Keep Codex auth switching, Codex app lifecycle control, and each tool's usage fetching in separate Platform
  types. Claude Code and Cursor are read-only: never write their files or Keychain items.

## Hard Rules

- Do not print or expose tokens, API keys, raw auth payloads, or saved sign-ins in logs, tests, docs, UI,
  issues, or commit messages.
- Do not commit `.env`, secrets, generated auth snapshots, personal app-support data, or build artifacts.
- Do not couple SwiftUI views directly to file I/O or process control.
- Do not assume a tool's internal file formats beyond what is observed today, and isolate each format in
  one Platform type.
- In-app copy is a title plus at most one short line.
