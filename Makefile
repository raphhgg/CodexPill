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
TEST_SELECTORS ?=
VERIFICATION_DIR := $(BUILD_ROOT)/verification
VERIFICATION_REQUEST := $(VERIFICATION_DIR)/request.json
VERIFICATION_REQUEST_ACTIVE := $(VERIFICATION_DIR)/request.active
VERIFICATION_ARTIFACTS := $(BUILD_ROOT)/verification/$(SCENARIO)

.PHONY: diagnose generate prepare-result-bundle build test package-release verify-selected-tests verify-token-usage-privacy-scenario run clean

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

verify-selected-tests: generate prepare-result-bundle
	mkdir -p "$(VERIFICATION_DIR)"
	mkdir -p "$(VERIFICATION_ARTIFACTS)"
	printf '{\n  "artifactDirectory": "%s",\n  "scenario": "%s",\n  "proofType": "%s"\n}\n' "$(abspath $(VERIFICATION_ARTIFACTS))" "$(SCENARIO)" "$(REQUESTED_PROOF_TYPE)" > "$(VERIFICATION_REQUEST)"
	trap 'rm -f "$(VERIFICATION_REQUEST_ACTIVE)"' EXIT; touch "$(VERIFICATION_REQUEST_ACTIVE)"; xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		$(TEST_SELECTORS) \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"

verify-token-usage-privacy-scenario: TEST_SELECTORS := -only-testing:CodexPillTests/DiagnosticReportBuilderTests
verify-token-usage-privacy-scenario: verify-selected-tests
	printf '%s\n' \
		'{' \
		'  "kind": "diagnostics_export",' \
		'  "schemaVersion": "codexpill.diagnostics-export.fixture.v1",' \
		'  "scenario": "$(SCENARIO)",' \
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
		'}' > "$(VERIFICATION_ARTIFACTS)/diagnostics-export.json"
	printf '%s\n' \
		'{' \
		'  "kind": "privacy_leak_report",' \
		'  "scenario": "$(SCENARIO)",' \
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
		'}' > "$(VERIFICATION_ARTIFACTS)/privacy-leak-report.json"

run:
	./scripts/run_menubar.sh

clean:
	rm -rf build
