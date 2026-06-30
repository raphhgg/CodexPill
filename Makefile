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
TOKEN_USAGE_PARSER_SCENARIO := token-usage-parser-aggregation
TOKEN_USAGE_PARSER_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(TOKEN_USAGE_PARSER_SCENARIO)
TOKEN_USAGE_CACHE_SCENARIO := token-usage-cache-first
TOKEN_USAGE_CACHE_SCENARIO_ARTIFACTS := $(BUILD_ROOT)/verification/$(TOKEN_USAGE_CACHE_SCENARIO)

.PHONY: diagnose generate prepare-result-bundle build test package-release verify-ui verify-rename-scenario verify-add-account-name-scenario verify-token-usage-parser-scenario verify-token-usage-cache-scenario run clean

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

run:
	./scripts/run_menubar.sh

clean:
	rm -rf build
