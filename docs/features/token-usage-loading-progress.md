# Token Usage Loading Progress

## User Story

As a Refill user with a large local Codex history, I want the Token Usage card to show one clear loading signal during a long scan, and no half-read numbers, so I never think the app is stuck or that I used nothing last month.

## Product Contract

Only Codex has a long scan: a first run, a new day after the cache, or a cache upgrade, reads the sessions of the last 30 days again. After that, only new or changed sessions are read, which takes seconds.

Progress must be honest. The percentage is sessions read out of sessions to read. No fake percentages, and no partial chart: days that are not read yet never draw as zero.

The loading state never exposes session rows, prompts, file paths, account identifiers, emails, hostnames, or auth material.

## While Loading

- Subtitle: `Last 30 days · Loading 8%`. It is the only loading signal.
- Chart: the last finished reading from the cache, dimmed, even from an older cache version that the scan rebuilds. With no cache, neutral placeholder bars.
- No hover numbers on the chart.
- The `By tool` / `Top models` switch and the selected split show as neutral placeholder blocks, in the shape of the finished rows.
- The card keeps the height it has once loaded, so nothing moves when the scan finishes.
- The open card updates in place. The menu is not rebuilt while it's open.

## Happy Path

1. User turns on Token Usage, or opens Refill on a new day.
2. The card shows the last finished chart dimmed, or placeholder bars on a first run, and `Loading 0%`. The percentage starts at once, while Claude Code and Cursor are read alongside.
3. The percentage climbs.
4. User closes and reopens the menu. The scan keeps running and the card shows its current progress.
5. When the scan finishes, the chart, the switch, the tool rows and the models appear in place.

## Edge Cases

- Codex reads no sessions in the period: the card shows `No token usage found yet`.
- A refresh with a loaded result: the chart stays, with no loading state.
- The user switches chart style during the scan: the new style draws the same cached chart, dimmed.

## Validation Targets

- Unit tests: the card in first run, cached, loading and finished states; the runtime shows the cached reading while it loads; the combined loader's preview lists Codex's cached days and the connected tools.
- Coordinator test: the open card's model updates in place when data arrives.
- Visual check: first run, cached and finished, in an isolated build with a small `<root>/sessions` fixture.
