# Usage History Token Source Spike

Issue: RGR-352

Date: 2026-05-19

## Question

Can CodexPill fetch recent historical token usage for the active account,
bucketed by day, safely enough to support a future opt-in Usage History feature?

## Recommendation

Use a local-session-history prototype path and defer any production Usage
History UI until account scoping and privacy policy are refined.

The useful source found for daily token totals is local Codex session JSONL, not
private backend usage endpoints. Codex session files include token-count event
rows that can be aggregated into local daily buckets without reading auth
payloads or calling backend APIs. This is enough to support a future local-only,
opt-in token history experiment, but it does not yet prove active-account or
saved-account separation.

Do not build production menu UI, persistence, or graphs from this issue. Do not
use backend `/usage` endpoints for this feature.

## Prototype Artifact

The prototype adds an isolated Platform/Codex scanner:

- `Sources/Platform/Codex/CodexSessionTokenUsageScanner.swift`
- `Tests/Platform/Codex/CodexSessionTokenUsageScannerTests.swift`
- `docs/features/token-usage.md`

The scanner reads only local session JSONL files passed to it by caller-owned
configuration. It does not know Codex auth files, saved snapshots, account
catalogs, SwiftUI, menus, backend APIs, or persistence policy.

## Candidate Source

### Local Codex session JSONL

Status: viable prototype source for local daily token buckets.

Codex session files are organized by date and contain JSONL event rows. Rows
with `payload.type == "token_count"` can include:

- `payload.info.last_token_usage`;
- `payload.info.total_token_usage`.

The prototype prefers `last_token_usage` because it is already a per-turn delta.
When only cumulative `total_token_usage` exists, it derives positive deltas
inside one session file and ignores non-positive cumulative movement.

Useful field classes available from token-count rows:

- total tokens;
- input tokens;
- cached input tokens;
- output tokens;
- reasoning output tokens;
- day bucket from session file date;
- model context when nearby session metadata includes a model value.

Fields not proven:

- stable active-account identifier;
- saved-account identifier;
- workspace/org identifier;
- remote-host attribution;
- cost-like values;
- complete model split for every token-count row.

Scope appears local Codex session specific. It is not proven to be active-account
specific, ChatGPT/account-wide, workspace/org-scoped, or remote-inclusive.

### Backend usage endpoints

Status: out of scope for this feature direction.

The earlier backend probe showed accessible backend usage surfaces either map to
current quota/rate-limit state or reject active bearer auth. A follow-up product
review clarified that those endpoints should not drive this spike. Public Codex
source indicates the relevant `/usage` surface backs rate-limit status rather
than historical daily token usage.

Backend usage endpoints should stay out of scope unless a future explicit-risk
issue asks for a documented API or a human-approved private API investigation.

## Active Account And Saved Accounts

This prototype cannot safely answer per-account history yet. Local session
history proves local daily token buckets, not account ownership. If the user
switches accounts during the date range, local session rows may include usage
from multiple accounts unless Codex exposes a reliable account marker in session
metadata or a local app-server method supplies account-scoped history.

Querying non-active saved accounts is not supported by this prototype. Future
options would require a separate human-reviewed design:

- isolated auth with an official local history API;
- explicit user-approved temporary switching;
- no saved-account history when the source is local-session scoped only.

Until account scoping is proven, the product should label any follow-up as local
Codex usage history, not active-account history.

## Privacy Notes

Session JSONL rows can contain prompts, responses, file paths, command text, and
other private content. The prototype parser reads only event type, token-count
objects, session date, and model context. It ignores message/content rows and
does not emit raw session rows.

No raw auth data, tokens, cookies, emails, stable account IDs, backend account
IDs, local paths, hostnames, prompts, responses, command text, or private
session samples are included in this document or tests. Tests use synthetic
JSONL fixtures only.

## Verification

The synthetic parser coverage proves:

- `last_token_usage` rows aggregate into day buckets;
- cumulative `total_token_usage` rows produce positive deltas;
- malformed rows are ignored;
- non-usage rows, including private message content, are ignored;
- model context is captured only as an optional model value;
- date filtering keeps the requested range.

Redacted local validation on this development machine found recent session files
with token-count rows over 31 day buckets. The rows exposed both
`last_token_usage` and `total_token_usage`, and the numeric field names included
`input_tokens`, `cached_input_tokens`, `output_tokens`,
`reasoning_output_tokens`, and `total_tokens`. The validation reported only
aggregate counts and field names, with no raw rows, file paths, prompts, account
identifiers, or session samples printed.

## Product Implication

Refine Usage History around an opt-in local-session scanner only after deciding
how to describe its scope honestly. The likely recommendation is:

- use local session JSONL behind Platform/Codex for local daily token buckets;
- do not claim active-account accuracy yet;
- defer saved-account split and account/workspace attribution;
- keep backend usage endpoints out of scope;
- require human review before adding UI, storage, or account-scoped claims.
