APP_NAME := CodexPill
PROJECT_PATH := $(APP_NAME).xcodeproj
AGENT_NAME ?= local
BUILD_ROOT := build
DERIVED_DATA := $(BUILD_ROOT)/DerivedData/$(AGENT_NAME)
RESULT_BUNDLE := $(BUILD_ROOT)/results/$(AGENT_NAME)/$(APP_NAME).xcresult
PROOF_EMITTER_RESULT_BUNDLE := $(BUILD_ROOT)/results/$(AGENT_NAME)/CodexPillProofEmitter.xcresult
PROOF_EMITTER_BINARY := $(DERIVED_DATA)/Build/Products/Debug/CodexPillProofEmitter
DEV_BUNDLE_ID ?= com.raphhgg.codexpill.dev
STAGING_BUNDLE_ID ?= com.raphhgg.codexpill.staging

.PHONY: diagnose generate prepare-result-bundle build test mutation build-proof-emitter emit-account-switch-proof emit-add-host-validation-failure-proof verify-account-switch-seal verify-add-host-validation-failure-seal run verify-ui verify-ui-live clean

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

build-proof-emitter: generate
	mkdir -p $(dir $(PROOF_EMITTER_RESULT_BUNDLE))
	rm -rf "$(PROOF_EMITTER_RESULT_BUNDLE)"
	xcodebuild build \
		-project $(PROJECT_PATH) \
		-scheme CodexPillProofEmitter \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(PROOF_EMITTER_RESULT_BUNDLE)"

emit-account-switch-proof: build-proof-emitter
	@if [ -z "$${OUTPUT_DIR:-}" ]; then \
		echo "Set OUTPUT_DIR to the proof output directory."; \
		exit 64; \
	fi
	"$(PROOF_EMITTER_BINARY)" emit-account-switch-proof --output-dir "$${OUTPUT_DIR}"

emit-add-host-validation-failure-proof: build-proof-emitter
	@if [ -z "$${OUTPUT_DIR:-}" ]; then \
		echo "Set OUTPUT_DIR to the proof output directory."; \
		exit 64; \
	fi
	"$(PROOF_EMITTER_BINARY)" emit-add-host-validation-failure-proof --output-dir "$${OUTPUT_DIR}"

verify-account-switch-seal:
	./scripts/verify_account_switch_seal.sh

verify-add-host-validation-failure-seal:
	SCENARIO=add-host-destination-validation-failed ./scripts/verify_account_switch_seal.sh

test: generate prepare-result-bundle
	xcodebuild test \
		-project $(PROJECT_PATH) \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-resultBundlePath "$(RESULT_BUNDLE)" \
		PRODUCT_BUNDLE_IDENTIFIER="$(STAGING_BUNDLE_ID)"

mutation:
	./scripts/run_mutation.sh

run:
	./scripts/run_menubar.sh

verify-ui:
	./scripts/verify_ui.sh

verify-ui-live:
	SCENARIO=$${SCENARIO:-live-menu-open} ./scripts/verify_ui.sh

clean:
	rm -rf build
