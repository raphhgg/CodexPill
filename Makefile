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
RENAME_SCENARIO := rename-account-label-only
RENAME_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(RENAME_SCENARIO)
ADD_ACCOUNT_NAME_SCENARIO := add-account-name-validation
ADD_ACCOUNT_NAME_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(ADD_ACCOUNT_NAME_SCENARIO)
ADD_ACCOUNT_ISOLATED_SUCCESS_SCENARIO := add-account-isolated-success
ADD_ACCOUNT_ISOLATED_SUCCESS_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(ADD_ACCOUNT_ISOLATED_SUCCESS_SCENARIO)
ADD_ACCOUNT_FAILURE_CLEANUP_SCENARIO := add-account-failure-cleanup
ADD_ACCOUNT_FAILURE_CLEANUP_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(ADD_ACCOUNT_FAILURE_CLEANUP_SCENARIO)
TOKEN_USAGE_PARSER_SCENARIO := token-usage-parser-aggregation
TOKEN_USAGE_PARSER_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(TOKEN_USAGE_PARSER_SCENARIO)
TOKEN_USAGE_CACHE_SCENARIO := token-usage-cache-first
TOKEN_USAGE_CACHE_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(TOKEN_USAGE_CACHE_SCENARIO)
TOKEN_USAGE_PRIVACY_SCENARIO := token-usage-privacy-no-raw-session
TOKEN_USAGE_PRIVACY_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(TOKEN_USAGE_PRIVACY_SCENARIO)

.PHONY: diagnose generate prepare-result-bundle build test package-release verify-ui verify-rename-scenario verify-add-account-name-scenario verify-add-account-isolated-success-scenario verify-add-account-failure-cleanup-scenario verify-token-usage-parser-scenario verify-token-usage-cache-scenario verify-token-usage-privacy-scenario run clean

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
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
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
		'  "testResultBundle": "$(RESULT_BUNDLE)"' \
		'}' > "$(TOKEN_USAGE_PRIVACY_SCENARIO_ARTIFACTS)/scenario-summary.json"

run:
	./scripts/run_menubar.sh

clean:
	rm -rf build
