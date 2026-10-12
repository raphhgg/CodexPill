# Theme

## User Story

As a Refill user, I want to pick one look for Refill, so the app icon, the usage bars and the Token Usage chart match.

## Product Contract

`Appearance › Theme` sets three things together:

- **App icon.** The capsule icon in the theme's color. Monochrome uses the Graphite icon. Tool Colors has no icon of its own and keeps the icon of the last theme picked.
- **Usage bars** on every tool card. Session uses the theme's strong shade, and Weekly a softer one. Under Tool Colors each card uses its own tool's color: Codex teal, Claude Code orange, Cursor indigo. Custom colors from `Usage Bars` still override the theme.
- **Token Usage.** Codex, Claude Code and Cursor are a strong, a middle and a soft shade of the theme, or their own colors under Tool Colors. Every theme also gives each tool a marker shape, a line dash and gaps between stacked parts, so color is never the only cue. See [Token Usage](../token-usage.md).

The menu bar icon stays black and white in every theme.

Themes: Cobalt (default), Deep Teal, Emerald, Violet, Honey, Rose, Monochrome, Tool Colors. The six colored themes use each icon's liquid hue.

The icon is a porcelain-and-glass capsule built as an Icon Composer document (`Resources/AppIcon.icon`). Its colour is Cobalt. Xcode compiles it into the asset catalog for macOS 26 and later, and generates an `AppIcon.icns` fallback for macOS 14 and 15.

macOS has no API that lets an app change its own Finder icon. Refill sets its in-app icon (`NSApplication.applicationIconImage`) instead. The choice changes:

- The `About Refill` alert.
- Every Refill alert and confirmation.
- The title-bar icon of Refill panels, such as shortcut capture.

The choice does not change Finder, Spotlight, Launchpad, or the Login Items list in System Settings. These always show Cobalt.

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

- Before themes, Refill saved only an icon color. The first theme is the one with that icon, so nobody's icon changes.
- A missing or unknown stored value falls back to Cobalt.
- Cobalt clears the in-app override, so alerts use the bundle icon.

## Rejected Alternatives

- `NSWorkspace.setIcon(_:forFile:)` on the app bundle changes Finder and
  Spotlight, but it writes a Finder custom icon into the signed bundle.
  `codesign --verify --strict` then fails with `Disallowed xattr
  com.apple.FinderInfo`. A Homebrew upgrade replaces the bundle and drops the
  custom icon. It also replaces the Liquid Glass icon with a flat image that
  ignores the Dark, Clear and Tinted icon styles.
- Alternate app icon sets (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`)
  compile on macOS, but AppKit has no API to select or load them.

## Maintenance

The six alternate icons (five colors and Graphite) live as Icon Composer documents in
`Design/AppIconColors/`. Run `scripts/render_app_icon_colors.sh` after editing
any `.icon` file. It renders the PNGs the app loads at runtime into
`Resources/AppIconColors/`, and the README icon into `docs/images/app-icon.png`.

## Acceptance Criteria

- The built app shows the Cobalt capsule icon in Finder and in the About alert.
- `Appearance › Theme` lists the eight themes in order, with Cobalt checked by
  default.
- Choosing a theme changes the About alert icon, the usage bars and the Token Usage card at once. Tool Colors keeps the icon.
- The choice survives a relaunch.

## Validation Targets

- Settings store tests for the default, persistence, and unknown stored values.
- Mapping tests proving each non-default colour loads a bundled image.
- Menu builder tests for the submenu order and checked state.
- Coordinator tests proving a selection persists and applies the colour.
- Manual QA on a built app for Finder, About, and an alert with each colour.
