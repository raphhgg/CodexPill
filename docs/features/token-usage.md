# Token Usage

## User Story

As a CodexPill user, I want to see when my Codex token usage is light or heavy over time, so I can understand my working rhythm from the menu bar without sending usage data anywhere.

## Product Contract

Token Usage is an optional, local-first menu bar feature. When enabled, CodexPill scans local Codex session records on this Mac, aggregates token-count events into daily buckets, and shows a compact token usage summary in the main menu.

The scan should be treated as a background data-loading job, not as work owned by the transient menu view. Opening or closing the menu must not restart the scan. Once enough local history has been scanned, changing period or chart style should derive a new presentation from cached aggregate data instead of visibly re-scanning local session files.

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
2. CodexPill starts scanning recent local Codex session JSONL files in the background.
3. User can close the menu or continue working while the scan completes.
4. CodexPill aggregates safe token totals by day and stores them in a derived cache.
5. The main menu shows a compact Token Usage card inside the active account area, directly below the Session and Weekly limit rows.
6. Chart-style changes update the visible card from cached aggregate data.

## UI / Copy / States

Preferences:

- `Token Usage`
- `Show Token Usage`
- `Chart Style`
- `Daily Bars`
- `Heat Strip`
- `Sparkline`

Default:

- Token Usage is off by default.
- Default period is `Last 30 Days`.

Menu card:

- Position: inside the active account area, directly below the Session and Weekly limit rows and before the divider/account-action sections.
- Title: `Token Usage`
- Scope label: `This Mac`
- Chart: compact chart for the selected period.
- Chart styles: `Daily Bars`, `Heat Strip`, and `Sparkline`.
- Chart design must go through a human review checkpoint before final implementation. RGR-360 should validate these three styles with screenshots and make sure the final Token Usage card lets the user choose between them.
- Summary copy:
  - `Today: <tokens> tokens`
  - `Last 30 days: <tokens> tokens`
  - `Peak day`
  - `<date>: <tokens> tokens`

V1 always uses `Last 30 days`. Period selection is intentionally not exposed in the menu until the cache/incremental scanner is proven on larger histories.

States:

- Off: no Token Usage card is shown.
- Loading: animated Token Usage placeholder with `Scanning local sessions...`; shown only while no cached aggregate result is available. See [Token Usage Loading Progress](token-usage-loading-progress.md).
- Updating: keep the previous chart visible while a background refresh is running.
- No data: `No token usage found yet`
- Unavailable/error: `Token usage unavailable`

## Cache / Refresh Contract

Token Usage should reuse cached aggregate data first and avoid restarting scans when the menu opens repeatedly.

Expected behavior:

- Enabling Token Usage checks a derived cache before scanning local sessions.
- The default and only visible period is `Last 30 Days`.
- `Last 7 Days` and `Last 90 Days` are deferred until the cache/incremental scanner is proven on large local histories.
- Opening or closing the menu does not cancel or restart the scan.
- Changing chart style never triggers a scan.
- Future period changes should be instant when the cached aggregate range covers the selected period.
- Manual refresh or app-level refresh may start a new background scan, but should not clear the currently visible cached chart before the refresh completes.
- Disabling Token Usage hides the card and stops any active scan, but keeps already-computed persisted aggregate data.
- Re-enabling Token Usage should show cached data immediately when available.
- The cache is persisted under the user cache directory because token usage aggregates are derived data.
- Scanning must stream session files instead of loading them fully into memory. Large files should still be scanned because they often represent heavy usage days.
- Scanning must be bounded by line size so corrupted session rows cannot grow memory unbounded. Rows beyond the guardrail may be skipped; Token Usage is an approximate local trend, not a billing-grade counter.
- Scanning should throttle between chunks so a cold scan can run in the background without pinning CPU.

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
- A future period selector changes period while a scan is already running.
- The user disables Token Usage while a scan is already running.
- The user disables Token Usage after a successful scan, then re-enables it during the same app run.
- The user opens and closes the menu repeatedly while a scan is already running.
- A future selected period requires more days than the currently cached scan result covers.

## Acceptance Criteria

- Token Usage can be enabled and disabled from Preferences.
- When disabled, the main menu does not show the Token Usage card.
- When enabled, the main menu shows a compact Token Usage card inside the active account area, directly below the Session and Weekly limit rows.
- The card displays the selected chart style for the selected period.
- The card displays today’s token total and the selected-period token total.
- The card displays the highest-usage day in the selected period when usage data exists.
- The card is clearly scoped to `This Mac`.
- The visible period is fixed to last 30 days for v1.
- The chart style can be changed between daily bars, heat strip, and sparkline.
- Enabling Token Usage starts a background scan that continues if the menu closes.
- The menu does not start duplicate concurrent scans for repeated opens while the current scan is still running.
- The scanner streams eligible session files instead of loading them fully into memory.
- The scanner parses large files safely instead of skipping them.
- The scanner skips oversized rows instead of trying to parse them into memory.
- Changing chart style updates presentation without re-scanning local session files.
- Future period changes use cached aggregate data when available.
- Re-enabling Token Usage during the same app run uses cached aggregate data immediately when available.
- Refreshing Token Usage keeps the previous chart visible until the new scan result is ready.
- Aggregation is derived from local Codex session token-count events, not backend `/api/codex/usage`.
- The implementation emits only aggregate token totals and never raw prompt/session/auth content.
- Synthetic fixture tests cover parsing, aggregation, malformed rows, and repeated cumulative totals.

## Candidate Execution Slices

### Prototype Token Usage Chart Variants

Purpose:

Validate the three supported chart styles for the Token Usage card before final implementation.

Contract:

- Use synthetic or fixture token data.
- Show the card in the intended menu position inside the active account area, directly below the Session and Weekly limit rows.
- Show the settings/menu path that lets the user choose chart style.
- Do not depend on the production scanner.
- Do not implement final persistence, preferences, backend access, account split, or remote host usage.
- Produce screenshots for human review.

Required variants:

- Daily bars.
- Heat strip.
- Sparkline.

Acceptance:

- Every style uses the same data and comparable card dimensions.
- Every style shows realistic `Today` and selected-period totals.
- Every style includes `This Mac` scope copy.
- The prototype shows how the user chooses between `Daily Bars`, `Heat Strip`, and `Sparkline`.
- The handoff includes screenshots and a short trade-off note for each variant.
- The issue is marked for human review before the final Token Usage UI implementation begins.

## Validation Targets

- Unit tests for token-count parsing from synthetic JSONL fixtures.
- Unit tests for repeated cumulative totals and delta aggregation.
- Unit tests for malformed or missing token-count rows.
- Unit tests for scan lifecycle: enable starts one scan, repeated menu opens do not duplicate it, chart-style changes do not scan, and covered period changes derive from cache.
- Unit tests or presentation tests for loading versus updating states.
- Presentation tests for card visibility, selected-period copy, empty state, and error state.
- Manual QA with Token Usage off, enabled with data, and enabled with no data.
- Manual QA confirming the scan continues after closing the menu, chart-style changes do not flash back to full loading, and disable/re-enable reuses cached data during the same app run.
- Human review of chart variants with screenshots before the final menu card design is locked.
- Privacy review confirming no prompts, auth values, account IDs, emails, local paths, hostnames, or raw rows are emitted.

## Out Of Scope / Deferrals

- Click-through detail panel.
- Inspecting an individual day.
- Secondary metrics such as average per day.
- Model breakdown.
- Saved-account attribution.
- Remote-host usage history.
- User-selectable periods.
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
