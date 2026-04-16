#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

APP_NAME="CodexPill"
AGENT_NAME="${AGENT_NAME:-local}"
DERIVED_DATA="build/DerivedData/${AGENT_NAME}"
APP_PATH="${DERIVED_DATA}/Build/Products/Debug/${APP_NAME}.app"
APP_EXECUTABLE="${APP_PATH}/Contents/MacOS/${APP_NAME}"
PROJECT_PATH="${APP_NAME}.xcodeproj"
VALIDATION_OUTPUT="${CODEXPILL_VALIDATION_OUTPUT:-}"

command -v tuist >/dev/null || {
  echo "Tuist is not installed. Install it first."
  exit 1
}

# Keep the loop shell-first. Generated Xcode artifacts are transient
# build intermediates for xcodebuild, not something we open in Xcode.
"${SCRIPT_DIR}/stop_menubar.sh" >/dev/null 2>&1 || true

TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open
xcodebuild build \
  -project "${PROJECT_PATH}" \
  -scheme "${APP_NAME}" \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA}"

if [[ -n "${VALIDATION_OUTPUT}" ]]; then
  CODEXPILL_VALIDATION_OUTPUT="${VALIDATION_OUTPUT}" \
  CODEXPILL_SUPPRESS_EMPTY_STATE_PROMPT=1 \
  "${APP_EXECUTABLE}" &
  exit 0
fi

open "${APP_PATH}"
