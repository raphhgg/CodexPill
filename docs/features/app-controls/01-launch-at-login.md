# Launch At Login

## User Story

As a rusage user, I want to choose whether rusage starts automatically
when I log in to macOS, so my account limits are visible without manually
opening the app every day.

## Product Contract

rusage exposes a `Launch at Login` switch in `Settings › General`.

The setting controls the macOS login item for the main app. It must use the
native macOS login item mechanism and reflect the current system state each
time the menu is built and each time the Settings window comes forward.

The product term is `Launch at Login`, not `Launch at Startup`.

## Happy Path

1. The user opens `Settings… › General`.
2. The user turns on `Launch at Login`.
3. rusage explains that it will ask macOS to open the app automatically
   when the user logs in.
4. The user confirms.
5. rusage enables the macOS login item.
6. The switch reflects the resulting state.

## UI / Copy / States

The switch is the last group of `Settings › General`:

```text
Launch at Login                      [switch]
```

Normal states:

- On: the login item is enabled.
- Off: the login item is disabled.
- Turning it on first shows:

```text
Launch rusage at Login?

rusage will ask macOS to open it automatically when you log in. You can turn
this off here or in System Settings.
```
- Turning it off disables it directly.

Blocked states add a row under the switch:

```text
Launch at Login                      [switch]
Needs approval in System Settings    [Open Login Items…]
```

While macOS waits for approval the switch stays on, and turning it on again
opens System Settings instead. When the state can't be read or set here the
switch is off and disabled, the row reads `Unavailable for this copy of rusage`,
and `Open Login Items…` opens System Settings.

## Edge Cases

- If enabling fails because macOS requires approval, rusage must not pretend
  the setting is enabled.
- If the login item is blocked in System Settings, rusage shows the approval
  row and routes the user to System Settings.
- If System Settings cannot be opened, rusage shows a short error and leaves
  the current login item state unchanged.
- If rusage cannot determine the login item state, the window fails safe: the
  switch is off and disabled, and the row routes to System Settings.

## Acceptance Criteria

- `Settings › General` includes the `Launch at Login` switch.
- Turning it on requires explicit confirmation before registering rusage
  as a macOS login item.
- Turning it off unregisters rusage as a macOS login item.
- A requires-approval or unavailable system state shows its row and
  `Open Login Items…`.
- The switch never claims launch at login is enabled when registration
  failed.

## Validation Targets

- Unit or boundary tests for mapping macOS login item statuses to menu states.
- Coordinator tests proving enabling asks for confirmation, disabling does not,
  and blocked or unavailable states open System Settings.
- Validation docs updated with the app-control invariant.
- Manual QA on a real macOS app build to verify the login item appears in
  System Settings and survives relaunch/login behavior.

## Out Of Scope / Deferrals

- No onboarding prompt asking users to enable launch at login.
- No automatic retry loop if macOS blocks the login item.
- No support for helper-app login items unless the main-app mechanism proves
  insufficient.

## Open Questions

- None for the v1 contract.

## Recommended Next Checkpoint

Manual QA on a signed or local macOS build:

1. Turn `Launch at Login` on.
2. Confirm rusage appears in macOS System Settings Login Items.
3. Turn it off.
4. Confirm the System Settings entry is removed or disabled.
