# Status Bar

The status bar feature owns CodexPill's closed-state menubar presentation: icon, label, hover behavior, and compact usage indicators.

## Purpose

The status bar gives the user a lightweight answer before opening the menu: which account is active and whether its limits look healthy.

## Owned Surface

- App icon or monochrome menubar icon.
- Optional label text.
- Hover-expanded text behavior.
- Compact session/weekly indicators.
- The `Preferences` submenu controls for icon style, label mode, pacing marker visibility, and accent color.
- Tooltip text.

## Relationship To Accounts

The status bar consumes account availability data, but account identity, switching, and refresh behavior remain owned by [Accounts](accounts/00-accounts.md).

## Relationship To Menubar

The status bar opens the menubar popup, whose composition is owned by [Menubar](menubar.md).
