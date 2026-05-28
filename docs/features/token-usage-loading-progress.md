# Token Usage Loading Progress

## User Story

As a CodexPill user with a large local Codex history, I want the Token Usage card to clearly show that scanning is progressing, so I do not think the app is stuck while the first local scan is still running.

## Product Contract

Token Usage first-load progress is a menu-card feedback feature. It does not make scanning faster by itself, and it must not pretend to know precise progress unless the scanner exposes real progress metadata.

When Token Usage has no cached aggregate data yet, CodexPill should replace the static `Scanning local sessions...` state with an animated, low-key loading card that feels alive and matches the selected chart style.

The loading state must be honest:

- animated placeholders are allowed;
- animated ellipsis is allowed;
- real file-count or byte progress is allowed only if the scanner exposes it;
- fake percentages are not allowed.

The loading card must not expose raw session rows, prompts, file paths, account identifiers, emails, hostnames, or auth material.

This feature is complementary to the incremental cache work. It improves perceived responsiveness during the first cold scan, but it does not replace the need for progressive partial results.

## Happy Path

1. User enables Token Usage.
2. No cache exists for the selected period.
3. The menu shows the Token Usage card in the normal card position.
4. The card shows an animated placeholder for the selected chart style.
5. The card shows concise progress copy such as `Scanning local sessions...`.
6. Once file discovery completes, the copy switches to real file-count progress such as `Scanning 42 of 310 sessions...`.
7. User closes the menu.
8. The scan continues in the background.
9. User reopens the menu while the scan is still running.
10. The card still shows an active loading/progress state, not a frozen static message.
11. Once aggregate data is available, the loading card is replaced by the real chart.

## UI / Copy / States

First cold scan with no cache:

- Title: `Token Usage`
- Subtitle: `Last 30 days`.
- Chart area: animated placeholder matching the selected chart style.
- Bottom copy: `Scanning local sessions...`

Recommended placeholder animations:

- Daily Bars: skeleton bars that gently pulse or sweep from left to right.
- Heat Strip: cells that softly brighten in sequence.
- Sparkline: a subtle animated line shimmer or moving highlight.

Animated ellipsis:

- Use `Scanning local sessions.`
- Then `Scanning local sessions..`
- Then `Scanning local sessions...`
- Loop while loading.

Real progress copy, after file discovery completes:

- `Scanning 12 of 84 sessions...`

The count is file-level progress only. It must not include file names, absolute paths, prompts, account identifiers, hostnames, or raw event content.

Do not show:

- fake percentages;
- exact local file paths;
- account names or hostnames;
- raw token events;
- scary implementation language such as `Parsing JSONL...`.

Background refresh with cached chart:

- Keep the existing chart visible.
- Use subtle copy such as `Updating...` only if needed.
- Do not replace an existing chart with a full loading skeleton.

No data after scan:

- `No token usage found yet`

Unavailable:

- `Token usage unavailable`

## Edge Cases

- The first scan takes several minutes because local history is several GB.
- The menu is closed while scanning.
- The menu is reopened repeatedly while scanning.
- The user changes chart style while scanning.
- The user changes period while scanning.
- The user disables Token Usage while scanning.
- A cached chart exists but a refresh is running.
- File discovery has not completed yet, so only generic loading copy is available.
- Reduced motion is enabled in macOS.

## Acceptance Criteria

- The no-cache loading state uses an animated placeholder instead of static text only.
- The loading copy visibly changes over time, at minimum through animated ellipsis.
- The animation respects the selected chart style where practical.
- The loading state does not imply a fake percentage or fake completion estimate.
- When scanner file-count progress is available, the loading copy shows `Scanning X of Y sessions...`.
- Closing and reopening the menu while scanning still shows an active loading state.
- Existing cached charts remain visible during refresh instead of being replaced by loading.
- Reduced-motion users get a non-distracting loading state without aggressive motion.
- No raw session content, file paths, account identifiers, emails, hostnames, or auth data are shown.

## Validation Targets

- Presentation tests for loading-state copy.
- Presentation tests or snapshot-style assertions proving each chart style can render a loading placeholder.
- Unit test or coordinator test proving repeated menu opens keep one active scan and keep the loading state alive.
- Manual QA on a large local history confirming the menu no longer feels frozen during first scan.
- Manual QA with Reduce Motion enabled.

## Out Of Scope / Deferrals

- Real percentage progress.
- Full incremental per-file cache.
- Partial chart publishing after each file/day.
- Scanner queue prioritization.
- Background refresh scheduling.
- Token Usage detail view.
- Remote-host token usage.

## Open Questions

- Should the loading subtitle always show the selected period, or should it switch to `Preparing token usage...` during first scan?
- Is animated ellipsis enough for v1, or should we require chart-style-specific skeleton animation in the first implementation?
- Should the card expose real file-count progress once the scanner has a stable progress model?

## Recommended Next Checkpoint

Create a small implementation issue:

- `Add animated Token Usage loading progress`

This can be implemented before the full incremental cache. It should not block the progressive-cache work, but it will make the current first-load behavior feel less broken while large histories are still being scanned.
