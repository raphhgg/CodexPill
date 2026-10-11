# Status Bar

The status bar feature owns CodexPill's closed-state menubar presentation: icon, label, hover behavior, and compact usage indicators.

## Purpose

The status bar gives the user a lightweight answer before opening the menu: which account is active and whether its limits look healthy.

## Owned Surface

- The live menubar glyph.
- Optional label text.
- Hover-expanded and shortcut-revealed text behavior.
- Compact session/weekly indicators.
- The `Preferences` submenu exposes `Menu Bar Label` and `Icon Style` controls for label mode, the reveal shortcut, and glyph style. Its `Usage Bars` controls (pace markers and accent color) style the usage bars inside the menu, not the glyph. App-level controls in the same submenu are owned by their own feature docs.
- Tooltip text.

## Menu Bar Glyph

The glyph shows the active account's two limits at a glance. Each style shows
what is left, not what is used, so a fuller glyph means more room.

| Style | Session limit | Weekly limit | No data |
| --- | --- | --- | --- |
| Hourglass (default) | Sand in the top bulb falls as you use it, and the used share fills the bottom bulb. | A base bar under the glass, filled left to right. | Empty glass and a faint base. |
| Moon | The lit phase of a moon, lit from the right: full at 100%, a thin crescent near 0. | An orbit ring, filled clockwise from 12 o'clock. | A faint moon outline and a faint ring. |
| Punch card | Top row of five slots. | Bottom row of five slots. | All slots hollow and faint. |

Punch card rounds up, so any amount left shows at least one solid slot. A
limit with no data uses its own no-data look while the other limit still shows
its level.

The glyph is a template image: black and clear, with partial transparency for
tracks and used parts. macOS recolors it for light and dark menu bars, so the
`Usage Bars` accent color does not apply to it. The glyph has no pace marker.
Pace markers stay in the menu's usage bars, where there is room to read them.

Saved styles from earlier builds map to the closest new style: `Dual Arc Badge`
to Moon, `Stacked Bars` to Punch card, `Twin Pills` to Hourglass, and any
unknown value to Hourglass.

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

## Relationship To Accounts

The status bar consumes account availability data, but account identity, switching, and refresh behavior remain owned by [Accounts](accounts/00-accounts.md).

## Relationship To Menubar

The status bar opens the menubar popup, whose composition is owned by [Menubar](menubar.md).
