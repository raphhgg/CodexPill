# Theme

## User Story

As a rusage user, I want to pick one look for rusage, so the usage bars and the Token Usage chart match.

## Product Contract

`Appearance › Theme` sets two things together:

- **Usage bars** on every tool card. Session uses the theme's strong shade, and Weekly a softer one. Under Tool Colors each card uses its own tool's color: Codex teal, Claude Code orange, Cursor indigo. Custom colors from `Usage Bars` still override the theme.
- **Token Usage.** Codex, Claude Code and Cursor are a strong, a middle and a soft shade of the theme, or their own colors under Tool Colors. Every theme also gives each tool a marker shape, a line dash and gaps between stacked parts, so color is never the only cue. See [Token Usage](../token-usage.md).

The app icon and the menu bar icon stay the same in every theme.

Themes: Cobalt (default), Deep Teal, Emerald, Violet, Honey, Rose, Monochrome, Tool Colors. The six colored themes are named after their hue.

## App Icon

rusage's icon is one glass lens in a porcelain ring, half full of cobalt: the pair to rbar's rail of three lenses. It is an Icon Composer document (`Resources/AppIcon.icon`). Xcode compiles it into the asset catalog for macOS 26 and later, with every Default, Dark, Clear and Tinted appearance, and generates an `AppIcon.icns` fallback for macOS 14 and 15. Finder, About, alerts and Login Items all show it.

## UI / Copy / States

```text
Appearance
    Show Tools
    Menu Bar Label
    Icon Style
    Usage Bars
    Theme
      ✓ Cobalt
        Deep Teal
        Emerald
        Violet
        Honey
        Rose
        ----------------
        Monochrome
        Tool Colors
    ----------------
    Show Token Usage
```

The current theme has a checkmark.

## Edge Cases

- A missing or unknown stored value falls back to Cobalt.

## Rejected Alternatives

- A theme-coloured app icon. macOS can't change an app's own Finder icon, so it only reached About and alerts, and Finder disagreed with them. rusage keeps one icon.

## Acceptance Criteria

- The built app shows the rusage icon in Finder and in the About alert, whatever the theme.
- `Appearance › Theme` lists the eight themes in order, with Cobalt checked by
  default.
- Choosing a theme changes the usage bars and the Token Usage card at once.
- The choice survives a relaunch.

## Validation Targets

- Settings store tests for the default, persistence, and unknown stored values.
- Menu builder tests for the submenu order and checked state.
- Coordinator tests proving a selection persists.
- Manual QA on a built app for Finder, About, and an alert with each colour.
