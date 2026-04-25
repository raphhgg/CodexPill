APP_NAME := CodexPill
PROJECT_PATH := $(APP_NAME).xcodeproj
AGENT_NAME ?= local
BUILD_ROOT := build
DERIVED_DATA := $(BUILD_ROOT)/DerivedData/$(AGENT_NAME)
RESULT_BUNDLE := $(BUILD_ROOT)/results/$(AGENT_NAME)/$(APP_NAME).xcresult
DEV_BUNDLE_ID ?= com.raphhgg.codexpill.dev
STAGING_BUNDLE_ID ?= com.raphhgg.codexpill.staging

.PHONY: diagnose generate prepare-result-bundle build test run verify-ui verify-ui-live clean

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

run:
	./scripts/run_menubar.sh

verify-ui:
	./scripts/verify_ui.sh

verify-ui-live:
	SCENARIO=$${SCENARIO:-live-menu-open} ./scripts/verify_ui.sh

clean:
	rm -rf build
