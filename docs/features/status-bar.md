# Status Bar

The status bar feature owns CodexPill's closed-state menubar presentation: icon, label, hover behavior, and compact usage indicators.

## Purpose

The status bar gives the user a lightweight answer before opening the menu: which account is active and whether its limits look healthy.

## Owned Surface

- App icon or monochrome menubar icon.
- Optional label text.
- Hover-expanded and shortcut-revealed text behavior.
- Compact session/weekly indicators.
- The `Preferences` submenu exposes `Menu Bar Label`, `Icon Style`, `Usage Bars`, and `Other Accounts Display` controls for label mode, the reveal shortcut, icon style, usage bar percent mode, usage bar layout, saved-account row presentation, pacing marker visibility, and accent color. App-level controls in the same submenu are owned by their own feature docs.
- Tooltip text.

## Usage Bars

Users can choose whether usage bars display consumed usage or remaining usage,
and whether the active account card uses the classic three-line rows or compact
single-line rows:

```text
Preferences
  Usage Bars
    Show % Used
    Show % Left
    Classic
    Compact
    Accent Color Session…
    Accent Color Weekly…
```

`Show % Used` is the default. `Show % Left` inverts the visible percent and bar fill while leaving the underlying Codex rate-limit data unchanged.
`Classic` is the default layout. `Compact` presents each session and weekly
limit as one row: title, bar, percent text, and reset text.
Session usage uses a green default accent. Weekly usage uses the macOS accent
color default.

## Other Accounts Display

Users can choose how saved inactive account rows appear:

```text
Preferences
  Other Accounts Display
    Show as Text
    Show as Bars
```

`Show as Text` is the default and keeps the compact account name plus session
and weekly text summary. `Show as Bars` shows the account name above session and
weekly usage bars while keeping the same account submenu actions.

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
