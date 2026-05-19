# CodexPill Phase 001 Closeout: Usage History discovery/prototype

## Status

Complete. RGR-352 landed through PR #126 on 2026-05-19.

## Phase Story

This phase answered the gating question for future Usage History work: CodexPill should not use private backend usage endpoints for historical token charts. The viable prototype path is local Codex session JSONL history, where `token_count` rows can be scanned into recent daily token buckets for the active local account.

The work intentionally stops at a prototype boundary. It adds a Platform/Codex scanner shape, synthetic parser coverage, and product documentation, but no menu UI, graph, background collection, or persistent Usage History storage.

## What Changed

- Added `Sources/Platform/Codex/CodexSessionTokenUsageScanner.swift` to parse local Codex session JSONL `event_msg` rows, extract `last_token_usage` and `total_token_usage`, and bucket totals by day.
- Added `Tests/Platform/Codex/CodexSessionTokenUsageScannerTests.swift` with synthetic JSONL fixtures for totals, malformed rows, windowing, and model/bucket behavior.
- Added `docs/features/token-usage.md` as the feature contract for the opt-in future direction.
- Added `docs/usage-history-token-source-spike.md` with the recommendation, field inventory, privacy limits, and explicit non-goals.

## Evidence

- Review result: merge-ready at `075774e79f089bfe2134a443b5b106e463a187e0`.
- GitHub CI: `Test` passed on the reviewed PR head before landing.
- Local landing verification: `make test` passed with 534 tests in 63 suites.
- Diff safety: `git diff --check` passed.
- Privacy/safety: Linear handoff and review evidence state no raw auth payloads, tokens, cookies, emails, stable account IDs, hostnames, local paths, raw session rows, prompts, responses, or private response samples were committed or included.

## Trust Boundary

Safe to claim: local Codex session JSONL can provide a prototype source for recent daily token buckets when token-count rows exist.

Do not overclaim: this phase does not prove durable account/workspace scoping, saved-account history import, cost/billing accuracy, or a production UI/storage policy.

## Follow-Up

Before building product UI, refine the opt-in Usage History feature with storage policy, active-account labeling, empty/error states, and explicit copy for the account/workspace scoping caveat.

## Diagram Prompts

### Product/Data Path

Create a polished editorial technical report graphic for CodexPill, 001: Usage History discovery/prototype.

Diagram type: Product/Data Path.
Goal: show what this phase made possible in the product, where it sits in the user/operator flow, and what is intentionally not claimed yet.

Phase inputs:
- Product: CodexPill, a native macOS menubar app for Codex account switching and per-account limit visibility.
- Phase title: Usage History discovery/prototype.
- Phase goal: prove whether historical token usage can be read safely for the active Codex account before planning UI.
- Phase outcome: local Codex session JSONL token_count rows are the viable source for recent daily token buckets; backend usage endpoints are not the path for this spike.
- User/operator entry point: opt-in future Usage History capability for active local account.
- Before-state: only current session and weekly rate-limit visibility; no historical token usage source proven.
- After-state: product can prototype day buckets from local session history with documented safety limits.
- Main product capability delivered: evidence-backed data-source recommendation.
- External inputs: Codex session JSONL files, active account local Codex data.
- Product-owned concepts: active account, token usage bucket, local scanner, findings document.
- Persistence/cache/state: no production persistence added; synthetic tests only.
- UI/surface/output: docs and prototype scanner; no menu graph or settings UI.
- Explicit non-goals / not-yet-supported claims: no saved-account history import, no cost dashboard, no workspace/account scoping guarantee, no production graph.

### Code/Object Map

Create a polished editorial technical report graphic for CodexPill, 001: Usage History discovery/prototype.

Diagram type: Code/Object Map.
Goal: show the real architecture/object relationships that explain how this phase works in code.

Phase inputs:
- Product: CodexPill.
- Phase title: Usage History discovery/prototype.
- Main implementation move: add an isolated Platform/Codex scanner that reads local Codex session JSONL token_count rows and produces daily token usage buckets for prototype evidence.
- Architecture boundaries: Platform/Codex owns Codex session parsing; docs own product recommendation; no SwiftUI/MenuBar UI and no production persistence.
- Real modules/types/classes/files to include: CodexSessionTokenUsageScanner.swift, CodexSessionTokenUsageDay, CodexSessionTokenUsageTotals, CodexSessionTokenUsageScannerTests.swift, docs/features/token-usage.md, docs/usage-history-token-source-spike.md.
- Important methods or responsibilities: scan recent session files, decode JSONL event_msg rows, read last_token_usage and total_token_usage totals, bucket by local day, keep synthetic parser tests, document active-account and privacy limits.
- Data/control flow: session files -> scanner -> token-count totals -> day buckets -> findings document and feature contract.
- Persistence/runtime dependencies: local Codex session history only; no CodexPill storage or background collection.
- Evidence/inspector/proof boundary: synthetic fixtures and redacted local probe evidence, not committed raw rows.
- Known deferred architecture work: account/workspace scoping, saved-account history, UI graph, persistent cache.
