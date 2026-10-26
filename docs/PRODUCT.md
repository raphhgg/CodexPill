# Product

rusage is a native macOS menubar app that shows Codex, Claude Code and Cursor usage limits and when they reset. rusage was called CodexPill before.

It is for people who use Codex, often next to Claude Code and Cursor, and want to see at a glance how much of each limit is left:

- see current usage (session, weekly, monthly, or billing cycle) before choosing which tool to use;
- spend a Codex reset credit when one is available;
- sign in to another Codex account from rusage when needed.

rusage shows one account per tool: the one each tool is signed in to on this Mac, by its email. For Codex that is the sign-in in `~/.codex/auth.json`. rusage keeps no list of saved accounts.

Codex is on until the user signs out of it. Claude Code and Cursor are opt-in and read-only: each is read only after the user connects it. It never writes their files or Keychain items, and it never runs them. For Claude and Cursor, the user can also opt in to rusage's own sign-in, which rusage keeps in its own Keychain item and renews itself.

Detailed product behavior and UX contracts live in [features](features/README.md).

## Target User

Primary user:

- a macOS developer who uses Codex, often next to Claude Code or Cursor;
- understands local developer tooling;
- wants quick visibility into which tool still has room.

Secondary user:

- a developer who occasionally signs in to a different Codex account;
- wants less friction, not a complex account-management dashboard.

## Core Outcomes

1. See which account each tool uses on this Mac.
2. See each tool's limits from the tool's own usage source, never from manual counters.
3. Sign in to another Codex account with a clear, bounded flow that changes nothing until the user confirms.
4. Understand when the app cannot read a tool or a tool is signed out.

## Product Principles

- Menubar-first, not settings-first.
- Local-first, no rusage cloud service.
- One account per tool, no account administration.
- Every tool section works the same way: a header with the plan, then the meters.
- In-app copy is a title plus at most one short line.
- Do not expose raw auth payloads, tokens, or secrets in UI or logs.
- Be honest when a reading is stale or failed.

## Core Concepts

### Tool

Codex, Claude Code or Cursor. Each has one menu card with its usage, and a side menu that shows its account.

### Account

The one account a tool uses right now on this Mac, read from that tool's own live sign-in. rusage holds it in memory with its latest known limits and stores no copy of the sign-in. Signing in to another Codex account replaces it.

### Usage Snapshot

The most recent reading of a tool's limits: one window per limit the tool reports, named by its length (session, weekly, monthly, billing cycle, or a length such as `8 days`), with reset times. A window the tool does not report is hidden, never shown as 0%.

### Reset Credit

A Codex credit that resets the current limits early. rusage shows how many are left and spends one only after the user confirms.

## Non-Goals

- Browser-based ChatGPT account switching.
- Saving several Codex accounts and switching between them.
- Signing in to Claude Code or Cursor, switching their accounts, renewing their sessions, or starting them to renew. Each tool renews its own sign-in when the user runs it. rusage's own Claude sign-in is separate and never touches Claude Code's.
- Cloud sync or multi-device account storage.
- Team/shared account management.
- Background telemetry pipeline.
