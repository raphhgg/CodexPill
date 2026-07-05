# Token Usage Incremental Cache

## User Story

As a CodexPill user with large local Codex history, I want Token Usage to become useful quickly and keep improving in the background, so the menu never sits on `Scanning local sessions...` for minutes before showing anything.

## Product Contract

Token Usage scanning must be cache-first and incremental. CodexPill should not require a full replay of all selected local session files before the menu can display usage data.

The first useful result should prioritize the currently selected visible period, currently `Last 30 Days` by default. Longer or heavier local history may continue scanning in the background, but the user should see either cached data, partial aggregate data, or explicit progress instead of an indefinite loading state.

The cache stores aggregate token buckets and file scan metadata only. It must not store raw session rows, prompts, auth payloads, account identifiers, emails, hostnames, or local file paths in user-visible surfaces, diagnostics, or tracker comments. If file identity is persisted, store only the minimum needed to detect whether a session file changed.

This task exists because real power-user Codex histories can be several GB, including individual session files larger than 1GB. Scanning everything synchronously before publishing the first card is not acceptable UX.

## Happy Path

1. User enables Token Usage.
2. CodexPill immediately checks the local Token Usage cache.
3. If cached aggregate data exists for the selected period, the menu shows it immediately.
4. If no cached aggregate data exists, CodexPill scans the selected period first.
5. The scan continues independently from the transient menu view.
6. Reopening the menu shows cached state when available, not a restarted scan.

## UI / Copy / States

Preferences:

- Keep `Last 30 Days` as the only visible v1 period.
- Defer `Last 7 Days` and `Last 90 Days` until the incremental cache proves fast enough for large histories and period changes feel instant.

Menu card states:

- Cached data available: show the chart immediately.
- First scan with no cache: show `Preparing token usage...` plus lightweight progress if available.
- Partial data: show the chart with available buckets and subtle copy such as `Updating...`.
- Background refresh: keep the previous chart visible and avoid replacing it with loading.
- No data after scan: `No token usage found yet`.
- Error: `Token usage unavailable`.

Progress should be deliberately low-key. This is a menubar app, not a migration wizard. Loading animation and copy are owned by [Token Usage Loading Progress](token-usage-loading-progress.md).

- `Scanning recent sessions...`
- `Updating token usage...`

## Cache Contract

Persist cache under `~/Library/Caches/CodexPill`, not Application Support, because the data is derived and can be rebuilt.

Cache contents:

- cache schema version;
- generated-at timestamp;
- covered day range;
- aggregate daily token buckets;
- per-file scan metadata needed for incremental refresh in the full implementation.

Per-file metadata should include:

- stable file identity if available;
- relative session date components or another privacy-safe scoped identity;
- file size;
- modification date;
- aggregate token contribution;
- scan status.

The current thin cache should be cache-first: if aggregate buckets exist for the
visible period, show them immediately and do not discard the whole cache just
because any Codex session file was modified after cache generation. Codex
session files are append-heavy, so a global newest-file freshness check turns
nearly every app rebuild or relaunch into a cold scan.

The full incremental cache must invalidate or partially refresh per-file
contributions when:

- cache schema version changes;
- a known file size or modification date changes;
- a new eligible session file appears;
- a previously failed file should be retried;
- the user manually refreshes.

Automatic and manual refreshes should update in place. When a cached entry
covers the selected window, unchanged per-file aggregate contributions should be
reused and progress should count only new or changed eligible files, not every
file in the selected period.
This reuse should also apply across local day rollover when the previous cache
overlaps the new selected window.

Disabling Token Usage hides the card and cancels active scan work, but should keep the persisted cache. Re-enabling should reuse cached aggregates immediately, then refresh in the background.

## Runtime Boundary

Token Usage scan lifecycle belongs behind a dedicated Token Usage runtime boundary, not in the global menu coordinator.

The runtime owns:

- active scan task identity;
- duplicate-scan prevention;
- progress throttling;
- cache-first load state;
- cancellation when Token Usage is disabled.

The menu coordinator owns only:

- user actions that mutate preferences;
- converting the current runtime state into a menu card;
- deciding whether a menu rebuild is safe while AppKit is tracking an open menu.

This keeps Token Usage as a local-history feature rather than making it an incidental concern of menu construction.

## Scanner Contract

The scanner should be split into two responsibilities:

- file discovery and prioritization;
- streaming parse of individual files into aggregate contributions.

The top-level scanner coordinates those two pieces. It should not know JSONL
line parsing details, and the file parser should not know how session files are
found or prioritized. This keeps future cache and progress work from turning
the scanner into the place where discovery, scheduling, parsing, and UI progress
all accrete together.

Prioritization:

- Scan files for the selected period first.
- Within the selected period, scan small/recent files first so useful data appears quickly.
- Scan huge files later and slowly.
- Do not skip huge files permanently, because they often represent heavy usage days.

Runtime behavior:

- Only one scan job may be active at a time.
- Opening the menu must not start duplicate scan jobs.
- Closing the menu must not cancel the scan unless Token Usage is disabled.
- Progress updates while the menu is closed should be coalesced and applied on
  the next menu open, not used to rebuild the hidden menu repeatedly.
- Changing chart style must not scan.
- Changing period may reprioritize the background queue, but should not clear already visible data.
- Scanner should publish aggregate progress after each file or day, not only at the end of the full scan.
- Selected-period progress should count eligible files in that period, not all
  historical session files.
- CPU and memory should remain bounded during cold scans.

## Edge Cases

- Local session history is several GB.
- A single session file is larger than 1GB.
- A huge file belongs to today or the selected period.
- The app quits mid-scan.
- The user disables Token Usage mid-scan.
- The user re-enables Token Usage after disabling it.
- A future period selector changes period while a scan is running.
- Session files are appended while the app is running.
- Session rows are malformed, truncated, or individually oversized.
- Cache exists but references files that no longer exist.
- Cache exists from an older schema version.

## Acceptance Criteria

- Enabling Token Usage does not require a full 90-day scan before showing the first useful card.
- With no cache, CodexPill prioritizes the selected period and can publish partial aggregate data before all eligible files are scanned.
- With cache, CodexPill shows cached aggregate data immediately.
- Reopening the menu does not restart or duplicate Token Usage scanning.
- Changing chart style does not trigger scanning.
- Changing period uses cached data when available and otherwise reprioritizes background scanning without blanking the existing chart.
- Automatic refresh reuses a cached all-time peak instead of replaying all
  historical session files.
- Refreshing `Last 30 Days` does not report or process every historical session
  as selected-period scan progress.
- Refreshing a cached selected period reparses only new or changed eligible
  session files and combines them with cached per-file aggregate contributions.
- Disabling Token Usage cancels active scan work but keeps the persisted cache.
- Re-enabling Token Usage reuses persisted cache when available.
- Large files are parsed slowly in the background, not skipped by default.
- Cold scanning stays within an agreed resource budget on a large-history fixture or local benchmark.
- Cache and diagnostics expose only aggregate metadata, never raw Codex session content.

## Validation Scenario Candidates

- `token-usage-parser-aggregation`
- `token-usage-cache-first`
- `token-usage-privacy-no-raw-session`

## Validation Intent

Feature risk: `state_truth`, `performance`, `privacy`

Primary proof for `token-usage-cache-first`: `contract-fixture`

Product scenarios:

- `token-usage-cache-first` proves that cached aggregate data is presented
  before scanner work when it covers the requested period, repeated runtime
  refreshes do not duplicate load jobs, visible chart data is preserved during
  refresh progress, and forced refresh reparses only new or changed eligible
  selected-period files.

Required evidence:

- focused test output from `LocalCodexSessionTokenUsageMenuProviderTests`,
  `TokenUsageMenuRuntimeTests`, and `TokenUsageCacheBackedRefreshPolicyTests`;
- `build/verification/token-usage-cache-first/scenario-summary.json`.

Non-claims:

- Does not prove Token Usage UI rendering.
- Does not prove diagnostics export privacy.
- Does not prove saved-account, workspace, organization, or remote-host usage
  history.
- Does not prove real local Codex history scanning.
- Does not prove live macOS menu-bar behavior.

Live opt-in: not required for this scenario.

## Proof Contract

| Acceptance Criterion | Owning Proof Layer | Command / Method | Artifact | Pass Condition | Privacy / Redaction |
| --- | --- | --- | --- | --- | --- |
| With cache, CodexPill shows cached aggregate data immediately and does not restart scanning on repeated menu opens. | `contract-fixture` | `make verify-token-usage-cache-scenario` running `LocalCodexSessionTokenUsageMenuProviderTests`, `TokenUsageMenuRuntimeTests`, and `TokenUsageCacheBackedRefreshPolicyTests`. | `build/results/local/CodexPill.xcresult` and `build/verification/token-usage-cache-first/scenario-summary.json`. | Cached data is presented before scanner work when it covers the requested period, repeated runtime refreshes keep one active load, chart-style/runtime refreshes do not blank loaded data, and visible chart data stays available during progress updates. This contract-fixture scenario does not prove Token Usage UI rendering or live menu interaction. | Synthetic aggregate and session-file fixtures only; no raw session rows, prompts, local paths, account identifiers, emails, hostnames, auth material, or token-like secrets. |
| Refreshing a cached selected period reparses only new or changed eligible files. | `contract-fixture` | `make verify-token-usage-cache-scenario` running cache/provider fixture tests. | `build/results/local/CodexPill.xcresult` and `build/verification/token-usage-cache-first/scenario-summary.json`. | Unchanged file contributions are reused, changed/new files are rescanned, selected-period totals match expected aggregate buckets, and progress counts only eligible files that need scanner work. | Fixtures use synthetic paths and rows only; no real absolute paths, raw session rows, prompts, account identifiers, emails, hostnames, auth material, or token-like secrets. |
| Scanner parses malformed, repeated, oversized, and large rows within bounded resources. | `contract-fixture` | Synthetic JSONL scanner tests, including malformed rows and large-file fixtures. | Parser result bundle plus resource benchmark or bounded-memory assertion. | Malformed or oversized rows are skipped safely, repeated cumulative totals do not overcount, and large eligible files are processed without loading the whole file into memory. | Synthetic JSONL only; no real prompts, session rows, account identifiers, emails, hostnames, auth payloads, or tokens. |
| Cache and diagnostics expose aggregate metadata only. | `diagnostics-export` plus `privacy-leak-proof` | `make verify-token-usage-privacy-scenario` running `DiagnosticReportBuilderTests`. | `build/results/local/CodexPill.xcresult`, `build/verification/token-usage-privacy-no-raw-session/diagnostics-export.json`, `privacy-leak-report.json`, and `scenario-summary.json`. | Exported diagnostics contain only Token Usage aggregate state/totals and fail if raw Codex session content, paths, account identifiers, emails, hostnames, auth material, or token-like values appear. | Real local data may be inspected only as manual degraded proof; committed artifacts must be synthetic or redacted. |

## Validation Targets

- Unit tests for cache read/write, schema invalidation, and corrupted cache recovery.
- Unit tests for file metadata change detection.
- Unit tests proving unchanged files reuse cached aggregate contributions.
- Unit tests proving changed/new files are rescanned.
- Unit tests proving repeated menu opens do not start duplicate scan jobs.
- Unit tests proving future period changes do not clear visible cached data.
- Scanner tests with synthetic large files that verify bounded memory behavior.
- Manual QA on a large local history confirming the menu does not sit indefinitely on `Scanning local sessions...`.
- Manual QA confirming CPU/RAM stay acceptable during cold scan.
- Privacy review confirming cache contents do not include raw session rows, prompts, auth, emails, hostnames, or file paths in exported diagnostics.

## Out Of Scope / Deferrals

- Cloud sync.
- Backend `/api/codex/usage`.
- Cost estimation.
- Model breakdown.
- Saved-account attribution.
- Remote-host token usage.
- Full historical `All Time` view.
- `Last 90 Days` in the public UI until cache behavior is proven.
- Rich progress UI beyond a small menu-card hint.

## Open Questions

- What exact CPU/RAM budget should be considered acceptable during cold scan?
- Should the cache store raw absolute file paths, hashed paths, or relative date/session identifiers? Recommendation: avoid absolute paths unless needed.
- Should manual refresh clear cache first, or update in place? Recommendation: update in place and keep previous chart visible.
- Should `Last 90 Days` remain hidden entirely or become an advanced/debug-only option after the cache lands?

## Recommended Next Checkpoint

Create one implementation issue from this contract:

- `Implement persistent incremental Token Usage cache`

This should replace the current full-scan-before-display behavior. It should land before treating Token Usage as release-ready for power users.
