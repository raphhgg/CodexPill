# Validation

This repo uses invariant-driven validation for behavior changes.

## Local rule

When behavior changes:

1. Update or add the affected invariant in the owning test layer.
2. Run the owning regression suite.
3. Run deterministic UI validation when menu structure, copy, or menu-state behavior changes.
4. Run live menubar validation when runtime menubar wiring or live account behavior changes.

Anything an agent can verify in this repo should be expressed as automated proof through the owning suite plus hosted or live smoke scenarios. Do not keep a separate agent-only QA checklist for behavior the validation system can prove.

## Owning layers

- Unit: pure rules such as account matching, menu-state policy, formatting, enable/disable behavior.
- Integration: persistence, auth snapshot parsing, app-server mapping, workflow orchestration against real seams.
- Deterministic UI validation: deterministic menubar snapshot shape and rendered screenshots.
- Live UI validation: real running menubar behavior, action wiring, and runtime snapshot proof.

## Artifact contract

- `make verify-ui` must write hosted screenshots plus JSON artifacts under `build/verification/<agent>/<scenario>/`
- `make verify-ui-live` must write at least `summary.json`, `runtime-assertions.json`, `live-menu-snapshot.json`, `validation-events.jsonl`, and a screenshot
- live summaries should include `proofSequence` and `failureStep` when a scenario relies on app-emitted runtime events

## Agent execution

- Use `make verify-ui` for deterministic menu validation.
- Use `make verify-ui-live` for live menubar smoke validation.
- Add or extend live smoke scenarios when runtime behavior must be proven by an agent.
- Keep manual-only checks in `docs/QA_HUMAN.md` for behaviors the agent cannot yet prove reliably.

## Automated coverage

The following behavior should be treated as automated first and should not live primarily in human QA checklists:

- app starts cleanly and the menu renders:
  - `SCENARIO=live-menu-open make verify-ui-live`
- status item content fallback and disabled menu-state behavior:
  - unit plus deterministic UI validation
- inactive account rendering and switch-action wiring metadata:
  - deterministic UI plus `SCENARIO=live-menu-open make verify-ui-live`
- end-to-end switch-account transition proof when explicitly opting into live auth mutation:
  - `CODEXPILL_ALLOW_LIVE_ACCOUNT_SWITCH_VALIDATION=1 SCENARIO=live-account-switch make verify-ui-live`
- text-on-hover behavior:
  - unit plus `SCENARIO=live-status-item-hover make verify-ui-live`
- save-current-account naming and duplicate handling:
  - `SaveCurrentAccountWorkflowTests`
- active-account refresh and identity matching:
  - `RefreshActiveAccountUseCaseTests`
- background wake or timer refresh failures stay silent in the UI:
  - `AccountsControllerTests`
- sign-in-another persistence and duplicate-avoidance rules:
  - `SignInAnotherWorkflowTests`
- switch-account relaunch and persistence behavior:
  - `SwitchAccountWorkflowTests`

If one of those areas needs more confidence, extend the owning suite or add a live smoke scenario. Do not add it back as a standing human checklist item unless there is still a real manual-only gap.

## Residual manual QA

Keep human QA only for behaviors the current automation cannot prove end to end, such as:

- native alert copy and text-entry UX
- real Codex sign-in flow completion through external app surfaces
- real inactive-account click dispatch when live account-switch validation is intentionally not enabled or Accessibility cannot enumerate the open menubar menu
- timer or lifecycle behavior not yet captured by a deterministic or live smoke scenario
- OS-level failures where pointer control, focus, or permissions block agent proof

## Current feature invariants

### `menubar.status_item_content.fallback_icon_only`

- `feature`: `menubar`
- `rule`: Status item content falls back to `Icon Only` when no active account rate-limit data exists.
- `owner_layer`: `unit`
- `proofs_required`: `["unit", "deterministic_ui", "live_ui"]`
- `scenarios`: `["empty_state", "no_rate_limit_data"]`

### `menubar.inactive_accounts.render_and_wired_for_switch`

- `feature`: `menubar`
- `rule`: Saved inactive accounts must render in `Other Accounts` or `More Accounts…` and expose enabled `switchAccount:` menu actions in the live runtime snapshot.
- `owner_layer`: `live_ui`
- `proofs_required`: `["deterministic_ui", "live_ui"]`
- `scenarios`: `["multiple_saved_accounts", "overflow_other_accounts"]`

### `accounts.save_current_account.refreshes_existing_snapshot`

- `feature`: `accounts`
- `rule`: `Save Current Account` stays available when the active auth already matches a saved account, because the workflow refreshes the existing snapshot.
- `owner_layer`: `integration`
- `proofs_required`: `["integration", "live_ui"]`
- `scenarios`: `["active_saved_account", "matched_saved_identity"]`

### `accounts.switch_account.menu_action_changes_active_account`

- `feature`: `accounts`
- `rule`: Selecting an inactive account from the running menubar emits the switch workflow event sequence and moves the current-account snapshot to the chosen target.
- `owner_layer`: `live_ui`
- `proofs_required`: `["integration", "live_ui"]`
- `scenarios`: `["switch_from_other_accounts"]`
- `event_evidence`: `["menu_action_dispatched", "switch_confirmation_presented", "switch_confirmation_accepted", "switch_workflow_started", "active_account_changed"]`

### `menubar.text_on_hover.stays_visible_inside_resized_bounds`

- `feature`: `menubar`
- `rule`: Text-on-hover mode remains visible while the pointer stays inside the resized status item after the title appears.
- `owner_layer`: `unit`
- `proofs_required`: `["unit", "live_ui"]`
- `scenarios`: `["hover_enter", "hover_resize", "hover_exit"]`
- `event_evidence`: `["status_item_hover_entered", "status_item_title_became_visible", "status_item_hover_exit_scheduled", "status_item_hover_exited", "status_item_title_hidden"]`

### `accounts.background_refresh_failure.logs_without_alert`

- `feature`: `accounts`
- `rule`: Background wake or timer refresh failures are logged but do not queue a blocking UI error message.
- `owner_layer`: `integration`
- `proofs_required`: `["integration"]`
- `scenarios`: `["wake_refresh_failure", "scheduled_refresh_failure"]`
