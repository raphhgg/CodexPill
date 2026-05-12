#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

ruby "${SCRIPT_DIR}/seed_demo_data.rb"

export AGENT_NAME="${AGENT_NAME:-demo}"
export CODEXPILL_BUNDLE_ID="${CODEXPILL_BUNDLE_ID:-com.raphhgg.codexpill.demo}"
export CODEXPILL_VALIDATION_APP_SUPPORT_DIR="${REPO_ROOT}/build/demo/CodexPillDemoAppSupport"
export CODEXPILL_VALIDATION_SETTINGS_FIXTURE="${REPO_ROOT}/build/demo/codexpill-demo-settings.json"
export CODEXPILL_VALIDATION_USER_DEFAULTS_SUITE="${CODEXPILL_VALIDATION_USER_DEFAULTS_SUITE:-CodexPill.demo}"
export CODEXPILL_VALIDATION_ACCOUNT_STATUS_CLIENT="memory"
export CODEXPILL_VALIDATION_REMOTE_HOST_CLIENT="memory"
export CODEXPILL_VALIDATION_CODEX_PROCESS_CLIENT="memory"
export CODEXPILL_SUPPRESS_EMPTY_STATE_PROMPT="1"
export CODEXPILL_VALIDATION_OUTPUT="${REPO_ROOT}/build/demo/live-menu-snapshot.json"
export CODEXPILL_VALIDATION_EVENTS_OUTPUT="${REPO_ROOT}/build/demo/validation-events.jsonl"
export CODEXPILL_VALIDATION_SCENARIO="demo-marketing-data"

echo "Launching CodexPill with isolated demo data."
echo "No real CodexPill app-support data or ~/.codex/auth.json will be used."
echo "Demo app support: ${CODEXPILL_VALIDATION_APP_SUPPORT_DIR}"
echo "Demo snapshot output: ${CODEXPILL_VALIDATION_OUTPUT}"

"${SCRIPT_DIR}/run_menubar.sh"
