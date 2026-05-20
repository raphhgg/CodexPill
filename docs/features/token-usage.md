# Token Usage

## User Story

As a CodexPill user, I want to see when my Codex token usage is light or heavy over time, so I can understand my working rhythm from the menu bar without sending usage data anywhere.

## Product Contract

Token Usage is an optional, local-first menu bar feature. When enabled, CodexPill scans local Codex session records on this Mac, aggregates token-count events into daily buckets, and shows a compact token usage summary in the main menu.

The feature is about local Codex usage history, not saved-account usage history. V1 must not imply that the graph is split by saved account, workspace, organization, or remote host.

CodexPill must not use undocumented backend usage endpoints, browser cookies, hidden WebViews, ChatGPT dashboard scraping, or manual prompt token counters for this feature.

CodexPill may read local Codex session logs as an observation surface, but it must not expose prompt content, raw session rows, file paths, auth payloads, account identifiers, emails, hostnames, or raw log bodies in UI, diagnostics, tracker comments, or test fixtures.

## Source Contract

The selected source is local Codex session history, not private backend usage endpoints.

Codex writes session JSONL files under its local sessions directory. Rows with `payload.type == "token_count"` can contain token usage snapshots for a turn or session, currently under `payload.info.last_token_usage` and `payload.info.total_token_usage`. CodexPill may scan those rows only through a `Platform/Codex` adapter. Feature and UI code must not know JSONL file layout, Codex internal row shapes, or local Codex storage paths.

Useful field classes in the local session rows:

- total token count;
- input token count;
- cached input token count;
- output token count;
- reasoning output token count;
- nearby model context when a `turn_context` row is present.

Token Usage treats daily buckets as local-session scoped. It does not promise a safe account boundary. Account-specific history remains deferred unless Codex session data exposes a stable, privacy-safe account marker or an official local API provides account-scoped usage history.

## Happy Path

1. User enables Token Usage from Preferences.
2. CodexPill scans recent local Codex session JSONL files for token-count events.
3. CodexPill aggregates safe token totals by day.
4. The main menu shows a compact Token Usage card below the active account area.
5. User can choose the display period from Preferences.

## UI / Copy / States

Preferences:

- `Token Usage`
- `Show Token Usage`
- `Period`
- `Last 7 Days`
- `Last 30 Days`
- `Last 90 Days`

Default:

- Token Usage is off by default.
- Default period is `Last 30 Days`.

Menu card:

- Position: below the active account card and above account/action sections.
- Title: `Token Usage`
- Scope label: `This Mac`
- Chart: compact daily bar chart for the selected period.
- Chart design must go through a human review checkpoint before final implementation. The issue should propose multiple visual variants with screenshots so the preferred direction can be selected deliberately.
- Summary copy:
  - `Today: <tokens> tokens`
  - `Last 30 days: <tokens> tokens`

When another period is selected, the second summary line should match the selected period:

- `Last 7 days: <tokens> tokens`
- `Last 30 days: <tokens> tokens`
- `Last 90 days: <tokens> tokens`

States:

- Off: no Token Usage card is shown.
- Loading: `Scanning local sessions...`
- No data: `No token usage found yet`
- Unavailable/error: `Token usage unavailable`

## Edge Cases

- No local Codex session files exist.
- Session files exist but contain no token-count events.
- Token-count events include repeated cumulative totals.
- A long-running thread crosses a day boundary.
- A thread is forked or resumed and inherits earlier totals.
- A session file is truncated, malformed, or too large to parse naively.
- Model metadata is missing or appears only in nearby `turn_context` rows.
- Multiple Codex homes exist; V1 only scans the active local Codex home.
- Remote hosts exist; V1 does not scan or display their token usage.

## Acceptance Criteria

- Token Usage can be enabled and disabled from Preferences.
- When disabled, the main menu does not show the Token Usage card.
- When enabled, the main menu shows a compact Token Usage card below the active account area.
- The card displays a daily bar chart for the selected period.
- The card displays today’s token total and the selected-period token total.
- The card is clearly scoped to `This Mac`.
- The selected period can be changed between last 7, 30, and 90 days.
- Aggregation is derived from local Codex session token-count events, not backend `/api/codex/usage`.
- The implementation emits only aggregate token totals and never raw prompt/session/auth content.
- Synthetic fixture tests cover parsing, aggregation, malformed rows, and repeated cumulative totals.

## Candidate Execution Slices

### Prototype Token Usage Chart Variants

Purpose:

Explore compact chart treatments for the Token Usage card before committing to the final UI direction.

Contract:

- Use synthetic or fixture token data.
- Show the card in the intended menu position below the active account area.
- Do not depend on the production scanner.
- Do not implement final persistence, preferences, backend access, account split, or remote host usage.
- Produce screenshots for human review.

Required variants:

- Minimal daily bars.
- Stock-style sparkline or area chart.
- Calendar-inspired heat strip or density view.
- Native compact card variant optimized for menu readability.

Acceptance:

- Every variant uses the same data and comparable card dimensions.
- Every variant shows realistic `Today` and selected-period totals.
- Every variant includes `This Mac` scope copy.
- The handoff includes screenshots and a short trade-off note for each variant.
- The issue is marked for human review before any final Token Usage UI implementation begins.

## Validation Targets

- Unit tests for token-count parsing from synthetic JSONL fixtures.
- Unit tests for repeated cumulative totals and delta aggregation.
- Unit tests for malformed or missing token-count rows.
- Presentation tests for card visibility, selected-period copy, empty state, and error state.
- Manual QA with Token Usage off, enabled with data, enabled with no data, and period changes.
- Human review of chart variants with screenshots before the final menu card design is locked.
- Privacy review confirming no prompts, auth values, account IDs, emails, local paths, hostnames, or raw rows are emitted.

## Out Of Scope / Deferrals

- Click-through detail panel.
- Inspecting an individual day.
- Model breakdown.
- Saved-account attribution.
- Remote-host usage history.
- Cost estimation.
- Exporting usage data.
- Browser dashboard scraping.
- Hidden WebView/cookie import.
- Backend private endpoint integration.
- Cloud sync or telemetry upload.

## Open Questions

- Should cached aggregates live under `~/Library/Caches/CodexPill` or be recomputed on demand?
- What refresh cadence is enough without making menu opening feel slow?
- Should the app expose a manual `Refresh Token Usage` action, or rely on the existing refresh flow?
- Which compact chart visual direction should ship: minimal bars, stock-style sparkline, calendar-like heat strip, or another native menu-friendly variant?

## Recommended Next Checkpoint

Use the Linear Token Usage issues created from this contract:

- RGR-360: Prototype Token Usage chart variants.
- RGR-361: Productionize local Token Usage aggregation.
- RGR-362: Implement opt-in Token Usage menu card.
