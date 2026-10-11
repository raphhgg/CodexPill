# App Icon

## User Story

As a Refill user, I want to pick the colour of the Refill app icon, so the
app's own windows and alerts match the look I prefer.

## Product Contract

The app icon is a porcelain-and-glass capsule built as an Icon Composer document
(`Resources/AppIcon.icon`). Its colour is Cobalt. Xcode compiles it into the
asset catalog for macOS 26 and later, and generates an `AppIcon.icns` fallback
for macOS 14 and 15.

Refill exposes an `App Icon` submenu in `Settings › Appearance` with six colours:
Cobalt, Deep teal, Emerald, Violet, Honey and Rose. Cobalt is the default. The
choice persists and is applied at launch.

macOS has no API that lets an app change its own Finder icon. Refill sets its
in-app icon (`NSApplication.applicationIconImage`) instead. The choice changes:

- The `About Refill` alert.
- Every Refill alert and confirmation.
- The title-bar icon of Refill panels, such as shortcut capture.

The choice does not change:

- Finder, Spotlight, Launchpad, and the Login Items list in System Settings.

These surfaces always show Cobalt.

## UI / Copy / States

```text
Settings
  Appearance
    Menu Bar Label
    Icon Style
    Usage Bars
    App Icon
      ✓ Cobalt
        Deep teal
        Emerald
        Violet
        Honey
        Rose
    ----------------
    Show Token Usage
```

The current colour has a checkmark.

## Edge Cases

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

The five alternate colours live as Icon Composer documents in
`Design/AppIconColors/`. Run `scripts/render_app_icon_colors.sh` after editing
any `.icon` file. It renders the PNGs the app loads at runtime into
`Resources/AppIconColors/`, and the README icon into `docs/images/app-icon.png`.

## Acceptance Criteria

- The built app shows the Cobalt capsule icon in Finder and in the About alert.
- `Settings › Appearance › App Icon` lists the six colours in order, with Cobalt checked by
  default.
- Choosing a colour changes the About alert and other alert icons immediately.
- The choice survives a relaunch.

## Validation Targets

- Settings tests for the default, persistence, and unknown stored values.
- Mapping tests proving each non-default colour loads a bundled image.
- Menu builder tests for the submenu order and checked state.
- Coordinator tests proving a selection persists and applies the colour.
- Manual QA on a built app for Finder, About, and an alert with each colour.
