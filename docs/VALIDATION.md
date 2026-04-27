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
- validation and test harnesses must never read from or write to the default user Application Support catalog
- validation and test harnesses must never control real product processes, such as quitting, force-quitting, relaunching, or driving the installed Codex app, unless the scenario explicitly opts into live mutation
- validation and test harnesses must never surface blocking native alerts; they must capture alert intent through non-interactive test presenters or validation artifacts instead

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
- progress-bar accent color customization and reset behavior:
  - unit plus deterministic UI validation
- inactive account rendering and switch-action wiring metadata:
  - deterministic UI plus `SCENARIO=live-menu-open make verify-ui-live`
- custom menubar rows stay flush with the rendered menu width:
  - `SCENARIO=live-menu-open make verify-ui-live`
- end-to-end switch-account transition proof when explicitly opting into live auth mutation:
  - `CODEXPILL_ALLOW_LIVE_ACCOUNT_SWITCH_VALIDATION=1 SCENARIO=live-account-switch make verify-ui-live`
- text-on-hover behavior:
  - unit plus `SCENARIO=live-status-item-hover make verify-ui-live`
- save-current-account naming and duplicate handling:
  - `SaveCurrentAccountWorkflowTests`
- save-current-account prompt presentation and cancellation:
  - `SCENARIO=live-save-current-account-name-dialog-cancelled make verify-ui-live`
- Add Account name-dialog presentation and cancellation:
  - `SCENARIO=live-add-account-name-dialog-cancelled make verify-ui-live`
- scheduled refresh timer requests and completes a background refresh:
  - `CODEXPILL_VALIDATION_AUTO_REFRESH_INTERVAL_SECONDS=2 SCENARIO=live-scheduled-refresh make verify-ui-live`
- active-account refresh and identity matching:
  - `RefreshActiveAccountUseCaseTests`
- effective plan display and App Server plan-code mapping:
  - `CodexAccountTests`, `CodexRateLimitWindowTests`, `MenuBarAccountPresentationTests`, and `RefreshActiveAccountUseCaseTests`
- app-server account/rate-limit response parsing, transient retry, and JSON-RPC error surfacing:
  - `CodexAppServerClientTests`
- background wake or timer refresh failures stay silent in the UI:
  - `AccountsControllerTests`
- sign-in-another persistence and duplicate-avoidance rules:
  - `SignInAnotherWorkflowTests`
- sign-in-another duplicate-name preflight and terminal pending-error handling:
  - `SignInAnotherWorkflowTests` plus `AccountsControllerTests`
- switch-account relaunch and persistence behavior:
  - `SwitchAccountWorkflowTests`
- remote-host SSH command mapping and failure surfacing:
  - `SSHRemoteHostClientTests`
- remote-host install-then-switch orchestration:
  - `SwitchAccountOnHostWorkflowTests`
- persisted remote-host refresh fallback when a host is offline:
  - `MenuBarLiveValidationTests`
- multiple connected remote hosts render distinct primary remote-account cards without changing the local accounts catalog:
  - deterministic UI plus `MenuBarLiveValidationTests`
- disconnected configured hosts stay manageable without rendering a primary remote-account card:
  - deterministic UI plus `MenuBarLiveValidationTests`
- validation-only live remote host switching proves submenu dispatch and remote-card update without depending on a real SSH box:
  - `SCENARIO=live-remote-host-switch make verify-ui-live`
- Add Host destination validation failure:
  - `SCENARIO=live-add-host-destination-validation-failed make verify-ui-live`

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

### `menubar.progress_bar_accent_color.persists_and_resets`

- `feature`: `menubar`
- `rule`: Progress bars share one persisted accent color, surface it in the display menu, and can reset it back to the default color.
- `owner_layer`: `unit`
- `proofs_required`: `["unit", "deterministic_ui"]`
- `scenarios`: `["custom_progress_accent_color", "reset_progress_accent_color"]`

### `menubar.inactive_accounts.render_and_wired_for_switch`

- `feature`: `menubar`
- `rule`: Saved inactive accounts must render in `Accounts` or `More Accounts…` as submenu parent rows, and those submenus must expose enabled `switchAccount:` targets in the live runtime snapshot.
- `owner_layer`: `live_ui`
- `proofs_required`: `["deterministic_ui", "live_ui"]`
- `scenarios`: `["accounts_section", "overflow_accounts"]`

### `menubar.custom_rows.stay_flush_with_rendered_menu_width`

- `feature`: `menubar`
- `rule`: Custom menubar rows must stay flush with the rendered menu width so hosted cards and other custom sections do not leave a visible right-side gap.
- `owner_layer`: `live_ui`
- `proofs_required`: `["live_ui"]`
- `scenarios`: `["live-menu-open"]`

### `accounts.save_current_account.refreshes_existing_snapshot`

- `feature`: `accounts`
- `rule`: `Save Current Account` stays available when the active auth already matches a saved account, because the workflow refreshes the existing snapshot.
- `owner_layer`: `integration`
- `proofs_required`: `["integration", "live_ui"]`
- `scenarios`: `["active_saved_account", "matched_saved_identity"]`

### `accounts.save_current_account.name_dialog_cancelled`

- `feature`: `accounts`
- `rule`: Triggering `Save Current Account` from the running menubar presents the name dialog and allows clean cancellation without mutating account state.
- `owner_layer`: `live_ui`
- `proofs_required`: `["live_ui"]`
- `scenarios`: `["live-save-current-account-name-dialog-cancelled", "save-current-account-name-dialog-cancelled"]`
- `event_evidence`: `["menu_action_dispatched", "save_current_account_name_dialog_presented", "save_current_account_name_dialog_cancelled"]`

### `accounts.add_account.name_dialog_cancelled`

- `feature`: `accounts`
- `rule`: Triggering `Add Account...` from the running menubar presents the name dialog and allows clean cancellation without mutating account state.
- `owner_layer`: `live_ui`
- `proofs_required`: `["live_ui"]`
- `scenarios`: `["live-add-account-name-dialog-cancelled", "add-account-name-dialog-cancelled"]`
- `event_evidence`: `["menu_action_dispatched", "add_account_name_dialog_presented", "add_account_name_dialog_cancelled"]`

### `accounts.add_account.duplicate_name_preflight`

- `feature`: `accounts`
- `rule`: Add Account rejects duplicate saved-account names before clearing live auth, relaunching Codex, or starting a pending sign-in.
- `owner_layer`: `unit`
- `proofs_required`: `["unit"]`
- `scenarios`: `["sign_in_another_duplicate_name_preflight"]`

### `accounts.add_account.terminal_completion_error_clears_pending_sign_in`

- `feature`: `accounts`
- `rule`: If pending Add Account completion reaches a terminal save failure, CodexPill surfaces one error and clears the pending sign-in so the monitor does not re-alert repeatedly.
- `owner_layer`: `unit`
- `proofs_required`: `["unit"]`
- `scenarios`: `["sign_in_another_terminal_completion_error"]`

### `accounts.scheduled_refresh.requested_and_completed`

- `feature`: `accounts`
- `rule`: The scheduled refresh timer refreshes the active local account without rotating saved inactive snapshots through the real local auth file. The running app emits completion or failure proof without surfacing a blocking alert. Failure events must include the sanitized refresh error so app-server contract drift is diagnosable from validation artifacts. Remote-host refresh behavior is covered by the remote-host invariants, not by this scheduled-refresh proof.
- `owner_layer`: `live_ui`
- `proofs_required`: `["integration", "live_ui"]`
- `scenarios`: `["scheduled_refresh"]`
- `event_evidence`: `["scheduled_refresh_requested", "scheduled_refresh_completed", "scheduled_refresh_failed"]`

### `accounts.app_server.rate_limit_refresh_errors_are_retryable_and_diagnosable`

- `feature`: `accounts`
- `rule`: App-server reads must handle JSON-RPC notification frames, surface JSON-RPC error messages from account or rate-limit responses, and retry transient rate-limit failures. When a refresh can only preserve old rate limits, CodexPill must not advance the rate-limit freshness timestamp.
- `owner_layer`: `integration`
- `proofs_required`: `["integration"]`
- `scenarios`: `["app_server_json_rpc_error", "app_server_transient_rate_limit_retry", "preserve_stale_rate_limits_without_marking_fresh"]`

### `accounts.effective_plan.normalizes_observed_plus_to_pro_upgrade`

- `feature`: `accounts`
- `rule`: CodexPill maps all known App Server plan codes to user-facing display names. When refreshed account metadata still says Plus but fresh rate-limit metadata reports Codex `prolite`, CodexPill displays and persists the account as Pro. `unknown` is treated as missing when choosing an effective plan. Other account plan disagreements must keep the account metadata plan until the backend plan taxonomy is understood.
- `owner_layer`: `unit`
- `proofs_required`: `["unit"]`
- `scenarios`: `["known_app_server_plan_display_names", "plus_prolite_displays_as_pro", "unknown_falls_back_to_known_plan", "team_prolite_does_not_downgrade"]`

### `accounts.switch_account.menu_action_changes_active_account`

- `feature`: `accounts`
- `rule`: Selecting an inactive account from the running menubar emits the switch workflow event sequence and changes the active-account snapshot. The live smoke additionally checks that the runtime snapshot moved to the clicked target.
- `owner_layer`: `live_ui`
- `proofs_required`: `["integration", "live_ui"]`
- `scenarios`: `["live-account-switch", "switch-account-changes-active-account"]`
- `event_evidence`: `["menu_action_dispatched", "switch_confirmation_presented", "switch_confirmation_accepted", "switch_workflow_started", "active_account_changed"]`
- `snapshot_evidence`: `["account_before", "account_after"]`

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

### `hosts.menu.local_catalog_remains_single_source_of_truth`

- `feature`: `hosts`
- `rule`: When a remote host is present, the main menu continues to source `Accounts` and `More Accounts…` from the local saved-account catalog for identity and actions, while allowing each row to display target-aware live usage when that saved account is actively verified on a host. If the same account is active on both This Mac and a remote host, the local current-account values remain authoritative for the row.
- `owner_layer`: `unit`
- `proofs_required`: `["unit", "deterministic_ui"]`
- `scenarios`: `["hosted_menu_with_host", "hosted_menu_local_and_remote_same_account"]`

### `hosts.account_actions_target_local_or_host_explicitly`

- `feature`: `hosts`
- `rule`: When a remote host is present, inactive account rows expose explicit `This Mac` and remote-host submenu actions instead of collapsing both targets into one ambiguous switch action.
- `owner_layer`: `deterministic_ui`
- `proofs_required`: `["unit", "deterministic_ui"]`
- `scenarios`: `["hosted_menu_with_host", "host_account_missing_on_host"]`

### `hosts.add_host.destination_validation_failed`

- `feature`: `hosts`
- `rule`: Triggering `Add Host…` from the running menubar presents the host setup dialog, accepts a destination entry, and emits validation feedback for an invalid host before allowing the workflow to continue.
- `owner_layer`: `live_ui`
- `proofs_required`: `["live_ui"]`
- `scenarios`: `["live-add-host-destination-validation-failed", "add-host-destination-validation-failed"]`
- `event_evidence`: `["menu_action_dispatched", "add_host_setup_presented", "add_host_validation_started", "add_host_validation_failed"]`

### `hosts.switch_workflow.installs_missing_accounts_before_switch`

- `feature`: `hosts`
- `rule`: Switching an account on a remote host installs the snapshot first when it is missing, skips installation when it is already present, and stops cleanly on install or switch failures.
- `owner_layer`: `integration`
- `proofs_required`: `["integration"]`
- `scenarios`: `["missing_remote_snapshot", "installed_remote_snapshot", "install_failure", "switch_failure"]`

### `hosts.switch_account_on_host.changes_remote_active_account`

- `feature`: `hosts`
- `rule`: Selecting `Switch on <host>` from a saved account submenu dispatches the host-targeted switch workflow and updates the primary remote-account card to the chosen account.
- `owner_layer`: `live_ui`
- `proofs_required`: `["integration", "live_ui"]`
- `scenarios`: `["live-remote-host-switch"]`
- `event_evidence`: `["menu_action_dispatched", "remote_host_switch_started", "remote_host_active_account_changed"]`

### `hosts.refresh_failure.preserves_fallback_state_and_marks_disconnected`

- `feature`: `hosts`
- `rule`: When CodexPill restores a persisted remote host and the remote refresh fails, it preserves the last known remote account fallback while marking the host disconnected and hiding the primary remote-account card.
- `owner_layer`: `live_ui`
- `proofs_required`: `["live_ui"]`
- `scenarios`: `["persisted_host_refresh_failure"]`

### `hosts.connected_cards.render_per_reachable_host_only`

- `feature`: `hosts`
- `rule`: Each reachable configured host with an active remote account renders its own `Remote Accounts` card, while unreachable hosts stay persisted but do not render primary remote cards.
- `owner_layer`: `live_ui`
- `proofs_required`: `["deterministic_ui", "live_ui"]`
- `scenarios`: `["hosted_menu_multiple_hosts", "mixed_persisted_host_restore"]`

### `hosts.disconnected_hosts.remain_targetable_without_remote_card`

- `feature`: `hosts`
- `rule`: A disconnected configured host remains available under `Hosts` and per-account remote switch targets, but it does not render in the primary `Remote Accounts` section.
- `owner_layer`: `deterministic_ui`
- `proofs_required`: `["deterministic_ui", "live_ui"]`
- `scenarios`: `["hosted_menu_disconnected_host", "persisted_host_refresh_failure"]`

### `hosts.reachable_verification_failures.remain_connected`

- `feature`: `hosts`
- `rule`: A reachable host whose remote account cannot be verified stays connected in host state and menu UI while surfacing verification failure instead of being collapsed into a disconnected host.
- `owner_layer`: `integration`
- `proofs_required`: `["integration", "live_ui"]`
- `scenarios`: `["remote_auth_read_failure", "explicit_host_switch_verification_failure"]`

### `notifications.policy.selects_single_best_account`

- `feature`: `notifications`
- `rule`: Notification policy is account-centric, selects one best currently usable saved account using the shared availability ranking logic, ignores barely usable candidates below the fixed headroom threshold, does not wait for future resets, and still surfaces the best already-usable fallback when the current account becomes out of capacity.
- `owner_layer`: `unit`
- `proofs_required`: `["unit"]`
- `scenarios`: `["blocked_to_unblocked", "weak_candidate_suppressed", "future_reset_does_not_defer_notification"]`

### `notifications.policy.when_out_uses_local_and_verified_remote_activity`

- `feature`: `notifications`
- `rule`: The "Current Runs Out" notification mode evaluates both the current local active account and the current verified remote active account, and it proposes another saved account only when the active target is out of capacity and another saved account is notification-worthy.
- `owner_layer`: `unit`
- `proofs_required`: `["unit"]`
- `scenarios`: `["local_active_out", "verified_remote_active_out", "low_but_not_out_suppressed", "active_account_newly_out_with_existing_fallback"]`

### `notifications.state.suppresses_repeat_delivery_until_activation`

- `feature`: `notifications`
- `rule`: Once CodexPill records a notification for a saved account, that account stays suppressed for future notification delivery until the app observes that account become active locally or on a verified remote host.
- `owner_layer`: `integration`
- `proofs_required`: `["integration"]`
- `scenarios`: `["ignored_notification", "activation_rearms_account"]`

### `notifications.state.settings_and_records_persist`

- `feature`: `notifications`
- `rule`: Notification mode toggles and per-account dedupe state persist across launches through `AppSettings`, so ignored notifications do not repeat after restart and activation re-arm state survives process restarts.
- `owner_layer`: `integration`
- `proofs_required`: `["integration"]`
- `scenarios`: `["settings_round_trip", "notification_state_round_trip"]`

### `notifications.delivery.requests_permission_on_first_enable_only`

- `feature`: `notifications`
- `rule`: CodexPill asks macOS for notification permission only when the user enables the first notification mode, and enabling the second mode later does not trigger a second permission request.
- `owner_layer`: `integration`
- `proofs_required`: `["integration"]`
- `scenarios`: `["first_toggle_enable", "second_toggle_enable_after_first"]`

### `notifications.delivery.enable_entry_recovers_permission`

- `feature`: `notifications`
- `rule`: The Notifications submenu exposes a simple `Enable Notifications…` action when app notification workflows are off or macOS notification authorization is denied; the action enables default app notification workflows when needed, requests macOS authorization when not determined, and opens System Settings instead of re-requesting when authorization was denied.
- `owner_layer`: `integration`
- `proofs_required`: `["unit", "integration"]`
- `scenarios`: `["menu_enable_entry_visibility", "not_determined_requests_authorization", "denied_opens_system_settings"]`

### `notifications.delivery.renders_policy_output_without_recomputing_selection`

- `feature`: `notifications`
- `rule`: The platform notification bridge renders the chosen account and action suggestions produced by notification policy, and for the "Current Runs Out" mode it explains which account is out, on which target, and which fallback account is ready, without recomputing best-account selection or target ranking on its own.
- `owner_layer`: `integration`
- `proofs_required`: `["integration"]`
- `scenarios`: `["direct_target_actions", "best_option_fallback"]`
