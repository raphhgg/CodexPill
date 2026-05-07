# Validation

This repo uses invariant-driven validation for behavior changes.

Seal-backed runtime validation migration is tracked in [seal-runtime-validation-migration-plan.md](seal-runtime-validation-migration-plan.md). That plan records the move from CodexPill-owned runtime/live gates toward Seal-owned proof verification and reporting while keeping lower-level CodexPill tests where they still add value.

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
- Seal-backed live summaries must list Seal-owned `seal-proof/result.json` and `seal-proof/report.md` artifacts
- `summary.sealResultPath` must point to Seal's `result.json` artifact and `summary.sealReportPath` must point to Seal's `report.md` artifact
- Seal-backed result JSON is the machine-readable gate evidence; the Markdown report is human-readable review evidence produced by Seal, not by CodexPill rendering logic
- For Seal-backed live scenarios, `summary.verdict_source` must be `"seal"` and top-level `summary.status` is only a temporary compatibility envelope derived from `seal-proof/result.json`
- For Seal-backed live scenarios, `validation-events.jsonl` and legacy proof-sequence fields are diagnostic-only; they cannot make a run pass when the Seal proof is missing or rejected
- Seal-backed live scenarios must clear stale `seal-proof/` and Seal verifier log/result artifacts before each run so neither stale Seal output nor stale legacy events can affect the verdict
- validation and test harnesses must never read from or write to the default user Application Support catalog
- validation and test harnesses must never control real product processes, such as quitting, force-quitting, relaunching, or driving the installed Codex app, unless the scenario explicitly opts into live mutation
- validation and test harnesses must never surface blocking native alerts; they must capture alert intent through non-interactive test presenters or validation artifacts instead

## Agent execution

- Use `make verify-ui` for deterministic menu validation.
- Use `make verify-ui-live` for live menubar smoke validation.
- Add or extend live smoke scenarios when runtime behavior must be proven by an agent.
- Track manual-only gaps as explicit issues or feature-document open questions until they can be covered by automated proof.
- Use [feature-to-seal-scenario-coverage.md](feature-to-seal-scenario-coverage.md) as the CodexPill-owned map from feature claims to Seal migration candidates. Seal docs may link to that map for adoption pressure or release-readiness context, but CodexPill remains the owner of the product semantics.
- Use [test-suite-relevance-after-seal-runtime-migration.md](test-suite-relevance-after-seal-runtime-migration.md) as the CodexPill-owned review of which lower-layer tests still add value after Seal owns migrated runtime/live proof, which legacy runtime assertions are migration candidates, and which tests are risky because they may mutate live auth or real user state if isolation is weakened.
- For PR or Linear handoff of Seal-backed live validation, attach or link `summary.sealReportPath` from the artifact root as the human-readable report, and include `summary.sealResultPath` as the machine-readable gate evidence. Do not paste the report body into PRs or Linear comments and do not parse Markdown for pass/fail status.

## Automated coverage

The following behavior should be treated as automated first and should not live primarily in human QA checklists:

- app starts cleanly and the menu renders:
  - `SCENARIO=live-menu-open make verify-ui-live`
- status item content fallback and disabled menu-state behavior:
  - unit plus deterministic UI validation
- progress-bar accent color customization and reset behavior:
  - unit plus deterministic UI validation
- current account pacing markers and preference toggle:
  - unit plus deterministic UI validation
- inactive account rendering and switch-action wiring metadata:
  - deterministic UI plus `SCENARIO=live-menu-open make verify-ui-live`
- custom menubar rows stay flush with the rendered menu width:
  - `SCENARIO=live-menu-open make verify-ui-live`
- end-to-end switch-account transition proof when explicitly opting into live auth mutation:
  - `CODEXPILL_ALLOW_LIVE_ACCOUNT_SWITCH_VALIDATION=1 SCENARIO=live-account-switch make verify-ui-live`
- Seal V1 boundary validation for account switching without live UI or real auth mutation:
  - `OUTPUT_DIR=build/validation-proof/account-switch make emit-account-switch-proof`
  - `swift run --package-path ../Seal seal-verifier --verbose build/validation-proof/account-switch`
- text-on-hover behavior:
  - unit plus `SCENARIO=live-status-item-hover make verify-ui-live`
- menu bar label reveal shortcut:
  - `StatusItemSettingsStoreTests`, `StatusItemRuntimeTests`, `GlobalShortcutRuntimeTests`, and deterministic UI validation
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
- Add Account duplicate-name preflight:
  - `AddAccountWorkflowTests`
- isolated Add Account success, duplicate identity, cancel, save-failure, and stale-temp cleanup behavior:
  - `AddAccountWorkflowTests`, `MenuBarAlertFactoryTests`, and `AppPathsTests`
- Add Account v0 contract coverage:
  - `AddAccountWorkflowTests`, `MenuBarAlertFactoryTests`, `AppPathsTests`, `MenuBarUIValidationTests`, and `SCENARIO=live-add-account-name-dialog-cancelled make verify-ui-live`
- switch-account relaunch and persistence behavior:
  - `SwitchAccountWorkflowTests`
- remote-host SSH command mapping and failure surfacing:
  - `SSHRemoteHostClientTests`
- remote-host install-then-switch orchestration:
  - `SwitchAccountOnHostWorkflowTests`
- remove-account active target sign-out before catalog deletion:
  - `DeleteSavedAccountUseCaseTests`, `ValidationRemoteHostClientTests`, `SSHRemoteHostClientTests`, and `MenuBarLiveValidationTests`
- persisted remote-host refresh fallback when a host is offline:
  - `MenuBarLiveValidationTests`
- multiple connected remote hosts render verified active account cards without changing the local accounts catalog:
  - deterministic UI plus `MenuBarLiveValidationTests`
- disconnected configured hosts stay manageable without rendering an active account card:
  - deterministic UI plus `MenuBarLiveValidationTests`
- validation-only live remote host switching proves submenu dispatch and active-card update without depending on a real SSH box:
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

### `validation.seal_run_adapter.resolves_account_switch`

- `feature`: `validation`
- `rule`: The CodexPill-owned Seal runner adapter must accept Seal's generic `--scenario`, `--proof-output`, and `--artifact-root` inputs, resolve `switch-account-changes-active-account` locally, emit proof through the existing account-switch proof emitter, and write adapter diagnostics under the runner-owned `adapter/` directory without teaching Seal CodexPill scenario semantics.
- `owner_layer`: `integration`
- `proofs_required`: `["integration", "seal_run"]`
- `scenarios`: `["switch-account-changes-active-account", "unsupported-scenario"]`

### `validation.seal_only_runtime.account_switch_authority`

- `feature`: `validation`
- `rule`: The selected CodexPill runtime validation flow for `switch-account-changes-active-account` must run through `seal run`; `proof/`, `reports/result.json`, `reports/report.md`, and `adapter/` are the only authoritative pass/fail artifacts. CodexPill may write a compatibility summary, but it must only point to Seal artifacts and mark legacy runtime output as non-authoritative.
- `owner_layer`: `integration`
- `proofs_required`: `["integration", "seal_run"]`
- `scenarios`: `["switch-account-changes-active-account"]`

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

### `accounts.active_cards.show_expected_pace_marker_only`

- `feature`: `accounts`
- `rule`: Active account cards may show a neutral expected-pace marker inside Session and Weekly progress bars when reset-window duration is available and `Preferences > Usage Bars > Show Pace Markers` is enabled, but they must not add pacing text or affect saved account catalog rows, ranking, switching, notifications, or persistence.
- `owner_layer`: `unit`
- `proofs_required`: `["unit", "deterministic_ui"]`
- `scenarios`: `["current_account_card", "remote_account_card", "missing_reset_window_duration", "show_markers_preference"]`

### `menubar.account_catalog.adapts_to_account_and_host_shape`

- `feature`: `menubar`
- `rule`: Saved account catalog presentation must adapt to the setup. A single saved account with no hosts uses `Account > Add Account…, Rename…, Remove…` and does not render a duplicate catalog row. Multiple saved accounts with no hosts render `Other Accounts` rows that exclude the active local account, while active local management and Add Account stay grouped under `Account > Add Account…, Rename…, Remove…`. Configured hosts keep the full `Accounts` / `More Accounts…` row design because rows expose local and remote target actions. Account row submenus must show a disabled email identity row, fall back to `No email` when the email is unknown, preserve the disabled usage row below it, and expose enabled `switchAccount:` targets in the live runtime snapshot.
- `owner_layer`: `live_ui`
- `proofs_required`: `["deterministic_ui", "live_ui"]`
- `scenarios`: `["single_account_management_menu", "other_accounts_excludes_active_local", "hosts_keep_full_accounts_section", "overflow_accounts"]`

### `menubar.custom_rows.stay_flush_with_rendered_menu_width`

- `feature`: `menubar`
- `rule`: Custom menubar rows must stay flush with the rendered menu width so hosted cards and other custom sections do not leave a visible right-side gap.
- `owner_layer`: `live_ui`
- `proofs_required`: `["live_ui"]`
- `scenarios`: `["live-menu-open"]`

### `accounts.add_account.name_dialog_cancelled`

- `feature`: `accounts`
- `rule`: Triggering `Add Account...` from the running menubar presents the name dialog and allows clean cancellation without mutating account state.
- `owner_layer`: `live_ui`
- `proofs_required`: `["live_ui"]`
- `scenarios`: `["live-add-account-name-dialog-cancelled", "add-account-name-dialog-cancelled"]`
- `event_evidence`: `["menu_action_dispatched", "add_account_name_dialog_presented", "add_account_name_dialog_cancelled"]`

### `accounts.add_account.v0_contract`

- `feature`: `accounts`
- `rule`: Add Account saves a new local account through an isolated Codex sign-in flow without switching the current local account. The flow must expose the device code in-app before browser handoff, allow safe cancellation, reject overlapping sign-in attempts without clearing the pending attempt, hydrate the newly saved inactive account with any usable rate-limit window when available, route optional local use through one success-alert decision that includes any CLI restart warning, block duplicate display names and duplicate captured identities, clean temporary auth state, and never mutate real user auth from tests unless an explicit live-auth scenario opts in.
- `owner_layer`: `integration`
- `proofs_required`: `["unit", "integration", "deterministic_ui", "live_ui"]`
- `scenarios`: `["add_account_duplicate_display_name_blocks_before_sign_in", "add_account_shows_device_code_and_copy_action", "add_account_copy_code_keeps_waiting", "add_account_saves_without_switching", "add_account_hydrates_saved_account_usage_after_save", "add_account_rejects_overlapping_sign_in_without_clearing_pending_flow", "add_account_use_on_this_mac_switches_without_second_confirmation", "add_account_cancel_cleans_up", "add_account_duplicate_identity_blocks_after_sign_in", "add_account_expired_code_allows_try_again", "add_account_failed_before_code_clears_state", "add_account_live_auth_mutation_aborts", "add_account_catalog_save_failure_does_not_switch", "add_account_quit_cleans_up", "add_account_startup_removes_stale_temp_homes"]`
- `automated_proofs`:
  - `add_account_duplicate_display_name_blocks_before_sign_in`: `AddAccountWorkflowTests.isolatedAddAccountRejectsDuplicateNameBeforeStartingLogin`
  - `add_account_shows_device_code_and_copy_action`: `MenuBarAlertFactoryTests.addAccountSignInRequestShowsDeviceCodeCopy`
  - `add_account_saves_without_switching`: `AddAccountWorkflowTests.completeIsolatedAddAccountPersistsCapturedAuthWithoutChangingActiveAccount`
  - `add_account_hydrates_saved_account_usage_after_save`: `AccountsControllerTests.completeIsolatedAddAccountHydratesNewInactiveAccountMetadata` and `HydrateSavedAccountsMetadataUseCaseTests.runBackfillsInactiveAccountsWithWeeklyOnlyRateLimits`
  - `add_account_rejects_overlapping_sign_in_without_clearing_pending_flow`: `AccountsControllerTests.startIsolatedAddAccountRejectsOverlapWithoutClearingActiveOperation`
  - `add_account_cancel_cleans_up`: `AddAccountWorkflowTests.cancelIsolatedAddAccountTerminatesLoginAndCleansTemporaryHome`
  - `add_account_duplicate_identity_blocks_after_sign_in`: `AddAccountWorkflowTests.completeIsolatedAddAccountRejectsAlreadySavedCapturedIdentity`
  - `add_account_sign_in_failures_are_account_outcomes`: `AccountActionFlowTests.promptUnavailablePreservesSanitizedFailureReason`, `AccountActionFlowTests.expiredSignInCodeOffersRetryWithOriginalName`, `AccountActionFlowTests.authCaptureFailureMapsToAccountSignInOutcome`, and `AccountActionFlowTests.loginVerificationFailureMapsToAccountSignInOutcome`
  - `add_account_live_auth_mutation_aborts`: `AddAccountWorkflowTests.completeIsolatedAddAccountAbortsWhenLiveAuthChangesDuringSignIn`
  - `add_account_catalog_save_failure_does_not_switch`: `AddAccountWorkflowTests.completeIsolatedAddAccountMapsCatalogSaveFailureAfterCapture` and `AddAccountWorkflowTests.completeIsolatedAddAccountMapsRepositorySaveFailureAfterSnapshotSave`
  - `add_account_startup_removes_stale_temp_homes`: `AppPathsTests.staleIsolatedCodexHomeCleanupRemovesOnlyOldSessionDirectories`
- `copy_or_shape_proofs`:
  - `add_account_use_on_this_mac_switches_without_second_confirmation`: `MenuBarAlertFactoryTests.addAccountSuccessRequestOffersOptionalLocalSwitch` and `MenuBarAlertFactoryTests.addAccountSuccessRequestMentionsRunningCliSessionsBeforeLocalSwitch` prove the success alert exposes the switch action and warning copy; `SwitchAccountWorkflowTests` prove the underlying switch execution path
  - `add_account_expired_code_allows_try_again`: `MenuBarAlertFactoryTests.addAccountFailureRequestsUseSpecificRecoveryCopy` proves the retry copy/actions only
  - `add_account_failed_before_code_clears_state`: `MenuBarAlertFactoryTests.addAccountFailureRequestsUseSpecificRecoveryCopy` and `MenuBarAlertFactoryTests.addAccountSignInFailureOutcomesRenderWithoutPlatformErrors` prove sign-in outcome rendering only
- `live_safe_scenarios`: `["live-add-account-name-dialog-cancelled"]`
- `manual_or_live_auth_gaps`: `["real_browser_device_auth_completion", "copy_code_clipboard_interaction", "success_alert_use_on_this_mac_coordinator_wiring", "expired_code_try_again_starts_fresh_login", "failed_before_code_state_cleanup", "app_quit_during_real_device_auth"]`

### `accounts.add_account.duplicate_name_preflight`

- `feature`: `accounts`
- `rule`: Add Account rejects duplicate saved-account names before clearing live auth, relaunching Codex, or starting a pending sign-in.
- `owner_layer`: `unit`
- `proofs_required`: `["unit"]`
- `scenarios`: `["add_account_duplicate_name_preflight"]`

### `accounts.add_account.terminal_completion_error_clears_pending_sign_in`

- `feature`: `accounts`
- `rule`: If pending Add Account completion reaches a terminal save failure, CodexPill surfaces one error and clears the pending sign-in so the monitor does not re-alert repeatedly.
- `owner_layer`: `unit`
- `proofs_required`: `["unit"]`
- `scenarios`: `["add_account_terminal_completion_error"]`

### `accounts.add_account.isolated_failure_cleanup`

- `feature`: `accounts`
- `rule`: Isolated Add Account must terminate and clean temporary `CODEX_HOME` state on cancellation, timeout, duplicate captured identity, live-auth mutation, and save failure. Retry after an expired code starts a fresh isolated login; stale isolated homes from interrupted attempts are removed on next app launch.
- `owner_layer`: `integration`
- `proofs_required`: `["unit", "integration"]`
- `scenarios`: `["isolated_add_account_cancel_cleanup", "isolated_add_account_duplicate_identity", "isolated_add_account_live_auth_changed", "isolated_add_account_catalog_save_failure", "stale_isolated_codex_home_cleanup"]`

### `accounts.remove_account.signs_out_active_targets_before_delete`

- `feature`: `accounts`
- `rule`: Removing a saved account must not leave that account actively logged in on a target CodexPill controls. If the account is active on This Mac, CodexPill signs out local auth and relaunches Codex before deleting the saved snapshot. If the account is active on a connected verified remote host, CodexPill signs out that host before deleting the saved snapshot. If any required sign-out fails, the saved account remains in the catalog and the failure is surfaced.
- `owner_layer`: `integration`
- `proofs_required`: `["unit", "integration", "live_ui"]`
- `scenarios`: `["remove_account_active_local_session_signs_out_before_delete", "remove_account_active_remote_session_signs_out_before_delete", "remove_account_signout_failure_keeps_saved_account", "remove_account_inactive_snapshot_delete"]`
- `automated_proofs`:
  - `remove_account_active_local_session_signs_out_before_delete`: `DeleteSavedAccountUseCaseTests.runSignsOutLocalAccountBeforeDeletingWhenRequested` and `MenuBarLiveValidationTests.removeAccountSignsOutLocalAndRemoteTargetsBeforeDeletingSavedAccount`
  - `remove_account_active_remote_session_signs_out_before_delete`: `ValidationRemoteHostClientTests.signOutClearsActiveAccountButKeepsInstalledSnapshot`, `SSHRemoteHostClientTests.signOutRemovesRemoteAuthPath`, and `MenuBarLiveValidationTests.removeAccountSignsOutLocalAndRemoteTargetsBeforeDeletingSavedAccount`
  - `remove_account_signout_failure_keeps_saved_account`: `DeleteSavedAccountUseCaseTests.runDoesNotDeleteSnapshotWhenLocalSignOutFails`
  - `remove_account_inactive_snapshot_delete`: `DeleteSavedAccountUseCaseTests.runDeletesSnapshotPersistsFilteredAccountsAndRecomputesActiveAccount`

### `accounts.scheduled_refresh.requested_and_completed`

- `feature`: `accounts`
- `rule`: The scheduled refresh timer refreshes the active local account without rotating saved inactive snapshots through the real local auth file. If the active local account resolves to the same saved account but the live auth fingerprint changed, CodexPill relinks that saved account snapshot from current live auth before persisting refreshed metadata. The running app emits completion or failure proof without surfacing a blocking alert. Failure events must include the sanitized refresh error so app-server contract drift is diagnosable from validation artifacts. Remote-host refresh behavior is covered by the remote-host invariants, not by this scheduled-refresh proof.
- `owner_layer`: `live_ui`
- `proofs_required`: `["integration", "live_ui"]`
- `scenarios`: `["scheduled_refresh"]`
- `event_evidence`: `["scheduled_refresh_requested", "scheduled_refresh_completed", "scheduled_refresh_failed"]`
- `snapshot_evidence`: `account_before`, `account_after`, and `ui_after_refresh` at `evidence/ui-after-refresh.json`
- `identity_fields`: `activeAccountId`, `savedAccountIds`, `savedAccountNames`, `savedAccountCount`
- `automated_proofs`: `["RefreshActiveAccountUseCaseTests.runRelinksSavedSnapshotWhenLiveAuthFingerprintChangedForSameAccount"]`

### `accounts.scheduled_refresh.no_blocking_alert_visible`

- `feature`: `accounts`
- `rule`: Completed scheduled refresh proof must assert `hasBlockingAlert == false` from the `ui_after_refresh` snapshot evidence.
- `owner_layer`: `live_ui`
- `proofs_required`: `["live_ui"]`
- `scenarios`: `["scheduled_refresh"]`
- `snapshot_evidence`: `ui_after_refresh`

### `accounts.app_server.rate_limit_refresh_errors_are_retryable_and_diagnosable`

- `feature`: `accounts`
- `rule`: App-server reads must handle JSON-RPC notification frames, surface JSON-RPC error messages from account or rate-limit responses, and retry transient rate-limit failures. When a refresh can only preserve old rate limits, CodexPill must not advance the rate-limit freshness timestamp.
- `owner_layer`: `integration`
- `proofs_required`: `["integration"]`
- `scenarios`: `["app_server_json_rpc_error", "app_server_transient_rate_limit_retry", "preserve_stale_rate_limits_without_marking_fresh", "invalidated_token_error_uses_actionable_copy"]`
- `automated_proofs`: `["MenuBarAlertFactoryTests.errorRequestMapsInvalidatedTokenBackendErrorsToActionableCopy"]`

### `accounts.rate_limits.classify_windows_by_duration`

- `feature`: `accounts`
- `rule`: CodexPill must not assume App Server `primary` always means session and `secondary` always means weekly. Session and weekly presentation, status-item indicators, and availability decisions classify returned windows by `windowDurationMins`; weekly-length windows such as Free-account `primary` windows render as weekly usage, not session usage. Legacy payloads without window durations may fall back to positional mapping.
- `owner_layer`: `domain`
- `proofs_required`: `["unit"]`
- `scenarios`: `["free_weekly_only_primary_window", "legacy_positional_rate_limit_payload"]`
- `automated_proofs`: `["CodexRateLimitWindowTests.rateLimitSnapshotClassifiesWindowsByDurationInsteadOfPosition", "CodexRateLimitWindowTests.rateLimitSnapshotKeepsLegacyPositionalFallbackWhenDurationsAreMissing", "AccountAvailabilityTests.availabilityServiceTreatsWeeklyOnlyAccountAsAvailableWhenWeeklyHasHeadroom", "MenuBarAccountPresentationTests.compactUsageSummaryMapsWeeklyDurationPrimaryWindowToWeeklyLabel"]`

### `accounts.effective_plan.maps_app_server_plan_codes`

- `feature`: `accounts`
- `rule`: CodexPill maps all known App Server plan codes to user-facing display names. `prolite` displays and persists as Pro x5, `pro` displays and persists as Pro x20, business aliases display as Business, and `team` displays as Team. When refreshed account metadata still says Plus but fresh rate-limit metadata reports an upgraded Pro-family Codex plan, CodexPill keeps that fresh rate-limit plan. `unknown` is treated as missing when choosing an effective plan. Other account plan disagreements must keep the account metadata plan until the backend plan taxonomy is understood.
- `owner_layer`: `unit`
- `proofs_required`: `["unit"]`
- `scenarios`: `["known_app_server_plan_display_names", "plus_prolite_displays_as_pro_x5", "unknown_falls_back_to_known_plan", "team_prolite_does_not_downgrade"]`

### `accounts.switch_account.menu_action_changes_active_account`

- `feature`: `accounts`
- `rule`: Selecting an inactive account emits the switch workflow event sequence and changes the active-account snapshot. For the selected runtime validation flow, Seal runner artifacts are the authoritative pass/fail gate.
- `owner_layer`: `seal_run`
- `proofs_required`: `["integration", "seal_run"]`
- `scenarios`: `["live-account-switch", "switch-account-changes-active-account"]`
- `event_evidence`: `["menu_action_dispatched", "switch_confirmation_presented", "switch_confirmation_accepted", "switch_workflow_started", "active_account_changed"]`
- `snapshot_evidence`: `["account_before", "account_after"]`
- `seal_only_runtime_validation`: `make verify-account-switch-seal` runs the CodexPill-owned explicit adapter through `seal run`. Seal outputs under `proof/`, `reports/`, and `adapter/` are authoritative; CodexPill's `codexpill-summary.json` is compatibility-only.

### `menubar.text_on_hover.stays_visible_inside_resized_bounds`

- `feature`: `menubar`
- `rule`: Text-on-hover mode remains visible while the pointer stays inside the resized status item after the title appears.
- `owner_layer`: `unit`
- `proofs_required`: `["unit", "live_ui"]`
- `scenarios`: `["hover_enter", "hover_resize", "hover_exit"]`
- `event_evidence`: `["status_item_hover_entered", "status_item_title_became_visible", "status_item_hover_exit_scheduled", "status_item_hover_exited", "status_item_title_hidden"]`

### `status_bar.reveal_shortcut.temporarily_shows_label`

- `feature`: `status-bar`
- `rule`: The configured global shortcut reveals the status item label temporarily without opening the menu or changing the saved `Menu Bar Label` display mode. `Icon Only` and `Text on Hover` can reveal via shortcut, `Icon + Text` remains visible, pressing the shortcut again while the temporary reveal is active collapses the label, and failed registration keeps the previous working shortcut.
- `owner_layer`: `unit`
- `proofs_required`: `["unit", "deterministic_ui", "manual"]`
- `scenarios`: `["shortcut_reveal_icon_only", "shortcut_reveal_text_on_hover", "shortcut_reveal_icon_and_text", "shortcut_reveal_toggle_collapse", "shortcut_registration_failure", "shortcut_default_restore"]`
- `automated_proofs`: `["MenuBarMenuStateTests", "StatusItemRuntimeTests", "StatusItemSettingsStoreTests", "GlobalShortcutRuntimeTests"]`
- `manual_or_os_gaps`: `["trigger_default_shortcut_from_another_app", "confirm_local_shortcut_conflicts_on_real_machine"]`

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
- `rule`: The selected Add Host validation-failure runtime flow records that destination validation started, failed in a handled way, and left the host catalog unchanged.
- `owner_layer`: `seal_runtime`
- `proofs_required`: `["seal_runtime"]`
- `scenarios`: `["live-add-host-destination-validation-failed", "add-host-destination-validation-failed"]`
- `event_evidence`: `["menu_action_dispatched", "add_host_setup_presented", "add_host_validation_started", "add_host_validation_failed"]`
- `seal_only_runtime_validation`: `make verify-add-host-validation-failure-seal` runs the CodexPill-owned explicit adapter through `seal run`. Seal outputs under `proof/`, `reports/`, and `adapter/` are authoritative; CodexPill's `codexpill-summary.json` is compatibility-only. The deterministic proof records before/after host catalog snapshots, handled validation failure, and sanitized domain feedback without raw SSH output.

### `hosts.switch_workflow.installs_missing_accounts_before_switch`

- `feature`: `hosts`
- `rule`: Switching an account on a remote host installs the snapshot first when it is missing or stale, skips installation only when the remote snapshot hash matches the current local saved snapshot, and stops cleanly on install or switch failures. If the selected account is the active local account, CodexPill preflights active-account refresh and relinks the saved snapshot from current local auth before remote install/switch so a stale saved refresh token is not copied to the host. If the status refresh fails but live auth identity still uniquely matches the selected saved account, CodexPill still relinks the saved snapshot from live auth before switching.
- `owner_layer`: `integration`
- `proofs_required`: `["integration"]`
- `scenarios`: `["missing_remote_snapshot", "installed_remote_snapshot", "stale_remote_snapshot", "active_local_snapshot_relinked_before_remote_switch", "active_local_status_refresh_failed_snapshot_relinked_by_live_identity", "install_failure", "switch_failure"]`
- `automated_proofs`: `["SwitchAccountOnHostWorkflowTests", "SSHRemoteHostClientTests.installationStateTreatsStaleRemoteSnapshotHashAsMissing", "AccountsControllerTests.switchToAccountOnHostRelinksActiveSnapshotBeforeRemoteInstall", "AccountsControllerTests.switchToAccountOnHostRelinksActiveSnapshotWhenStatusRefreshFailsButLiveIdentityStillMatches"]`

### `hosts.switch_account_on_host.changes_remote_active_account`

- `feature`: `hosts`
- `rule`: Selecting `Switch on <host>` from a saved account submenu dispatches the host-targeted switch workflow and updates the host's active account card to the chosen account.
- `owner_layer`: `live_ui`
- `proofs_required`: `["integration", "live_ui"]`
- `scenarios`: `["live-remote-host-switch"]`
- `event_evidence`: `["menu_action_dispatched", "remote_host_switch_started", "remote_host_active_account_changed"]`

### `hosts.refresh_failure.preserves_fallback_state_and_marks_disconnected`

- `feature`: `hosts`
- `rule`: When CodexPill restores a persisted remote host and the remote refresh fails, it preserves the last known remote account fallback while marking the host disconnected and hiding the host from active account cards.
- `owner_layer`: `live_ui`
- `proofs_required`: `["live_ui"]`
- `scenarios`: `["persisted_host_refresh_failure"]`

### `accounts.active_cards.group_local_and_remote_same_account`

- `feature`: `accounts`
- `rule`: If the same saved account is active locally and on one or more connected verified remote hosts, CodexPill renders one `Active Account` card with compact location context such as `This Mac + debian-vm`; it must not render a duplicate remote active card for the same saved account.
- `owner_layer`: `unit`
- `proofs_required`: `["unit", "deterministic_ui"]`
- `scenarios`: `["hosted_menu_local_and_remote_same_account", "hosted_menu_with_host", "hosted_menu_disconnected_host"]`

### `accounts.active_cards.render_verified_active_targets_only`

- `feature`: `accounts`
- `rule`: The top active-account section renders local and connected verified remote active accounts as one collection. Different active accounts render as separate cards under `Active Accounts`; the same remote account used on multiple hosts is grouped into one card with joined host context. Unreachable, unverified, verifying, failed, or missing-active-account hosts stay persisted but do not render active account cards.
- `owner_layer`: `live_ui`
- `proofs_required`: `["deterministic_ui", "live_ui"]`
- `scenarios`: `["hosted_menu_multiple_hosts", "hosted_menu_with_host", "mixed_persisted_host_restore"]`

### `hosts.disconnected_hosts.remain_targetable_without_active_card`

- `feature`: `hosts`
- `rule`: A disconnected configured host remains available under `Hosts` and per-account remote switch targets, but it does not render in the primary `Active Account(s)` section.
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
- `rule`: Notification mode toggles and per-account dedupe state persist across launches through `CodexPillSettingsStore`, so ignored notifications do not repeat after restart and activation re-arm state survives process restarts.
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
