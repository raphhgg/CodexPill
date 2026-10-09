# Product

CodexPill is a native macOS menubar app for people who actively use multiple Codex accounts and need to switch between them quickly without losing track of account plan and rate-limit state.

The product replaces manual auth-file swapping and repeated app restarts with a small, deliberate workflow:

- save Codex accounts as reusable local snapshots;
- switch the active Codex account from the menubar;
- see current session and weekly Codex usage before choosing which account to use;
- use the same saved accounts on configured remote hosts;
- optionally see Claude Code and Cursor usage next to Codex.

Detailed product behavior and UX contracts live in [features](features/README.md).

## Target User

Primary user:

- a macOS Codex power user;
- uses two or more Codex accounts;
- understands local developer tooling;
- wants fast switching and quick visibility into rate-limit availability.

Secondary user:

- a developer who occasionally switches between personal and work Codex accounts;
- wants less friction, not a complex account-management dashboard.

## Core Outcomes

1. Add another Codex account without disrupting the current local session.
2. See which saved account is active locally and remotely.
3. Switch accounts from the menubar with a clear, bounded flow.
4. Refresh Codex account metadata and rate limits from Codex app-server surfaces.
5. Understand when the app cannot confidently match live auth to a saved account.

## Product Principles

- Menubar-first, not settings-first.
- Local-first, no CodexPill cloud service.
- Fast account switching over broad account administration.
- Explicit boundaries around file I/O, process control, and Codex integration.
- Do not expose raw auth payloads, tokens, or secrets in UI or logs.
- Be honest when account identity cannot be matched confidently.

## Core Concepts

### Saved Account

A locally stored account entry managed by CodexPill. It includes a user-facing label, saved auth snapshot reference, optional Codex metadata, and latest known rate-limit snapshot.

### Active Account

The currently effective Codex account represented by live Codex auth state on a target.

### Account Snapshot

A stored copy of Codex auth state used for later re-activation. A snapshot is not the same thing as canonical account identity.

### Rate-Limit Snapshot

The most recently fetched local or remote view of Codex session and weekly availability.

### Display-Only Provider

A non-Codex tool whose usage CodexPill shows but never manages. Claude Code and Cursor are display-only providers. Each one is opt-in and has its own menu section below the saved accounts. CodexPill does not switch, sign in to, or save accounts for them. Their usage never affects Codex account availability, ranking, or notifications.

### Remote Host

A user-configured SSH target where CodexPill can install saved account snapshots, switch remote Codex auth, and verify the remote active account.

## Non-Goals

- Browser-based ChatGPT account switching.
- Account switching, sign-in, or session refresh for Claude Code, Cursor, or other non-Codex tools.
- Cloud sync or multi-device account storage.
- Team/shared account management.
- Background telemetry pipeline.
- Large multi-window preferences UI unless the menubar surface becomes too constrained.
