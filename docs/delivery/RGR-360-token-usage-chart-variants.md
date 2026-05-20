# RGR-360 Token Usage Chart Variants

This prototype uses synthetic fixture buckets only. It does not read local Codex session logs, auth files, account identifiers, prompts, local paths, remote hosts, backend APIs, persistence, or production scanner output.

All variants use the same 30-day fixture data, the same `Token Usage` / `This Mac` header, `Today: 22,400 tokens`, and `Last 30 days: 680,200 tokens`. They are rendered at the same menu width inside the active account area, directly below the Session and Weekly rows and above the account/action sections.

## Variants

- Minimal Bars: highest daily readability and easiest day-to-day comparison. Trade-off: most visually chart-like and a little heavier inside a compact menu.
- Sparkline: best for trend and rhythm scanning. Trade-off: weaker exact daily comparison than bars.
- Heat Strip: most compact and calendar-inspired. Trade-off: token magnitude is approximate and depends more on color perception.
- Native Compact: most menu-native and summary-forward. Trade-off: hides more day-by-day shape in favor of immediate totals.

## Recommendation

Use Minimal Bars if the final feature prioritizes daily clarity. Use Native Compact if the menu needs to stay quiet and account switching remains the dominant task. I would not pick Heat Strip as the default unless the human reviewer strongly values density over precision.
