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

## Validation Scenario Candidates

- `launch-at-login-menu-states`
- `launch-at-login-enable-confirmation`
- `launch-at-login-blocked-opens-settings`
- `launch-at-login-real-os-smoke`

## Proof Contract

| Acceptance Criterion | Owning Proof Layer | Command / Method | Artifact | Pass Condition | Privacy / Redaction |
| --- | --- | --- | --- | --- | --- |
| Preferences shows checked, unchecked, blocked, and unavailable Launch at Login states truthfully. | `unit` plus `deterministic-ui` | Login-item state mapping tests and `make verify-ui SCENARIO=launch-at-login-menu-states`. | Test result, hosted menu screenshot, UI tree, scenario summary, and `build/verification/launch-at-login-menu-states/launch-at-login-states.json`. | Checked, unchecked, blocked, and unavailable states map to the documented row copy, checked state, and action selector without claiming registration success when macOS reports failure or blocked state. The deterministic scenario does not register/unregister a real login item, open System Settings, prove signed-app Login Items visibility, or prove the enable confirmation workflow. | Synthetic login-item state only; artifacts must not include private machine paths, account identifiers, auth payloads, tokens, emails, or hostnames. |
| Enabling requires confirmation before registering the macOS login item. | `workflow-event-log` | `make verify-launch-at-login-enable-confirmation-scenario` running `MenuBarMenuBuilderTests` with fake login-item controller and confirmation presenter. | `build/results/local/CodexPill.xcresult`, `build/verification/launch-at-login-enable-confirmation/workflow-receipt.json`, and `scenario-summary.json`. | The fake controller is not called before confirmation; confirming calls register once; cancelling leaves state unchanged; registration failure reports an error without claiming enabled state. The deterministic scenario does not register a real macOS login item, prove signed-app Login Items visibility, live menu-bar clicks, or live System Settings UI. | Event receipts must avoid user account names, private paths, tokens, or system identifiers. |
| Disabling unregisters directly. | `workflow-event-log` | `make verify-launch-at-login-enable-confirmation-scenario` running `MenuBarMenuBuilderTests` with fake login-item controller. | `build/results/local/CodexPill.xcresult`, `build/verification/launch-at-login-enable-confirmation/workflow-receipt.json`, and `scenario-summary.json`. | Selecting checked `Launch at Login` calls unregister once without showing the enable confirmation. The deterministic scenario does not unregister a real macOS login item or prove live System Settings state. | Synthetic state only; no private system identifiers. |
| Blocked or unavailable state opens System Settings instead of toggling. | `workflow-event-log` | `make verify-launch-at-login-blocked-opens-settings-scenario` running `MenuBarMenuBuilderTests` with fake system opener. | `build/results/local/CodexPill.xcresult`, `build/verification/launch-at-login-blocked-opens-settings/workflow-receipt.json`, and `scenario-summary.json`. | Blocked/unavailable rows call the System Settings opener and do not call register/unregister; menu projection shows `Launch at Login…`, unchecked state, and `openLoginItemsSettings:` action. The deterministic scenario does not open real System Settings, mutate real macOS login-item approval state, prove live menu-bar clicks, or prove signed-app Login Items visibility. | Receipts must not record private preference paths or local account data. |
| A real macOS build appears in System Settings and survives toggle on/off. | `manual-qa` or explicit opt-in live OS proof | Signed/local app build manual QA, only after explicit operator opt-in for live Login Items mutation in the current thread. | Maintainer checklist with summarized System Settings evidence, pre-test state, post-test cleanup state, and blocker classification when incomplete. | The login item appears, toggles on/off, leaves the menu state truthful after refresh, and the operator restores the original Login Items state before closing the gate. | Manual notes must not include Apple account identifiers, local usernames, private paths, or screenshots containing unrelated private data. Screenshots are optional and must be cropped/redacted before sharing. |

## Live / Manual Gate Contract

`launch-at-login-real-os-smoke` is a manual gate, not a default Kite scenario.
It must not be promoted into `.kite/scenarios.json` until CodexPill has a
product-local command or checklist runner that records explicit live opt-in,
pre-state, actions, cleanup, privacy review, blocker taxonomy, degraded proof,
and non-claims.

The gate is blocked unless the operator explicitly approves live macOS Login
Items mutation in the current thread. That approval must name the build under
test, allow opening System Settings, and allow toggling the CodexPill login item
on and off. Native UI automation, VM/simulator runs, and unattended System
Settings mutation remain out of scope unless they are separately approved.

The checklist must record only summarized evidence:

- opt-in timestamp and build identity, without private local paths;
- original Launch at Login state before mutation;
- whether CodexPill appeared in System Settings Login Items;
- whether enabling, refreshing, and disabling left the menu truthful;
- cleanup result restoring the original Login Items state;
- blocker classification if any step cannot complete.

Cleanup is part of the pass condition. The operator must restore the original
Login Items state, quit any extra test copy of CodexPill, close System Settings,
and remove or quarantine temporary install artifacts when the test copied the
app outside the build directory. If cleanup cannot be confirmed, the gate is
blocked even if the toggle appeared to work.

Use this blocker taxonomy for incomplete live proof:

- `operator_opt_in_missing`
- `build_identity_block`
- `system_settings_block`
- `login_item_registration_block`
- `cleanup_block`
- `privacy_block`

When this gate is not run, the runnable fake/controller scenarios still prove
menu truth, confirmation gating, no-toggle blocked routing, and fake
workflow-event receipts. They do not prove real macOS login item registration or
unregistration, signed-app visibility in System Settings, persistence across
login/relaunch, live native menu clicks, or real System Settings routing.

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
