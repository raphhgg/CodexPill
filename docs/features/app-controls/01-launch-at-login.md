# Launch At Login

## User Story

As a CodexPill user, I want to choose whether CodexPill starts automatically
when I log in to macOS, so my account limits are visible without manually
opening the app every day.

## Product Contract

CodexPill exposes a `Launch at Login` control in the `Preferences` submenu.

The setting controls the macOS login item for the main app. It must use the
native macOS login item mechanism and reflect the current system state when the
menu is built or refreshed.

The product term is `Launch at Login`, not `Launch at Startup`.

## Happy Path

1. The user opens the CodexPill menu.
2. The user opens `Preferences`.
3. The user selects `Launch at Login`.
4. CodexPill explains that it will ask macOS to open the app automatically
   when the user logs in.
5. The user confirms.
6. CodexPill enables the macOS login item.
7. The menu reflects the resulting checked state.

## UI / Copy / States

The entry appears at the bottom of `Preferences`, separated from visual
preferences:

```text
Preferences
  Menu Bar Label
  Icon Style
  Usage Bars
  ----------------
  Launch at Login
```

Normal states:

- Checked `Launch at Login`: the login item is enabled.
- Unchecked `Launch at Login`: the login item is disabled.
- Selecting unchecked `Launch at Login` first shows:

```text
Launch CodexPill at Login?

CodexPill will ask macOS to open it automatically when you log in. You can turn
this off here or in System Settings.
```
- Selecting checked `Launch at Login` disables it directly.

Blocked state:

```text
Preferences
  Menu Bar Label
  Icon Style
  Usage Bars
  ----------------
  Launch at Login…
```

`Launch at Login…` means macOS needs external user action, such as approving or
re-enabling the login item in System Settings. Selecting it opens System
Settings to the relevant Login Items surface instead of trying to toggle again.

## Edge Cases

- If enabling fails because macOS requires approval, CodexPill must not pretend
  the setting is enabled.
- If the login item is disabled or blocked in System Settings, CodexPill shows
  `Launch at Login…` and routes the user to System Settings.
- If System Settings cannot be opened, CodexPill shows a short error and leaves
  the current login item state unchanged.
- If CodexPill cannot determine the login item state, the menu should fail safe:
  show `Launch at Login…`, keep it unchecked, and route to System Settings.

## Acceptance Criteria

- `Preferences` includes `Launch at Login` at the bottom, after a separator.
- The normal row behaves like a native checkbox item.
- Enabling the row requires explicit confirmation before registering CodexPill
  as a macOS login item.
- Disabling the row unregisters CodexPill as a macOS login item.
- A blocked or requires-approval system state renders `Launch at Login…`.
- Selecting `Launch at Login…` opens System Settings instead of toggling the
  setting.
- The menu state never claims launch at login is enabled when registration
  failed or macOS reports the item as blocked.

## Validation Targets

- Unit or boundary tests for mapping macOS login item statuses to menu states.
- Menu builder tests for checked, unchecked, blocked, and unavailable states.
- Coordinator tests proving enabling asks for confirmation, disabling does not,
  and blocked or unavailable rows open System Settings.
- Validation docs updated with the app-control invariant.
- Manual QA on a real macOS app build to verify the login item appears in
  System Settings and survives relaunch/login behavior.

## Out Of Scope / Deferrals

- No onboarding prompt asking users to enable launch at login.
- No separate full Preferences window.
- No automatic retry loop if macOS blocks the login item.
- No support for helper-app login items unless the main-app mechanism proves
  insufficient.

## Open Questions

- None for the v1 contract.

## Recommended Next Checkpoint

Manual QA on a signed or local macOS build:

1. Toggle `Preferences > Launch at Login` on.
2. Confirm CodexPill appears in macOS System Settings Login Items.
3. Toggle it off.
4. Confirm the System Settings entry is removed or disabled.
