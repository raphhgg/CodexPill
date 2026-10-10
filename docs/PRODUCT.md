# Product

CodexPill is a native macOS menubar app for people who actively use multiple Codex accounts and need to switch between them quickly without losing track of account plan and rate-limit state.

The product replaces manual auth-file swapping and repeated app restarts with a small, deliberate workflow:

- save Codex accounts as reusable local snapshots;
- switch the active Codex account from the menubar;
- see current session and weekly Codex usage before choosing which account to use;
- use the same saved accounts on configured remote hosts;
- optionally see Claude and Cursor usage next to Codex;
- save several Cursor sign-ins and switch Cursor between them.

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

### Other Providers

Claude and Cursor are optional providers next to Codex. Each one is opt-in and has its own menu section below the saved accounts. Their usage never affects Codex account availability, ranking, or notifications.

- **Claude.** CodexPill keeps one sign-in of its own, used only to read usage. Switching Claude accounts is planned but not built yet.
- **Cursor.** CodexPill reads Cursor's sign-in to show usage, and can save several Cursor sign-ins and switch Cursor between them. A switch quits Cursor, puts the saved sign-in back into Cursor's local database, and reopens Cursor. See [Cursor Usage](features/cursor-usage.md#account-switching).

### Remote Host

A user-configured SSH target where CodexPill can install saved account snapshots, switch remote Codex auth, and verify the remote active account.

## Non-Goals

- Browser-based ChatGPT account switching.
- Account switching for non-Codex tools other than Cursor and, later, Claude.
- Signing in to or refreshing the session of a non-Codex tool on its behalf. Cursor switching only puts back a sign-in Cursor itself created.
- Cloud sync or multi-device account storage.
- Team/shared account management.
- Background telemetry pipeline.
- Large multi-window preferences UI unless the menubar surface becomes too constrained.
