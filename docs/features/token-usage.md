# Token Usage History

Usage History is an opt-in future feature for helping users understand how much
Codex work they have done over time. The feature is token-first: daily totals
matter more than cost or billing semantics.

## Current Prototype Contract

The current candidate source is local Codex session history, not private backend
usage endpoints.

Codex writes session JSONL files under its local sessions directory. Rows with
`payload.type == "token_count"` can contain token usage snapshots for a turn or
session, currently under `payload.info.last_token_usage` and
`payload.info.total_token_usage`. CodexPill may scan those rows only through a
Platform/Codex adapter. Feature and UI code must not know JSONL file layout,
Codex internal row shapes, or local Codex storage paths.

Useful field classes in the local session rows:

- total token count;
- input token count;
- cached input token count;
- output token count;
- reasoning output token count;
- nearby model context when a `turn_context` row is present.

The prototype treats daily buckets as local-session scoped. It does not prove a
safe account boundary. Account-specific history remains deferred unless Codex
session data exposes a stable, privacy-safe account marker or an official local
API provides account-scoped usage history.

## Privacy Rules

Usage History must not store, display, log, export, or commit raw session rows.
Session rows can contain private prompts, tool output, file names, command text,
or other sensitive content. Any prototype or validation output must be
aggregate-only and must not include raw rows, account identifiers, emails, local
paths, hostnames, prompts, responses, or auth material.

## Non-Goals For This Prototype

- No production menu UI.
- No graph or settings entry.
- No persistent Usage History database.
- No backend `/usage` integration.
- No account split, workspace split, remote-host split, or cost dashboard.
