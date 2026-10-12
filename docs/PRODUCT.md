# Product

CodexPill is a native macOS menubar app for Codex account switching, and for limits of Codex, Claude and Cursor on this Mac.

It is for people who use more than one Codex account, or Codex next to Claude Code and Cursor, and want to see at a glance how much of each limit is left:

- save Codex accounts as reusable local sign-ins;
- switch the Codex account from the menubar;
- see current usage (session, weekly, monthly, or billing cycle) before choosing which account or tool to use;
- spend a Codex reset credit when one is available.

Codex is always on. Claude Code and Cursor are opt-in and read-only: each is read only after the user connects it, and CodexPill shows the one account each tool is signed in to, by its email. It never writes their files or Keychain items. The one thing it runs is `claude doctor`, which lets Claude Code renew its own expired sign-in.

Detailed product behavior and UX contracts live in [features](features/README.md).

## Target User

Primary user:

- a macOS developer who uses two or more Codex accounts, often next to Claude Code or Cursor;
- understands local developer tooling;
- wants fast Codex switching and quick visibility into which account or tool still has room.

Secondary user:

- a developer who occasionally switches between a personal and a work account;
- wants less friction, not a complex account-management dashboard.

## Core Outcomes

1. Add another Codex account without disrupting the current session.
2. See which account each tool uses on this Mac.
3. Switch Codex accounts from the menubar with a clear, bounded flow.
4. See each tool's limits from the tool's own usage source, never from manual counters.
5. Understand when the app cannot read a tool or cannot confidently match the live sign-in to a saved account.

## Product Principles

- Menubar-first, not settings-first.
- Local-first, no CodexPill cloud service.
- Fast account switching over broad account administration.
- Every tool section works the same way: a header with the plan, then the meters.
- In-app copy is a title plus at most one short line.
- Do not expose raw auth payloads, tokens, or secrets in UI or logs.
- Be honest when a reading is stale, failed, or the account cannot be matched.

## Core Concepts

### Tool

Codex, Claude Code or Cursor. Each has one menu card with its usage, and a side menu. Codex's side menu holds its saved accounts. A tool's usage never affects another tool's account ranking.

### Saved Account

A Codex sign-in stored by CodexPill, so the user can switch back to it: a saved `auth.json` snapshot with a user-facing label, optional Codex metadata, and the latest known limits. Claude Code and Cursor have no saved accounts.

### Active Account

The account a tool uses right now on this Mac, read from that tool's own live sign-in.

### Usage Snapshot

The most recent reading of a tool's limits: one window per limit the tool reports, named by its length (session, weekly, monthly, billing cycle, or a length such as `8 days`), with reset times. A window the tool does not report is hidden, never shown as 0%.

### Reset Credit

A Codex credit that resets the current limits early. CodexPill shows how many are left and spends one only after the user confirms.

## Non-Goals

- Browser-based ChatGPT account switching.
- Signing in to Claude Code or Cursor, switching their accounts, or renewing their sessions with CodexPill's own code. Claude Code renews its own expired sign-in when CodexPill runs `claude doctor` while Claude Code is not running.
- Cloud sync or multi-device account storage.
- Team/shared account management.
- Background telemetry pipeline.
- Large multi-window preferences UI unless the menubar surface becomes too constrained.
