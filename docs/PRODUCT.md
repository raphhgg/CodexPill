# Product

CodexPill is a native macOS menubar app for account switching and limits for Codex, Claude and Cursor on this Mac.

It is for people who use more than one account in these tools and want to see, at a glance, how much of each limit is left and switch accounts without editing auth files or restarting apps by hand:

- save accounts as reusable local sign-ins;
- switch the account a tool uses from the menubar;
- see current usage (session, weekly, or billing cycle) before choosing which account to use;
- spend a Codex reset credit when one is available.

Codex is always on. Claude Code and Cursor are opt-in: each is read only after the user connects it.

Detailed product behavior and UX contracts live in [features](features/README.md).

## Target User

Primary user:

- a macOS developer who uses Codex, Claude Code or Cursor with two or more accounts;
- understands local developer tooling;
- wants fast switching and quick visibility into which account still has room.

Secondary user:

- a developer who occasionally switches between a personal and a work account;
- wants less friction, not a complex account-management dashboard.

## Core Outcomes

1. Add another account without disrupting the current session.
2. See which saved account each tool uses on this Mac.
3. Switch accounts from the menubar with a clear, bounded flow.
4. See each tool's limits from the tool's own usage source, never from manual counters.
5. Understand when the app cannot read a tool or cannot confidently match the live sign-in to a saved account.

## Product Principles

- Menubar-first, not settings-first.
- Local-first, no CodexPill cloud service.
- Fast account switching over broad account administration.
- Every tool section works the same way: a header with the plan, the meters, and the same account actions.
- In-app copy is a title plus at most one short line.
- Do not expose raw auth payloads, tokens, or secrets in UI or logs.
- Be honest when a reading is stale, failed, or the account cannot be matched.

## Core Concepts

### Tool

Codex, Claude Code or Cursor. Each has one menu card with its usage, and a side menu with its saved accounts. A tool's usage never affects another tool's account ranking.

### Saved Account

A locally stored sign-in managed by CodexPill, so the user can switch back to it.

- **Codex.** A saved `auth.json` snapshot with a user-facing label, optional Codex metadata, and the latest known limits.
- **Claude Code.** Claude Code's own sign-in for that account in a CodexPill Keychain item, matched by Claude Code's account record, with its latest known limits. It is added by running Claude Code's login in a throwaway folder, or by saving the sign-in Claude Code uses now. Switching is refused while Claude Code runs.
- **Cursor.** A copy of Cursor's sign-in rows in a CodexPill Keychain item, with its latest known limits. It is added by signing in through Cursor in a separate window with a throwaway profile, or by saving the sign-in Cursor uses now. A switch quits Cursor, writes the saved sign-in back into Cursor's local database, and reopens Cursor. CodexPill never renews a saved Cursor sign-in, so an expired one keeps its last limits.

### Active Account

The account a tool uses right now on this Mac, read from that tool's own live sign-in.

### Usage Snapshot

The most recent reading of a tool's limits: one window per limit the tool reports (session, weekly, billing cycle), with reset times. A window the tool does not report is hidden, never shown as 0%.

### Reset Credit

A Codex credit that resets the current limits early. CodexPill shows how many are left and spends one only after the user confirms.

## Non-Goals

- Browser-based ChatGPT account switching.
- Signing in to Claude Code or Cursor, or renewing their sessions, with CodexPill's own code. CodexPill runs the tool's own login and lets the tool renew its sign-ins: Claude Code renews a saved copy in a throwaway folder, and its own expired sign-in when it isn't running. Switching only puts back a sign-in the tool itself created.
- Cloud sync or multi-device account storage.
- Team/shared account management.
- Background telemetry pipeline.
- Large multi-window preferences UI unless the menubar surface becomes too constrained.
