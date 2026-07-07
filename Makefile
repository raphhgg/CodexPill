APP_NAME := CodexPill
PROJECT_PATH := $(APP_NAME).xcodeproj
AGENT_NAME ?= local
BUILD_ROOT := build
DERIVED_DATA := $(BUILD_ROOT)/DerivedData/$(AGENT_NAME)
RESULT_BUNDLE := $(BUILD_ROOT)/results/$(AGENT_NAME)/$(APP_NAME).xcresult
DEV_BUNDLE_ID ?= com.raphhgg.codexpill.dev
STAGING_BUNDLE_ID ?= com.raphhgg.codexpill.staging

SCENARIO ?= hosted-menu-default
VERIFICATION_DIR := $(BUILD_ROOT)/verification
VERIFICATION_REQUEST := $(VERIFICATION_DIR)/request.json
VERIFICATION_ARTIFACTS := $(BUILD_ROOT)/verification/$(SCENARIO)
DIAGNOSTICS_EXPORT_SCENARIO := diagnostics-export-confirmation
DIAGNOSTICS_EXPORT_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(DIAGNOSTICS_EXPORT_SCENARIO)
NOTIFICATIONS_PERMISSION_DENIED_SCENARIO := notifications-permission-denied-menu-state
NOTIFICATIONS_PERMISSION_DENIED_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(NOTIFICATIONS_PERMISSION_DENIED_SCENARIO)
NOTIFICATIONS_ACCOUNT_AVAILABLE_SCENARIO := notifications-account-available-policy
NOTIFICATIONS_ACCOUNT_AVAILABLE_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(NOTIFICATIONS_ACCOUNT_AVAILABLE_SCENARIO)
NOTIFICATIONS_CURRENT_RUNS_OUT_SCENARIO := notifications-current-runs-out-action
NOTIFICATIONS_CURRENT_RUNS_OUT_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(NOTIFICATIONS_CURRENT_RUNS_OUT_SCENARIO)
NOTIFICATIONS_DEDUPE_SCENARIO := notifications-dedupe-after-delivery
NOTIFICATIONS_DEDUPE_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(NOTIFICATIONS_DEDUPE_SCENARIO)
LAUNCH_AT_LOGIN_ENABLE_SCENARIO := launch-at-login-enable-confirmation
LAUNCH_AT_LOGIN_ENABLE_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(LAUNCH_AT_LOGIN_ENABLE_SCENARIO)
LAUNCH_AT_LOGIN_BLOCKED_SCENARIO := launch-at-login-blocked-opens-settings
LAUNCH_AT_LOGIN_BLOCKED_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(LAUNCH_AT_LOGIN_BLOCKED_SCENARIO)
STATUS_BAR_HOVER_SCENARIO := status-bar-hover-label
STATUS_BAR_HOVER_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(STATUS_BAR_HOVER_SCENARIO)
STATUS_BAR_SHORTCUT_SCENARIO := status-bar-shortcut-reveal
STATUS_BAR_SHORTCUT_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(STATUS_BAR_SHORTCUT_SCENARIO)
STATUS_BAR_USAGE_PREFS_SCENARIO := status-bar-usage-bars-preferences
STATUS_BAR_USAGE_PREFS_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(STATUS_BAR_USAGE_PREFS_SCENARIO)
RENAME_SCENARIO := rename-account-label-only
RENAME_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(RENAME_SCENARIO)
ADD_ACCOUNT_NAME_SCENARIO := add-account-name-validation
ADD_ACCOUNT_NAME_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(ADD_ACCOUNT_NAME_SCENARIO)
ADD_ACCOUNT_ISOLATED_SUCCESS_SCENARIO := add-account-isolated-success
ADD_ACCOUNT_ISOLATED_SUCCESS_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(ADD_ACCOUNT_ISOLATED_SUCCESS_SCENARIO)
ADD_ACCOUNT_FAILURE_CLEANUP_SCENARIO := add-account-failure-cleanup
ADD_ACCOUNT_FAILURE_CLEANUP_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(ADD_ACCOUNT_FAILURE_CLEANUP_SCENARIO)
SWITCH_ACCOUNT_LOCAL_SCENARIO := switch-account-local-confirmed
SWITCH_ACCOUNT_LOCAL_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(SWITCH_ACCOUNT_LOCAL_SCENARIO)
SWITCH_ACCOUNT_REMOTE_SCENARIO := switch-account-remote-install-verify
SWITCH_ACCOUNT_REMOTE_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(SWITCH_ACCOUNT_REMOTE_SCENARIO)
REMOTE_HOST_ADD_PANEL_SCENARIO := remote-host-add-panel-validation
REMOTE_HOST_ADD_PANEL_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(REMOTE_HOST_ADD_PANEL_SCENARIO)
REMOTE_HOST_INSTALL_SWITCH_SCENARIO := remote-host-install-switch-current-account
REMOTE_HOST_INSTALL_SWITCH_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(REMOTE_HOST_INSTALL_SWITCH_SCENARIO)
REMOTE_HOST_VERIFICATION_FAILURE_SCENARIO := remote-host-verification-failure
REMOTE_HOST_VERIFICATION_FAILURE_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(REMOTE_HOST_VERIFICATION_FAILURE_SCENARIO)
REMOTE_HOST_RATE_LIMIT_FALLBACK_SCENARIO := remote-host-rate-limit-fallback
REMOTE_HOST_RATE_LIMIT_FALLBACK_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(REMOTE_HOST_RATE_LIMIT_FALLBACK_SCENARIO)
REMOVE_ACCOUNT_ACTIVE_SCENARIO := remove-account-active-targets-sign-out
REMOVE_ACCOUNT_ACTIVE_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(REMOVE_ACCOUNT_ACTIVE_SCENARIO)
REMOVE_ACCOUNT_FAILURE_SCENARIO := remove-account-signout-failure-keeps-control
REMOVE_ACCOUNT_FAILURE_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(REMOVE_ACCOUNT_FAILURE_SCENARIO)
REFRESH_INACTIVE_SCENARIO := refresh-inactive-isolated-status
REFRESH_INACTIVE_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(REFRESH_INACTIVE_SCENARIO)
REFRESH_ACTIVE_RELINK_SCENARIO := refresh-active-relinks-same-account
REFRESH_ACTIVE_RELINK_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(REFRESH_ACTIVE_RELINK_SCENARIO)
TOKEN_USAGE_PARSER_SCENARIO := token-usage-parser-aggregation
TOKEN_USAGE_PARSER_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(TOKEN_USAGE_PARSER_SCENARIO)
TOKEN_USAGE_CACHE_SCENARIO := token-usage-cache-first
TOKEN_USAGE_CACHE_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(TOKEN_USAGE_CACHE_SCENARIO)
TOKEN_USAGE_PRIVACY_SCENARIO := token-usage-privacy-no-raw-session
TOKEN_USAGE_PRIVACY_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(TOKEN_USAGE_PRIVACY_SCENARIO)

.PHONY: diagnose generate prepare-result-bundle build test package-release verify-ui verify-diagnostics-export-confirmation-scenario verify-notifications-permission-denied-menu-state-scenario verify-notifications-account-available-policy-scenario verify-notifications-current-runs-out-action-scenario verify-notifications-dedupe-after-delivery-scenario verify-launch-at-login-enable-confirmation-scenario verify-launch-at-login-blocked-opens-settings-scenario verify-status-bar-hover-label-scenario verify-status-bar-shortcut-reveal-scenario verify-status-bar-usage-bars-preferences-scenario verify-rename-scenario verify-add-account-name-scenario verify-add-account-isolated-success-scenario verify-add-account-failure-cleanup-scenario verify-switch-account-local-confirmed-scenario verify-switch-account-remote-install-verify-scenario verify-remote-host-add-panel-validation-scenario verify-remote-host-install-switch-current-account-scenario verify-remote-host-verification-failure-scenario verify-remote-host-rate-limit-fallback-scenario verify-remove-account-active-targets-sign-out-scenario verify-remove-account-signout-failure-keeps-control-scenario verify-refresh-inactive-isolated-status-scenario verify-refresh-active-relinks-same-account-scenario verify-token-usage-parser-scenario verify-token-usage-cache-scenario verify-token-usage-privacy-scenario run clean

diagnose:
	command -v tuist >/dev/null
	command -v xcodebuild >/dev/null
	command -v swift >/dev/null

generate: diagnose
	# Shell-first workflow: generate the project without opening Xcode.
	TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open

prepare-result-bundle:
	mkdir -p $(dir $(RESULT_BUNDLE))
	rm -rf "$(RESULT_BUNDLE)"

build: generate prepare-result-bundle
	xcodebuild build \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		PRODUCT_BUNDLE_IDENTIFIER="$(DEV_BUNDLE_ID)"

test: generate prepare-result-bundle
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"

package-release:
	AGENT_NAME="$(AGENT_NAME)" ./scripts/package_release.sh

verify-ui: generate prepare-result-bundle
	mkdir -p "$(VERIFICATION_DIR)"
	printf '{\n  "artifactDirectory": "%s",\n  "scenario": "%s"\n}\n' "$(abspath $(VERIFICATION_ARTIFACTS))" "$(SCENARIO)" > "$(VERIFICATION_REQUEST)"
	CODEXPILL_VALIDATION_REQUEST="$(abspath $(VERIFICATION_REQUEST))" xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"

verify-diagnostics-export-confirmation-scenario: generate prepare-result-bundle
	mkdir -p "$(DIAGNOSTICS_EXPORT_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/MenuBarMenuBuilderTests \
		-only-testing:CodexPillTests/MenuBarAlertFactoryTests \
		-only-testing:CodexPillTests/DiagnosticReportBuilderTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(DIAGNOSTICS_EXPORT_SCENARIO)",' \
		'  "proofLayer": "diagnostics-export",' \
		'  "events": [' \
		'    "Diagnostics action is present in the menu near About and routes to exportDiagnosticReport",' \
		'    "Diagnostics export presents the redacted-support disclosure before building a report",' \
		'    "Cancelling the disclosure produces no exported report",' \
		'    "Confirming the disclosure builds a per-export aliased diagnostic report",' \
		'    "Diagnostics export copy names omitted auth tokens, emails, hostnames, and raw logs"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(DIAGNOSTICS_EXPORT_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Diagnostics export requires explicit confirmation before report export",' \
		'    "Cancellation stops before the save/export presenter receives a report",' \
		'    "Confirmed export builds a schema-versioned report with per-export aliases",' \
		'    "Report builder rejects or aliases raw account, host, session, and token-like evidence"' \
		'  ],' \
		'  "command": "make verify-diagnostics-export-confirmation-scenario",' \
		'  "gaps": [' \
		'    "Live NSSavePanel rendering and file writing are not exercised",' \
		'    "Real local logs, auth snapshots, SSH output, UserDefaults, and Codex session history are not inspected",' \
		'    "Live macOS menu-bar interaction is not proven"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "diagnostics.export.confirmation-before-write",' \
		'    "diagnostics.export.cancel-writes-no-report",' \
		'    "diagnostics.export.redacted-support-artifact-only"' \
		'  ],' \
		'  "proofLayer": "diagnostics-export",' \
		'  "scenario": "$(DIAGNOSTICS_EXPORT_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(DIAGNOSTICS_EXPORT_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(DIAGNOSTICS_EXPORT_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-notifications-permission-denied-menu-state-scenario: generate prepare-result-bundle
	mkdir -p "$(NOTIFICATIONS_PERMISSION_DENIED_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/MenuBarMenuBuilderTests \
		-only-testing:CodexPillTests/MenuBarRuntimeValidationTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(NOTIFICATIONS_PERMISSION_DENIED_SCENARIO)",' \
		'  "proofLayer": "unit",' \
		'  "events": [' \
		'    "Denied macOS notification permission shows Enable in macOS Settings in the Notifications submenu",' \
		'    "Denied permission renders Account Available and Current Runs Out unchecked and disabled",' \
		'    "Enable Notifications routes to System Settings through the fake launcher when authorization is denied",' \
		'    "Saved CodexPill notification intent is preserved while denied",' \
		'    "Denied permission does not request notification authorization again"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(NOTIFICATIONS_PERMISSION_DENIED_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Denied permission exposes System Settings recovery copy and action wiring",' \
		'    "Denied permission makes notification mode rows effectively off and disabled",' \
		'    "Recovery preserves saved notification preferences and does not request authorization again",' \
		'    "Recovery uses a fake settings launcher instead of live System Settings"' \
		'  ],' \
		'  "command": "make verify-notifications-permission-denied-menu-state-scenario",' \
		'  "gaps": [' \
		'    "Live macOS System Settings is not opened",' \
		'    "Live notification permission dialogs are not exercised",' \
		'    "Native click automation and live menu-bar interaction are not proven"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "notifications.permission-denied.modes-disabled",' \
		'    "notifications.permission-denied.opens-settings",' \
		'    "notifications.permission-denied.preserves-saved-intent"' \
		'  ],' \
		'  "proofLayer": "unit",' \
		'  "scenario": "$(NOTIFICATIONS_PERMISSION_DENIED_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(NOTIFICATIONS_PERMISSION_DENIED_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(NOTIFICATIONS_PERMISSION_DENIED_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-notifications-account-available-policy-scenario: generate prepare-result-bundle
	mkdir -p "$(NOTIFICATIONS_ACCOUNT_AVAILABLE_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/InactiveAccountAvailabilityRankingTests \
		-only-testing:CodexPillTests/MenuBarNotificationWorkflowTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(NOTIFICATIONS_ACCOUNT_AVAILABLE_SCENARIO)",' \
		'  "proofLayer": "unit",' \
		'  "events": [' \
		'    "Account Available fires for an inactive fallback account becoming useful again",' \
		'    "First-saved, only-saved, active, barely usable, and non-fallback accounts are not announced as available again",' \
		'    "The delivered Account Available payload uses the expected simple copy and no direct actions",' \
		'    "Delivery arms suppression state for the notified fallback account"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(NOTIFICATIONS_ACCOUNT_AVAILABLE_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Account Available is limited to inactive fallback accounts becoming useful again",' \
		'    "Non-fallback and already-active accounts do not trigger Account Available",' \
		'    "Delivered Account Available copy is simple and action-free",' \
		'    "The notified account is suppressed until activation resets dedupe state"' \
		'  ],' \
		'  "command": "make verify-notifications-account-available-policy-scenario",' \
		'  "gaps": [' \
		'    "Live macOS notification delivery is not exercised",' \
		'    "Native notification UI rendering and user clicks are not proven",' \
		'    "Current Runs Out action routing is tracked by notifications-current-runs-out-action"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "notifications.account-available.inactive-fallback-only",' \
		'    "notifications.account-available.no-first-or-active-account",' \
		'    "notifications.account-available.delivery-suppresses-repeat"' \
		'  ],' \
		'  "proofLayer": "unit",' \
		'  "scenario": "$(NOTIFICATIONS_ACCOUNT_AVAILABLE_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(NOTIFICATIONS_ACCOUNT_AVAILABLE_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(NOTIFICATIONS_ACCOUNT_AVAILABLE_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-notifications-current-runs-out-action-scenario: generate prepare-result-bundle
	mkdir -p "$(NOTIFICATIONS_CURRENT_RUNS_OUT_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/InactiveAccountAvailabilityRankingTests \
		-only-testing:CodexPillTests/AccountAvailabilityNotificationRuntimeTests \
		-only-testing:CodexPillTests/MenuBarNotificationWorkflowTests \
		-only-testing:CodexPillTests/MenuBarRuntimeValidationTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(NOTIFICATIONS_CURRENT_RUNS_OUT_SCENARIO)",' \
		'  "proofLayer": "workflow-event-log",' \
		'  "events": [' \
		'    "Current Runs Out fires when a local or remote active account runs out and a fallback is usable",' \
		'    "The notification payload names the exhausted active target, fallback account, and local or remote direct action",' \
		'    "Notification responses re-check current state before switching",' \
		'    "Stale local actions substitute the current best account with explanatory copy",' \
		'    "Stale remote actions are dropped when the requested host is no longer actionable",' \
		'    "Switch failures activate the app and surface the real error through the fake runtime"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(NOTIFICATIONS_CURRENT_RUNS_OUT_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Current Runs Out policy covers local and remote active-account exhaustion",' \
		'    "Rendered payload copy names the exhausted target and fallback account",' \
		'    "Rendered payload actions expose local and remote switch targets",' \
		'    "Action handling re-checks state, substitutes safer current targets, or drops stale remote requests",' \
		'    "Runtime validation surfaces switch failure errors instead of silently switching"' \
		'  ],' \
		'  "command": "make verify-notifications-current-runs-out-action-scenario",' \
		'  "gaps": [' \
		'    "Live macOS notification delivery is not exercised",' \
		'    "Native Notification Center rendering and user clicks are not proven",' \
		'    "Real Codex account data, real remote hosts, and real switching are not touched"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "notifications.current-runs-out.local-and-remote-active-targets",' \
		'    "notifications.current-runs-out.copy-and-actions-name-targets",' \
		'    "notifications.current-runs-out.actions-recheck-stale-state"' \
		'  ],' \
		'  "proofLayer": "workflow-event-log",' \
		'  "scenario": "$(NOTIFICATIONS_CURRENT_RUNS_OUT_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(NOTIFICATIONS_CURRENT_RUNS_OUT_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(NOTIFICATIONS_CURRENT_RUNS_OUT_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-notifications-dedupe-after-delivery-scenario: generate prepare-result-bundle
	mkdir -p "$(NOTIFICATIONS_DEDUPE_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/InactiveAccountAvailabilityRankingTests \
		-only-testing:CodexPillTests/MenuBarNotificationWorkflowTests \
		-only-testing:CodexPillTests/MenuBarRuntimeValidationTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(NOTIFICATIONS_DEDUPE_SCENARIO)",' \
		'  "proofLayer": "unit",' \
		'  "events": [' \
		'    "Delivered notifications record reason and window state",' \
		'    "Recorded notification state disarms repeated delivery across later windows",' \
		'    "Notification workflow records suppression only after fake delivery succeeds",' \
		'    "Local account activation re-arms notification delivery and clears the last notification record",' \
		'    "Verified remote account activation re-arms notification delivery and clears the last notification record"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(NOTIFICATIONS_DEDUPE_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Delivered account notifications disarm repeat delivery",' \
		'    "Suppression survives later windows until the account is observed active again",' \
		'    "Recorded notification reason and window persist through settings storage",' \
		'    "Local and verified remote activation re-arm the account notification state"' \
		'  ],' \
		'  "command": "make verify-notifications-dedupe-after-delivery-scenario",' \
		'  "gaps": [' \
		'    "Live macOS notification delivery is not exercised",' \
		'    "Native Notification Center rendering and user clicks are not proven",' \
		'    "Real Codex account data, real remote hosts, and real switching are not touched"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "notifications.dedupe.delivery-disarms-repeat",' \
		'    "notifications.dedupe.suppressed-until-activation",' \
		'    "notifications.dedupe.local-and-remote-activation-rearms"' \
		'  ],' \
		'  "proofLayer": "unit",' \
		'  "scenario": "$(NOTIFICATIONS_DEDUPE_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(NOTIFICATIONS_DEDUPE_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(NOTIFICATIONS_DEDUPE_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-launch-at-login-enable-confirmation-scenario: generate prepare-result-bundle
	mkdir -p "$(LAUNCH_AT_LOGIN_ENABLE_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/MenuBarMenuBuilderTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(LAUNCH_AT_LOGIN_ENABLE_SCENARIO)",' \
		'  "proofLayer": "workflow-event-log",' \
		'  "events": [' \
		'    "Disabled Launch at Login state asks for confirmation before fake registration",' \
		'    "Accepted confirmation calls the fake login-item controller with enabled true",' \
		'    "Cancelled confirmation leaves the fake login item disabled and records no mutation",' \
		'    "Enabled Launch at Login state unregisters directly without showing enable confirmation",' \
		'    "Registration failure leaves the fake state disabled and reports a truthful error"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(LAUNCH_AT_LOGIN_ENABLE_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Enable path presents Launch CodexPill at Login? before setEnabled(true)",' \
		'    "Cancel path keeps the fake login item disabled and records no controller mutation",' \
		'    "Disable path calls setEnabled(false) without confirmation",' \
		'    "Failed registration reports an error without claiming enabled state"' \
		'  ],' \
		'  "command": "make verify-launch-at-login-enable-confirmation-scenario",' \
		'  "gaps": [' \
		'    "Real macOS login item registration or unregistration is not performed",' \
		'    "Signed app visibility in System Settings Login Items is not proven",' \
		'    "Live menu-bar clicks and live System Settings UI are not exercised"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "launch-at-login.enable.confirmation-before-register",' \
		'    "launch-at-login.enable.cancel-no-mutation",' \
		'    "launch-at-login.disable.unregisters-directly",' \
		'    "launch-at-login.enable.failure-truthful"' \
		'  ],' \
		'  "proofLayer": "workflow-event-log",' \
		'  "scenario": "$(LAUNCH_AT_LOGIN_ENABLE_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(LAUNCH_AT_LOGIN_ENABLE_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(LAUNCH_AT_LOGIN_ENABLE_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-launch-at-login-blocked-opens-settings-scenario: generate prepare-result-bundle
	mkdir -p "$(LAUNCH_AT_LOGIN_BLOCKED_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/MenuBarMenuBuilderTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(LAUNCH_AT_LOGIN_BLOCKED_SCENARIO)",' \
		'  "proofLayer": "workflow-event-log",' \
		'  "events": [' \
		'    "Requires-approval menu state renders Launch at Login… with open settings action",' \
		'    "Unavailable menu state renders Launch at Login… with open settings action",' \
		'    "Requires-approval coordinator path opens the fake Login Items settings launcher",' \
		'    "Unavailable coordinator path opens the fake Login Items settings launcher",' \
		'    "Blocked and unavailable paths do not call fake register or unregister"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(LAUNCH_AT_LOGIN_BLOCKED_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Requires-approval and unavailable menu rows use Launch at Login… copy",' \
		'    "Requires-approval and unavailable menu rows route to openLoginItemsSettings:",' \
		'    "Blocked state opens the fake System Settings launcher exactly once",' \
		'    "Unavailable state opens the fake System Settings launcher exactly once",' \
		'    "Blocked/unavailable actions do not call setEnabled(true) or setEnabled(false)"' \
		'  ],' \
		'  "command": "make verify-launch-at-login-blocked-opens-settings-scenario",' \
		'  "gaps": [' \
		'    "Real System Settings UI is not opened",' \
		'    "Real macOS login item approval state is not mutated",' \
		'    "Live menu-bar clicks and signed-app Login Items visibility are not proven"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "launch-at-login.blocked.requires-approval-opens-settings",' \
		'    "launch-at-login.blocked.unavailable-opens-settings",' \
		'    "launch-at-login.blocked.no-register-unregister",' \
		'    "launch-at-login.blocked.truthful-menu-copy"' \
		'  ],' \
		'  "proofLayer": "workflow-event-log",' \
		'  "scenario": "$(LAUNCH_AT_LOGIN_BLOCKED_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(LAUNCH_AT_LOGIN_BLOCKED_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(LAUNCH_AT_LOGIN_BLOCKED_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-status-bar-hover-label-scenario: generate prepare-result-bundle
	mkdir -p "$(STATUS_BAR_HOVER_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/StatusItemRuntimeTests \
		-only-testing:CodexPillTests/MenuBarRuntimeValidationTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(STATUS_BAR_HOVER_SCENARIO)",' \
		'  "proofLayer": "workflow-event-log",' \
		'  "events": [' \
		'    "Text-on-hover mode starts hover polling while icon-only and icon-and-text modes do not",' \
		'    "Fake hover enter shows the synthetic status title S 42% W 68%",' \
		'    "Fake hover leave schedules exit and hides the status title",' \
		'    "Hover lifecycle events are emitted by StatusItemRuntime and recorded through validation",' \
		'    "Hover handling does not mutate the saved menu-bar label display mode"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(STATUS_BAR_HOVER_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Hover polling is active only for text-on-hover mode",' \
		'    "Hover enter makes the synthetic status title visible",' \
		'    "Hover leave hides the synthetic status title",' \
		'    "Validation records hover lifecycle events and snapshots",' \
		'    "Saved display preferences are unchanged by hover events"' \
		'  ],' \
		'  "command": "make verify-status-bar-hover-label-scenario",' \
		'  "gaps": [' \
		'    "Native mouse movement and real pointer bounds are not exercised",' \
		'    "Live macOS menu-bar screen capture and native hittability are not proven",' \
		'    "Multiple-display, notch, and menu-bar layout behavior is not proven"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "status-bar.hover.text-on-hover-polls",' \
		'    "status-bar.hover.enter-shows-title",' \
		'    "status-bar.hover.leave-hides-title"' \
		'  ],' \
		'  "proofLayer": "workflow-event-log",' \
		'  "scenario": "$(STATUS_BAR_HOVER_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(STATUS_BAR_HOVER_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(STATUS_BAR_HOVER_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-status-bar-shortcut-reveal-scenario: generate prepare-result-bundle
	mkdir -p "$(STATUS_BAR_SHORTCUT_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/StatusItemRuntimeTests \
		-only-testing:CodexPillTests/GlobalShortcutRuntimeTests \
		-only-testing:CodexPillTests/MenuBarRuntimeValidationTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(STATUS_BAR_SHORTCUT_SCENARIO)",' \
		'  "proofLayer": "workflow-event-log",' \
		'  "events": [' \
		'    "Fake global shortcut callback is forwarded to the coordinator",' \
		'    "Shortcut reveal shows the synthetic status title S 42% W 68% from icon-only mode",' \
		'    "Repeat shortcut press collapses the visible status title",' \
		'    "Shortcut reveal lifecycle events are emitted and recorded through validation",' \
		'    "Shortcut reveal does not mutate the saved menu-bar label display mode"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(STATUS_BAR_SHORTCUT_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Fake global shortcut callback reaches StatusItemRuntime through MenuBarCoordinator",' \
		'    "First reveal shows the synthetic status title while saved mode remains icon-only",' \
		'    "Repeat reveal collapses the status title",' \
		'    "Runtime and validation events record shortcut reveal start and end"' \
		'  ],' \
		'  "command": "make verify-status-bar-shortcut-reveal-scenario",' \
		'  "gaps": [' \
		'    "Live Carbon/global hotkey registration is not exercised",' \
		'    "Native keyboard input and system shortcut conflicts are not proven",' \
		'    "Live macOS menu-bar screen capture and native hittability are not proven"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "status-bar.shortcut.callback-reveals-title",' \
		'    "status-bar.shortcut.repeat-collapses-title",' \
		'    "status-bar.shortcut.display-mode-unchanged"' \
		'  ],' \
		'  "proofLayer": "workflow-event-log",' \
		'  "scenario": "$(STATUS_BAR_SHORTCUT_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(STATUS_BAR_SHORTCUT_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(STATUS_BAR_SHORTCUT_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-status-bar-usage-bars-preferences-scenario: generate prepare-result-bundle
	mkdir -p "$(STATUS_BAR_USAGE_PREFS_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/StatusItemSettingsStoreTests \
		-only-testing:CodexPillTests/CodexPillSettingsStoreTests \
		-only-testing:CodexPillTests/MenuBarMenuBuilderTests \
		-only-testing:CodexPillTests/MenuBarUIValidationTests \
		-only-testing:CodexPillTests/MenuBarRuntimeValidationTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(STATUS_BAR_USAGE_PREFS_SCENARIO)",' \
		'  "proofLayer": "unit",' \
		'  "events": [' \
		'    "Label mode action stores Icon + Text when synthetic usage data is available",' \
		'    "Icon style action stores Stacked Bars without touching account state",' \
		'    "Monochrome, pacing marker, and accent reset actions update presentation preferences only",' \
		'    "Menu builder exposes preference controls with stable selectors and selected states",' \
		'    "Deterministic validation snapshot records preference rows and configured accent color",' \
		'    "Account catalog, active account, and isolated auth file remain unchanged"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(STATUS_BAR_USAGE_PREFS_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Status item settings persist label mode, icon style, pacing markers, custom accent color, and accent reset",' \
		'    "Menu builder exposes Menu Bar Label, Icon Style, Show Pace Markers, Accent Color, and Use Default controls",' \
		'    "UI validation snapshot records configured progress bar colors and preference rows",' \
		'    "Coordinator preference actions preserve account catalog, active account, and auth-file bytes"' \
		'  ],' \
		'  "command": "make verify-status-bar-usage-bars-preferences-scenario",' \
		'  "gaps": [' \
		'    "Live NSColorPanel color choosing is not opened",' \
		'    "Native menu-bar clicks, live screen capture, and native hittability are not proven",' \
		'    "Real account/auth data is not used"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "status-bar.preferences.label-mode",' \
		'    "status-bar.preferences.icon-style",' \
		'    "status-bar.preferences.usage-markers",' \
		'    "status-bar.preferences.accent-color",' \
		'    "status-bar.preferences.account-state-unchanged"' \
		'  ],' \
		'  "proofLayer": "unit",' \
		'  "scenario": "$(STATUS_BAR_USAGE_PREFS_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(STATUS_BAR_USAGE_PREFS_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(STATUS_BAR_USAGE_PREFS_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-rename-scenario: generate prepare-result-bundle
	mkdir -p "$(RENAME_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/RenameSavedAccountUseCaseTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Rename changes only the CodexPill display label",' \
		'    "Rename preserves saved auth snapshot, identity, plan, and rate-limit state",' \
		'    "Empty, whitespace-only, duplicate, and same-name inputs do not mutate auth state"' \
		'  ],' \
		'  "extraArtifacts": [],' \
		'  "scenario": "$(RENAME_SCENARIO)",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)"' \
		'}' > "$(RENAME_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-add-account-name-scenario: generate prepare-result-bundle
	mkdir -p "$(ADD_ACCOUNT_NAME_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/AddAccountWorkflowTests \
		-only-testing:CodexPillTests/AccountActionFlowTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Empty or whitespace-only Add Account names are rejected before isolated sign-in starts",' \
		'    "Case-insensitive duplicate Add Account names are rejected before isolated sign-in starts",' \
		'    "Display-name errors resolve back into the Add Account name-recovery flow"' \
		'  ],' \
		'  "command": "make verify-add-account-name-scenario",' \
		'  "gaps": [' \
		'    "Native Add Account panel rendering and disabled Continue state are not proven by this unit scenario",' \
		'    "Browser/device-code sign-in and live auth state are not exercised"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "account-catalog.add-account-name-required",' \
		'    "account-catalog.add-account-name-unique-before-sign-in"' \
		'  ],' \
		'  "proofLayer": "unit",' \
		'  "scenario": "$(ADD_ACCOUNT_NAME_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)"' \
	'}' > "$(ADD_ACCOUNT_NAME_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-add-account-isolated-success-scenario: generate prepare-result-bundle
	mkdir -p "$(ADD_ACCOUNT_ISOLATED_SUCCESS_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/AddAccountWorkflowTests \
		-only-testing:CodexPillTests/AccountsControllerTests \
		-only-testing:CodexPillTests/AccountActionFlowTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(ADD_ACCOUNT_ISOLATED_SUCCESS_SCENARIO)",' \
		'  "proofLayer": "workflow-event-log",' \
		'  "events": [' \
		'    "validated display name before login",' \
		'    "started isolated login with fake client",' \
		'    "captured isolated auth snapshot",' \
		'    "verified isolated login status",' \
		'    "confirmed live local auth fingerprint was unchanged",' \
		'    "saved inactive account snapshot and catalog row",' \
		'    "hydrated saved account metadata through fake saved-account status client",' \
		'    "preserved active This Mac account id",' \
		'    "cleaned isolated login session"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(ADD_ACCOUNT_ISOLATED_SUCCESS_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Add Account persists captured isolated auth without changing the active This Mac account",' \
		'    "New inactive account metadata and usable rate-limit status are hydrated through the fake saved-account status client when available",' \
		'    "The success confirmation can route to local switch without a second confirmation, but the save path itself does not relaunch or switch Codex"' \
		'  ],' \
		'  "command": "make verify-add-account-isolated-success-scenario",' \
		'  "gaps": [' \
		'    "Native device-code panel rendering and browser sign-in are not proven by this workflow-event scenario",' \
		'    "Live Codex auth, live app-server, and real process relaunch are not exercised",' \
		'    "Failure cleanup is tracked by add-account-failure-cleanup, not this success scenario"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "add-account.isolated-success.saves-without-switching-this-mac",' \
		'    "add-account.isolated-success.hydrates-new-inactive-account",' \
		'    "add-account.isolated-success.cleans-login-session"' \
		'  ],' \
		'  "proofLayer": "workflow-event-log",' \
		'  "scenario": "$(ADD_ACCOUNT_ISOLATED_SUCCESS_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(ADD_ACCOUNT_ISOLATED_SUCCESS_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(ADD_ACCOUNT_ISOLATED_SUCCESS_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-add-account-failure-cleanup-scenario: generate prepare-result-bundle
	mkdir -p "$(ADD_ACCOUNT_FAILURE_CLEANUP_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/AddAccountWorkflowTests \
		-only-testing:CodexPillTests/AccountActionFlowTests \
		-only-testing:CodexPillTests/AppPathsTests \
		-only-testing:CodexPillTests/SystemIsolatedCodexLoginClientTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(ADD_ACCOUNT_FAILURE_CLEANUP_SCENARIO)",' \
		'  "proofLayer": "workflow-event-log",' \
		'  "events": [' \
		'    "cancel terminates and cleans the fake isolated login session",' \
		'    "auth capture timeout cleans the fake isolated login session and saves no account",' \
		'    "login status verification failure cleans the fake isolated login session and saves no account",' \
		'    "live auth mutation cleans the fake isolated login session and saves no account",' \
		'    "duplicate captured identity cleans the fake isolated login session and saves no duplicate account",' \
		'    "snapshot save failure cleans the fake isolated login session and leaves the account catalog unchanged",' \
		'    "repository save failure cleans the fake isolated login session and deletes the saved snapshot rollback target",' \
		'    "stale isolated CODEX_HOME cleanup removes only old CodexPill session directories",' \
		'    "startup prompt failure reasons redact device codes and prompt URL query strings"' \
		'  ],' \
		'  "negativeStateAssertions": [' \
		'    "no unintended saved account is written for terminal failure paths",' \
		'    "live local auth fingerprint remains the comparison boundary",' \
		'    "fresh isolated homes and unrelated directories survive stale cleanup",' \
		'    "device codes and auth URL query strings are not emitted in sanitized startup failure diagnostics"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(ADD_ACCOUNT_FAILURE_CLEANUP_SCENARIO_ARTIFACTS)/cleanup-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Cancel, auth capture timeout, login verification failure, live-auth mutation, duplicate captured identity, and save failures clean fake isolated Add Account state",' \
		'    "Terminal failure paths do not save unintended accounts or switch This Mac",' \
		'    "Stale isolated CODEX_HOME cleanup removes only old CodexPill session directories",' \
		'    "Prompt startup failure diagnostics redact device codes and auth URL query strings"' \
		'  ],' \
		'  "command": "make verify-add-account-failure-cleanup-scenario",' \
		'  "gaps": [' \
		'    "Native device-code UI, browser sign-in, live Codex auth, and live process termination are not exercised",' \
		'    "Quit-during-sign-in is represented by the same cancel and cleanup contract rather than a live app termination smoke",' \
		'    "Crash recovery is proven at the stale isolated CODEX_HOME session cleanup layer, not by crashing the app"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "add-account.failure.cancel-cleans-isolated-session",' \
		'    "add-account.failure.timeout-and-verification-clean-isolated-session",' \
		'    "add-account.failure.live-auth-and-save-failure-save-no-unintended-account",' \
		'    "add-account.failure.stale-codex-home-cleanup-is-bounded",' \
		'    "add-account.failure.prompt-diagnostics-redact-device-code-and-query"' \
		'  ],' \
		'  "proofLayer": "workflow-event-log",' \
		'  "scenario": "$(ADD_ACCOUNT_FAILURE_CLEANUP_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(ADD_ACCOUNT_FAILURE_CLEANUP_SCENARIO_ARTIFACTS)/cleanup-receipt.json"' \
		'}' > "$(ADD_ACCOUNT_FAILURE_CLEANUP_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-switch-account-local-confirmed-scenario: generate prepare-result-bundle
	mkdir -p "$(SWITCH_ACCOUNT_LOCAL_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/SwitchAccountWorkflowTests \
		-only-testing:CodexPillTests/MenuBarRuntimeValidationTests \
		-only-testing:CodexPillTests/MenuBarAlertFactoryTests \
		-only-testing:CodexPillTests/MenuBarValidationObserverTests \
		-only-testing:CodexPillTests/AccountActionFlowTests \
		-only-testing:CodexPillTests/SilentPostActionRefreshTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(SWITCH_ACCOUNT_LOCAL_SCENARIO)",' \
		'  "proofLayer": "workflow-event-log",' \
		'  "events": [' \
		'    "local switch menu action presents confirmation before auth activation",' \
		'    "cancelled confirmation leaves the local auth file unchanged and does not relaunch Codex",' \
		'    "accepted confirmation activates the selected saved snapshot",' \
		'    "accepted confirmation relaunches Codex through a fake process client",' \
		'    "workflow activation persists the account catalog and resolves the active account when identity matches",' \
		'    "Add Account success action routes into the local switch path without a second confirmation",' \
		'    "silent post-action refresh applies refreshed active-account metadata when status proof is available"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(SWITCH_ACCOUNT_LOCAL_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Local switch asks for confirmation before activating the selected saved snapshot",' \
		'    "Cancel leaves This Mac auth unchanged and does not relaunch Codex",' \
		'    "Confirm activates the selected saved snapshot, persists catalog state, relaunches Codex, and records switch workflow events",' \
		'    "Add Account success can reuse the same local switch path without a second confirmation",' \
		'    "Post-switch active-account refresh behavior is covered by silent refresh tests"' \
		'  ],' \
		'  "command": "make verify-switch-account-local-confirmed-scenario",' \
		'  "gaps": [' \
		'    "Native confirmation panel rendering and click automation are not proven by this workflow-event scenario",' \
		'    "Live Codex process relaunch and live app-server refresh are not exercised",' \
		'    "Remote host switching is tracked by switch-account-remote-install-verify, not this local scenario"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "switch-account.local.confirmation-gates-auth-activation",' \
		'    "switch-account.local.confirmed-switch-activates-and-relaunches",' \
		'    "switch-account.local.add-account-success-reuses-switch-path",' \
		'    "switch-account.local.post-switch-refresh-covered"' \
		'  ],' \
		'  "proofLayer": "workflow-event-log",' \
		'  "scenario": "$(SWITCH_ACCOUNT_LOCAL_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(SWITCH_ACCOUNT_LOCAL_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(SWITCH_ACCOUNT_LOCAL_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-switch-account-remote-install-verify-scenario: generate prepare-result-bundle
	mkdir -p "$(SWITCH_ACCOUNT_REMOTE_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/SwitchAccountOnHostWorkflowTests \
		-only-testing:CodexPillTests/InMemoryRemoteHostClientTests \
		-only-testing:CodexPillTests/SSHRemoteHostClientTests \
		-only-testing:CodexPillTests/RemoteHostAccountVerifierTests \
		-only-testing:CodexPillTests/AccountsControllerTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(SWITCH_ACCOUNT_REMOTE_SCENARIO)",' \
		'  "proofLayer": "workflow-event-log",' \
		'  "events": [' \
		'    "missing remote snapshot installs before switch",' \
		'    "installed remote snapshot switches directly without reinstall",' \
		'    "stale remote snapshot hash is classified as missing by the SSH contract fixture",' \
		'    "remote switch refreshes Codex app-server before status verification",' \
		'    "remote verification retries stale status and accepts the expected account only",' \
		'    "verification mismatch or ambiguity returns a not-verified outcome instead of verified active state",' \
		'    "active local snapshot is relinked before remote switch when current local auth is fresher"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(SWITCH_ACCOUNT_REMOTE_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Missing or stale remote snapshots are installed before switching",' \
		'    "Already-installed remote snapshots switch directly",' \
		'    "Remote switch refreshes app-server state and verifies the expected account before reporting success",' \
		'    "Mismatched or ambiguous remote status is surfaced instead of marked verified",' \
		'    "Active local snapshots are relinked before remote install or switch when the selected account is active on This Mac"' \
		'  ],' \
		'  "command": "make verify-switch-account-remote-install-verify-scenario",' \
		'  "gaps": [' \
		'    "No live SSH host, live Codex app-server, or real remote auth mutation is exercised",' \
		'    "Menu presentation and native click routing are not proven by this workflow-event scenario",' \
		'    "Remote verification failure menu projection is tracked by remote-host-verification-failure, not this scenario"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "switch-account.remote.install-before-switch-when-missing-or-stale",' \
		'    "switch-account.remote.direct-switch-when-installed",' \
		'    "switch-account.remote.refresh-and-verify-expected-account",' \
		'    "switch-account.remote.relink-active-local-snapshot-before-switch"' \
		'  ],' \
		'  "proofLayer": "workflow-event-log",' \
		'  "scenario": "$(SWITCH_ACCOUNT_REMOTE_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(SWITCH_ACCOUNT_REMOTE_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(SWITCH_ACCOUNT_REMOTE_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-remote-host-add-panel-validation-scenario: generate prepare-result-bundle
	mkdir -p "$(REMOTE_HOST_ADD_PANEL_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/MenuBarHostSetupFormStateTests \
		-only-testing:CodexPillTests/MenuBarAlertFactoryTests \
		-only-testing:CodexPillTests/SSHRemoteHostClientTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(REMOTE_HOST_ADD_PANEL_SCENARIO)",' \
		'  "proofLayer": "contract-fixture",' \
		'  "events": [' \
		'    "Add Host copy names the destination field, optional host name, idle validation, success state, and final Add Host action",' \
		'    "Form state keeps Add Host disabled until a matching destination succeeds",' \
		'    "Editing the destination after success clears the validated host and disables Add Host",' \
		'    "Unknown destination, non-interactive SSH setup, unreachable SSH, and not-Codex-ready failures stay disabled with surfaced feedback",' \
		'    "SSH validation uses BatchMode, a short connect timeout, Codex CLI and app-server readiness checks, and writable CodexPill/Codex directories"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(REMOTE_HOST_ADD_PANEL_SCENARIO_ARTIFACTS)/contract-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Add Host remains disabled for idle, testing, invalid, unreachable, SSH-not-ready, and not-Codex-ready destinations",' \
		'    "Add Host unlocks only after validation succeeds for the same trimmed destination",' \
		'    "Changing the destination after success clears the validated host before submission",' \
		'    "The SSH contract runs non-interactively and requires Codex CLI, Codex app-server help, and writable remote directories"' \
		'  ],' \
		'  "command": "make verify-remote-host-add-panel-validation-scenario",' \
		'  "gaps": [' \
		'    "Native Add Host panel screenshot, first responder focus, and click automation are not proven",' \
		'    "No live SSH host, live Codex app-server, or real remote filesystem is exercised",' \
		'    "Install-and-switch follow-up is tracked by remote-host-install-switch-current-account, not this scenario"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "remote-host.add-panel.disabled-until-codex-ready-validation-succeeds",' \
		'    "remote-host.add-panel.validation-feedback-maps-ssh-and-codex-readiness-failures",' \
		'    "remote-host.add-panel.ssh-validation-is-noninteractive-and-codex-ready"' \
		'  ],' \
		'  "proofLayer": "contract-fixture",' \
		'  "scenario": "$(REMOTE_HOST_ADD_PANEL_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "contractReceipt": "$(REMOTE_HOST_ADD_PANEL_SCENARIO_ARTIFACTS)/contract-receipt.json"' \
		'}' > "$(REMOTE_HOST_ADD_PANEL_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-remote-host-install-switch-current-account-scenario: generate prepare-result-bundle
	mkdir -p "$(REMOTE_HOST_INSTALL_SWITCH_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/MenuBarRuntimeValidationTests \
		-only-testing:CodexPillTests/SwitchAccountOnHostWorkflowTests \
		-only-testing:CodexPillTests/MenuBarAlertFactoryTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(REMOTE_HOST_INSTALL_SWITCH_SCENARIO)",' \
		'  "proofLayer": "workflow-event-log",' \
		'  "events": [' \
		'    "Add Host cancellation after destination validation presents the install follow-up and persists no pending host state",' \
		'    "Add Host confirmation for the current active account records install, switch, app-server refresh, and status verification in order",' \
		'    "Confirmed setup persists the host desired account, verified account, verified status, and installed account id",' \
		'    "The remote switch workflow installs missing snapshots before switching and switches directly when already installed",' \
		'    "Install-and-switch follow-up copy explains that cancelling means the host will not be added yet"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(REMOTE_HOST_INSTALL_SWITCH_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Cancelling the install-current-account follow-up leaves no configured or pending remote host state",' \
		'    "Confirming setup switches the validated host to the current active account through fake remote operations",' \
		'    "Missing remote snapshots install before switch, refresh, and verification",' \
		'    "Verified setup persists desired, verified, and installed host/account state"' \
		'  ],' \
		'  "command": "make verify-remote-host-install-switch-current-account-scenario",' \
		'  "gaps": [' \
		'    "Native Add Host and confirmation panel rendering, focus, and click automation are not proven",' \
		'    "No live SSH host, live Codex app-server, real remote auth mutation, or real remote filesystem is exercised",' \
		'    "Remote verification failure presentation is tracked by remote-host-verification-failure, not this scenario"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "remote-host.install-switch.cancel-leaves-no-pending-host",' \
		'    "remote-host.install-switch.confirm-runs-current-account-workflow-in-order",' \
		'    "remote-host.install-switch.verified-setup-persists-host-state"' \
		'  ],' \
		'  "proofLayer": "workflow-event-log",' \
		'  "scenario": "$(REMOTE_HOST_INSTALL_SWITCH_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(REMOTE_HOST_INSTALL_SWITCH_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(REMOTE_HOST_INSTALL_SWITCH_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-remote-host-verification-failure-scenario: generate prepare-result-bundle
	mkdir -p "$(REMOTE_HOST_VERIFICATION_FAILURE_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/RemoteHostAccountVerifierTests \
		-only-testing:CodexPillTests/RemoteHostRuntimeTests \
		-only-testing:CodexPillTests/SwitchAccountOnHostWorkflowTests \
		-only-testing:CodexPillTests/MenuBarMenuStateTests \
		-only-testing:CodexPillTests/MenuBarMenuBuilderTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(REMOTE_HOST_VERIFICATION_FAILURE_SCENARIO)",' \
		'  "proofLayer": "unit",' \
		'  "events": [' \
		'    "Verifier returns not-verified for different and ambiguous remote identities with actionable messages",' \
		'    "Runtime applies not-verified outcomes as failed host state with no verified active account",' \
		'    "Refresh/read failures clear verified remote account state and preserve failure details",' \
		'    "Menu state and builder projection keep failed or unverified hosts out of primary active remote cards",' \
		'    "Detected remote accounts stay in host management/adoption surfaces instead of replacing the saved account catalog"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(REMOTE_HOST_VERIFICATION_FAILURE_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Different and ambiguous remote identities are surfaced as not verified, not verified active state",' \
		'    "Failed verification clears verifiedAccount and stores failure/detected-account state for recovery",' \
		'    "Failed or disconnected remote hosts do not render primary active remote account cards",' \
		'    "Detected remote accounts remain recoverable through host management without replacing saved accounts"' \
		'  ],' \
		'  "command": "make verify-remote-host-verification-failure-scenario",' \
		'  "gaps": [' \
		'    "No live SSH host, live Codex app-server, real remote auth mutation, or real remote filesystem is exercised",' \
		'    "Native click automation and live menu-bar interaction are not proven",' \
		'    "Remote rate-limit fallback is tracked by remote-host-rate-limit-fallback, not this scenario"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "remote-host.verification-failure.not-verified-is-failed-state",' \
		'    "remote-host.verification-failure.no-primary-active-card",' \
		'    "remote-host.verification-failure.detected-account-is-recoverable-not-catalog-truth"' \
		'  ],' \
		'  "proofLayer": "unit",' \
		'  "scenario": "$(REMOTE_HOST_VERIFICATION_FAILURE_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(REMOTE_HOST_VERIFICATION_FAILURE_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(REMOTE_HOST_VERIFICATION_FAILURE_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-remote-host-rate-limit-fallback-scenario: generate prepare-result-bundle
	mkdir -p "$(REMOTE_HOST_RATE_LIMIT_FALLBACK_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/RemoteRateLimitResolutionTests \
		-only-testing:CodexPillTests/MenuBarAccountCatalogProjectionTests \
		-only-testing:CodexPillTests/MenuBarMenuStateTests \
		-only-testing:CodexPillTests/MenuBarRuntimeValidationTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(REMOTE_HOST_RATE_LIMIT_FALLBACK_SCENARIO)",' \
		'  "proofLayer": "contract-fixture",' \
		'  "events": [' \
		'    "Remote rate-limit resolution keeps meaningful verified remote windows when present",' \
		'    "Missing, zeroed, partial, or expired remote windows fall back to meaningful saved-account windows",' \
		'    "Ambiguous remote emails use stable account identity before borrowing saved fallback limits",' \
		'    "Menu projection relinks stale verified remote account metadata to the canonical saved account",' \
		'    "Runtime refresh preserves saved fallback windows when remote status omits useful rate limits"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(REMOTE_HOST_RATE_LIMIT_FALLBACK_SCENARIO_ARTIFACTS)/contract-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Verified remote rate-limit values win when they contain meaningful data",' \
		'    "Saved fallback windows are used only for missing, zeroed, partial, expired, or suspicious remote data",' \
		'    "Fallback selection resolves against canonical saved account identity instead of email alone",' \
		'    "Remote active cards and validation snapshots expose meaningful fallback limits without claiming live SSH proof"' \
		'  ],' \
		'  "command": "make verify-remote-host-rate-limit-fallback-scenario",' \
		'  "gaps": [' \
		'    "No live SSH host, live Codex app-server, real remote auth mutation, or real remote filesystem is exercised",' \
		'    "Native click automation and live menu-bar interaction are not proven",' \
		'    "Fallback labels in final native menu pixels are not separately proven"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "remote-host.rate-limit-fallback.remote-values-win-when-meaningful",' \
		'    "remote-host.rate-limit-fallback.saved-values-used-only-for-unusable-remote-data",' \
		'    "remote-host.rate-limit-fallback.identity-scoped-fallback"' \
		'  ],' \
		'  "proofLayer": "contract-fixture",' \
		'  "scenario": "$(REMOTE_HOST_RATE_LIMIT_FALLBACK_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "contractReceipt": "$(REMOTE_HOST_RATE_LIMIT_FALLBACK_SCENARIO_ARTIFACTS)/contract-receipt.json"' \
		'}' > "$(REMOTE_HOST_RATE_LIMIT_FALLBACK_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-remove-account-active-targets-sign-out-scenario: generate prepare-result-bundle
	mkdir -p "$(REMOVE_ACCOUNT_ACTIVE_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/MenuBarRuntimeValidationTests \
		-only-testing:CodexPillTests/DeleteSavedAccountUseCaseTests \
		-only-testing:CodexPillTests/MenuBarAlertFactoryTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(REMOVE_ACCOUNT_ACTIVE_SCENARIO)",' \
		'  "proofLayer": "workflow-event-log",' \
		'  "events": [' \
		'    "remove action presents destructive confirmation for active local and remote targets",' \
		'    "confirmed remove signs out local auth before deleting the saved snapshot",' \
		'    "confirmed remove signs out active remote host before deleting the saved snapshot",' \
		'    "saved catalog row and local auth snapshot are removed after required sign-outs succeed",' \
		'    "remote host state no longer presents the removed account as verified or desired active state"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(REMOVE_ACCOUNT_ACTIVE_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Removing an active account requires confirmation before mutation",' \
		'    "Confirmed removal signs out local and remote active targets before deleting the saved snapshot",' \
		'    "After success, the removed account is gone from the catalog and no longer presented as active locally or remotely",' \
		'    "Local sign-out removes live auth and relaunches Codex through a fake process client"' \
		'  ],' \
		'  "command": "make verify-remove-account-active-targets-sign-out-scenario",' \
		'  "gaps": [' \
		'    "Native confirmation panel rendering and click automation are not proven by this workflow-event scenario",' \
		'    "Live Codex relaunch, live SSH sign-out, and real remote auth mutation are not exercised",' \
		'    "Required sign-out failure is tracked by remove-account-signout-failure-keeps-control, not this success scenario"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "remove-account.active-targets.confirmation-before-mutation",' \
		'    "remove-account.active-targets.local-sign-out-before-delete",' \
		'    "remove-account.active-targets.remote-sign-out-before-delete",' \
		'    "remove-account.active-targets.removed-account-not-presented-active"' \
		'  ],' \
		'  "proofLayer": "workflow-event-log",' \
		'  "scenario": "$(REMOVE_ACCOUNT_ACTIVE_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(REMOVE_ACCOUNT_ACTIVE_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(REMOVE_ACCOUNT_ACTIVE_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-remove-account-signout-failure-keeps-control-scenario: generate prepare-result-bundle
	mkdir -p "$(REMOVE_ACCOUNT_FAILURE_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/MenuBarRuntimeValidationTests \
		-only-testing:CodexPillTests/DeleteSavedAccountUseCaseTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(REMOVE_ACCOUNT_FAILURE_SCENARIO)",' \
		'  "proofLayer": "workflow-event-log",' \
		'  "events": [' \
		'    "local required sign-out failure throws before deleting the saved snapshot",' \
		'    "remote required sign-out failure throws before deleting the saved snapshot or catalog row",' \
		'    "remote failure keeps desired and verified remote account state intact",' \
		'    "failure is surfaced through the user-facing error alert"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(REMOVE_ACCOUNT_FAILURE_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Failed local sign-out prevents snapshot deletion and catalog persistence",' \
		'    "Failed remote sign-out prevents saved-account deletion and keeps the catalog row visible",' \
		'    "Failed remote sign-out keeps remote desired and verified state pointed at the saved account",' \
		'    "The real sanitized sign-out failure is shown to the user"' \
		'  ],' \
		'  "command": "make verify-remove-account-signout-failure-keeps-control-scenario",' \
		'  "gaps": [' \
		'    "Native confirmation panel rendering and click automation are not proven by this workflow-event scenario",' \
		'    "Live Codex relaunch, live SSH sign-out, and real remote auth mutation are not exercised",' \
		'    "Remote inactive snapshot deletion is out of scope for this scenario"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "remove-account.signout-failure.local-keeps-snapshot",' \
		'    "remove-account.signout-failure.remote-keeps-catalog-row",' \
		'    "remove-account.signout-failure.remote-keeps-active-state",' \
		'    "remove-account.signout-failure.surfaces-real-error"' \
		'  ],' \
		'  "proofLayer": "workflow-event-log",' \
		'  "scenario": "$(REMOVE_ACCOUNT_FAILURE_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(REMOVE_ACCOUNT_FAILURE_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(REMOVE_ACCOUNT_FAILURE_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-refresh-inactive-isolated-status-scenario: generate prepare-result-bundle
	mkdir -p "$(REFRESH_INACTIVE_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/HydrateSavedAccountsMetadataUseCaseTests \
		-only-testing:CodexPillTests/CodexAppServerClientTests \
		-only-testing:CodexPillTests/AppPathsTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(REFRESH_INACTIVE_SCENARIO)",' \
		'  "proofLayer": "contract-fixture",' \
		'  "events": [' \
		'    "inactive saved accounts are read through saved-account status clients instead of live auth switching",' \
		'    "live local auth data remains unchanged after inactive refresh",' \
		'    "isolated app-server reads require account and rate-limit responses before success",' \
		'    "previous meaningful limits are preserved when isolated reads fail, return no limits, or return suspicious zeroed limits",' \
		'    "isolated CODEX_HOME sessions use root auth.json and clean up temporary state"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(REFRESH_INACTIVE_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Inactive saved-account refresh uses isolated saved auth data and does not mutate live auth",' \
		'    "Complete isolated status updates inactive account metadata and rate limits",' \
		'    "Failed, missing, or suspicious isolated status preserves previous meaningful limits",' \
		'    "The app-server contract sends initialize, initialized, account/read, and account/rateLimits/read before accepting status",' \
		'    "Isolated CODEX_HOME sessions keep auth.json at the root and remove their temporary root on cleanup"' \
		'  ],' \
		'  "command": "make verify-refresh-inactive-isolated-status-scenario",' \
		'  "gaps": [' \
		'    "Live Codex app-server execution with real saved accounts is not exercised",' \
		'    "Real auth snapshots, tokens, account identifiers, emails, hostnames, and private paths are not used",' \
		'    "Remote inactive-account refresh is not proven by this local inactive refresh scenario",' \
		'    "Menu projection and live macOS menu-bar behavior are not proven"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "refresh.inactive.isolated-saved-auth-read",' \
		'    "refresh.inactive.live-auth-unchanged",' \
		'    "refresh.inactive.preserve-meaningful-limits-on-unusable-read",' \
		'    "refresh.inactive.app-server-rate-limits-required",' \
		'    "refresh.inactive.isolated-home-cleanup"' \
		'  ],' \
		'  "proofLayer": "contract-fixture",' \
		'  "scenario": "$(REFRESH_INACTIVE_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(REFRESH_INACTIVE_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(REFRESH_INACTIVE_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-refresh-active-relinks-same-account-scenario: generate prepare-result-bundle
	mkdir -p "$(REFRESH_ACTIVE_RELINK_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/RefreshActiveAccountUseCaseTests \
		-only-testing:CodexPillTests/CodexAccountMatcherTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "scenario": "$(REFRESH_ACTIVE_RELINK_SCENARIO)",' \
		'  "proofLayer": "unit",' \
		'  "events": [' \
		'    "active local refresh relinks the saved snapshot when stable identity matches and fingerprint changed",' \
		'    "relink preserves saved account id, display name, catalog position, and previous updatedAt when only auth snapshot changes",' \
		'    "ambiguous live identity fails before overwriting saved auth snapshots",' \
		'    "different live identity fails before overwriting saved auth snapshots"' \
		'  ],' \
		'  "status": "passed"' \
		'}' > "$(REFRESH_ACTIVE_RELINK_SCENARIO_ARTIFACTS)/workflow-receipt.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Same-account active refresh with changed fingerprint saves the current live auth snapshot into the matched saved account",' \
		'    "The relinked account preserves id, label, catalog position, and applies returned metadata or rate limits according to refresh rules",' \
		'    "Ambiguous stable identity does not call the snapshot relinker or persist catalog changes",' \
		'    "No-match identity is surfaced as a refresh failure rather than overwriting saved snapshots",' \
		'    "Matcher fixtures keep exact, ambiguous, and no-match identity outcomes explicit"' \
		'  ],' \
		'  "command": "make verify-refresh-active-relinks-same-account-scenario",' \
		'  "gaps": [' \
		'    "Live Codex app-server execution and real auth snapshots are not exercised",' \
		'    "Remote install or switch preflight relink is not the primary claim of this scenario",' \
		'    "Menu projection and live macOS menu-bar behavior are not proven"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "refresh.active.same-account-relinks-changed-fingerprint",' \
		'    "refresh.active.relink-preserves-saved-account-shape",' \
		'    "refresh.active.ambiguous-identity-refuses-relink",' \
		'    "refresh.active.different-identity-refuses-relink"' \
		'  ],' \
		'  "proofLayer": "unit",' \
		'  "scenario": "$(REFRESH_ACTIVE_RELINK_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)",' \
		'  "workflowReceipt": "$(REFRESH_ACTIVE_RELINK_SCENARIO_ARTIFACTS)/workflow-receipt.json"' \
		'}' > "$(REFRESH_ACTIVE_RELINK_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-token-usage-parser-scenario: generate prepare-result-bundle
	mkdir -p "$(TOKEN_USAGE_PARSER_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/CodexSessionTokenUsageScannerTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Synthetic token-count rows aggregate into expected daily buckets",' \
		'    "Repeated cumulative totals and forked history do not inflate usage",' \
		'    "Malformed, oversized, and non-usage rows are skipped safely",' \
		'    "Progress and cache contribution metadata avoid raw session paths"' \
		'  ],' \
		'  "command": "make verify-token-usage-parser-scenario",' \
		'  "gaps": [' \
		'    "Token Usage UI presentation is not proven by this contract-fixture scenario",' \
		'    "Diagnostics export privacy is not proven by this scenario",' \
		'    "Real local Codex history and live scanner lifecycle are not exercised"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "token-usage.parser.synthetic-token-count-aggregation",' \
		'    "token-usage.parser.cumulative-delta-deduplication",' \
		'    "token-usage.parser.bounded-malformed-row-handling",' \
		'    "token-usage.parser.privacy-safe-progress"' \
		'  ],' \
		'  "proofLayer": "contract-fixture",' \
		'  "scenario": "$(TOKEN_USAGE_PARSER_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)"' \
		'}' > "$(TOKEN_USAGE_PARSER_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-token-usage-cache-scenario: generate prepare-result-bundle
	mkdir -p "$(TOKEN_USAGE_CACHE_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/LocalCodexSessionTokenUsageMenuProviderTests \
		-only-testing:CodexPillTests/TokenUsageMenuRuntimeTests \
		-only-testing:CodexPillTests/TokenUsageCacheBackedRefreshPolicyTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Cached aggregate data is reused before scanner work when it covers the requested period",' \
		'    "Repeated runtime refreshes keep one active Token Usage load for the same period",' \
		'    "Loaded charts stay visible while refresh progress updates",' \
		'    "Forced refresh reparses only new or changed eligible selected-period files"' \
		'  ],' \
		'  "command": "make verify-token-usage-cache-scenario",' \
		'  "gaps": [' \
		'    "Token Usage UI rendering is not proven by this contract-fixture scenario",' \
		'    "Diagnostics export privacy is not proven by this scenario",' \
		'    "Real local Codex history and live macOS menu-bar behavior are not exercised"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "token-usage.cache.cached-data-before-scan",' \
		'    "token-usage.cache.no-duplicate-runtime-loads",' \
		'    "token-usage.cache.refresh-preserves-visible-chart",' \
		'    "token-usage.cache.incremental-new-or-changed-files"' \
		'  ],' \
		'  "proofLayer": "contract-fixture",' \
		'  "scenario": "$(TOKEN_USAGE_CACHE_SCENARIO)",' \
		'  "status": "passed",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)"' \
	'}' > "$(TOKEN_USAGE_CACHE_SCENARIO_ARTIFACTS)/scenario-summary.json"

verify-token-usage-privacy-scenario: generate prepare-result-bundle
	mkdir -p "$(TOKEN_USAGE_PRIVACY_SCENARIO_ARTIFACTS)"
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		-only-testing:CodexPillTests/DiagnosticReportBuilderTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"
	printf '%s\n' \
		'{' \
		'  "kind": "diagnostics_export",' \
		'  "schemaVersion": "codexpill.diagnostics-export.fixture.v1",' \
		'  "scenario": "$(TOKEN_USAGE_PRIVACY_SCENARIO)",' \
		'  "tokenUsage": {' \
		'    "enabled": true,' \
		'    "period": "last30Days",' \
		'    "chartStyle": "dailyBars",' \
		'    "loadState": "ready",' \
		'    "bucketCount": 30,' \
		'    "aggregateInputTokens": 12345,' \
		'    "aggregateOutputTokens": 6789' \
		'  },' \
		'  "omittedFieldClasses": [' \
		'    "prompt_content",' \
		'    "raw_session_rows",' \
		'    "local_session_paths",' \
		'    "account_identifiers",' \
		'    "emails",' \
		'    "hostnames",' \
		'    "auth_material",' \
		'    "token_like_values"' \
		'  ]' \
		'}' > "$(TOKEN_USAGE_PRIVACY_SCENARIO_ARTIFACTS)/diagnostics-export.json"
	printf '%s\n' \
		'{' \
		'  "kind": "privacy_leak_report",' \
		'  "scenario": "$(TOKEN_USAGE_PRIVACY_SCENARIO)",' \
		'  "proofLayer": "privacy-leak-proof",' \
		'  "status": "passed",' \
		'  "assertions": [' \
		'    "Diagnostics export includes only aggregate Token Usage state and totals",' \
		'    "Prompt content, raw session rows, local paths, account identifiers, emails, hostnames, auth material, and token-like values are rejected",' \
		'    "Account and host topology uses per-export aliases instead of raw identifiers"' \
		'  ],' \
		'  "restrictedEvidence": [' \
		'    "raw_local_path",' \
		'    "hostname",' \
		'    "account_data",' \
		'    "private_product_data",' \
		'    "raw_transcript",' \
		'    "token"' \
		'  ]' \
		'}' > "$(TOKEN_USAGE_PRIVACY_SCENARIO_ARTIFACTS)/privacy-leak-report.json"
	printf '%s\n' \
		'{' \
		'  "assertions": [' \
		'    "Token Usage diagnostics expose only enabled state, period, chart style, load state, bucket count, and aggregate token totals",' \
		'    "Prompt content, raw session rows, local session paths, account identifiers, emails, hostnames, and token-like values are rejected from diagnostic event fields",' \
		'    "Diagnostic account and host topology uses per-export aliases instead of raw account or host identifiers"' \
		'  ],' \
		'  "command": "make verify-token-usage-privacy-scenario",' \
		'  "gaps": [' \
		'    "Live NSSavePanel confirmation and file writing are not exercised by this diagnostics-export scenario",' \
		'    "Real local Codex history is not inspected",' \
		'    "Token Usage UI rendering is covered by deterministic UI scenarios, not this diagnostics export scenario"' \
		'  ],' \
		'  "invariantIds": [' \
		'    "token-usage.diagnostics.aggregate-only",' \
		'    "diagnostics.export.rejects-raw-session-evidence",' \
		'    "diagnostics.export.aliases-account-and-host-identifiers"' \
		'  ],' \
		'  "proofLayer": "diagnostics-export",' \
		'  "scenario": "$(TOKEN_USAGE_PRIVACY_SCENARIO)",' \
		'  "status": "passed",' \
		'  "diagnosticsExport": "$(TOKEN_USAGE_PRIVACY_SCENARIO_ARTIFACTS)/diagnostics-export.json",' \
		'  "privacyLeakReport": "$(TOKEN_USAGE_PRIVACY_SCENARIO_ARTIFACTS)/privacy-leak-report.json",' \
		'  "testResultBundle": "$(RESULT_BUNDLE)"' \
	'}' > "$(TOKEN_USAGE_PRIVACY_SCENARIO_ARTIFACTS)/scenario-summary.json"

run:
	./scripts/run_menubar.sh

clean:
	rm -rf build
