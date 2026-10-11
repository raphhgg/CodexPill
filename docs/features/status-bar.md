# Status Bar

The status bar feature owns Refill's closed-state menubar presentation: icon, label, hover behavior, and compact usage indicators.

## Purpose

The status bar gives the user a lightweight answer before opening the menu: how the first tool in the menu stands against its limits.

## Owned Surface

- App icon or monochrome menubar icon.
- Optional label text.
- Hover-expanded and shortcut-revealed text behavior.
- Compact indicators for the first menu card's windows (see below).
- `Settings › Appearance` exposes `Menu Bar Label`, `Icon Style`, and `Usage Bars` controls for label mode, the reveal shortcut, icon style, usage percent mode, meter layout, pacing marker visibility, and usage colors. Other Settings items are owned by their own feature docs. Claude's per-model weekly limits (`Show Model Limits`) never reach the icon or its label.
- Tooltip text.

## Menu Bar Label Reveal Shortcut

Refill ships with the global shortcut `⌃⌥⌘L` while the app is running.
Pressing it temporarily reveals the same status item label that appears on hover
for about three seconds without opening the menu and without changing the saved
`Menu Bar Label` display mode. Pressing the shortcut again while the label is
visible collapses it.

Users can configure the shortcut from:

```text
Settings › Appearance
  Menu Bar Label
    Reveal Shortcut…    ⌃⌥⌘L
```

If a configured shortcut cannot be registered, Refill keeps the previous
working shortcut and shows an error.

## Usage Bars

```text
Settings › Appearance
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
  available. The status item bars invert with it: a full bar means the window
  is untouched, an empty bar means it is used up. Pace markers move to the
  matching position. Countdowns for full windows are unchanged.
- `Session Color…` and `Weekly Color…` color the session and weekly bars in the
  menu and in the colored (non-monochrome) status item icon. With `Same Color
  for Both` on, the session color is used for both. Picking a weekly color turns
  `Same Color for Both` off.
- An accent color chosen before this option existed becomes the session color,
  and with `Same Color for Both` on by default it keeps coloring both bars.
- `Use Default Colors` clears both colors and turns `Same Color for Both` back on.

## What The Icon Shows

The icon follows the first card in the menu, so the user picks it by moving that card to the top.

- Two windows fill both meters, session first. One window, such as Codex Pro's weekly limit, Codex Free's monthly limit, or Cursor's billing cycle, fills the lower meter.
- A window the tool does not report draws as an outline-only track, never as 0%. A card with no reading draws both tracks as outlines.
- With no card at all, the icon is Refill's pill.
- A stale reading is not dimmed.
- The label reads `S 11% W 60%`, `W 17%` for one weekly window, `M 3%` for one monthly window, `8d 9%` for a window with no name, or `82%` for a billing cycle alone. A full window shows its countdown instead.
- The tooltip names the tool and plan, the account in use (masked with Hide Emails), and the reset of any full window.

## Relationship To Accounts

The status bar consumes account availability data, but account identity, switching, and refresh behavior remain owned by [Accounts](accounts/00-accounts.md).

## Relationship To Menubar

The status bar opens the menubar popup, whose composition is owned by [Menubar](menubar.md).
