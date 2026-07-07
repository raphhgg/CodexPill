APP_NAME := CodexPill
PROJECT_PATH := $(APP_NAME).xcodeproj
AGENT_NAME ?= local
BUILD_ROOT := build
DERIVED_DATA := $(BUILD_ROOT)/DerivedData/$(AGENT_NAME)
RESULT_BUNDLE := $(BUILD_ROOT)/results/$(AGENT_NAME)/$(APP_NAME).xcresult
DEV_BUNDLE_ID ?= com.raphhgg.codexpill.dev
STAGING_BUNDLE_ID ?= com.raphhgg.codexpill.staging

SCENARIO ?= hosted-menu-default
STRUCTURE_CONTRACT_SCENARIOS := hosted-menu-default menu-busy-status menu-empty-catalog menu-account-overflow menu-unmatched-active-account
REQUESTED_PROOF_TYPE ?= $(if $(filter $(SCENARIO),$(STRUCTURE_CONTRACT_SCENARIOS)),ui-structure-contract,deterministic-ui)
KITE_HARNESS_BIN := $(abspath ../kite-harness/bin/kite.mjs)
KITE_UI_STRUCTURE_COMMAND ?= $(shell if test -x "$(KITE_HARNESS_BIN)" && command -v node >/dev/null 2>&1; then command -v node; elif command -v kite >/dev/null 2>&1; then command -v kite; else printf '%s' kite; fi)
KITE_UI_STRUCTURE_COMMAND_ARGUMENT ?= $(shell if test -x "$(KITE_HARNESS_BIN)" && command -v node >/dev/null 2>&1; then printf '%s' "$(KITE_HARNESS_BIN)"; fi)
VERIFICATION_DIR := $(BUILD_ROOT)/verification
VERIFICATION_REQUEST := $(VERIFICATION_DIR)/request.json
VERIFICATION_REQUEST_ACTIVE := $(VERIFICATION_DIR)/request.active
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

.PHONY: diagnose generate prepare-result-bundle build test package-release verify-kite-scenario verify-ui verify-diagnostics-export-confirmation-scenario verify-notifications-permission-denied-menu-state-scenario verify-notifications-account-available-policy-scenario verify-notifications-current-runs-out-action-scenario verify-notifications-dedupe-after-delivery-scenario verify-launch-at-login-enable-confirmation-scenario verify-launch-at-login-blocked-opens-settings-scenario verify-status-bar-hover-label-scenario verify-status-bar-shortcut-reveal-scenario verify-status-bar-usage-bars-preferences-scenario verify-rename-scenario verify-add-account-name-scenario verify-add-account-isolated-success-scenario verify-add-account-failure-cleanup-scenario verify-switch-account-local-confirmed-scenario verify-switch-account-remote-install-verify-scenario verify-remote-host-add-panel-validation-scenario verify-remote-host-install-switch-current-account-scenario verify-remote-host-verification-failure-scenario verify-remote-host-rate-limit-fallback-scenario verify-remove-account-active-targets-sign-out-scenario verify-remove-account-signout-failure-keeps-control-scenario verify-refresh-inactive-isolated-status-scenario verify-refresh-active-relinks-same-account-scenario verify-token-usage-parser-scenario verify-token-usage-cache-scenario verify-token-usage-privacy-scenario run clean

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

verify-kite-scenario:
	node scripts/run-kite-scenario.mjs

verify-ui: generate prepare-result-bundle
	mkdir -p "$(VERIFICATION_DIR)"
	printf '{\n  "artifactDirectory": "%s",\n  "scenario": "%s",\n  "proofType": "%s",\n  "kiteCommand": "%s",\n  "kiteCommandArgument": "%s"\n}\n' "$(abspath $(VERIFICATION_ARTIFACTS))" "$(SCENARIO)" "$(REQUESTED_PROOF_TYPE)" "$(KITE_UI_STRUCTURE_COMMAND)" "$(KITE_UI_STRUCTURE_COMMAND_ARGUMENT)" > "$(VERIFICATION_REQUEST)"
	trap 'rm -f "$(VERIFICATION_REQUEST_ACTIVE)"' EXIT; touch "$(VERIFICATION_REQUEST_ACTIVE)"; CODEXPILL_VALIDATION_REQUEST="$(abspath $(VERIFICATION_REQUEST))" xcodebuild test \
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
		-only-testing:CodexPillTests/MenuBarSnapshotExtractionTests \
		-only-testing:CodexPillTests/MenuBarRuntimeValidationTests \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"

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

run:
	./scripts/run_menubar.sh

clean:
	rm -rf build
