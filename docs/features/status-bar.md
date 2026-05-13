# Status Bar

The status bar feature owns CodexPill's closed-state menubar presentation: icon, label, hover behavior, and compact usage indicators.

## Purpose

The status bar gives the user a lightweight answer before opening the menu: which account is active and whether its limits look healthy.

## Owned Surface

- App icon or monochrome menubar icon.
- Optional label text.
- Hover-expanded and shortcut-revealed text behavior.
- Compact session/weekly indicators.
- The `Preferences` submenu exposes `Menu Bar Label`, `Icon Style`, and `Usage Bars` controls for label mode, the reveal shortcut, icon style, pacing marker visibility, and accent color. App-level controls in the same submenu are owned by their own feature docs.
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

## Relationship To Accounts

The status bar consumes account availability data, but account identity, switching, and refresh behavior remain owned by [Accounts](accounts/00-accounts.md).

## Relationship To Menubar

The status bar opens the menubar popup, whose composition is owned by [Menubar](menubar.md).
