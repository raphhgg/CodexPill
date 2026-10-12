# Token Usage Loading Progress

## User Story

As a Refill user with a large local Codex history, I want the Token Usage card to show real progress during the first scan, and to show my other tools right away, so I never think the app is stuck.

## Product Contract

Only Codex has a long first scan: a first run, or a cache upgrade, reads every session of the last 30 days. After that, only new or changed sessions are read, which takes seconds. Claude Code and Cursor are read before Codex and show at once.

Progress must be honest. Codex reads sessions newest day first and reports every finished day, so the card draws a day as soon as it's final. The percentage is sessions read out of sessions to read. No fake percentages.

The loading state never exposes session rows, prompts, file paths, account identifiers, emails, hostnames, or auth material.

## While Codex Reads

- Subtitle: `Last 30 days · Reading Codex sessions · 41%`.
- `Bars`: finished Codex days draw their real segment. Unread days show a low Codex stub, and the next one to finish pulses.
- `Area`: finished days draw the Codex layer. A shimmer runs along the baseline over the unread days.
- `Lines`: the Codex line grows leftwards from today, with a pulsing dot at its tip.
- `By tool`: the Codex row shows `Reading sessions · 41%`, a moving shimmer bar, and `Models appear when reading finishes`.
- `Top models`: models from ready tools rank first, followed by a `Codex models` row with the percentage. Tool shares show token totals until Codex finishes, because the total still grows.
- Hover shows `Codex …` for unread days.
- Reduce Motion: nothing moves; stubs stay still and the percentage still updates.
- The open card updates in place as days finish. The menu is not rebuilt while it's open.

## Happy Path

1. User turns on Token Usage, or updates to a build with a new cache version.
2. The card shows Claude Code and Cursor right away, and Codex at 0%.
3. Codex days fill in from today backwards, and the percentage climbs.
4. User closes and reopens the menu. The scan keeps running and the card shows its current progress.
5. When the scan finishes, Codex's models and the tool shares appear.

## Edge Cases

- No Claude Code or Cursor connected: only the Codex parts show, still filling in.
- Codex reads no sessions in the period: the card shows `No token usage found yet`.
- A refresh with a cached result: the cached chart stays, with no reading state.
- The user switches chart or split during the scan: the new view shows the same progress.

## Validation Targets

- Unit tests: the scan reports finished days newest first; the combined loader passes ready tools with every Codex progress update; a reading card marks Codex days pending, keeps Codex out of the top models, and holds shares.
- Coordinator test: the open card's model updates in place when data arrives.
- Visual check: every chart and split in reading state, in color and monochrome.
