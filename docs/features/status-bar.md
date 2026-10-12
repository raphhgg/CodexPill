# Status Bar

The status bar feature owns Refill's closed-state menubar presentation: icon, label, hover behavior, and compact usage indicators.

## Purpose

The status bar gives the user a lightweight answer before opening the menu: how the first tool in the menu stands against its limits.

## Owned Surface

- The live menubar glyph.
- Optional label text.
- Hover-expanded and shortcut-revealed text behavior.
- Compact indicators for the first menu card's windows (see below).
- `Appearance` exposes `Menu Bar Label`, `Icon Style`, and `Usage Bars` controls for label mode, the reveal shortcut, icon style, usage percent mode, meter layout, pacing marker visibility, and usage colors. Other app items are owned by their own feature docs. Its `Usage Bars` controls style the usage bars inside the menu, not the glyph. Claude's per-model weekly limits (`Show Fable Limits` in the Claude side menu) never reach the icon or its label.
- Tooltip text.

## Menu Bar Glyph

The glyph shows the active account's two limits at a glance. It fills the
same percent the menu card shows: with `Show % Used` (the default) a card that
reads 32% used fills 32% of the glyph, and with `Show % Left` a card that reads
68% left fills 68%. More ink always means a bigger number on the card.

| Style | Session limit | Weekly limit | No data |
| --- | --- | --- | --- |
| Glasses (default) | The left glass's liquid by area: 32% fills 32% of the glass. | The right glass, the same way. | Two faint empty glasses. |
| Moon | The lit share of a moon, lit from the right, by area: 32% lights 32% of the disc. | An orbit ring, filled clockwise from 12 o'clock. | A faint moon outline and a faint ring. |
| Punch card | Top row of five slots. | Bottom row of five slots. | All slots hollow and faint. |

Punch card fills the nearest slot count, rounding half up (32% fills 2 of 5,
28% fills 1). Any amount above 0% fills at least one slot, and only 100% fills
the whole row.

Some accounts report only one limit. The glyph then shows that limit in its
main element (one wide glass, the moon phase, or a single centred row of slots)
and drops the secondary element (the right glass, the orbit ring, or the second
row).
It never draws a second mark for a limit the account does not have. The menu
names which limit it is.

The glyph is a template image: black and clear, with partial transparency for
tracks and used parts. macOS recolors it for light and dark menu bars, so the
`Usage Bars` accent color does not apply to it. The glyph has no pace marker.
Pace markers stay in the menu's usage bars, where there is room to read them.

Saved styles from earlier builds map to the closest new style: `Dual Arc Badge`
to Moon, `Stacked Bars` to Punch card, and `Hourglass`, `Twin Pills` and any
unknown value to Glasses.

## Menu Bar Label Reveal Shortcut

Refill ships with the global shortcut `⌃⌥⌘L` while the app is running.
Pressing it temporarily reveals the same status item label that appears on hover
for about three seconds without opening the menu and without changing the saved
`Menu Bar Label` display mode. Pressing the shortcut again while the label is
visible collapses it.

Users can configure the shortcut from:

```text
Appearance
  Menu Bar Label
    Reveal Shortcut…    ⌃⌥⌘L
```

If a configured shortcut cannot be registered, Refill keeps the previous
working shortcut and shows an error.

## Usage Bars

```text
Appearance
  Usage Bars
    Show % Used           (default)
    Show % Left
    ─────
    Classic Layout        (default)
    Compact Layout
    ─────
    Show Pace Markers
    ─────
    Session Color…
    Weekly Color…
    Same Color for Both   (default on)
    Use Default Colors
```

- `Show % Left` changes every usage percentage Refill shows (status item
  label, active account meters, saved account rows) to the share still
  available. The glyph follows the same choice. Pace markers move to the
  matching position. Countdowns for full windows are unchanged.
- `Session Color…` and `Weekly Color…` color the session and weekly bars in the
  menu. With `Same Color
  for Both` on, the session color is used for both. Picking a weekly color turns
  `Same Color for Both` off.
- An accent color chosen before this option existed becomes the session color,
  and with `Same Color for Both` on by default it keeps coloring both bars.
- `Use Default Colors` clears both colors and turns `Same Color for Both` back on.

## What The Icon Shows

The icon follows the first card in the menu, so the user picks it by moving that card to the top.

- Two windows fill the glyph's session and weekly parts, the shorter window first. One window, such as Codex Pro's weekly limit, Codex Free's monthly limit, or Cursor's billing cycle, shows in the glyph's main element.
- A window the tool does not report uses its own no-data look, never 0%. A card with no reading shows the no-data glyph.
- With no card at all, the icon is the chosen style's no-data glyph, so a style change shows at once.
- A stale reading is not dimmed.
- The label reads `S 11% W 60%`, `W 17%` for one weekly window, `M 3%` for one monthly window, `8d 9%` for a window with no name, or `82%` for a billing cycle alone. A full window shows its countdown instead.
- The tooltip names the tool and plan, the account in use (masked with Hide Emails), and the reset of any full window.

## Relationship To Accounts

The status bar consumes account availability data, but account identity, switching, and refresh behavior remain owned by [Accounts](accounts/00-accounts.md).

## Relationship To Menubar

The status bar opens the menubar popup, whose composition is owned by [Menubar](menubar.md).
