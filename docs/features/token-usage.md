# Token Usage

## User Story

As a Refill user, I want to see when my Codex token usage is light or heavy over time, so I can understand my working rhythm from the menu bar without sending usage data anywhere.

## Product Contract

Token Usage is an optional, local-first menu bar feature. When enabled, Refill scans local Codex session records on this Mac, aggregates token-count events into daily buckets, and shows a compact token usage summary in the main menu.

The scan should be treated as a background data-loading job, not as work owned by the transient menu view. Opening or closing the menu must not restart the scan. Once enough local history has been scanned, changing period or chart style should derive a new presentation from cached aggregate data instead of visibly re-scanning local session files.

The feature is about local Codex usage history, not saved-account usage history. V1 must not imply that the graph is split by saved account, workspace, organization, or remote host.

For Codex, Refill must not use undocumented backend usage endpoints, browser cookies, hidden WebViews, ChatGPT dashboard scraping, or manual prompt token counters for this feature. Cursor is the one exception, described in [Other Tools](#other-tools): Cursor keeps usage only on its servers, so Refill reads it the way Cursor's own dashboard does.

Refill may read local Codex session logs as an observation surface, but it must not expose prompt content, raw session rows, file paths, auth payloads, account identifiers, emails, hostnames, or raw log bodies in UI, diagnostics, tracker comments, or test fixtures.

## Source Contract

The selected source is local Codex session history, not private backend usage endpoints.

Codex writes session JSONL files under its local sessions directory. Rows with `payload.type == "token_count"` can contain token usage snapshots for a turn or session, currently under `payload.info.last_token_usage` and `payload.info.total_token_usage`. Refill may scan those rows only through a `Platform/Codex` adapter. Feature and UI code must not know JSONL file layout, Codex internal row shapes, or local Codex storage paths.

Useful field classes in the local session rows:

- total token count;
- input token count;
- cached input token count;
- output token count;
- reasoning output token count;
- nearby model context when a `turn_context` row is present.

Token Usage treats daily buckets as local-session scoped. It does not promise a safe account boundary. Account-specific history remains deferred unless Codex session data exposes a stable, privacy-safe account marker or an official local API provides account-scoped usage history.

## Other Tools

When Claude Code or Cursor is connected in Refill, the Token Usage card adds its daily tokens. Each tool is read only while it is connected, and a tool that can't be read shows `Unavailable` on its own line without hiding the others.

Every tool counts the same way so days compare: input, cached input, cache writes, and output, all included. Dollars are not shown, because Codex and Claude plans are flat subscriptions.

| Tool | Source | Scope | Model |
| --- | --- | --- | --- |
| Codex | Local session JSONL, as above. | This Mac | `payload.model` of the latest `turn_context` (or `session_meta`) row before each `token_count`. Earlier rows count as `unknown`. |
| Claude Code | Local transcripts under `<CLAUDE_CONFIG_DIR or ~/.claude>/projects/**/*.jsonl`, through `Platform/Claude`. | This Mac | `message.model` of each assistant row. |
| Cursor | `POST https://cursor.com/api/dashboard/get-filtered-usage-events` with Cursor's session cookie and `Origin: https://cursor.com`, through `Platform/Cursor`. Undocumented: it is the endpoint Cursor's usage page calls. | Cursor account | `model` of each event. |

Claude Code rules:

- Only assistant rows with `message.usage` are decoded, and only the type, timestamp, `requestId`, `message.id`, `message.model`, and the four token counts are kept. Content is never kept.
- A response is identified by `message.id` and `requestId`. Claude Code writes a response once per content block and copies it into resumed sessions, so each response counts once across all files.
- The day is the local day of the row's `timestamp`.
- Rows are cached per transcript (path relative to the projects folder, size, and modification date), so unchanged transcripts are not read again. Claude Code deletes transcripts after 30 days by default. Cached rows for deleted transcripts are kept for 400 days.

Cursor rules:

- The request body is `{startDate, endDate, page, pageSize}`, with Unix milliseconds as strings and pages of 1,000. Refill reads at most 20 pages and shows Cursor as unavailable rather than undercount.
- Each event's tokens are `inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens`. Events without `tokenUsage` count as zero.
- The day is the local day of the event's `timestamp`.

Card:

- `All-time peak` uses the larger of Codex's all-time peak and the busiest combined day in the period, because only Codex has all-time history. The card no longer shows a peak; the value stays for a later detail view.

## Happy Path

1. User enables `Appearance › Show Token Usage`.
2. Refill starts scanning recent local Codex session JSONL files in the background.
3. User can close the menu or continue working while the scan completes.
4. Refill aggregates safe token totals by day and stores them in a derived cache.
5. The main menu shows the Token Usage card after the tool cards.

## UI / Copy / States

Appearance:

- `Show Token Usage`

Default:

- Token Usage is off by default.
- The period is always `Last 30 days`.
- Chart `Bars`, split `By tool`.

Menu card, in the main menu after the tool cards and before `Add Account`:

- Title row: `Token Usage` and the chart toggle, three icons: bars, area, lines.
- Subtitle: `Last 30 days · 10B · Today 390M`.
- Chart, 44 pt high:
  - `Bars`: one bar per day, stacked by tool, Codex at the bottom.
  - `Area`: the same stack as smoothed areas.
  - `Lines`: one line per tool, each against its own busiest day, so a small tool keeps its shape. The split gives the amounts.
  - Hovering a day shows a tooltip: `Oct 12: 390M tokens`, then each tool's tokens.
- Split toggle: `By tool` or `Top models`.
  - `By tool`: one row per tool with today and the 30-day total, a bar of its models, and a legend with the top two models and `Other`.
  - `Top models`: each tool's share of the period, then the five biggest models across tools.
- Model names are shortened: `claude-opus-5-5` reads `Opus 5.5`, `gpt-5.6-sol` reads `GPT-5.6 Sol`.
- Toggle clicks switch the view and leave the menu open. Refill remembers both choices. Saved styles from before (`dailyBars`, `heatStrip`, `sparkline`) open as `Bars`.
- The card keeps the same height whichever split is shown.

Colors follow the [theme](app-controls/02-theme.md):

- Single-color themes and Monochrome draw Codex, Claude Code and Cursor as a strong, a middle and a soft shade. Tool Colors uses Codex teal, Claude Code orange, Cursor indigo. A tool's models are fading shades of its color.
- So no part relies on color alone, every theme gives each tool a marker shape (circle, square, triangle), a line dash in `Lines` and `Top models` (solid, dashed, dotted), a 1 pt gap between stacked bars, and an edge between areas.

States:

- Off: no card.
- Reading: Codex's first scan. Claude Code and Cursor show at once, and only the Codex parts wait. See [Token Usage Loading Progress](token-usage-loading-progress.md).
- Updating: the previous chart stays while a background refresh runs.
- No data: `No token usage found yet`.
- Unavailable: `Token usage unavailable`. A single connected tool that can't be read shows `Unavailable` on its own row.

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
- A future period selector changes period while a scan is already running.
- The user disables Token Usage while a scan is already running.
- The user disables Token Usage after a successful scan, then re-enables it during the same app run.
- The user opens and closes the menu repeatedly while a scan is already running.
- A future selected period requires more days than the currently cached scan result covers.

## Acceptance Criteria

- Token Usage can be enabled and disabled from `Appearance`.
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

## Chart Style History

RGR-360 compared chart variants inside the active account card and shipped `Daily Bars`, `Heat Strip`, and `Sparkline` with RGR-362. [RGR-360-token-usage-chart-variants.md](../delivery/RGR-360-token-usage-chart-variants.md) keeps that review record. The multi-tool card replaced them with `Bars`, `Area`, and `Lines`, chosen from rendered prototypes in October 2026.

## Validation Targets

- Unit tests for token-count parsing from synthetic JSONL fixtures.
- Unit tests for repeated cumulative totals and delta aggregation.
- Unit tests for malformed or missing token-count rows.
- Unit tests for scan lifecycle: enable starts one scan, repeated menu opens do not duplicate it, chart-style changes do not scan, and covered period changes derive from cache.
- Unit tests or presentation tests for loading versus updating states.
- Presentation tests for card visibility, selected-period copy, empty state, and error state.
- Manual QA with Token Usage off, enabled with data, and enabled with no data.
- Manual QA confirming the scan continues after closing the menu, chart-style changes do not flash back to full loading, and disable/re-enable reuses cached data during the same app run.
- Privacy review confirming no prompts, auth values, account IDs, emails, local paths, hostnames, or raw rows are emitted.

## Out Of Scope / Deferrals

- Click-through detail panel.
- Inspecting an individual day.
- Secondary metrics such as average per day.
- Model breakdown beyond the top three models per tool.
- Saved-account attribution.
- Remote-host usage history.
- User-selectable periods.
- Cost estimation.
- Exporting usage data.
- Browser dashboard scraping.
- Hidden WebView/cookie import.
- Backend private endpoint integration for Codex.
- Cloud sync or telemetry upload.

## Open Questions

- Should cached aggregates live under `~/Library/Caches/Refill` or be recomputed on demand?
- What refresh cadence is enough without making menu opening feel slow?
- Should the app expose a manual `Refresh Token Usage` action, or rely on the existing refresh flow?

## Recommended Next Checkpoint

Use the Linear Token Usage issues created from this contract:

- RGR-360: Prototype Token Usage chart variants.
- RGR-361: Productionize local Token Usage aggregation.
- RGR-362: Implement opt-in Token Usage menu card.
