# Status Bar

The status bar feature owns CodexPill's closed-state menubar presentation: icon, label, hover behavior, and compact usage indicators.

## Purpose

The status bar gives the user a lightweight answer before opening the menu: which account is active and whether its limits look healthy.

## Owned Surface

- App icon or monochrome menubar icon.
- Optional label text.
- Hover-expanded and shortcut-revealed text behavior.
- Compact session/weekly indicators.
- The `Preferences` submenu exposes `Menu Bar Label`, `Icon Style`, and `Usage Bars` controls for label mode, the reveal shortcut, icon style, usage percent mode, meter layout, pacing marker visibility, and usage colors. App-level controls in the same submenu are owned by their own feature docs.
- Tooltip text.

## Menu Bar Label Reveal Shortcut

CodexPill ships with the global shortcut `⌃⌥⌘L` while the app is running.
Pressing it temporarily reveals the same status item label that appears on hover
for about three seconds without opening the menu and without changing the saved
`Menu Bar Label` display mode. Pressing the shortcut again while the label is
visible collapses it.

Users can configure the shortcut from:

```text
Preferences
  Menu Bar Label
    Reveal Shortcut…    ⌃⌥⌘L
```

If a configured shortcut cannot be registered, CodexPill keeps the previous
working shortcut and shows an error.

## Usage Bars Preferences

```text
Preferences
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

- `Show % Left` changes every usage percentage CodexPill shows (status item
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

## Relationship To Accounts

The status bar consumes account availability data, but account identity, switching, and refresh behavior remain owned by [Accounts](accounts/00-accounts.md).

## Relationship To Menubar

The status bar opens the menubar popup, whose composition is owned by [Menubar](menubar.md).
