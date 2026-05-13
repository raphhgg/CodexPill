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

.PHONY: diagnose generate prepare-result-bundle build test package-release verify-ui verify-ui-live run clean

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

verify-ui-live: verify-ui

run:
	./scripts/run_menubar.sh

clean:
	rm -rf build
